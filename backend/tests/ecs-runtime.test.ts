import {serve} from '@hono/node-server';
import WebSocket,{WebSocketServer} from 'ws';
import {afterEach,expect,it,vi} from 'vitest';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {TestDatabase} from './sqlite-local';
import {LocalObjectStore} from '../src/runtime/files';
import {SqliteDatabase} from '../src/runtime/database';
import {auth,type BackendEnv} from '../src/auth';
import {ChangeSignals} from '../src/signals';
import {createHandler} from '../src/runtime/server';
import {sha256} from '../src/http';
import type {WSContext} from 'hono/ws';
const directories:string[]=[],databases:SqliteDatabase[]=[],signals:ChangeSignals[]=[];
afterEach(async()=>{for(const s of signals.splice(0))s.close();for(const db of databases.splice(0))db.close();for(const directory of directories.splice(0))await rm(directory,{recursive:true,force:true});});
async function fixture(){
 const directory=await mkdtemp(join(tmpdir(),'leafy-ecs-'));directories.push(directory);
 const db=new TestDatabase();databases.push(db);const rooms=new ChangeSignals({DB:db});signals.push(rooms);
 const env={DB:db,FILES:new LocalObjectStore(join(directory,'files')),RELEASES:new LocalObjectStore(join(directory,'releases')),SIGNALS:rooms,ENVIRONMENT:'staging',API_ORIGIN:'https://api-staging.myleafy.space',SITE_ORIGIN:'https://staging.myleafy.space',AUTH_SECRET:'test-only-migration-secret-32-characters',MEDIA_SIGNING_SECRET:'test-only-media-secret-32-characters'} as BackendEnv;
 return {directory,db,env};
}
it('batch rollback includes preceding writes and rejects another connection statements',async()=>{
 const {db}=await fixture();
 await expect(db.batch([db.prepare("INSERT INTO mutation_assertions(ok) VALUES(1)"),db.prepare("INSERT INTO mutation_assertions(ok) VALUES(0)")])).rejects.toThrow();
 expect(await db.prepare('SELECT count(*) n FROM mutation_assertions').first()).toEqual({n:0});
 const other=new SqliteDatabase(':memory:');databases.push(other);
 await expect(db.batch([other.prepare('SELECT 1')])).rejects.toThrow('Foreign database');
});
it('immutable file commits verify hashes, reject traversal and support ranges',async()=>{
 const {env}=await fixture(),bytes=new TextEncoder().encode('0123456789'),hash=await sha256(bytes);
 expect(await env.FILES.put('images/a.jpg',bytes,{sha256:hash})).toMatchObject({size:10});
 expect(await env.FILES.put('images/a.jpg',bytes,{onlyIf:{etagDoesNotMatch:'*'}})).toBeNull();
 await expect(env.FILES.put('images/b.jpg',bytes,{sha256:'0'.repeat(64)})).rejects.toMatchObject({code:'file_integrity'});
 await expect(env.FILES.head('../escape')).rejects.toMatchObject({code:'invalid_path'});
 const range=await env.FILES.get('images/a.jpg',{range:new Headers({range:'bytes=2-5'})});
 expect(await new Response(range!.body).text()).toBe('2345');expect(range!.range).toEqual({offset:2,length:4});
 const suffix=await env.FILES.get('images/a.jpg',{range:new Headers({range:'bytes=-3'})});expect(await new Response(suffix!.body).text()).toBe('789');
 await expect(env.FILES.get('images/a.jpg',{range:new Headers({range:'bytes=20-'})})).rejects.toMatchObject({status:416});
 expect(await env.FILES.head('images/b.jpg')).toBeNull();
});
it('signed bearer sessions retain identity after SQLite backup and reconnection',async()=>{
 const {env,db,directory}=await fixture();
 const response=await auth(env).handler(new Request(`${env.API_ORIGIN}/v1/auth/sign-in/anonymous`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}));
 expect(response.ok).toBe(true);
 const token=response.headers.get('set-auth-token');expect(token).toBeTruthy();
 const headers=new Headers({authorization:`Bearer ${token}`});
 const original=await auth(env).api.getSession({headers,query:{disableRefresh:true}});expect(original).toBeTruthy();
 const path=join(directory,'copied.sqlite');await db.native.backup(path);
 const copy=new SqliteDatabase(path);databases.push(copy);
 const restored=await auth({...env,DB:copy}).api.getSession({headers,query:{disableRefresh:true}});
 expect(restored?.user.id).toBe(original?.user.id);expect(restored?.session.id).toBe(original?.session.id);
});
it('gateway rejects direct admin routes and freezes auth, release and site APIs together',async()=>{
 const {env,directory}=await fixture(),maintenance=join(directory,'maintenance'),handler=createHandler(env,maintenance);
 expect((await handler(new Request(`${env.API_ORIGIN}/admin/actions`,{method:'POST'}))).status).toBe(404);
 expect((await handler(new Request('https://attacker.invalid/v1/auth/get-session'))).status).toBe(421);
 expect((await handler(new Request(`${env.SITE_ORIGIN}/api/admin/me`))).status).toBe(403);
 await writeFile(maintenance,'test');
 for(const path of [`${env.API_ORIGIN}/v1/auth/sign-in/anonymous`,`${env.API_ORIGIN}/v1/releases/android/latest`,`${env.SITE_ORIGIN}/api/admin/login`])expect((await handler(new Request(path))).status).toBe(503);
});
it('signal delivery isolates rooms and closes expired sessions before publishing',async()=>{
 const {db,env}=await fixture(),now=Date.now();
 db.native.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi')");
 db.native.prepare('INSERT INTO identity_user(id,name,email,emailVerified,createdAt,updatedAt,isAnonymous) VALUES(?,?,?,0,?,?,1)').run('u','test','u@anonymous.invalid',now,now);
 db.native.prepare('INSERT INTO identity_session(id,expiresAt,token,createdAt,updatedAt,userId) VALUES(?,?,?,?,?,?)').run('s',now+60000,'test',now,now,'u');
 db.native.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id,community_access_status) VALUES('p','bjfu','test','测试',1,'bjfu','approved')").run();
 db.native.prepare("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES('u','p','bjfu','test')").run();
 const socket={send:vi.fn(),close:vi.fn()} as unknown as WSContext;
 env.SIGNALS.subscribe(socket,{authId:'u',profileId:'p',identityCampus:'bjfu',campusId:'bjfu',sessionId:'s',sessionExpires:now+60000},'feed');
 await env.SIGNALS.publish('profile:p','one');expect(socket.send).not.toHaveBeenCalled();
 await env.SIGNALS.publish('campus:bjfu','two');expect(socket.send).toHaveBeenCalledWith(JSON.stringify({type:'changed',event_id:'two'}));
 db.native.prepare("DELETE FROM identity_session WHERE id='s'").run();
 await env.SIGNALS.publish('campus:bjfu','three');expect(socket.close).toHaveBeenCalledWith(1008,'Subscription expired');expect(socket.send).toHaveBeenCalledTimes(1);
});

