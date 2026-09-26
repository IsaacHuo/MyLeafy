import type { BackendEnv } from './auth';
import type { AdminContext } from './admin-auth';
import { ApiError } from './http';

const encode=(bytes:Uint8Array)=>btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const decode=(value:string)=>Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));
async function key(env:BackendEnv){
  if(!env.MEDIA_SIGNING_SECRET||env.MEDIA_SIGNING_SECRET.length<32)throw new ApiError(503,'media_unavailable','文件服务尚未配置。');
  return crypto.subtle.importKey('raw',new TextEncoder().encode(`admin-media:${env.MEDIA_SIGNING_SECRET}`),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
}
export async function adminMediaURL(env:BackendEnv,context:AdminContext,bucket:string,path:string){
  const payload=encode(new TextEncoder().encode(JSON.stringify({admin:context.id,session:context.tokenHash,bucket,path,expires:Math.min(Date.parse(context.expiresAt),Date.now()+600000)})));
  const signature=encode(new Uint8Array(await crypto.subtle.sign('HMAC',await key(env),new TextEncoder().encode(payload))));
  const url=new URL('/v1/admin-media',env.API_ORIGIN);url.searchParams.set('ticket',`${payload}.${signature}`);return url.toString();
}
export async function readAdminMedia(env:BackendEnv,ticket:string){
  const signingKey=await key(env);
  let claim:{admin:string;session:string;bucket:string;path:string;expires:number};
  try{
    if(ticket.length>4000)throw new Error();
    const [payload,signature,extra]=ticket.split('.');
    if(extra||!await crypto.subtle.verify('HMAC',signingKey,decode(signature),new TextEncoder().encode(payload)))throw new Error();
    claim=JSON.parse(new TextDecoder().decode(decode(payload)));
    if(!claim||typeof claim.expires!=='number'||claim.expires<=Date.now()||!['community-images','community-attachments','community-banner-assets'].includes(claim.bucket)||typeof claim.path!=='string')throw new Error();
  }catch{throw new ApiError(403,'invalid_ticket','文件预览凭证已失效。');}
  const session=await env.DB.prepare('SELECT 1 ok FROM admin_sessions s JOIN admin_accounts a ON a.id=s.admin_id WHERE s.token_hash=? AND a.id=? AND a.active=1 AND s.revoked_at IS NULL AND s.expires_at>?').bind(claim.session,claim.admin,new Date().toISOString().replace('Z','000Z')).first();
  if(!session)throw new ApiError(403,'invalid_ticket','管理员会话已失效。');
  const file=await env.DB.prepare("SELECT content_type FROM file_objects WHERE bucket=? AND path=? AND state='attached'").bind(claim.bucket,claim.path).first<{content_type:string}>();
  if(!file)throw new ApiError(404,'not_found','文件不存在。');
  const object=await env.FILES.get(`${claim.bucket}/${claim.path}`);
  if(!object)throw new ApiError(404,'not_found','文件不存在。');
  return new Response(object.body,{headers:{'Content-Type':file.content_type,'Content-Length':String(object.size),'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Content-Disposition':file.content_type.startsWith('image/')||file.content_type==='application/pdf'?'inline':'attachment'}});
}
