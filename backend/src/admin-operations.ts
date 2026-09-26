import type { BackendEnv } from './auth';
import type { AdminContext } from './admin-auth';
import { adminHydrate } from './admin-data';
import { choice, dateValue, booleanValue, commitAdmin, insertStatement, updateStatement } from './admin-write';
import { decode, guard, rows, statement, type Bind, type Row } from './db';
import { ApiError, integer, text, uuid } from './http';

const now=()=>new Date().toISOString().replace('Z','000Z');

export async function updateFeedback(env:BackendEnv,context:AdminContext,params:Row){
  const id=uuid(params.id);
  const result=await commitAdmin(env,context,'updateFeedback','feedback',id,[
    guard(env.DB,'EXISTS(SELECT 1 FROM feedback_submissions WHERE id=?)',[id]),
    updateStatement(env,'feedback_submissions',id,{status:choice(params.status,['open','reviewed','closed']),admin_note:text(params.adminNote??params.admin_note,4000,false)||null,reviewed_by:context.id,reviewed_at:now()}),
  ]);
  return decode('feedback_submissions',result[0]);
}

export async function revokeAdminSession(env:BackendEnv,context:AdminContext,params:Row){
  const id=text(params.id,64);
  if(!/^[a-f0-9]{64}$/.test(id))throw new ApiError(400,'bad_request','会话标识无效。');
  const result=await commitAdmin(env,context,'revokeAdminSession','session',id,[
    guard(env.DB,'EXISTS(SELECT 1 FROM admin_sessions WHERE token_hash=? AND revoked_at IS NULL)',[id]),
    statement(env.DB,'UPDATE admin_sessions SET revoked_at=? WHERE token_hash=? RETURNING token_hash AS id,admin_id,revoked_at',[now(),id]),
  ],'super_admin');
  return result[0];
}

export async function deleteRating(env:BackendEnv,context:AdminContext,params:Row,dish=false){
  const target=dish?'dish':'teacher',table=dish?'dish_catalog':'teachers',ratings=`${target}_ratings`,key=`${target}_id`;
  const id=integer(Number(params[dish?'dishID':'teacherID']??params[key]),1,Number.MAX_SAFE_INTEGER),user=uuid(params.userID??params.user_id);
  const result=await commitAdmin(env,context,dish?'deleteDishRating':'deleteTeacherRating',`${target}_rating`,`${target}:${id}:${user}`,[
    guard(env.DB,`EXISTS(SELECT 1 FROM ${ratings} WHERE ${key}=? AND user_id=?)`,[id,user]),
    statement(env.DB,`DELETE FROM ${ratings} WHERE ${key}=? AND user_id=? RETURNING *`,[id,user]),
    statement(env.DB,`UPDATE ${table} SET rating_count=(SELECT count(*) FROM ${ratings} WHERE ${key}=?),rating_average=coalesce((SELECT ((sum(stars)*20+count(*))/(2*count(*)))/10.0 FROM ${ratings} WHERE ${key}=?),0),${[1,2,3,4,5].map(star=>`rating_${star}_count=(SELECT count(*) FROM ${ratings} WHERE ${key}=? AND stars=${star})`).join(',')},updated_at=? WHERE id=?`,[id,id,id,id,id,id,id,now(),id]),
  ]);
  return {...result[0],id:`${target}:${id}:${user}`,target};
}

export async function announcement(env:BackendEnv,context:AdminContext,params:Row,creating=false){
  const id=creating?crypto.randomUUID():uuid(params.id),current=creating?null:(await rows(env.DB,'SELECT * FROM site_announcements WHERE id=?',[id]))[0];
  if(!creating&&!current)throw new ApiError(404,'not_found','公告不存在。');
  const payload:Row={updated_by:context.id,updated_at:now()};
  for(const [key,max]of [['title',120],['body',4000]] as const)if(creating||key in params)payload[key]=text(params[key],max);
  if(creating||'status'in params)payload.status=choice(params.status,['draft','published','archived'],'draft');
  if(creating||'level'in params)payload.level=choice(params.level,['info','warning','urgent'],'info');
  for(const [camel,snake]of [['publishedAt','published_at'],['expiresAt','expires_at']])if(camel in params||snake in params)payload[snake]=dateValue(params[snake]??params[camel]);
  const campus=text(params.campusID??params.campus_id,64,false);if(campus&&campus!=='all')payload.campus_id=campus;
  if(payload.status==='published'&&!payload.published_at&&!current?.published_at)payload.published_at=now();
  const published=payload.published_at??current?.published_at,expires='expires_at'in payload?payload.expires_at:current?.expires_at;
  if(published&&expires&&Date.parse(String(expires))<=Date.parse(String(published)))throw new ApiError(400,'bad_request','公告截止时间必须晚于发布时间。');
  const result=await commitAdmin(env,context,creating?'createAnnouncement':'updateAnnouncement','announcement',id,creating?
    [insertStatement(env,'site_announcements',{...payload,id,created_by:context.id})]:
    [guard(env.DB,'EXISTS(SELECT 1 FROM site_announcements WHERE id=? AND updated_at=?)',[id,current!.updated_at as string]),updateStatement(env,'site_announcements',id,payload)]);
  return decode('site_announcements',result[0]);
}

