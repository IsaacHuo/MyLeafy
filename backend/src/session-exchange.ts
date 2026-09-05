import { auth, type BackendEnv } from './auth';
import { atomic, guard, statement } from './db';
import { ApiError, text, uuid } from './http';

function claims(token:string):{sub:string;session_id:string;exp:number;role:string}{
  try{
    const part=token.split('.')[1];
    const result=JSON.parse(atob(part.replace(/-/g,'+').replace(/_/g,'/')));
    uuid(result.sub);uuid(result.session_id);
    if(result.role!=='authenticated'||typeof result.exp!=='number'||result.exp*1000<=Date.now())throw new Error();
    return result;
  }catch{throw new ApiError(401,'legacy_session_invalid','旧登录状态已失效，请重新登录。');}
}
export async function signedSessionToken(secret:string,token:string){
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const signature=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(token)));
  return `${token}.${btoa(String.fromCharCode(...signature)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}`;
}
export async function exchangeSession(env:BackendEnv,body:Record<string,unknown>){
  if(!env.LEGACY_SUPABASE_URL||!env.LEGACY_SUPABASE_PUBLISHABLE_KEY)throw new ApiError(503,'legacy_exchange_unavailable','旧会话迁移尚未配置。');
  const token=text(body.access_token,8192),payload=claims(token);
  const url=new URL('/auth/v1/user',env.LEGACY_SUPABASE_URL);
  if(url.protocol!=='https:')throw new Error('Legacy identity provider requires HTTPS');
  let response:Response;
  try{response=await fetch(url,{headers:{Authorization:`Bearer ${token}`,apikey:env.LEGACY_SUPABASE_PUBLISHABLE_KEY},signal:AbortSignal.timeout(15000)});}
  catch{throw new ApiError(503,'legacy_provider_unavailable','旧认证服务暂时不可访问，请稍后重试。',true);}
  if(!response.ok)throw new ApiError(response.status>=500?503:401,'legacy_session_invalid','旧登录状态无法验证，请重新登录。',response.status>=500);
  const user=await response.json() as {id:string};
  if(user.id!==payload.sub)throw new ApiError(401,'legacy_session_invalid','旧登录状态无效。');
  const migrated=await env.DB.prepare('SELECT u.id FROM identity_user u JOIN auth_users a ON a.id=u.id WHERE u.id=? AND (a.banned_until IS NULL OR a.banned_until<=?)').bind(user.id,new Date().toISOString().replace('Z','000Z')).first();
  if(!migrated)throw new ApiError(409,'identity_not_migrated','账号尚未完成迁移，请稍后重试。');
  const context=await auth(env).$context;
  const session=await context.internalAdapter.createSession(user.id);
  if(!session)throw new Error('Session creation failed');
  try{
    const result=await atomic(env.DB,[
      guard(env.DB,'EXISTS(SELECT 1 FROM identity_session s JOIN auth_users u ON u.id=s.userId WHERE s.id=? AND s.userId=? AND (u.banned_until IS NULL OR u.banned_until<=?))',[session.id,user.id,new Date().toISOString().replace('Z','000Z')]),
      statement(env.DB,'INSERT INTO legacy_session_exchanges(legacy_user_id,legacy_session_id,identity_session_id,created_at) VALUES(?,?,?,?) ON CONFLICT(legacy_user_id,legacy_session_id) DO NOTHING',[user.id,payload.session_id,session.id,new Date().toISOString().replace('Z','000Z')]),
      statement(env.DB,'DELETE FROM identity_session WHERE id=? AND NOT EXISTS(SELECT 1 FROM legacy_session_exchanges WHERE identity_session_id=?)',[session.id,session.id]),
      statement(env.DB,'SELECT s.id,s.token,s.expiresAt FROM legacy_session_exchanges x JOIN identity_session s ON s.id=x.identity_session_id WHERE x.legacy_user_id=? AND x.legacy_session_id=? AND s.expiresAt>?',[user.id,payload.session_id,Date.now()]),
    ]);
    const active=result[result.length-2].results[0];
    if(!active)throw new ApiError(401,'session_expired','迁移会话已失效，请重新登录。');
    return {token:await signedSessionToken(env.AUTH_SECRET!,active.token as string),user_id:user.id,expires_at:new Date(active.expiresAt as number).toISOString().replace('Z','000Z')};
  }catch(error){await context.internalAdapter.deleteSession(session.token);throw error;}
}
