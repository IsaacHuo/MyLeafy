import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, guard, outbox, rows, statement, type Row } from './db';
import { ApiError, integer, readBytes, sha256, text, uuid } from './http';
import { publishingGuard, requireCommunity } from './community';
import { canonicalContentTypes, isAttachmentSizeAllowed, isContentTypeAllowed, isOOXML, isPDF, isUTF8Markdown, jpegDimensions, sanitizedDisplayName, supportedExtension } from './media-validation';

const imageBucket='community-images',attachmentBucket='community-attachments';
export function objectKey(bucket:string,path:string){
  if(![imageBucket,attachmentBucket,'community-banner-assets'].includes(bucket)||path.startsWith('/')||path.includes('\\')||path.split('/').some(p=>!p||p==='.'||p==='..')||/[\u0000-\u001f\u007f]/.test(path))throw new ApiError(400,'invalid_path','文件路径无效。');
  return `${bucket}/${path}`;
}
function pendingPostGuard(env:BackendEnv,who:Actor,postId:string){
  return guard(env.DB,"EXISTS(SELECT 1 FROM posts WHERE id=? AND author_id=? AND campus_id=? AND status='pending_review')",[postId,who.profileId,requireCommunity(who)]);
}
function validatedImage(bytes:Uint8Array,max:number){
  const size=jpegDimensions(bytes);
  if(bytes.length>1048576||!size||size.width>max||size.height>max)throw new ApiError(422,'invalid_image','图片尺寸或格式无效。');
  return size;
}
export async function upload(env:BackendEnv,who:Actor,request:Request){
  const url=new URL(request.url),kind=url.searchParams.get('kind'),uploadId=uuid(url.searchParams.get('upload_id'));
  if(!['full','thumb','attachment','avatar','cover'].includes(kind??''))throw new ApiError(400,'invalid_request','上传类型无效。');
  const profileImage=kind==='avatar'||kind==='cover';
  const postId=profileImage?null:uuid(url.searchParams.get('post_id'));
  const name=sanitizedDisplayName(url.searchParams.get('name'));
  const extension=kind==='attachment'?supportedExtension(name):'jpg';
  if(!extension)throw new ApiError(400,'invalid_attachment','附件名称或格式无效。');
  const bytes=await readBytes(request,kind==='attachment'?10485760:1048576);
  let contentType='image/jpeg';
  if(kind==='attachment'){
    if(extension==='jpg'||!isAttachmentSizeAllowed(bytes.length)||!isContentTypeAllowed(extension,request.headers.get('content-type')??''))throw new ApiError(422,'invalid_attachment','附件类型或大小无效。');
    const valid=extension==='pdf'?isPDF(bytes):extension==='docx'?isOOXML(bytes,'word/document.xml'):extension==='xlsx'?isOOXML(bytes,'xl/workbook.xml'):isUTF8Markdown(bytes);
    if(!valid)throw new ApiError(422,'invalid_attachment','附件内容与格式不匹配。');
    contentType=canonicalContentTypes[extension];
  }else validatedImage(bytes,kind==='thumb'?480:kind==='avatar'?512:kind==='cover'?1800:1600);
  const path=profileImage?`${kind==='avatar'?'avatars':'profile-covers'}/${who.profileId}/${uploadId}.jpg`:
    `posts/${who.profileId}/${postId}/${kind==='attachment'?'':`${kind}/`}${uploadId}.${extension}`;
  const bucket=kind==='attachment'?attachmentBucket:imageBucket,key=objectKey(bucket,path),hash=await sha256(bytes);
  await atomic(env.DB,[actorGuard(env.DB,who,!profileImage),...(postId?[publishingGuard(env.DB,who),pendingPostGuard(env,who,postId)]:[]),
    statement(env.DB,"INSERT INTO file_objects(bucket,path,owner_id,post_id,sha256,byte_size,content_type,state) VALUES(?,?,?,?,?,?,?,'uploaded') ON CONFLICT(bucket,path) DO NOTHING",[bucket,path,who.profileId,postId,hash,bytes.length,contentType]),
    guard(env.DB,"EXISTS(SELECT 1 FROM file_objects WHERE bucket=? AND path=? AND owner_id=? AND sha256=? AND state='uploaded')",[bucket,path,who.profileId,hash]),
  ]);
  const written=await env.FILES.put(key,bytes,{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType},customMetadata:{sha256:hash}});
  if(!written){
    const existing=await env.FILES.head(key);
    if(!existing||existing.customMetadata?.sha256!==hash||existing.size!==bytes.length)throw new ApiError(409,'upload_conflict','文件已存在且内容不同。');
  }
  // Visibility is granted only by the later profile update / attachment transaction.
  return {bucket,path,sha256:hash,byte_size:bytes.length,content_type:contentType,display_name:name};
}

