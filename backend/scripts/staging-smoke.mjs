import { cloudflareToken } from './migration/cloudflare-auth.mjs';
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

const config=JSON.parse(await readFile(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
const staging=config.env.staging;
if(staging.vars.ENVIRONMENT!=='staging'||staging.name!=='myleafy-api-staging')throw new Error('Refusing to run smoke fixtures outside the dedicated staging environment');
if(process.env.CLOUDFLARE_ACCOUNT_ID!==config.account_id)throw new Error('Cloudflare account mismatch');
const sqlURL=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}/d1/database/${staging.d1_databases[0].database_id}/query`;
async function sql(query,params=[]){
  const response=await fetch(sqlURL,{method:'POST',headers:{Authorization:`Bearer ${await cloudflareToken()}`,'Content-Type':'application/json'},body:JSON.stringify({sql:query,params}),signal:AbortSignal.timeout(20000)});
  const data=await response.json();
  if(!response.ok||!data.success)throw new Error(`D1 fixture query failed (HTTP ${response.status})`);
  return data.result.flatMap(r=>r.results);
}
const [control]=await sql('SELECT mode FROM backend_control WHERE id=1');
if(control?.mode!=='active')throw new Error('Staging must be explicitly enabled by an operator before acceptance; smoke tests never change global write switches');
const base=staging.vars.API_ORIGIN,checks=[];
async function call(path,body,token,method=body===undefined?'GET':'POST'){
  const response=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body!==undefined?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(20000)});
  const payload=await response.json();
  if(!response.ok)throw new Error(`${path}: HTTP ${response.status} (${payload.errorEnvelope?.code??payload.code??'unknown'})`);
  return {payload,token:response.headers.get('set-auth-token')};
}
let ownToken;
try{
  assert.equal((await call('/health')).payload.status,'ok');checks.push('health');
  const session=await call('/v1/auth/sign-in/anonymous',{});assert.ok(session.token);ownToken=session.token;checks.push('anonymous-auth');
  const identity=`cf-smoke-${randomUUID()}`;
  const profile=(await call('/v1/profile/bootstrap',{campus_id:'bjfu',edu_id:identity},session.token)).payload.profile;
  const repeated=(await call('/v1/profile/bootstrap',{campus_id:'bjfu',edu_id:identity},session.token)).payload.profile;
  assert.equal(repeated.id,profile.id);checks.push('repeat-bootstrap-keeps-session');
  await call('/v1/profile',{nickname:'迁移测试'},session.token,'PATCH');
  await call('/v1/community/terms',{},session.token);
  const post={id:randomUUID(),title:'迁移测试',body:'仅测试环境数据'};
  await call('/v1/community/posts',post,session.token);await call('/v1/community/posts',post,session.token);checks.push('idempotent-post');
  const comment={id:randomUUID(),post_id:post.id,body:'测试评论'};
  await call('/v1/community/comments',comment,session.token);await call('/v1/community/comments',comment,session.token);
  const detail=(await call(`/v1/community/posts/${post.id}`,undefined,session.token)).payload;
  assert.equal(detail.comment_count,1);checks.push('idempotent-comment-count');
  const feed=(await call('/v1/community/feed',undefined,session.token)).payload;
  assert.ok(feed.posts.some(p=>p.id===post.id));checks.push('hydrated-feed');
  const denied=await fetch(base+'/v1/profile',{signal:AbortSignal.timeout(20000)});assert.equal(denied.status,401);checks.push('unauthenticated-denied');
  const integrity=await sql('PRAGMA foreign_key_check');assert.equal(integrity.length,0);checks.push('remote-foreign-keys');
  const report={generated_at:new Date().toISOString(),environment:'staging',passed:checks};
  await mkdir(new URL('../.local/',import.meta.url),{recursive:true,mode:0o700});
  await writeFile(new URL('../.local/staging-smoke.json',import.meta.url),JSON.stringify(report,null,2)+'\n',{mode:0o600});
  console.log(JSON.stringify(report,null,2));
}finally{
  // Only this run's generated identity is deleted; manual tester data and switches remain untouched.
  if(ownToken)await call('/v1/account',undefined,ownToken,'DELETE');
}
