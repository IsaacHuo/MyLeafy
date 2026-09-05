import { hash } from 'bcryptjs';
import type { BackendEnv } from './auth';
import { adminGuard, audit, type AdminContext, type AdminRole } from './admin-auth';
import { adminHydrate } from './admin-data';
import { atomic, decode, encode, guard, outbox, statement, type Bind, type Row } from './db';
import { ApiError, integer, text, uuid } from './http';

export function choice(value:unknown,allowed:string[],fallback?:string){
  const result=value==null?fallback:value;
  if(typeof result!=='string'||!allowed.includes(result))throw new ApiError(400,'bad_request','状态或类型无效。');
  return result;
}
export function dateValue(value:unknown){
  if(value==null||value==='')return null;
  const date=new Date(text(value,40));if(!Number.isFinite(date.getTime()))throw new ApiError(400,'bad_request','日期无效。');
  return date.toISOString().replace('Z','000Z');
}
export function arrayValue(value:unknown){
  let result=value;
  if(typeof result==='string'){try{result=JSON.parse(result);}catch{throw new ApiError(400,'bad_request','请输入有效 JSON 数组。');}}
  if(!Array.isArray(result))throw new ApiError(400,'bad_request','字段必须是数组。');return result;
}
export function booleanValue(value:unknown,fallback=false){
  if(value==null)return fallback;
  if(typeof value!=='boolean')throw new ApiError(400,'bad_request','布尔字段无效。');return value;
}
export async function commitAdmin(env:BackendEnv,context:AdminContext,action:string,table:string,id:string|null,operations:D1PreparedStatement[],role:AdminRole='operator'){
  const result=await atomic(env.DB,[adminGuard(env,context,role),...operations,audit(env,context,action,table,id)]);
  return result.flatMap(r=>r.results);
}
export function updateStatement(env:BackendEnv,table:string,id:Bind,payload:Row){
  const encoded=encode(table,payload),keys=Object.keys(encoded);
  return statement(env.DB,`UPDATE ${table} SET ${keys.map(key=>`"${key}"=?`).join(',')} WHERE id=? RETURNING *`,[...keys.map(key=>encoded[key] as Bind),id]);
}
export function insertStatement(env:BackendEnv,table:string,payload:Row){
  const encoded=encode(table,payload),keys=Object.keys(encoded);
  return statement(env.DB,`INSERT INTO ${table}(${keys.map(key=>`"${key}"`).join(',')}) VALUES(${keys.map(()=>'?').join(',')}) RETURNING *`,keys.map(key=>encoded[key] as Bind));
}

export async function upsertCatalog(env:BackendEnv,context:AdminContext,action:string,params:Row){
  const table=({upsertTeacher:'teachers',upsertCourse:'course_catalog',upsertDish:'dish_catalog'} as Record<string,string>)[action];
  const id=params.id==null?null:integer(Number(params.id),1,Number.MAX_SAFE_INTEGER);
  const campus=text(params.campusID??params.campus_id,64,false)||null;
  if(!id&&!campus)throw new ApiError(400,'bad_request','新增目录记录前必须选择具体学校。');
  const payload:Row={name:text(params.name,200),status:choice(params.status,['published','hidden'],'published'),updated_at:new Date().toISOString().replace('Z','000Z')};
  if(campus)payload.campus_id=campus;
  if(table==='dish_catalog')payload.location=text(params.location,200);else payload.unit=text(params.unit,200);
  if(table==='course_catalog'){
    const credit=Math.round(Number(params.credit??0)*10)/10;
    if(!Number.isFinite(credit)||credit<0||credit>999.9)throw new ApiError(400,'bad_request','学分必须在 0–999.9 之间。');
    payload.category=text(params.category??'公选课',100);payload.credit=credit;
  }
  const result=await commitAdmin(env,context,action,table,id==null?null:String(id),[
    ...(id?[guard(env.DB,`EXISTS(SELECT 1 FROM ${table} WHERE id=?)`,[id])]:[]),
    id?updateStatement(env,table,id,payload):insertStatement(env,table,payload),
  ]);
  return decode(table,result[0]);
}
export async function setCatalogStatus(env:BackendEnv,context:AdminContext,action:string,params:Row){
  const table=({setTeacherStatus:'teachers',setCourseStatus:'course_catalog',setDishStatus:'dish_catalog',setPostgraduateSourceStatus:'postgraduate_sources'} as Record<string,string>)[action];
  const id=table==='postgraduate_sources'?uuid(params.id):integer(Number(params.id),1,Number.MAX_SAFE_INTEGER);
  const status=choice(params.status,table==='postgraduate_sources'?['published','hidden','archived']:['published','hidden']);
  const result=await commitAdmin(env,context,action,table,String(id),[guard(env.DB,`EXISTS(SELECT 1 FROM ${table} WHERE id=?)`,[id]),updateStatement(env,table,id,{status,updated_at:new Date().toISOString().replace('Z','000Z')})]);
  return decode(table,result[0]);
}

