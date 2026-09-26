import { afterEach, expect, it } from 'vitest';
import { LocalD1 } from './d1-local';
import type { Actor, BackendEnv } from '../src/auth';
import { createPost, termsVersion } from '../src/community';
import { attach, attachmentDownload, readFile, upload, validateAttachment, validateImages, setProfileImage } from '../src/media';
import { pendingPost } from '../src/interactions';

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
  expect(await pendingPost(env,who,postId)).toMatchObject({status:'pending_review'});
  for(let i=0;i<2;i++){
    const url=`https://api.invalid/v1/files/upload?kind=attachment&upload_id=${crypto.randomUUID()}&post_id=${postId}&name=notes.pdf`;
    const request=()=>new Request(url,{method:'POST',headers:{'Content-Type':'application/pdf'},body:pdf});
    const file=await upload(env,who,request());
    expect((await upload(env,who,request())).path).toBe(file.path);
    const receipt=await validateAttachment(env,who,{post_id:postId,object_path:file.path,display_name:'notes.pdf'});
    const result=await attach(env,who,{receipt_id:receipt.receipt_id,id:crypto.randomUUID(),sort_order:i},'attachment');
    expect(result.status).toBe(i===0?'pending_review':'published');
    expect(await pendingPost(env,who,postId)).toEqual({id:postId,author_id:who.profileId,status:result.status});
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

it('recovers identical attachment retries before and after publication, without consuming another slot',async()=>{
  const {env,who,db}=setup(),postId=crypto.randomUUID();
  await createPost(env,who,{id:postId,title:'重试',body:'正文',attachment_count:2});
  for(let sort=0;sort<2;sort++){
    const file=await upload(env,who,new Request(`https://api.invalid/v1/files/upload?kind=attachment&upload_id=${crypto.randomUUID()}&post_id=${postId}&name=notes.pdf`,{method:'POST',headers:{'Content-Type':'application/pdf'},body:pdf}));
    const validation={post_id:postId,object_path:file.path,display_name:'notes.pdf'};
    const receipt=await validateAttachment(env,who,validation),body={receipt_id:receipt.receipt_id,id:crypto.randomUUID(),sort_order:sort};
    const results=await Promise.all([attach(env,who,body,'attachment'),attach(env,who,body,'attachment')]);
    expect(results[0]).toEqual(results[1]);
    expect(await validateAttachment(env,who,validation)).toEqual(receipt);
    expect(await attach(env,who,body,'attachment')).toEqual(results[0]);
    await expect(attach(env,who,{...body,id:crypto.randomUUID()},'attachment')).rejects.toMatchObject({status:409});
    await expect(attach(env,{...who,profileId:crypto.randomUUID()},body,'attachment')).rejects.toMatchObject({status:404});
  }
  expect(db.sqlite.prepare('SELECT count(*) n FROM post_attachments').get()!.n).toBe(2);
  expect(db.sqlite.prepare('SELECT status FROM posts WHERE id=?').get(postId)!.status).toBe('published');
});
it('renews an expired unconsumed receipt and authorizes uppercase attachment download IDs',async()=>{
  const {env,who,db}=setup(),postId=crypto.randomUUID();
  env.API_ORIGIN='https://api.invalid';env.MEDIA_SIGNING_SECRET='test-only-signing-secret-longer-than-32-characters';
  await createPost(env,who,{id:postId,title:'恢复上传',body:'正文',attachment_count:1});
  const file=await upload(env,who,new Request(`https://api.invalid/v1/files/upload?kind=attachment&upload_id=${crypto.randomUUID()}&post_id=${postId}&name=notes.pdf`,{method:'POST',headers:{'Content-Type':'application/pdf'},body:pdf}));
  const body={post_id:postId,object_path:file.path,display_name:'notes.pdf'},expired=await validateAttachment(env,who,body);
  db.sqlite.prepare("UPDATE private_community_attachment_upload_receipts SET expires_at='2000-01-01T00:00:00.000000Z' WHERE id=?").run(expired.receipt_id as string);
  const renewed=await validateAttachment(env,who,body),id=crypto.randomUUID();
  expect(renewed.receipt_id).not.toBe(expired.receipt_id);
  await expect(attach(env,who,{id,receipt_id:expired.receipt_id,sort_order:0},'attachment')).rejects.toMatchObject({status:404});
  await attach(env,who,{id,receipt_id:renewed.receipt_id,sort_order:0},'attachment');
  expect(await attachmentDownload(env,who,id.toUpperCase())).toMatchObject({display_name:'notes.pdf',byte_size:pdf.length});
  await expect(attachmentDownload(env,{...who,campusId:'other'},id)).rejects.toMatchObject({status:404});
  expect(db.sqlite.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
});

it('revalidates consumed image receipts and retries profile image assignment safely',async()=>{
  const {env,who,db}=setup(),postId=crypto.randomUUID();
  // Minimal SOF header for the deterministic server dimension validator.
  const jpeg=new Uint8Array([255,216,255,192,0,7,8,0,1,0,1,255,217]);
  await createPost(env,who,{id:postId,title:'图片重试',body:'正文',image_count:1});
  const send=(kind:string)=>upload(env,who,new Request(`https://api.invalid/v1/files/upload?kind=${kind}&upload_id=${crypto.randomUUID()}&post_id=${postId}`,{method:'POST',headers:{'Content-Type':'image/jpeg'},body:jpeg}));
  const full=await send('full'),thumb=await send('thumb'),validation={post_id:postId,full_path:full.path,thumbnail_path:thumb.path};
  const expired=await validateImages(env,who,validation);
  db.sqlite.prepare("UPDATE private_community_upload_receipts SET expires_at='2000-01-01T00:00:00.000000Z'").run();
  const renewed=await validateImages(env,who,validation);expect(renewed.receipt_id).not.toBe(expired.receipt_id);
  const body={id:crypto.randomUUID(),receipt_id:renewed.receipt_id,sort_order:0};
  expect(await attach(env,who,body,'image')).toMatchObject({status:'published'});
  expect(await validateImages(env,who,validation)).toEqual(renewed);
  expect(await attach(env,who,body,'image')).toMatchObject({status:'published'});
  const avatar=await send('avatar'),patch={kind:'avatar',path:avatar.path};
  await setProfileImage(env,who,patch);await setProfileImage(env,who,patch);
  expect(db.sqlite.prepare('SELECT avatar_path FROM profiles WHERE id=?').get(who.profileId)!.avatar_path).toBe(avatar.path);
});