async function ownedObject(env:BackendEnv,who:Actor,bucket:string,path:string,postId:string|null){
  objectKey(bucket,path);
  const record=await env.DB.prepare("SELECT * FROM file_objects WHERE bucket=? AND path=? AND owner_id=? AND post_id IS ? AND state='uploaded'").bind(bucket,path,who.profileId,postId).first<Row>();
  if(!record)throw new ApiError(404,'not_found','待验证文件不存在。');
  const file=await env.FILES.get(objectKey(bucket,path));if(!file)throw new ApiError(404,'not_found','上传尚未完成，请重试。');
  const bytes=new Uint8Array(await file.arrayBuffer());
  if(await sha256(bytes)!==record.sha256||bytes.length!==record.byte_size)throw new ApiError(422,'file_integrity','文件校验失败。');
  return {record,bytes};
}

export async function validateImages(env:BackendEnv,who:Actor,body:Row){
  const postId=uuid(body.post_id),fullPath=text(body.full_path,512),thumbPath=text(body.thumbnail_path,512);
  const [full,thumb]=await Promise.all([ownedObject(env,who,imageBucket,fullPath,postId),ownedObject(env,who,imageBucket,thumbPath,postId)]);
  const prefix=`posts/${who.profileId}/${postId}/`;
  if(!fullPath.startsWith(`${prefix}full/`)||!thumbPath.startsWith(`${prefix}thumb/`))throw new ApiError(403,'path_mismatch','图片路径不属于该帖子。');
  const f=validatedImage(full.bytes,1600),t=validatedImage(thumb.bytes,480),id=crypto.randomUUID();
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),pendingPostGuard(env,who,postId),
    statement(env.DB,`INSERT INTO private_community_upload_receipts(id,auth_user_id,profile_id,post_id,full_path,thumbnail_path,full_sha256,thumbnail_sha256,full_size,thumbnail_size,full_width,full_height,thumbnail_width,thumbnail_height)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(full_path) DO NOTHING`,[id,who.authId,who.profileId,postId,fullPath,thumbPath,full.record.sha256 as string,thumb.record.sha256 as string,full.bytes.length,thumb.bytes.length,f.width,f.height,t.width,t.height]),
    statement(env.DB,'SELECT id,auth_user_id,thumbnail_path,expires_at,consumed_at FROM private_community_upload_receipts WHERE full_path=?',[fullPath]),
  ]);
  const receipt=result[result.length-2].results[0];
  if(!receipt||receipt.auth_user_id!==who.authId||receipt.thumbnail_path!==thumbPath||receipt.consumed_at||Date.parse(receipt.expires_at as string)<=Date.now())throw new ApiError(409,'receipt_unavailable','上传验证凭证已使用或过期，请重新上传。');
  return {receipt_id:receipt.id};
}

