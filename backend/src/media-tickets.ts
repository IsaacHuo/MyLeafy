import type { Actor, BackendEnv } from './auth';
import { ApiError } from './http';

function base64(bytes:Uint8Array){return btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');}
function unbase64(value:string){return Uint8Array.from(atob(value.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));}
async function signingKey(env:BackendEnv){
  if(!env.MEDIA_SIGNING_SECRET||env.MEDIA_SIGNING_SECRET.length<32)throw new ApiError(503,'media_unavailable','文件服务尚未配置。');
  return crypto.subtle.importKey('raw',new TextEncoder().encode(env.MEDIA_SIGNING_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
}
export async function signedMediaURL(env:BackendEnv,who:Actor,bucket:string,path:string){
  const payload=base64(new TextEncoder().encode(JSON.stringify({session_id:who.sessionId,profile_id:who.profileId,bucket,path,expires:Math.min(who.sessionExpires,Date.now()+600000)})));
  const signature=base64(new Uint8Array(await crypto.subtle.sign('HMAC',await signingKey(env),new TextEncoder().encode(payload))));
  const url=new URL('/v1/files/download',env.API_ORIGIN);url.searchParams.set('ticket',`${payload}.${signature}`);return url.toString();
}
export async function verifyMediaTicket(env:BackendEnv,ticket:string){
  if(ticket.length>4000)throw new ApiError(403,'invalid_ticket','下载凭证无效。');
  const [payload,signature,extra]=ticket.split('.');
  const key=await signingKey(env);
  let claim:{session_id:string;profile_id:string;bucket:string;path:string;expires:number};
  try{
    if(extra||!await crypto.subtle.verify('HMAC',key,unbase64(signature),new TextEncoder().encode(payload)))throw new Error();
    claim=JSON.parse(new TextDecoder().decode(unbase64(payload)));
    if(typeof claim.expires!=='number'||claim.expires<=Date.now()||typeof claim.session_id!=='string'||typeof claim.profile_id!=='string'||typeof claim.bucket!=='string'||typeof claim.path!=='string')throw new Error();
  }catch{throw new ApiError(403,'invalid_ticket','下载凭证已失效，请重新打开内容。');}
  const record=await env.DB.prepare(`SELECT s.userId,s.expiresAt,p.id,p.campus_id AS identity_campus,
    CASE WHEN c.status='active' AND c.is_community_enabled=1 AND (p.campus_id='bjfu' OR p.community_access_status='approved') THEN c.id ELSE NULL END AS campus_id
    FROM identity_session s JOIN auth_users u ON u.id=s.userId JOIN profile_auth_links l ON l.auth_user_id=s.userId JOIN profiles p ON p.id=l.profile_id
    LEFT JOIN campuses c ON c.id=CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END
    WHERE s.id=? AND p.id=? AND s.expiresAt>? AND (u.banned_until IS NULL OR u.banned_until<=?)`).bind(claim.session_id,claim.profile_id,Date.now(),new Date().toISOString().replace('Z','000Z')).first<{userId:string;expiresAt:number;id:string;identity_campus:string;campus_id:string|null}>();
  if(!record)throw new ApiError(403,'invalid_ticket','下载凭证已失效，请重新登录。');
  const who:Actor={authId:record.userId,profileId:record.id,identityCampus:record.identity_campus,campusId:record.campus_id,sessionId:claim.session_id,sessionExpires:record.expiresAt};
  return {who,bucket:claim.bucket,path:claim.path};
}