export async function pinPost(env:BackendEnv,context:AdminContext,params:Row){
  const post=uuid(params.postID??params.post_id),scope=choice(params.scope,['global','category']),category=scope==='category'?text(params.category,100):null;
  const starts=dateValue(params.startsAt??params.starts_at)??now(),ends=dateValue(params.endsAt??params.ends_at);
  if(ends&&ends<=starts)throw new ApiError(400,'bad_request','置顶截止时间必须晚于开始时间。');
  const priority=integer(Number(params.priority??0),-1000,1000),id=crypto.randomUUID();
  const result=await commitAdmin(env,context,'pinPost','post',post,[
    guard(env.DB,"EXISTS(SELECT 1 FROM posts WHERE id=? AND status='published')",[post]),
    statement(env.DB,"UPDATE community_post_pins SET status='inactive',updated_at=? WHERE post_id=? AND scope=? AND coalesce(category,'')=coalesce(?,'') AND status='active'",[now(),post,scope,category]),
    statement(env.DB,"INSERT INTO community_post_pins(id,post_id,campus_id,scope,category,priority,starts_at,ends_at,reason,created_by) SELECT ?,id,campus_id,?,?,?,?,?,?,? FROM posts WHERE id=? RETURNING *",[id,scope,category,priority,starts,ends,text(params.reason,1000,false)||null,context.id,post]),
    statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'campus:'||campus_id FROM posts WHERE id=?",[crypto.randomUUID(),post]),
  ]);
  return (await adminHydrate(env,context,'community_post_pins',result))[0];
}

export async function unpinPost(env:BackendEnv,context:AdminContext,params:Row){
  const binds:Bind[]=[now()],where=["status='active'"];
  if(params.id){where.push('id=?');binds.push(uuid(params.id));}
  else{where.push('post_id=?');binds.push(uuid(params.postID??params.post_id));
    if(params.scope){const scope=choice(params.scope,['global','category']);where.push('scope=?');binds.push(scope);
      if(scope==='category'&&params.category){where.push('category=?');binds.push(text(params.category,100));}
    }
  }
  const result=await commitAdmin(env,context,'unpinPost','post',null,[
    statement(env.DB,`INSERT INTO change_outbox(id,room) SELECT lower(hex(randomblob(16))),'campus:'||campus_id FROM community_post_pins WHERE ${where.join(' AND ')} GROUP BY campus_id`,binds.slice(1)),
    statement(env.DB,`UPDATE community_post_pins SET status='inactive',updated_at=? WHERE ${where.join(' AND ')} RETURNING *`,binds),
  ]);
  return {updated:result.length,items:await adminHydrate(env,context,'community_post_pins',result)};
}

export async function resolveModerationReport(env:BackendEnv,context:AdminContext,params:Row){
  const id=uuid(params.id),status=choice(params.status,['reviewed','resolved','rejected']),note=text(params.resolutionNote??params.resolution_note??status,4000);
  const hide=booleanValue(params.hideContent??params.hide_content),mute=booleanValue(params.muteUser??params.mute_user),timestamp=now();
  const until=dateValue(params.mutedUntil??params.muted_until)??new Date(Date.now()+365*86400000).toISOString().replace('Z','000Z');
  if(mute&&until<=timestamp)throw new ApiError(400,'bad_request','禁言截止时间必须晚于当前时间。');
  const report=(await rows(env.DB,'SELECT * FROM community_reports WHERE id=?',[id]))[0];
  if(!report)throw new ApiError(404,'not_found','举报不存在。');
  const ops=[guard(env.DB,"EXISTS(SELECT 1 FROM community_reports WHERE id=? AND status IN('open','reviewed') AND status=?)",[id,report.status as string])];
  if(hide&&report.target_type==='post'){
    ops.push(statement(env.DB,"UPDATE community_post_pins SET status='inactive',updated_at=? WHERE post_id=? AND status='active'",[timestamp,report.post_id as string]));
    ops.push(statement(env.DB,"UPDATE posts SET status='hidden',moderated_by=?,moderated_at=?,moderation_reason=?,media_cleanup_hold=1,media_purge_after=NULL,updated_at=? WHERE id=? AND status<>'deleted'",[context.id,timestamp,note,timestamp,report.post_id as string]));
  }else if(hide&&report.target_type==='comment'){
    ops.push(statement(env.DB,"UPDATE comments SET status='hidden',moderated_by=?,moderated_at=?,moderation_reason=?,updated_at=? WHERE id=? AND status<>'deleted'",[context.id,timestamp,note,timestamp,report.comment_id as string]));
    ops.push(statement(env.DB,"UPDATE posts SET comment_count=(SELECT count(*) FROM comments WHERE post_id=posts.id AND status='published') WHERE id=(SELECT post_id FROM comments WHERE id=?)",[report.comment_id as string]));
  }
  if(mute&&report.reported_user_id)ops.push(statement(env.DB,'UPDATE profiles SET muted_until=?,muted_reason=?,muted_by=?,muted_at=? WHERE id=?',[until,text(params.mutedReason??params.muted_reason??'Community report upheld',1000),context.id,timestamp,report.reported_user_id as string]));
  if(hide)ops.push(statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'campus:'||campus_id FROM posts WHERE id=?",[crypto.randomUUID(),report.post_id as string|null]));
  ops.push(updateStatement(env,'community_reports',id,{status,resolved_by:context.id,resolved_at:timestamp,resolution_note:note}));
  return (await adminHydrate(env,context,'community_reports',await commitAdmin(env,context,'resolveModerationReport','report',id,ops)))[0];
}