export async function moderate(env:BackendEnv,context:AdminContext,action:string,params:Row){
  const table=action.includes('Comment')?'comments':action.includes('Poll')?'community_polls':'posts';
  const ids=Array.isArray(params.ids)?params.ids.map(uuid):[uuid(params.id)];
  if(!ids.length||ids.length>50)throw new ApiError(400,'bad_request','一次最多操作 50 条内容。');
  const unique=[...new Set(ids)],slots=unique.map(()=>'?').join(','),status=choice(params.status,['published','hidden']),reason=text(params.reason,1000,false)||null,now=new Date().toISOString().replace('Z','000Z');
  const operations=[guard(env.DB,`(SELECT count(*) FROM ${table} WHERE id IN(${slots}) AND status<>'deleted'${table==='posts'?" AND status<>'pending_review'":''})=?`,[...unique,unique.length]),
    statement(env.DB,`UPDATE ${table} SET status=?,moderated_by=?,moderated_at=?,moderation_reason=?,updated_at=?${table==='posts'?',media_cleanup_hold=?,media_purge_after=NULL':''} WHERE id IN(${slots}) RETURNING *`,[status,context.id,now,reason,now,...(table==='posts'?[status==='hidden'?1:0]:[]),...unique])];
  if(table==='comments')operations.push(statement(env.DB,`UPDATE posts SET comment_count=(SELECT count(*) FROM comments WHERE post_id=posts.id AND status='published') WHERE id IN(SELECT post_id FROM comments WHERE id IN(${slots}))`,unique));
  if(table==='posts'||table==='community_polls')operations.push(statement(env.DB,`INSERT INTO change_outbox(id,room) SELECT lower(hex(randomblob(16))),'campus:'||campus_id FROM ${table} WHERE id IN(${slots}) GROUP BY campus_id`,unique));
  const result=await commitAdmin(env,context,action,table,unique.length===1?unique[0]:null,operations);
  const items=await adminHydrate(env,context,table,result);
  return action.startsWith('bulk')?{requested:ids.length,updated:items.length,items}:items[0];
}
export async function retryPostPublish(env:BackendEnv,context:AdminContext,params:Row){
  const id=uuid(params.id),now=new Date().toISOString().replace('Z','000Z');
  const result=await commitAdmin(env,context,'retryPostPublish','posts',id,[
    guard(env.DB,"EXISTS(SELECT 1 FROM posts p WHERE p.id=? AND p.status='pending_review' AND p.expected_image_count>0 AND p.expected_image_count=(SELECT count(*) FROM post_images WHERE post_id=p.id) AND p.expected_attachment_count=(SELECT count(*) FROM post_attachments WHERE post_id=p.id))",[id]),
    statement(env.DB,"UPDATE posts SET status='published',image_upload_completed_at=?,attachment_upload_completed_at=?,updated_at=?,media_cleanup_hold=0,media_purge_after=NULL WHERE id=? RETURNING *",[now,now,now,id]),
    statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'campus:'||campus_id FROM posts WHERE id=?",[crypto.randomUUID(),id]),
  ]);return (await adminHydrate(env,context,'posts',result))[0];
}
export async function reviewPollDeletion(env:BackendEnv,context:AdminContext,params:Row){
  const id=uuid(params.id),status=choice(params.status,['approved','rejected']),reason=text(params.reason,300,false)||null;
  const result=await commitAdmin(env,context,'reviewPollDeletion','community_polls',id,[
    guard(env.DB,"EXISTS(SELECT 1 FROM community_polls WHERE id=? AND deletion_status='pending' AND status<>'deleted')",[id]),
    statement(env.DB,`UPDATE community_polls SET deletion_status=?,deletion_reviewed_by=?,deletion_reviewed_at=?,deletion_review_reason=?${status==='approved'?",status='deleted'":''} WHERE id=? RETURNING *`,[status,context.id,new Date().toISOString().replace('Z','000Z'),reason,id]),
    statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'campus:'||campus_id FROM community_polls WHERE id=?",[crypto.randomUUID(),id]),
  ]);return decode('community_polls',result[0]);
}
export async function mute(env:BackendEnv,context:AdminContext,params:Row,enabled:boolean){
  const id=uuid(params.id),until=enabled?dateValue(params.mutedUntil??params.muted_until):null;
  if(enabled&&(!until||Date.parse(until)<=Date.now()))throw new ApiError(400,'bad_request','禁言截止时间必须晚于当前时间。');
  const result=await commitAdmin(env,context,enabled?'muteProfile':'unmuteProfile','profiles',id,[
    guard(env.DB,'EXISTS(SELECT 1 FROM profiles WHERE id=?)',[id]),
    updateStatement(env,'profiles',id,{muted_until:until,muted_reason:enabled?text(params.reason??'Muted by admin',1000):null,muted_by:enabled?context.id:null,muted_at:enabled?new Date().toISOString().replace('Z','000Z'):null}),
  ]);return (await adminHydrate(env,context,'profiles',result))[0];
}

