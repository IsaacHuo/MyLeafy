import { afterEach, expect, it, vi } from 'vitest';
import { LocalD1 } from './d1-local';
import { actor, auth, type BackendEnv } from '../src/auth';
import { bootstrap, deleteAccount, requestProfileEmail, verifyProfileEmail } from '../src/identity';

const databases:LocalD1[]=[];
afterEach(()=>{vi.unstubAllGlobals();for(const db of databases.splice(0))db.close();});
function setup(){
  const db=new LocalD1();databases.push(db);
  db.sqlite.exec("UPDATE backend_control SET mode='active'; INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  const env={DB:db.binding(),ENVIRONMENT:'staging',API_ORIGIN:'https://api.test.invalid',SITE_ORIGIN:'https://site.test.invalid',AUTH_SECRET:'test-only-random-secret-at-least-32-characters-long'} as BackendEnv;
  return {db,env};
}
async function anonymousSession(env:BackendEnv){
  const response=await auth(env).handler(new Request(`${env.API_ORIGIN}/v1/auth/sign-in/anonymous`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}));
  const body=await response.json() as {user:{id:string};token:string};
  expect(response.status,JSON.stringify(body)).toBe(200);
  const token=response.headers.get('set-auth-token');expect(token).toBeTruthy();
  return {userId:body.user.id,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`}};
}
it('real Better Auth anonymous sessions survive repeated bootstrap and keep one durable school profile',async()=>{
  const {db,env}=setup();
  const first=await anonymousSession(env),second=await anonymousSession(env);
  const request=(headers:Record<string,string>)=>new Request(`${env.API_ORIGIN}/v1/profile/bootstrap`,{method:'POST',headers,body:JSON.stringify({campus_id:'bjfu',edu_id:'test-123'})});
  const a=await bootstrap(env,request(first.headers));
  const again=await bootstrap(env,request(first.headers));
  const b=await bootstrap(env,request(second.headers));
  expect(a.profile.id).toBe(b.profile.id);expect(again.profile.id).toBe(a.profile.id);
  expect((await actor(env,request(first.headers))).profileId).toBe(a.profile.id);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM profiles').get()!.n).toBe(1);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM profile_auth_links').get()!.n).toBe(2);
});
it('an anonymous session cannot select another general-campus account by supplied UUID',async()=>{
  const {env}=setup(),session=await anonymousSession(env);
  const request=new Request(`${env.API_ORIGIN}/v1/profile/bootstrap`,{method:'POST',headers:session.headers,body:JSON.stringify({campus_id:'general',edu_id:crypto.randomUUID()})});
  await expect(bootstrap(env,request)).rejects.toMatchObject({status:403,code:'identity_mismatch'});
});
it('account deletion removes all linked device sessions and preserves unrelated replies',async()=>{
  const {db,env}=setup();
  const session=await anonymousSession(env),second=await anonymousSession(env),other=await anonymousSession(env);
  const request=(headers:Record<string,string>,edu:string)=>new Request(`${env.API_ORIGIN}/v1/profile/bootstrap`,{method:'POST',headers,body:JSON.stringify({campus_id:'bjfu',edu_id:edu})});
  const profile=(await bootstrap(env,request(session.headers,'test-deletion'))).profile;
  await bootstrap(env,request(second.headers,'test-deletion'));
  const survivor=(await bootstrap(env,request(other.headers,'test-survivor'))).profile;
  const postId=crypto.randomUUID(),rootId=crypto.randomUUID(),replyId=crypto.randomUUID();
  db.sqlite.prepare("INSERT INTO posts(id,author_id,title,body,campus_id,status) VALUES(?,?,'标题','正文','bjfu','published')").run(postId,survivor.id as string);
  db.sqlite.prepare("INSERT INTO comments(id,post_id,author_id,body,status) VALUES(?,?,?,'根评论','published')").run(rootId,postId,profile.id as string);
  db.sqlite.prepare("INSERT INTO comments(id,post_id,author_id,body,status,parent_comment_id,reply_to_comment_id) VALUES(?,?,?,'保留回复','published',?,?)").run(replyId,postId,survivor.id as string,rootId,rootId);
  expect((await deleteAccount(env,new Request(`${env.API_ORIGIN}/v1/account`,{method:'DELETE',headers:session.headers}))).deleted).toBe(true);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM profiles WHERE id=?').get(profile.id as string)!.n).toBe(0);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM identity_user WHERE id IN (?,?)').get(session.userId,second.userId)!.n).toBe(0);
  expect(db.sqlite.prepare('SELECT parent_comment_id FROM comments WHERE id=?').get(replyId)!.parent_comment_id).toBeNull();
  expect(db.sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
});
it('notification email becomes visible only after successful OTP verification',async()=>{
  const {db,env}=setup();env.EMAIL_API_KEY='synthetic-key';env.EMAIL_FROM='test@example.invalid';env.TEST_EMAIL_RECIPIENT='recipient@example.invalid';
  const session=await anonymousSession(env);
  await bootstrap(env,new Request(`${env.API_ORIGIN}/v1/profile/bootstrap`,{method:'POST',headers:session.headers,body:JSON.stringify({campus_id:'bjfu',edu_id:'email-test'})}));
  let otp='';
  vi.stubGlobal('fetch',vi.fn(async(url:string,options:RequestInit)=>{
    expect(url).toBe('https://api.resend.com/emails');
    const body=JSON.parse(options.body as string);otp=body.text.match(/\d{8}/)[0];
    return new Response('{"id":"synthetic-email"}',{status:200});
  }));
  const request=(body:object)=>new Request(`${env.API_ORIGIN}/v1/profile/email/request`,{method:'POST',headers:session.headers,body:JSON.stringify(body)});
  await requestProfileEmail(env,request({email:env.TEST_EMAIL_RECIPIENT}));
  expect(db.sqlite.prepare('SELECT bound_email FROM profiles').get()!.bound_email).toBeNull();
  expect(otp).toHaveLength(8);
  await verifyProfileEmail(env,request({email:env.TEST_EMAIL_RECIPIENT,otp}));
  expect(db.sqlite.prepare('SELECT bound_email FROM profiles').get()!.bound_email).toBe(env.TEST_EMAIL_RECIPIENT);
});