export async function validateAttachment(env:BackendEnv,who:Actor,body:Row){
  const postId=uuid(body.post_id),path=text(body.object_path,512),name=sanitizedDisplayName(body.display_name),extension=supportedExtension(name);
  if(!name||!extension||!path.startsWith(`posts/${who.profileId}/${postId}/`)||!path.endsWith(`.${extension}`))throw new ApiError(400,'invalid_attachment','附件信息无效。');
  const file=await ownedObject(env,who,attachmentBucket,path,postId),id=crypto.randomUUID();
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),pendingPostGuard(env,who,postId),
    statement(env.DB,`INSERT INTO private_community_attachment_upload_receipts(id,auth_user_id,profile_id,post_id,object_path,display_name,content_type,file_extension,byte_size,sha256)
      VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(object_path) DO NOTHING`,[id,who.authId,who.profileId,postId,path,name,canonicalContentTypes[extension],extension,file.bytes.length,file.record.sha256 as string]),
    statement(env.DB,'SELECT * FROM private_community_attachment_upload_receipts WHERE object_path=?',[path]),
  ]);
  const receipt=result[result.length-2].results[0];
  if(!receipt||receipt.auth_user_id!==who.authId||receipt.consumed_at||Date.parse(receipt.expires_at as string)<=Date.now())throw new ApiError(409,'receipt_unavailable','上传验证凭证已使用或过期，请重新上传。');
  return {receipt_id:receipt.id,byte_size:receipt.byte_size,sha256:receipt.sha256,content_type:receipt.content_type,file_extension:receipt.file_extension};
}

export async function attach(env:BackendEnv,who:Actor,body:Row,kind:'image'|'attachment'){
  const receiptId=uuid(body.receipt_id),id=uuid(body.id),sort=integer(body.sort_order,0,kind==='image'?3:1);
  const receipts=kind==='image'?'private_community_upload_receipts':'private_community_attachment_upload_receipts';
  const table=kind==='image'?'post_images':'post_attachments';
  const receipt=await env.DB.prepare(`SELECT * FROM ${receipts} WHERE id=? AND profile_id=? AND auth_user_id=?`).bind(receiptId,who.profileId,who.authId).first<Row>();
  if(!receipt)throw new ApiError(404,'not_found','验证凭证不存在。');
  const postId=receipt.post_id as string,now=new Date().toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),publishingGuard(env.DB,who),pendingPostGuard(env,who,postId),
    guard(env.DB,`EXISTS(SELECT 1 FROM ${receipts} WHERE id=? AND profile_id=? AND auth_user_id=? AND consumed_at IS NULL AND expires_at>?)`,[receiptId,who.profileId,who.authId,now]),
    guard(env.DB,`(SELECT count(*) FROM ${table} WHERE post_id=?)<(SELECT ${kind==='image'?'expected_image_count':'expected_attachment_count'} FROM posts WHERE id=?)`,[postId,postId]),
    kind==='image'?statement(env.DB,`INSERT INTO post_images(id,post_id,path,thumbnail_path,sort_order,width,height,full_width,full_height,thumbnail_width,thumbnail_height)
      SELECT ?,post_id,full_path,thumbnail_path,?,full_width,full_height,full_width,full_height,thumbnail_width,thumbnail_height FROM ${receipts} WHERE id=?`,[id,sort,receiptId]):
      statement(env.DB,`INSERT INTO post_attachments(id,post_id,path,display_name,content_type,file_extension,byte_size,sha256,sort_order) SELECT ?,post_id,object_path,display_name,content_type,file_extension,byte_size,sha256,? FROM ${receipts} WHERE id=?`,[id,sort,receiptId]),
    statement(env.DB,`UPDATE ${receipts} SET consumed_at=? WHERE id=?`,[now,receiptId]),
    statement(env.DB,`UPDATE file_objects SET state='attached' WHERE post_id=? AND path IN(SELECT ${kind==='image'?'full_path':'object_path'} FROM ${receipts} WHERE id=?${kind==='image'?` UNION SELECT thumbnail_path FROM ${receipts} WHERE id=?`:''})`,[postId,receiptId,...(kind==='image'?[receiptId]:[])]),
    statement(env.DB,`UPDATE posts SET
      image_upload_completed_at=CASE WHEN expected_image_count=(SELECT count(*) FROM post_images WHERE post_id=posts.id) THEN ? ELSE NULL END,
      attachment_upload_completed_at=CASE WHEN expected_attachment_count=(SELECT count(*) FROM post_attachments WHERE post_id=posts.id) THEN ? ELSE NULL END,
      status=CASE WHEN expected_image_count=(SELECT count(*) FROM post_images WHERE post_id=posts.id) AND expected_attachment_count=(SELECT count(*) FROM post_attachments WHERE post_id=posts.id) THEN 'published' ELSE status END,updated_at=? WHERE id=? RETURNING *`,[now,now,now,postId]),
    outbox(env.DB,`campus:${requireCommunity(who)}`),
  ]);
  return {attached:true,post_id:postId,status:result[result.length-3].results[0].status};
}