it('real Node HTTP bindings complete WebSocket upgrade and deliver signals',async()=>{
 const {env,db,directory}=await fixture();
 db.native.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi')");
 const signed=await auth(env).handler(new Request(`${env.API_ORIGIN}/v1/auth/sign-in/anonymous`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}));
 const token=signed.headers.get('set-auth-token'),user=(await signed.json()).user;
 db.native.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id,community_access_status) VALUES('p','bjfu','socket-test','测试',1,'bjfu','approved')").run();
 db.native.prepare("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES(?,'p','bjfu','socket-test')").run(user.id);
 const wss=new WebSocketServer({noServer:true});
 const server=serve({hostname:'127.0.0.1',port:0,fetch:createHandler(env,join(directory,'maintenance')),websocket:{server:wss}});
 if(!server.listening)await new Promise<void>(resolve=>server.once('listening',resolve));
 const address=server.address();if(!address||typeof address==='string')throw new Error('Expected TCP listener');
 const socket=new WebSocket(`ws://127.0.0.1:${address.port}/v1/events/feed`,{headers:{Host:new URL(env.API_ORIGIN).host,Authorization:`Bearer ${token}`}});
 try{
  await new Promise<void>((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Upgrade timeout')),3000);socket.once('open',()=>{clearTimeout(timer);resolve();});socket.once('error',error=>{clearTimeout(timer);reject(error);});});
  const received=new Promise<string>((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Signal timeout')),3000);socket.once('message',data=>{clearTimeout(timer);resolve(data.toString());});});
  await env.SIGNALS.publish('campus:bjfu','tcp-proof');
  expect(JSON.parse(await received)).toEqual({type:'changed',event_id:'tcp-proof'});
 }finally{socket.terminate();env.SIGNALS.close();wss.close();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
