import { afterEach, expect, it } from 'vitest';
import { LocalD1 } from './d1-local';
import type { Actor, BackendEnv } from '../src/auth';
import { createPost, termsVersion } from '../src/community';
import { attach, readFile, upload, validateAttachment } from '../src/media';

const databases:LocalD1[]=[];
afterEach(()=>{for(const db of databases.splice(0))db.close();});
function setup(){
  const db=new LocalD1();databases.push(db);
  const now=Date.now(),who:Actor={authId:crypto.randomUUID(),profileId:crypto.randomUUID(),campusId:'bjfu',identityCampus:'bjfu',sessionId:crypto.randomUUID(),sessionExpires:now+3600000};
  db.sqlite.exec("UPDATE backend_control SET mode='active'; INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  db.sqlite.prepare('INSERT INTO identity_user(id,name,email,emailVerified,createdAt,updatedAt,isAnonymous) VALUES(?,?,?,0,?,?,1)').run(who.authId,'test',`${who.authId}@anonymous.invalid`,now,now);
  db.sqlite.prepare('INSERT INTO identity_session(id,expiresAt,token,createdAt,updatedAt,userId) VALUES(?,?,?,?,?,?)').run(who.sessionId,who.sessionExpires,'test-token',now,now,who.authId);
  db.sqlite.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id,community_access_status) VALUES(?,'bjfu','123','测试',1,'bjfu','approved')").run(who.profileId);
  db.sqlite.prepare("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES(?,?,'bjfu','123')").run(who.authId,who.profileId);
  db.sqlite.prepare('INSERT INTO community_terms_acceptances(user_id,terms_version) VALUES(?,?)').run(who.profileId,termsVersion);
  const objects=new Map<string,any>();
  const files={
    async put(key:string,bytes:Uint8Array,options:any){if(objects.has(key))return null;const data=bytes.slice();const object={size:data.length,customMetadata:options.customMetadata,httpEtag:'"test-etag"',arrayBuffer:async()=>data.buffer,body:new ReadableStream({start(c){c.enqueue(data);c.close();}})};objects.set(key,object);return object;},
    async get(key:string){return objects.get(key)??null;},async head(key:string){return objects.get(key)??null;},async delete(key:string){objects.delete(key);},
  };
  return {db,who,env:{DB:db.binding(),FILES:files} as unknown as BackendEnv};
}
const pdf='%PDF-1.7\nbody\n%%EOF';
it('uploads immutable files, consumes a receipt once, and publishes only the complete attachment set',async()=>{
  const {env,who,db}=setup(),postId=crypto.randomUUID();
  await createPost(env,who,{id:postId,title:'资料',body:'附件',attachment_count:2});
  for(let i=0;i<2;i++){
    const url=`https://api.invalid/v1/files/upload?kind=attachment&upload_id=${crypto.randomUUID()}&post_id=${postId}&name=notes.pdf`;
    const request=()=>new Request(url,{method:'POST',headers:{'Content-Type':'application/pdf'},body:pdf});
    const file=await upload(env,who,request());
    expect((await upload(env,who,request())).path).toBe(file.path);
    const receipt=await validateAttachment(env,who,{post_id:postId,object_path:file.path,display_name:'notes.pdf'});
    const result=await attach(env,who,{receipt_id:receipt.receipt_id,id:crypto.randomUUID(),sort_order:i},'attachment');
    expect(result.status).toBe(i===0?'pending_review':'published');
    await expect(attach(env,who,{receipt_id:receipt.receipt_id,id:crypto.randomUUID(),sort_order:i},'attachment')).rejects.toMatchObject({status:409});
  }
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM post_attachments').get()!.n).toBe(2);
});
it('rejects an upload to another author post and blocks cross-campus downloads',async()=>{
  const {env,who}=setup(),postId=crypto.randomUUID();
  await createPost(env,who,{id:postId,title:'资料',body:'附件',attachment_count:1});
  const url=`https://api.invalid/v1/files/upload?kind=attachment&upload_id=${crypto.randomUUID()}&post_id=${postId}&name=notes.pdf`;
  const request=()=>new Request(url,{method:'POST',headers:{'Content-Type':'application/pdf'},body:pdf});
  await expect(upload(env,{...who,profileId:crypto.randomUUID()},request())).rejects.toMatchObject({status:409});
  const file=await upload(env,who,request());
  await expect(readFile(env,{...who,profileId:crypto.randomUUID(),campusId:'other'},file.bucket,file.path,new Request('https://api.invalid'))).rejects.toMatchObject({status:404});
});
