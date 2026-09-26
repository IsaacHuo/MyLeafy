import { compare } from 'bcryptjs';
import type { BackendEnv } from './auth';
import { atomic, decode, guard, statement, type Row } from './db';
import { ApiError, readJSON, sha256, text } from './http';
import { permissionsForRole } from './admin-permissions';

export type AdminRole='super_admin'|'operator'|'viewer';
export type AdminContext={id:string;role:AdminRole;tokenHash:string;requestId:string;ip:string;userAgent:string|null;expiresAt:string};
const publicFields='id,username,display_name,role,active,last_login_at,created_at,updated_at';

export async function adminLogin(env:BackendEnv,request:Request){
  const body=await readJSON(request),username=text(body.username,64).toLowerCase();
  const password=typeof body.password==='string'?body.password:'';
  if(!password||password.length>1024)throw new ApiError(400,'bad_request','账号或密码格式无效。');
  const ip=request.headers.get('x-leafy-client-ip')??'0.0.0.0',attempt=crypto.randomUUID(),now=new Date().toISOString().replace('Z','000Z'),cutoff=new Date(Date.now()-15*60000).toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[statement(env.DB,`INSERT INTO admin_login_attempts(id,username,ip_address,error_code)
    SELECT ?,?,?,'in_progress' WHERE (SELECT count(*) FROM admin_login_attempts WHERE normalized_username=? AND ip_address=? AND attempted_at>? AND succeeded=0 AND coalesce(error_code,'')<>'rate_limited')<5
      AND (SELECT count(*) FROM admin_login_attempts WHERE ip_address=? AND attempted_at>? AND succeeded=0 AND coalesce(error_code,'')<>'rate_limited')<20 RETURNING id`,[attempt,username,ip,username,ip,cutoff,ip,cutoff])]);
  if(!result[result.length-2].results.length){
    await env.DB.prepare("INSERT INTO admin_login_attempts(username,ip_address,error_code) VALUES(?,?,'rate_limited')").bind(username,ip).run();
    throw new ApiError(429,'rate_limited','登录尝试过于频繁，请稍后再试。',true);
  }
  const account=await env.DB.prepare('SELECT * FROM admin_accounts WHERE username=?').bind(username).first<Row>();
  const matches=account?.active===1&&await compare(password,account.password_hash as string);
  if(!matches){
    await env.DB.prepare("UPDATE admin_login_attempts SET error_code='invalid_credentials' WHERE id=?").bind(attempt).run();
    throw new ApiError(401,'unauthorized','账号或密码错误。');
  }
  const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),n=>n.toString(16).padStart(2,'0')).join(''),tokenHash=await sha256(token),expires=new Date(Date.now()+12*3600000).toISOString().replace('Z','000Z');
  const signedIn=await atomic(env.DB,[
    guard(env.DB,'EXISTS(SELECT 1 FROM admin_accounts WHERE id=? AND active=1 AND password_hash=? AND role=?)',[account!.id as string,account!.password_hash as string,account!.role as string]),
    statement(env.DB,'INSERT INTO admin_sessions(token_hash,admin_id,expires_at) VALUES(?,?,?)',[tokenHash,account!.id as string,expires]),
    statement(env.DB,'UPDATE admin_login_attempts SET succeeded=1,error_code=NULL WHERE id=?',[attempt]),
    statement(env.DB,`UPDATE admin_accounts SET last_login_at=? WHERE id=? RETURNING ${publicFields}`,[now,account!.id as string]),
    statement(env.DB,"INSERT INTO admin_audit_logs(admin_id,action,ip_address,request_id,outcome) VALUES(?,'admin-login',?,?,'success')",[account!.id as string,ip,request.headers.get('x-request-id')??crypto.randomUUID()]),
  ]);
  const admin=decode('admin_accounts',signedIn[signedIn.length-3].results[0]);
  return {token,admin,permissions:permissionsForRole(admin.role as AdminRole),expires_at:expires,session:{expires_at:expires}};
}
export async function authenticateAdmin(env:BackendEnv,request:Request):Promise<AdminContext>{
  const bearer=request.headers.get('authorization')??'';
  if(!/^Bearer [a-f0-9]{64}$/i.test(bearer))throw new ApiError(401,'unauthorized','管理员会话已失效。');
  const tokenHash=await sha256(bearer.slice(7)),now=new Date().toISOString().replace('Z','000Z');
  const session=await env.DB.prepare('SELECT a.id,a.role,s.expires_at FROM admin_sessions s JOIN admin_accounts a ON a.id=s.admin_id WHERE s.token_hash=? AND s.revoked_at IS NULL AND s.expires_at>? AND a.active=1').bind(tokenHash,now).first<{id:string;role:AdminRole;expires_at:string}>();
  if(!session)throw new ApiError(401,'unauthorized','管理员会话已失效。');
  return {id:session.id,role:session.role,expiresAt:session.expires_at,tokenHash,requestId:request.headers.get('x-request-id')??crypto.randomUUID(),ip:request.headers.get('x-leafy-client-ip')??'0.0.0.0',userAgent:request.headers.get('user-agent')};
}
export function adminGuard(env:BackendEnv,context:AdminContext,minimum:AdminRole='viewer'){
  const roles=minimum==='super_admin'?['super_admin']:minimum==='operator'?['super_admin','operator']:['super_admin','operator','viewer'];
  if(!roles.includes(context.role))throw new ApiError(403,'forbidden','无权执行此操作。');
  return guard(env.DB,`EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_accounts a ON a.id=s.admin_id WHERE s.token_hash=? AND a.id=? AND a.active=1 AND s.revoked_at IS NULL AND s.expires_at>? AND a.role IN(${roles.map(()=>'?').join(',')}))`,[context.tokenHash,context.id,new Date().toISOString().replace('Z','000Z'),...roles]);
}
export function audit(env:BackendEnv,context:AdminContext,action:string,targetType:string,targetId:string|null){
  // Do not persist arbitrary action parameters: they can contain passwords or personal data.
  return statement(env.DB,"INSERT INTO admin_audit_logs(admin_id,action,target_type,target_id,ip_address,user_agent,request_id,outcome) VALUES(?,?,?,?,?,?,?,'success')",[context.id,action,targetType,targetId,context.ip,context.userAgent,context.requestId]);
}
export async function adminMe(env:BackendEnv,context:AdminContext){
  const account=await env.DB.prepare(`SELECT ${publicFields} FROM admin_accounts WHERE id=?`).bind(context.id).first<Row>();
  if(!account)throw new ApiError(401,'unauthorized','管理员账号不存在。');
  return {admin:decode('admin_accounts',account),permissions:permissionsForRole(context.role),session:{expires_at:context.expiresAt}};
}
export async function adminLogout(env:BackendEnv,context:AdminContext){
  await atomic(env.DB,[adminGuard(env,context),statement(env.DB,'UPDATE admin_sessions SET revoked_at=? WHERE token_hash=?',[new Date().toISOString().replace('Z','000Z'),context.tokenHash]),audit(env,context,'admin-logout','session',null)]);
  return {success:true};
}
