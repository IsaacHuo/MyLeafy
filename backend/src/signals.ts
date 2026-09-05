import { DurableObject } from 'cloudflare:workers';

type Subscription={expires:number;sessionId:string;profileId:string;campusId:string|null;scope:'feed'|'notifications'};

/** Only the authenticated API obtains room bindings; clients cannot choose room IDs. */
export class ChangeSignals extends DurableObject<Env> {
  async fetch(request:Request):Promise<Response>{
    const path=new URL(request.url).pathname;
    if(path==='/connect'&&request.headers.get('upgrade')?.toLowerCase()==='websocket'){
      const expires=Number(request.headers.get('x-session-expires'));
      const sessionId=request.headers.get('x-session-id'),profileId=request.headers.get('x-profile-id');
      const scope=request.headers.get('x-subscription-scope');
      if(!Number.isFinite(expires)||expires<=Date.now()||!sessionId||!profileId||(scope!=='feed'&&scope!=='notifications'))return new Response('Invalid subscription',{status:401});
      const pair=new WebSocketPair();this.ctx.acceptWebSocket(pair[1]);
      pair[1].serializeAttachment({expires,sessionId,profileId,campusId:request.headers.get('x-campus-id'),scope} satisfies Subscription);
      await this.scheduleCheck();return new Response(null,{status:101,webSocket:pair[0]});
    }
    if(path==='/publish'&&request.method==='POST'){
      const event=await request.json() as {id:string};
      if(typeof event.id!=='string'||event.id.length>100)return new Response('Invalid event',{status:400});
      for(const socket of await this.authorizedSockets()){
        try{socket.send(JSON.stringify({type:'changed',event_id:event.id}));}catch{socket.close(1011,'Reconnect required');}
      }
      return new Response(null,{status:204});
    }
    return new Response('Not found',{status:404});
  }
  async authorizedSockets(){
    const sockets=this.ctx.getWebSockets(),valid:WebSocket[]=[];
    for(let start=0;start<sockets.length;start+=80){
      const group=sockets.slice(start,start+80),subscriptions=group.map(s=>s.deserializeAttachment() as Subscription);
      const sessions=await this.env.DB.prepare(`SELECT s.id,l.profile_id,
        CASE WHEN c.status='active' AND c.is_community_enabled=1 AND (p.campus_id='bjfu' OR p.community_access_status='approved') THEN c.id ELSE NULL END AS campus_id
        FROM identity_session s JOIN auth_users u ON u.id=s.userId JOIN profile_auth_links l ON l.auth_user_id=s.userId JOIN profiles p ON p.id=l.profile_id
        LEFT JOIN campuses c ON c.id=CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END
        WHERE s.id IN(${subscriptions.map(()=>'?').join(',')}) AND s.expiresAt>? AND (u.banned_until IS NULL OR u.banned_until<=?)`)
        .bind(...subscriptions.map(s=>s.sessionId),Date.now(),new Date().toISOString().replace('Z','000Z')).all<{id:string;profile_id:string;campus_id:string|null}>();
      group.forEach((socket,i)=>{
        const state=subscriptions[i],session=sessions.results.find(s=>s.id===state.sessionId);
        if(state.expires<=Date.now()||!session||session.profile_id!==state.profileId||(state.scope==='feed'&&(!state.campusId||session.campus_id!==state.campusId)))socket.close(1008,'Subscription expired');
        else valid.push(socket);
      });
    }
    return valid;
  }
  webSocketMessage(socket:WebSocket,message:string|ArrayBuffer){if(message==='ping')socket.send('pong');else socket.close(1008,'Unsupported message');}
  webSocketClose(socket:WebSocket,code:number,reason:string){socket.close(code,reason);}
  async scheduleCheck(){if(this.ctx.getWebSockets().length)await this.ctx.storage.setAlarm(Date.now()+60000);}
  async alarm(){await this.authorizedSockets();await this.scheduleCheck();}
}
