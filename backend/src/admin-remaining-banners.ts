import type { BackendEnv } from './auth';
import { adminGuard, audit, type AdminContext } from './admin-auth';
import { booleanValue, choice, commitAdmin, dateValue, insertStatement, updateStatement } from './admin-write';
import { atomic, decode, guard, outbox, requireWritable, rows, statement, type Row } from './db';
import { ApiError, integer, readBytes, sha256, text, uuid } from './http';
import { jpegDimensions } from './media-validation';

const bucket='community-banner-assets',maxBytes=2*1024*1024;
const now=()=>new Date().toISOString().replace('Z','000Z');
const routes=['timetable','community','schedule_reports','custom_schedules','timetable_background','profile'];
const key=(path:string)=>`${bucket}/${path}`;
function campusID(value:unknown){const id=text(value,64).toLowerCase();if(!/^[a-z0-9][a-z0-9-]{1,63}$/.test(id)||['all','general','guest'].includes(id))throw new ApiError(400,'bad_request','请先选择具体学校。');return id;}
function base64(bytes:Uint8Array){return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function unbase64(value:string){return Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));}
async function signingKey(env:BackendEnv){
  if(!env.MEDIA_SIGNING_SECRET||env.MEDIA_SIGNING_SECRET.length<32)throw new ApiError(503,'media_unavailable','文件服务尚未配置。');
  return crypto.subtle.importKey('raw',new TextEncoder().encode(`admin-banner-upload:${env.MEDIA_SIGNING_SECRET}`),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
}
export function validateBannerImage(bytes:Uint8Array,mime:string){
  if(!bytes.length||bytes.length>maxBytes)throw new ApiError(413,'payload_too_large','Banner 图片不得超过 2 MB。');
  let dimensions:{width:number;height:number}|null=null;
  if(mime==='image/jpeg')dimensions=jpegDimensions(bytes);
  else if(mime==='image/png'&&bytes.length>=33&&[137,80,78,71,13,10,26,10].every((value,index)=>bytes[index]===value)){
    const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
    if(view.getUint32(8)===13&&new TextDecoder().decode(bytes.subarray(12,16))==='IHDR')dimensions={width:view.getUint32(16),height:view.getUint32(20)};
  }
  if(!dimensions)throw new ApiError(422,'invalid_image','无法读取 Banner 图片尺寸或类型。');
  const {width,height}=dimensions,ratio=width/height;
  if(width<600||height<200||width>4096||height>2048||ratio<1.8||ratio>4.5)throw new ApiError(422,'invalid_image','Banner 图片需为 1.8:1 至 4.5:1，且至少 600×200。');
  return dimensions;
}
export async function prepareCommunityBannerImageUpload(env:BackendEnv,context:AdminContext,params:Row){
  adminGuard(env,context,'operator');const campus=campusID(params.campusID??params.campus_id),mime=choice(params.mimeType??params.mime_type,['image/jpeg','image/png']),size=integer(Number(params.byteSize??params.byte_size),1,maxBytes);
  const id=crypto.randomUUID(),path=`${campus}/pending/${context.id}/${id}.${mime==='image/png'?'png':'jpg'}`,expires=new Date(Math.min(Date.parse(context.expiresAt),Date.now()+600000)).toISOString().replace('Z','000Z');
  const payload=base64(new TextEncoder().encode(JSON.stringify({id,expires:Date.parse(expires)}))),signature=base64(new Uint8Array(await crypto.subtle.sign('HMAC',await signingKey(env),new TextEncoder().encode(payload))));
  await commitAdmin(env,context,'prepareCommunityBannerImageUpload','admin_banner_uploads',id,[
    guard(env.DB,"EXISTS(SELECT 1 FROM campuses WHERE id=? AND status='active' AND is_community_enabled=1)",[campus]),
    statement(env.DB,'INSERT INTO admin_banner_uploads(id,path,admin_id,token_hash,campus_id,mime_type,byte_size,expires_at,created_at) VALUES(?,?,?,?,?,?,?,?,?)',[id,path,context.id,context.tokenHash,campus,mime,size,expires,now()]),
  ]);
  const url=new URL('/api/admin/banner-upload',env.SITE_ORIGIN);url.searchParams.set('ticket',`${payload}.${signature}`);
  return {path,signed_url:url.toString(),max_bytes:maxBytes};
}
async function uploadContext(env:BackendEnv,ticket:string,request:Request,requestId:string){
  if(ticket.length>2000)throw new ApiError(403,'invalid_ticket','上传凭证无效。');
  let id:string;
  try{
    const [payload,signature,extra]=ticket.split('.');
    if(extra||!await crypto.subtle.verify('HMAC',await signingKey(env),unbase64(signature),new TextEncoder().encode(payload)))throw new Error();
    const claim=JSON.parse(new TextDecoder().decode(unbase64(payload)));id=uuid(claim.id);
    if(typeof claim.expires!=='number'||claim.expires<=Date.now())throw new Error();
  }catch{throw new ApiError(403,'invalid_ticket','上传凭证已失效，请重新选择图片。');}
  const [receipt]=await rows(env.DB,`SELECT u.*,a.role,s.expires_at AS session_expires FROM admin_banner_uploads u JOIN admin_accounts a ON a.id=u.admin_id JOIN admin_sessions s ON s.token_hash=u.token_hash AND s.admin_id=a.id WHERE u.id=? AND u.consumed_at IS NULL AND u.expires_at>? AND a.active=1 AND a.role IN('operator','super_admin') AND s.revoked_at IS NULL AND s.expires_at>?`,[id,now(),now()]);
  if(!receipt)throw new ApiError(403,'invalid_ticket','上传凭证已失效，请重新选择图片。');
  const context:AdminContext={id:receipt.admin_id as string,role:receipt.role as AdminContext['role'],tokenHash:receipt.token_hash as string,expiresAt:receipt.session_expires as string,requestId,ip:request.headers.get('x-leafy-client-ip')??'0.0.0.0',userAgent:request.headers.get('user-agent')};
  return {receipt,context};
}
export async function uploadCommunityBanner(env:BackendEnv,request:Request,requestId:string){
  await requireWritable(env.DB);const {receipt,context}=await uploadContext(env,new URL(request.url).searchParams.get('ticket')??'',request,requestId);
  const contentType=request.headers.get('content-type')??'',data=await readBytes(request,maxBytes+65536);
  let bytes:Uint8Array,mime:string;
  if(contentType.startsWith('multipart/form-data')){
    let form:FormData;try{form=await new Response(data,{headers:{'Content-Type':contentType}}).formData();}catch{throw new ApiError(400,'bad_request','上传表单无效。');}
    const file=form.get('');if(!(file instanceof Blob))throw new ApiError(400,'bad_request','上传表单缺少图片。');
    bytes=new Uint8Array(await file.arrayBuffer());mime=file.type;
  }else{bytes=data;mime=contentType.split(';')[0].trim();}
  if(mime!==receipt.mime_type||bytes.length!==receipt.byte_size)throw new ApiError(422,'invalid_image','图片类型或大小与上传声明不一致。');
  validateBannerImage(bytes,mime);const digest=await sha256(bytes),path=receipt.path as string;
  // Commit the live admin/session/receipt guards before R2. The later banner
  // transaction checks them again before making any file visible to clients.
  await atomic(env.DB,[adminGuard(env,context,'operator'),guard(env.DB,'EXISTS(SELECT 1 FROM admin_banner_uploads WHERE id=? AND consumed_at IS NULL AND expires_at>?)',[receipt.id as string,now()]),audit(env,context,'uploadCommunityBannerImage','admin_banner_uploads',receipt.id as string)]);
  const written=await env.FILES.put(key(path),bytes,{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType:mime},customMetadata:{sha256:digest}});
  if(!written){const existing=await env.FILES.head(key(path));if(existing?.customMetadata?.sha256!==digest||existing.size!==bytes.length)throw new ApiError(409,'upload_conflict','图片已存在且内容不同，请重新选择图片。');}
  return {uploaded:true,path};
}
function bannerPayload(params:Row,current?:Row):Row{
  const merged={...current,...params},kind=choice(params.destinationKind??params.destination_kind??current?.destination_kind,['none','community_post','app_route','https_url'],'none');
  let value=text(params.destinationValue??params.destination_value??current?.destination_value,2048,false)||null;
  if(kind==='none')value=null;else if(!value)throw new ApiError(400,'bad_request','请选择有效的 Banner 跳转目标。');
  else if(kind==='community_post')value=uuid(value);
  else if(kind==='app_route')value=choice(value,routes);
  else{
    let url:URL;try{url=new URL(value);}catch{throw new ApiError(400,'bad_request','Banner 网页目标无效。');}
    if(url.protocol!=='https:'||!url.hostname||url.username||url.password)throw new ApiError(400,'bad_request','Banner 网页只允许 HTTPS。');value=url.toString();
  }
  const expires=('expiresAt' in params||'expires_at' in params)?dateValue(params.expiresAt??params.expires_at):current?.expires_at??null;
  if(expires&&Date.parse(String(expires))<=Date.now())throw new ApiError(400,'bad_request','已过期的 Banner 不能发布。');
  return {title:text(merged.title,60),subtitle:text(merged.subtitle,180),destination_kind:kind,destination_value:value,expires_at:expires};
}
function destinationGuard(env:BackendEnv,payload:Row,campus:string){return payload.destination_kind==='community_post'?[guard(env.DB,"EXISTS(SELECT 1 FROM posts WHERE id=? AND campus_id=? AND status='published')",[payload.destination_value as string,campus])]:[];}
type Image={path:string;digest:string;size:number;mime:string;pending?:Row};
async function imageForBanner(env:BackendEnv,context:AdminContext,params:Row,campus:string,id:string,revision:number):Promise<Image|null>{
  const path=text(params.imageUploadPath??params.image_upload_path,512,false);let bytes:Uint8Array,mime:string,pending:Row|undefined;
  if(path){
    [pending]=await rows(env.DB,'SELECT * FROM admin_banner_uploads WHERE path=? AND admin_id=? AND token_hash=? AND campus_id=? AND consumed_at IS NULL AND expires_at>?',[path,context.id,context.tokenHash,campus,now()]);
    if(!pending)throw new ApiError(403,'invalid_ticket','图片上传凭证不属于当前学校或管理员，或已被使用。');
    const object=await env.FILES.get(key(path));if(!object)throw new ApiError(400,'upload_incomplete','图片尚未上传完成。');
    bytes=new Uint8Array(await object.arrayBuffer());mime=pending.mime_type as string;
    if(bytes.length!==pending.byte_size||await sha256(bytes)!==object.customMetadata?.sha256)throw new ApiError(422,'file_integrity','图片校验失败，请重新上传。');
  }else{
    const dataURL=text(params.imageDataURL??params.image_data_url,maxBytes*2,false);if(!dataURL)return null;
    const parsed=/^data:(image\/(?:jpeg|png));base64,([A-Za-z0-9+/=\s]+)$/.exec(dataURL);if(!parsed)throw new ApiError(400,'invalid_image','Banner 图片编码无效。');
    try{bytes=Uint8Array.from(atob(parsed[2].replace(/\s/g,'')),c=>c.charCodeAt(0));}catch{throw new ApiError(400,'invalid_image','Banner 图片编码无效。');}mime=parsed[1];
  }
  validateBannerImage(bytes,mime);const finalPath=`${campus}/${id}/r${revision}-${crypto.randomUUID()}.${mime==='image/png'?'png':'jpg'}`,digest=await sha256(bytes);
  if(!await env.FILES.put(key(finalPath),bytes,{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType:mime,cacheControl:'31536000'},customMetadata:{sha256:digest}}))throw new ApiError(409,'upload_conflict','图片路径发生冲突，请重试。');
  return {path:finalPath,digest,size:bytes.length,mime,pending};
}
function imageOperations(env:BackendEnv,image:Image){return [
  ...(image.pending?[guard(env.DB,'EXISTS(SELECT 1 FROM admin_banner_uploads WHERE id=? AND consumed_at IS NULL AND expires_at>?)',[image.pending.id as string,now()]),statement(env.DB,'UPDATE admin_banner_uploads SET consumed_at=? WHERE id=?',[now(),image.pending.id as string]),statement(env.DB,'INSERT INTO file_delete_jobs(bucket,path) VALUES(?,?) ON CONFLICT DO NOTHING',[bucket,image.pending.path as string])]:[]),
  statement(env.DB,"INSERT INTO file_objects(bucket,path,sha256,byte_size,content_type,state) VALUES(?,?,?,?,?,'attached')",[bucket,image.path,image.digest,image.size,image.mime]),
];}
export async function saveCommunityBanner(env:BackendEnv,context:AdminContext,params:Row,creating:boolean){
  adminGuard(env,context,'operator');await requireWritable(env.DB);const id=creating?crypto.randomUUID():uuid(params.id),date=now();
  const current=creating?undefined:(await rows(env.DB,'SELECT * FROM community_banners WHERE id=?',[id]))[0];
  if(!creating&&!current)throw new ApiError(404,'not_found','Banner 不存在。');
  const campus=campusID(params.campusID??params.campus_id??current?.campus_id);
  if(current&&campus!==current.campus_id)throw new ApiError(400,'bad_request','Banner 所属学校不可更改。');
  const payload=bannerPayload(params,current),revision=creating?1:Number(current!.revision)+1;
  const image=await imageForBanner(env,context,params,campus,id,revision),remove=booleanValue(params.removeImage??params.remove_image);
  const imagePath=image?.path??(remove?null:current?.image_path??null);
  const operations=[guard(env.DB,"EXISTS(SELECT 1 FROM campuses WHERE id=? AND status='active' AND is_community_enabled=1)",[campus]),...destinationGuard(env,payload,campus),...(image?imageOperations(env,image):[])];
  if(current)operations.push(guard(env.DB,'EXISTS(SELECT 1 FROM community_banners WHERE id=? AND revision=?)',[id,current.revision as number]));
  if(creating)operations.push(statement(env.DB,"UPDATE community_banners SET status='archived',updated_by=?,updated_at=? WHERE campus_id=? AND status='published'",[context.id,date,campus]));
  const data={...payload,image_path:imagePath,revision,updated_by:context.id,updated_at:date,status:creating?'published':current?.status==='published'?'draft':current?.status,published_at:creating?date:current?.status==='published'?null:current?.published_at};
  operations.push(creating?insertStatement(env,'community_banners',{...data,id,campus_id:campus,created_by:context.id}):updateStatement(env,'community_banners',id,data));
  if(current?.image_path&&current.image_path!==imagePath)operations.push(statement(env.DB,'INSERT INTO file_delete_jobs(bucket,path) VALUES(?,?) ON CONFLICT DO NOTHING',[bucket,current.image_path as string]),statement(env.DB,"UPDATE file_objects SET state='deleting' WHERE bucket=? AND path=?",[bucket,current.image_path as string]));
  operations.push(outbox(env.DB,`campus:${campus}`));
  try{const result=await commitAdmin(env,context,creating?'createCommunityBanner':'updateCommunityBanner','community_banners',id,operations);return decode('community_banners',result.find(row=>row.id===id)!);}
  catch(error){if(image)await env.FILES.delete(key(image.path));throw error;}
}
export async function publishCommunityBanner(env:BackendEnv,context:AdminContext,params:Row){
  adminGuard(env,context,'operator');const id=uuid(params.id),[current]=await rows(env.DB,'SELECT * FROM community_banners WHERE id=?',[id]);
  if(!current)throw new ApiError(404,'not_found','Banner 不存在。');const date=now(),payload=bannerPayload({},current);
  if(current.image_path){
    const [file]=await rows(env.DB,"SELECT * FROM file_objects WHERE bucket=? AND path=? AND state='attached'",[bucket,current.image_path as string]),object=await env.FILES.get(key(current.image_path as string));
    if(!file||!object)throw new ApiError(422,'file_integrity','Banner 图片不存在，请重新上传。');
    const bytes=new Uint8Array(await object.arrayBuffer());if(bytes.length!==file.byte_size||await sha256(bytes)!==file.sha256)throw new ApiError(422,'file_integrity','Banner 图片校验失败，请重新上传。');validateBannerImage(bytes,file.content_type as string);
  }
  const result=await commitAdmin(env,context,'publishCommunityBanner','community_banners',id,[guard(env.DB,'EXISTS(SELECT 1 FROM community_banners WHERE id=? AND revision=? AND (expires_at IS NULL OR expires_at>?))',[id,current.revision as number,date]),...destinationGuard(env,payload,current.campus_id as string),
    statement(env.DB,"UPDATE community_banners SET status='archived',updated_by=?,updated_at=? WHERE campus_id=? AND status='published' AND id<>?",[context.id,date,current.campus_id as string,id]),
    updateStatement(env,'community_banners',id,{status:'published',published_at:date,updated_by:context.id,updated_at:date}),outbox(env.DB,`campus:${current.campus_id}`)]);
  return decode('community_banners',result[0]);
}
export async function archiveCommunityBanner(env:BackendEnv,context:AdminContext,params:Row){
  const id=uuid(params.id);const result=await commitAdmin(env,context,'archiveCommunityBanner','community_banners',id,[guard(env.DB,'EXISTS(SELECT 1 FROM community_banners WHERE id=?)',[id]),updateStatement(env,'community_banners',id,{status:'archived',updated_by:context.id,updated_at:now()}),statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'campus:'||campus_id FROM community_banners WHERE id=?",[crypto.randomUUID(),id])]);return decode('community_banners',result[0]);
}
