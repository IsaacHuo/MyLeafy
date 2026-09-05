import { DurableObject } from 'cloudflare:workers';

/** Internal room; the API authenticates and selects the room before obtaining this binding. */
export class ChangeSignals extends DurableObject<Env> {
  async fetch(request: Request):Promise<Response>{
    const path=new URL(request.url).pathname;
    if(path==='/connect'&&request.headers.get('upgrade')?.toLowerCase()==='websocket'){
      const expires=Number(request.headers.get('x-session-expires'));
      if(!Number.isFinite(expires)||expires<=Date.now())return new Response('Session expired',{status:401});
      const pair=new WebSocketPair();this.ctx.acceptWebSocket(pair[1]);pair[1].serializeAttachment({expires});
      const alarm=await this.ctx.storage.getAlarm();if(alarm===null||expires<alarm)await this.ctx.storage.setAlarm(expires);
      return new Response(null,{status:101,webSocket:pair[0]});
    }
    if(path==='/publish'&&request.method==='POST'){
      const event=await request.json() as {id:string};
      if(typeof event.id!=='string'||event.id.length>100)return new Response('Invalid event',{status:400});
      for(const socket of this.ctx.getWebSockets()){
        const {expires}=socket.deserializeAttachment() as {expires:number};
        if(expires<=Date.now()){socket.close(1008,'Session expired');continue;}
        try{socket.send(JSON.stringify({type:'changed',event_id:event.id}));}catch{socket.close(1011,'Reconnect required');}
      }
      return new Response(null,{status:204});
    }
    return new Response('Not found',{status:404});
  }
  webSocketMessage(socket:WebSocket,message:string|ArrayBuffer){if(message==='ping')socket.send('pong');else socket.close(1008,'Unsupported message');}
  webSocketClose(socket:WebSocket,code:number,reason:string){socket.close(code,reason);}
  async alarm(){
    let next=Infinity;for(const socket of this.ctx.getWebSockets()){
      const {expires}=socket.deserializeAttachment() as {expires:number};
      if(expires<=Date.now())socket.close(1008,'Session expired');else next=Math.min(next,expires);
    }if(Number.isFinite(next))await this.ctx.storage.setAlarm(next);
  }
}
