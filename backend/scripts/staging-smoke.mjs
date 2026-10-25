import SQLite from 'better-sqlite3';
import WebSocket from 'ws';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

if(process.env.ENVIRONMENT!=='staging'||process.env.DATA_DIRECTORY!=='/var/lib/myleafy/staging')throw new Error('Refusing smoke fixtures outside dedicated ECS staging');
const database=new SQLite('/var/lib/myleafy/staging/database.sqlite',{fileMustExist:true});database.pragma('foreign_keys=ON');
async function sql(query,params=[]){const statement=database.prepare(query);if(statement.reader)return statement.all(...params);statement.run(...params);return [];}
const [control]=await sql('SELECT mode FROM backend_control WHERE id=1');
if(control?.mode!=='active')throw new Error('Staging must be explicitly enabled by an operator before acceptance; smoke tests never change global write switches');
const base=process.env.SMOKE_API_ORIGIN??'http://127.0.0.1:8081',checks=[];
if(!['127.0.0.1','localhost'].includes(new URL(base).hostname))throw new Error('Private staging smoke URL required');
async function call(path,body,token,method=body===undefined?'GET':'POST'){
  const response=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(20000)});
  const payload=await response.json();
  if(!response.ok)throw new Error(`${path}: HTTP ${response.status} (${payload.errorEnvelope?.code??payload.code??'unknown'})`);
  return {payload,token:response.headers.get('set-auth-token')};
}
let ownToken,ownUserId,socket;
try{
  assert.equal((await call('/health')).payload.status,'ok');checks.push('health');
  const session=await call('/v1/auth/sign-in/anonymous',{});assert.ok(session.token);ownToken=session.token;ownUserId=session.payload.user.id;assert.ok(ownUserId);checks.push('anonymous-auth');
  const identity=`ecs-smoke-${randomUUID()}`;
  const profile=(await call('/v1/profile/bootstrap',{campus_id:'bjfu',edu_id:identity},session.token)).payload.profile;
  const repeated=(await call('/v1/profile/bootstrap',{campus_id:'bjfu',edu_id:identity},session.token)).payload.profile;
  assert.equal(repeated.id,profile.id);checks.push('repeat-bootstrap-keeps-session');
  await call('/v1/profile',{nickname:'迁移测试'},session.token,'PATCH');
  await call('/v1/community/terms',{},session.token);
  socket=new WebSocket(base.replace(/^http/,'ws')+'/v1/events/feed',{headers:{Authorization:`Bearer ${session.token}`}});
  await new Promise((done,reject)=>{const timeout=setTimeout(()=>reject(new Error('WebSocket open timeout')),10000);socket.once('open',()=>{clearTimeout(timeout);done();});socket.once('error',error=>{clearTimeout(timeout);reject(error);});});
  const changed=new Promise((done,reject)=>{const timeout=setTimeout(()=>reject(new Error('WebSocket signal timeout')),10000);socket.on('message',bytes=>{const event=JSON.parse(bytes.toString());if(event.type==='changed'){clearTimeout(timeout);done();}});});
  const post={id:randomUUID(),title:'迁移测试',body:'仅测试环境数据'};
  await call('/v1/community/posts',post,session.token);await call('/v1/community/posts',post,session.token);checks.push('idempotent-post');await changed;checks.push('websocket-outbox-delivery');
  const comment={id:randomUUID(),post_id:post.id,body:'测试评论'};
  await call('/v1/community/comments',comment,session.token);await call('/v1/community/comments',comment,session.token);
  const detail=(await call(`/v1/community/posts/${post.id}`,undefined,session.token)).payload;
  assert.equal(detail.comment_count,1);checks.push('idempotent-comment-count');
  const feed=(await call('/v1/community/feed',undefined,session.token)).payload;
  assert.ok(feed.posts.some(p=>p.id===post.id));checks.push('hydrated-feed');
  const denied=await fetch(base+'/v1/profile',{signal:AbortSignal.timeout(20000)});assert.equal(denied.status,401);checks.push('unauthenticated-denied');
  const integrity=await sql('PRAGMA foreign_key_check');assert.equal(integrity.length,0);checks.push('remote-foreign-keys');
  const health=(await call('/health')).payload;
  const site=await fetch(base);assert.equal(site.status,200);assert.match(await site.text(),/<div id="root"/);checks.push('website-through-caddy');
  const release=await (await fetch(base+'/release.json')).json();assert.equal(release.commit,health.commit);checks.push('website-api-same-commit');
  const admin=await fetch(base+'/api/admin/me',{headers:{Origin:'http://localhost:8081','Sec-Fetch-Site':'same-origin'}});assert.equal(admin.status,401);checks.push('private-admin-proxy-denied');
  const report={generated_at:new Date().toISOString(),environment:'staging',commit:health.commit,passed:checks};
  await writeFile(join(process.env.DATA_DIRECTORY,'smoke-report.json'),JSON.stringify(report,null,2)+'\n',{mode:0o600});
  console.log(JSON.stringify(report,null,2));
}finally{
  socket?.close();
  // Only this run's generated identity is deleted; manual tester data and switches remain untouched.
  if(ownUserId){
    const linked=await sql('SELECT profile_id FROM profile_auth_links WHERE auth_user_id=?',[ownUserId]);
    if(linked.length)await call('/v1/account',undefined,ownToken,'DELETE');
    else await sql('DELETE FROM identity_user WHERE id=? AND isAnonymous=1 AND NOT EXISTS(SELECT 1 FROM profile_auth_links WHERE auth_user_id=identity_user.id)',[ownUserId]);
  }
  database.close();
}