export async function setProfileImage(env:BackendEnv,who:Actor,body:Row){
  const kind=body.kind;if(kind!=='avatar'&&kind!=='cover')throw new ApiError(400,'invalid_request','图片类型无效。');
  const path=text(body.path,512),prefix=`${kind==='avatar'?'avatars':'profile-covers'}/${who.profileId}/`;
  if(!path.startsWith(prefix))throw new ApiError(403,'path_mismatch','图片不属于当前账号。');
  const file=await ownedObject(env,who,imageBucket,path,null);validatedImage(file.bytes,kind==='avatar'?512:1800);
  await atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,`UPDATE profiles SET ${kind==='avatar'?'avatar_path':'cover_path'}=?,updated_at=? WHERE id=?`,[path,new Date().toISOString().replace('Z','000Z'),who.profileId]),statement(env.DB,"UPDATE file_objects SET state='attached' WHERE bucket=? AND path=?",[imageBucket,path])]);
  return {updated:true,path};
}

export async function readFile(env:BackendEnv,who:Actor,bucket:string,path:string,request:Request){
  const key=objectKey(bucket,path);
  const accessible=await env.DB.prepare(`SELECT f.* FROM file_objects f LEFT JOIN posts p ON p.id=f.post_id WHERE f.bucket=? AND f.path=? AND f.state<>'deleting'
    AND ((f.owner_id=? AND (f.post_id IS NULL OR p.status IN('published','pending_review','hidden'))) OR (f.state='attached' AND p.status='published' AND p.campus_id=? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id))
      OR (f.bucket='community-images' AND f.post_id IS NULL AND EXISTS(SELECT 1 FROM profiles u WHERE u.id=f.owner_id AND (u.avatar_path=f.path OR u.cover_path=f.path) AND (u.community_campus_id=? OR u.campus_id=?)))
      OR (f.bucket='community-banner-assets' AND f.state='attached' AND EXISTS(SELECT 1 FROM community_banners b WHERE b.image_path=f.path AND b.campus_id=? AND b.status='published' AND (b.expires_at IS NULL OR b.expires_at>?))))`).bind(bucket,path,who.profileId,who.campusId,who.profileId,who.campusId,who.campusId,who.campusId,new Date().toISOString().replace('Z','000Z')).first<Row>();
  if(!accessible)throw new ApiError(404,'not_found','文件不存在或无权访问。');
  const object=await env.FILES.get(key,{range:request.headers});if(!object)throw new ApiError(404,'not_found','文件不存在。');
  const headers=new Headers({'Content-Type':accessible.content_type as string,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','ETag':object.httpEtag,'Accept-Ranges':'bytes'});
  if(bucket===attachmentBucket)headers.set('Content-Disposition','attachment');
  if(request.headers.get('if-none-match')===object.httpEtag)return new Response(null,{status:304,headers});
  let status=200;
  if(object.range&&'offset' in object.range){
    const start=object.range.offset??0,length=object.range.length??object.size-start;
    headers.set('Content-Range',`bytes ${start}-${start+length-1}/${object.size}`);headers.set('Content-Length',String(length));status=206;
  }else headers.set('Content-Length',String(object.size));
  return new Response(object.body,{status,headers});
}