export async function upsertRuntime(env:BackendEnv,context:AdminContext,params:Row,calendar=false){
  const table=calendar?'national_calendar_runtime_configs':'semester_runtime_configs',now=new Date().toISOString().replace('Z','000Z'),isActive=booleanValue(params.isActive??params.is_active),id=params.id==null?null:uuid(params.id);
  const payload:Row={is_active:isActive,updated_by:context.id,updated_at:now};
  if(calendar){payload.year=integer(Number(params.year),2000,2100);payload.holidays=arrayValue(params.holidays);payload.solar_terms=arrayValue(params.solarTerms??params.solar_terms);}
  else{
    payload.campus_id=text(params.campusID??params.campus_id??'bjfu',64);payload.semester_id=text(params.semesterID??params.semester_id,64);
    const date=text(params.semesterStartDate??params.semester_start_date,10);
    const parsed=new Date(`${date}T00:00:00Z`);
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==date)throw new ApiError(400,'bad_request','学期首日无效。');
    payload.semester_start_date=date;payload.supported_weeks=integer(Number(params.supportedWeeks??params.supported_weeks??20),1,30);
    if(payload.campus_id==='bjfu'&&payload.supported_weeks!==20)throw new ApiError(400,'bad_request','北林课表固定保留 20 周。');
    payload.graduate_timetable_term_code=text(params.graduateTimetableTermCode??params.graduate_timetable_term_code,100);payload.calendar_events=arrayValue(params.calendarEvents??params.calendar_events??[]);
  }
  const encoded=encode(table,payload),keys=Object.keys(encoded),natural=calendar?'year=?':'campus_id=? AND semester_id=?',naturalValues:Bind[]=calendar?[payload.year as number]:[payload.campus_id as string,payload.semester_id as string];
  const operations:D1PreparedStatement[]=[];
  if(isActive)operations.push(statement(env.DB,`UPDATE ${table} SET is_active=0 WHERE is_active=1${calendar?'':' AND campus_id=?'}`,calendar?[]:[payload.campus_id as string]));
  operations.push(statement(env.DB,`INSERT INTO ${table}(id,created_by,${keys.map(k=>`"${k}"`).join(',')}) VALUES(coalesce(?,(SELECT id FROM ${table} WHERE ${natural}),?),?,${keys.map(()=>'?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${keys.map(k=>`"${k}"=excluded."${k}"`).join(',')} RETURNING *`,[id,...naturalValues,crypto.randomUUID(),context.id,...keys.map(k=>encoded[k] as Bind)]));
  const result=await commitAdmin(env,context,calendar?'upsertNationalCalendarRuntimeConfig':'upsertSemesterRuntimeConfig',table,id,operations);return decode(table,result[0]);
}

export async function updateAdminAccount(env:BackendEnv,context:AdminContext,action:string,params:Row){
  adminGuard(env,context,'super_admin');
  const creating=action==='createAdmin',id=creating?crypto.randomUUID():uuid(params.id),payload:Row={updated_at:new Date().toISOString().replace('Z','000Z')};
  if(creating||params.username!=null)payload.username=text(params.username,64).toLowerCase();
  if(creating||params.displayName!=null||params.display_name!=null)payload.display_name=text(params.displayName??params.display_name??params.username,120);
  if(creating||params.role!=null)payload.role=choice(params.role,['super_admin','operator','viewer'],'operator');
  if(action==='disableAdmin')payload.active=false;else if(params.active!=null)payload.active=booleanValue(params.active);
  if(creating||typeof params.password==='string'&&params.password.length){
    const password=typeof params.password==='string'?params.password:'';
    if(password.length<8||new TextEncoder().encode(password).length>72)throw new ApiError(400,'bad_request','密码至少 8 个字符且不超过 72 字节。');
    payload.password_hash=await hash(password,12);
  }
  const operations:D1PreparedStatement[]=[];
  if(creating){payload.id=id;payload.created_by=context.id;operations.push(insertStatement(env,'admin_accounts',payload));}
  else{
    operations.push(guard(env.DB,'EXISTS(SELECT 1 FROM admin_accounts WHERE id=?)',[id]));
    if(payload.active===false||payload.role&&payload.role!=='super_admin')operations.push(guard(env.DB,"NOT EXISTS(SELECT 1 FROM admin_accounts WHERE id=? AND role='super_admin' AND active=1) OR (SELECT count(*) FROM admin_accounts WHERE role='super_admin' AND active=1)>1",[id]));
    const securityKeys=['username','password_hash','role','active'].filter(k=>k in payload);
    if(securityKeys.length)operations.push(statement(env.DB,`DELETE FROM admin_sessions WHERE admin_id=? AND EXISTS(SELECT 1 FROM admin_accounts WHERE id=? AND (${securityKeys.map(k=>`${k}<>?`).join(' OR ')}))`,[id,id,...securityKeys.map(k=>typeof payload[k]==='boolean'?(payload[k]?1:0):payload[k] as Bind)]));
    operations.push(updateStatement(env,'admin_accounts',id,payload));
  }
  const result=await commitAdmin(env,context,action,'admin_accounts',id,operations,'super_admin');const account=decode('admin_accounts',result[0]);delete account.password_hash;return account;
}
