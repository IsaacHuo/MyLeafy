import { upgradeWebSocket } from '@hono/node-server';
import type { Context } from 'hono';
import type { WSContext } from 'hono/ws';
import type { Actor, BackendEnv } from './auth';
type Subscription = { socket: WSContext; who: Actor; scope: 'feed'|'notifications'; room: string };
/** Single-process rooms. Persistent outbox remains the delivery authority. */
export class ChangeSignals {
  private subscriptions = new Set<Subscription>();
  private timer: ReturnType<typeof setInterval>;
  constructor(private env: Pick<BackendEnv,'DB'>) {
    this.timer = setInterval(() => { void this.check().catch(()=>console.error(JSON.stringify({event:'signal_authorization_failed'}))); },60_000);
    this.timer.unref();
  }
  subscribe(socket: WSContext, who: Actor, scope: Subscription['scope']) {
    const subscription = {socket,who,scope,room:scope==='feed'?`campus:${who.campusId}`:`profile:${who.profileId}`};
    this.subscriptions.add(subscription); return subscription;
  }
  remove(subscription: Subscription) { this.subscriptions.delete(subscription); }
  private async authorized(s: Subscription) {
    const row = await this.env.DB.prepare(`SELECT l.profile_id,
      CASE WHEN c.status='active' AND c.is_community_enabled=1 AND (p.campus_id='bjfu' OR p.community_access_status='approved') THEN c.id ELSE NULL END AS campus_id
      FROM identity_session s JOIN auth_users u ON u.id=s.userId JOIN profile_auth_links l ON l.auth_user_id=s.userId JOIN profiles p ON p.id=l.profile_id
      LEFT JOIN campuses c ON c.id=CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END
      WHERE s.id=? AND s.expiresAt>? AND (u.banned_until IS NULL OR u.banned_until<=?)`)
      .bind(s.who.sessionId,Date.now(),new Date().toISOString().replace('Z','000Z')).first<{profile_id:string;campus_id:string|null}>();
    return s.who.sessionExpires>Date.now() && row?.profile_id===s.who.profileId && (s.scope!=='feed' || !!s.who.campusId && row.campus_id===s.who.campusId);
  }
  async check() {
    for(const s of this.subscriptions) {
      let allowed=false;
      try { allowed=!!await this.authorized(s); } catch { /* Authorization failures close sockets. */ }
      if(!allowed) {s.socket.close(1008,'Subscription expired');this.remove(s);}
    }
  }
  async publish(room:string,id:string) {
    await this.check();
    for(const s of this.subscriptions) if(s.room===room) {
      try{s.socket.send(JSON.stringify({type:'changed',event_id:id}));}
      catch{s.socket.close(1011,'Reconnect required');this.remove(s);}
    }
  }
  close() {clearInterval(this.timer);for(const s of this.subscriptions)s.socket.close(1001,'Service restarting');this.subscriptions.clear();}
}
export function connectSignals(c:Context<{Bindings:BackendEnv;Variables:{requestId:string}}>,who:Actor,scope:'feed'|'notifications') {
  let subscription: Subscription | undefined;
  return upgradeWebSocket(() => ({
    onOpen(_event,socket) { subscription=c.env.SIGNALS.subscribe(socket,who,scope);void c.env.SIGNALS.check(); },
    onMessage(event,socket) {if(event.data==='ping')socket.send('pong');else socket.close(1008,'Unsupported message');},
    onClose() {if(subscription)c.env.SIGNALS.remove(subscription);},
    onError() {if(subscription)c.env.SIGNALS.remove(subscription);},
  }))(c,async()=>{});
}
