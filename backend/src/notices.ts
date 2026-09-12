import type { Actor, BackendEnv } from './auth';
import { actor, auth } from './auth';
import { actorGuard, atomic, decode, guard, outbox, rows, sessionGuard, statement, type Row } from './db';
import { requireCommunity } from './community';
import { ApiError, integer, text, uuid } from './http';
import { signedMediaURL } from './media-tickets';

const now=()=>new Date().toISOString().replace('Z','000Z');
export async function announcements(env:BackendEnv,who:Actor,url:URL){
  const timestamp=now(),limit=integer(Number(url.searchParams.get('limit')??20),1,100);
  return rows(env.DB,"SELECT a.*,r.read_at FROM site_announcements a LEFT JOIN site_announcement_reads r ON r.announcement_id=a.id AND r.user_id=? WHERE a.campus_id=? AND a.status='published' AND a.published_at<=? AND (a.expires_at IS NULL OR a.expires_at>?) AND r.dismissed_at IS NULL ORDER BY a.published_at DESC,a.id DESC LIMIT ?",[who.authId,who.campusId??who.identityCampus,timestamp,timestamp,limit]);
}
export async function announcementRead(env:BackendEnv,who:Actor,id:string,dismiss=false){
  uuid(id);const timestamp=now();
  await atomic(env.DB,[actorGuard(env.DB,who),guard(env.DB,"EXISTS(SELECT 1 FROM site_announcements WHERE id=? AND campus_id=? AND status='published' AND published_at<=? AND (expires_at IS NULL OR expires_at>?))",[id,who.campusId??who.identityCampus,timestamp,timestamp]),
    statement(env.DB,`INSERT INTO site_announcement_reads(announcement_id,user_id,read_at,dismissed_at) VALUES(?,?,?,?) ON CONFLICT(announcement_id,user_id) DO UPDATE SET read_at=coalesce(site_announcement_reads.read_at,excluded.read_at)${dismiss?',dismissed_at=coalesce(site_announcement_reads.dismissed_at,excluded.dismissed_at)':''}`,[id,who.authId,timestamp,dismiss?timestamp:null]),
  ]);return {updated:true};
}
export async function notificationSettings(env:BackendEnv,who:Actor,body?:Row){
  if(body){
    if(typeof body.muted_all!=='boolean')throw new ApiError(400,'bad_request','通知设置无效。');
    const result=await atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,'INSERT INTO community_notification_settings(user_id,muted_all,updated_at) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET muted_all=excluded.muted_all,updated_at=excluded.updated_at RETURNING *',[who.profileId,body.muted_all?1:0,now()])]);
    return decode('community_notification_settings',result[result.length-2].results[0]);
  }
  const record=(await rows(env.DB,'SELECT * FROM community_notification_settings WHERE user_id=?',[who.profileId]))[0];
  return record?decode('community_notification_settings',record):{user_id:who.profileId,muted_all:false,updated_at:null};
}
export async function dismissNotification(env:BackendEnv,who:Actor,id:string){
  uuid(id);await atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,'UPDATE community_notifications SET dismissed_at=coalesce(dismissed_at,?),is_read=1 WHERE id=? AND recipient_id=?',[now(),id,who.profileId]),outbox(env.DB,`profile:${who.profileId}`)]);return {updated:true};
}
export async function banner(env:BackendEnv,who:Actor){
  const timestamp=now();
  const record=(await rows(env.DB,"SELECT * FROM community_banners WHERE campus_id=? AND status='published' AND published_at<=? AND (expires_at IS NULL OR expires_at>?) ORDER BY published_at DESC,revision DESC,id DESC LIMIT 1",[requireCommunity(who),timestamp,timestamp]))[0];
  if(!record)return null;
  return {...record,signed_image_url:record.image_path?await signedMediaURL(env,who,'community-banner-assets',String(record.image_path)):null};
}
export async function postgraduateSources(env:BackendEnv,who:Actor,url:URL){
  requireCommunity(who);
  return (await rows(env.DB,"SELECT * FROM postgraduate_sources WHERE status='published' ORDER BY updated_at DESC,id LIMIT ?",[integer(Number(url.searchParams.get('limit')??100),1,500)])).map(r=>decode('postgraduate_sources',r));
}
export async function submitFeedback(env:BackendEnv,request:Request,body:Row){
  const session=await auth(env).api.getSession({headers:request.headers,query:{disableRefresh:true}});
  if(!session)throw new ApiError(401,'unauthenticated','请先登录。');
  let who:Actor|null=null;
  try{who=await actor(env,request);}catch(error){if(!(error instanceof ApiError&&error.code==='profile_required'))throw error;}
  const campus=who?.campusId??who?.identityCampus??'general';
  if(body.device_info!=null&&(typeof body.device_info!=='object'||Array.isArray(body.device_info)))throw new ApiError(400,'bad_request','设备信息无效。');
  const device=JSON.stringify(body.device_info??{});if(new TextEncoder().encode(device).length>8192)throw new ApiError(400,'bad_request','设备信息过长。');
  await atomic(env.DB,[sessionGuard(env.DB,session.user.id,session.session.id),
    statement(env.DB,'INSERT INTO feedback_submissions(user_id,campus_id,issue_type,body,contact,device_info) VALUES(?,?,?,?,?,?)',[who?.profileId??null,campus,text(body.issue_type,40),text(body.body,4000),text(body.contact,200,false)||null,device]),
  ]);return {submitted:true};
}
