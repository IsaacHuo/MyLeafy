import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, rows, statement, type Row } from './db';
import { ApiError, integer, sha256, text, uuid } from './http';
import { publicProfile, requireCommunity } from './community';

function courses(value:unknown){
  if(!Array.isArray(value)||value.length>500)throw new ApiError(400,'invalid_courses','课程数量无效。');
  const allowed=['id','course_name','teacher','room','location','day_of_week','weeks','duration'];
  return value.map((course:Row)=>{
    if(!course||typeof course!=='object'||Object.keys(course).some(key=>!allowed.includes(key)))throw new ApiError(400,'invalid_courses','课表分享只能包含课程字段。');
    const list=(value:unknown,max:number)=>{
      if(!Array.isArray(value)||!value.length||value.length>max)throw new ApiError(400,'invalid_courses','课程周次或节次无效。');
      return [...new Set(value.map(item=>integer(item,1,max)))].sort((a,b)=>a-b);
    };
    return {id:uuid(course.id),course_name:text(course.course_name,200),teacher:text(course.teacher,200,false),room:text(course.room,200,false),location:text(course.location,200,false),day_of_week:integer(course.day_of_week,1,7),weeks:list(course.weeks,60),duration:list(course.duration,24)};
  });
}
function snapshot(row:Row):Row {
  return {...decode('timetable_snapshots',row),calendar_config:typeof row.calendar_config==='string'?JSON.parse(row.calendar_config):null};
}
export function timetableCalendar(value:unknown){
  if(value==null)return null;
  if(typeof value!=='object'||Array.isArray(value))throw new ApiError(400,'invalid_calendar','课表日期与作息无效。');
  const config=value as Row;
  if(Object.keys(config).some(k=>!['semester_start_date','periods'].includes(k)))throw new ApiError(400,'invalid_calendar','课表设置包含未知字段。');
  const start=text(config.semester_start_date,10),date=new Date(`${start}T00:00:00Z`);
  if(!/^\d{4}-\d{2}-\d{2}$/.test(start)||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==start||date.getUTCDay()!==1)throw new ApiError(400,'invalid_calendar','第一周必须从星期一开始。');
  if(!Array.isArray(config.periods)||!config.periods.length||config.periods.length>24)throw new ApiError(400,'invalid_calendar','课表需要 1 至 24 节作息。');
  let previousEnd=-1;
  const periods=config.periods.map((raw:unknown,index:number)=>{
    if(!raw||typeof raw!=='object'||Array.isArray(raw))throw new ApiError(400,'invalid_calendar','节次无效。');
    const slot=raw as Row;
    if(Object.keys(slot).some(k=>!['period','startHour','startMinute','endHour','endMinute'].includes(k)))throw new ApiError(400,'invalid_calendar','节次包含未知字段。');
    const period=integer(slot.period,1,24),startHour=integer(slot.startHour,0,23),startMinute=integer(slot.startMinute,0,59),endHour=integer(slot.endHour,0,23),endMinute=integer(slot.endMinute,0,59);
    const start=startHour*60+startMinute,end=endHour*60+endMinute;
    if(period!==index+1||start>=end||start<previousEnd)throw new ApiError(400,'invalid_calendar','节次必须按顺序排列且不重叠。');
    previousEnd=end;return {period,startHour,startMinute,endHour,endMinute};
  });
  return {semester_start_date:start,periods};
}
export async function publishTimetable(env:BackendEnv,who:Actor,body:Row){
  const campus=requireCommunity(who),semester=text(body.semester_id,64),items=courses(body.courses),calendar=timetableCalendar(body.calendar_config),now=new Date().toISOString().replace('Z','000Z');
  if(calendar&&items.some(c=>Math.max(...c.weeks)>20||Math.max(...c.duration)>calendar.periods.length))throw new ApiError(400,'invalid_calendar','课程超出当前课表的周次或节次。');
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),guard(env.DB,'EXISTS(SELECT 1 FROM profiles WHERE id=? AND is_profile_complete=1)',[who.profileId]),
    statement(env.DB,`INSERT INTO timetable_snapshots(owner_id,campus_id,semester_id,courses,course_count,published_at,calendar_config) VALUES(?,?,?,?,?,?,?)
      ON CONFLICT(owner_id,semester_id) DO UPDATE SET calendar_config=excluded.calendar_config,courses=excluded.courses,course_count=excluded.course_count,published_at=excluded.published_at,updated_at=excluded.published_at,campus_id=excluded.campus_id RETURNING *`,[who.profileId,campus,semester,JSON.stringify(items),items.length,now,calendar==null?null:JSON.stringify(calendar)]),
  ]);
  const record=snapshot(result[result.length-2].results[0]);
  const [owner]=await rows(env.DB,'SELECT * FROM profiles WHERE id=?',[String(record.owner_id)]);
  return {...record,owner:publicProfile(owner,who.profileId)};
}
export async function timetables(env:BackendEnv,who:Actor,url:URL){
  const semester=text(url.searchParams.get('semester_id'),64,false)||null;
  const found=await rows(env.DB,`SELECT s.* FROM timetable_snapshots s WHERE s.campus_id=? AND (? IS NULL OR s.semester_id=?) AND (s.owner_id=? OR EXISTS(SELECT 1 FROM timetable_share_members m WHERE m.owner_id=s.owner_id AND m.viewer_id=? AND m.campus_id=s.campus_id AND m.revoked_at IS NULL)) ORDER BY s.published_at DESC,s.id LIMIT 100`,[requireCommunity(who),semester,semester,who.profileId,who.profileId]);
  if(!found.length)return [];
  const owners=[...new Set(found.map(s=>s.owner_id as string))];
  const profiles=await rows(env.DB,`SELECT * FROM profiles WHERE id IN(${owners.map(()=>'?').join(',')})`,owners);
  return found.map<Row>(s=>({...snapshot(s),owner:publicProfile(profiles.find(p=>p.id===s.owner_id)!,who.profileId)}));
}
export async function invite(env:BackendEnv,who:Actor){
  const campus=requireCommunity(who),alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ234567';
  let code='';while(code.length<12){for(const byte of crypto.getRandomValues(new Uint8Array(24)))if(byte<Math.floor(256/alphabet.length)*alphabet.length&&code.length<12)code+=alphabet[byte%alphabet.length];}
  const id=crypto.randomUUID(),expires=new Date(Date.now()+7*86400000).toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,'EXISTS(SELECT 1 FROM timetable_snapshots WHERE owner_id=? AND campus_id=?)',[who.profileId,campus]),
    statement(env.DB,`INSERT INTO timetable_invites(id,owner_id,campus_id,semester_id,code_hash,expires_at) SELECT ?,owner_id,campus_id,semester_id,?,? FROM timetable_snapshots WHERE owner_id=? AND campus_id=? ORDER BY published_at DESC,id LIMIT 1 RETURNING id,owner_id,semester_id,expires_at,accepted_by,accepted_at,created_at`,[id,await sha256(code),expires,who.profileId,campus]),
  ]);
  return {...result[result.length-2].results[0],code};
}
export async function acceptInvite(env:BackendEnv,who:Actor,body:Row){
  const campus=requireCommunity(who),code=text(body.code,32).replace(/[\s-]/g,'').toUpperCase();
  if(!/^[A-Z0-9]{12}$/.test(code))throw new ApiError(400,'INVALID_INVITE_CODE','邀请码无效。');
  const hash=await sha256(code),now=new Date().toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,`EXISTS(SELECT 1 FROM timetable_invites i JOIN timetable_snapshots s ON s.owner_id=i.owner_id AND s.semester_id=i.semester_id AND s.campus_id=i.campus_id WHERE i.code_hash=? AND i.campus_id=? AND i.expires_at>? AND i.accepted_by IS NULL AND i.owner_id<>?)`,[hash,campus,now,who.profileId]),
    statement(env.DB,`INSERT INTO timetable_share_members(owner_id,viewer_id,campus_id) SELECT owner_id,?,campus_id FROM timetable_invites WHERE code_hash=? AND campus_id=?
      ON CONFLICT(owner_id,viewer_id) DO UPDATE SET campus_id=excluded.campus_id,revoked_at=NULL,updated_at=?`,[who.profileId,hash,campus,now]),
    statement(env.DB,'UPDATE timetable_invites SET accepted_by=?,accepted_at=? WHERE code_hash=? AND campus_id=?',[who.profileId,now,hash,campus]),
    statement(env.DB,'SELECT s.* FROM timetable_snapshots s JOIN timetable_invites i ON i.owner_id=s.owner_id AND i.semester_id=s.semester_id AND i.campus_id=s.campus_id WHERE i.code_hash=? AND i.campus_id=?',[hash,campus]),
  ]);
  const record=snapshot(result[result.length-2].results[0]);
  const [owner]=await rows(env.DB,'SELECT * FROM profiles WHERE id=?',[String(record.owner_id)]);
  return {...record,owner:publicProfile(owner,who.profileId)};
}
export async function shareMembers(env:BackendEnv,who:Actor,incoming=false):Promise<Row[]>{
  const members=await rows(env.DB,`SELECT * FROM timetable_share_members WHERE ${incoming?'viewer_id':'owner_id'}=? AND campus_id=? AND revoked_at IS NULL ORDER BY created_at DESC,id`,[who.profileId,requireCommunity(who)]);
  const ids=[...new Set(members.flatMap(m=>[m.viewer_id as string,m.owner_id as string]))],profiles:Row[]=[];
  for(let i=0;i<ids.length;i+=80)profiles.push(...await rows(env.DB,`SELECT * FROM profiles WHERE id IN(${ids.slice(i,i+80).map(()=>'?').join(',')})`,ids.slice(i,i+80)));
  return members.map(m=>({...m,viewer:publicProfile(profiles.find(p=>p.id===m.viewer_id)!,who.profileId),owner:publicProfile(profiles.find(p=>p.id===m.owner_id)!,who.profileId)}));
}
export async function ownedInvites(env:BackendEnv,who:Actor,url:URL){
  const semester=text(url.searchParams.get('semester_id'),64,false)||null;
  return rows(env.DB,'SELECT id,owner_id,semester_id,expires_at,accepted_by,accepted_at,created_at FROM timetable_invites WHERE owner_id=? AND campus_id=? AND (? IS NULL OR semester_id=?) ORDER BY created_at DESC,id LIMIT 20',[who.profileId,requireCommunity(who),semester,semester]);
}
export async function revokeShare(env:BackendEnv,who:Actor,id:string,leaving=false){
  id=uuid(id);const now=new Date().toISOString().replace('Z','000Z');
  await atomic(env.DB,[actorGuard(env.DB,who,true),guard(env.DB,`EXISTS(SELECT 1 FROM timetable_share_members WHERE id=? AND ${leaving?'viewer_id':'owner_id'}=?)`,[id,who.profileId]),statement(env.DB,'UPDATE timetable_share_members SET revoked_at=?,updated_at=? WHERE id=?',[now,now,id])]);
  return {revoked:true};
}
export async function stopSharing(env:BackendEnv,who:Actor){
  const now=new Date().toISOString().replace('Z','000Z');await atomic(env.DB,[actorGuard(env.DB,who,true),
    statement(env.DB,'UPDATE timetable_share_members SET revoked_at=?,updated_at=? WHERE owner_id=? AND revoked_at IS NULL',[now,now,who.profileId]),
    statement(env.DB,'UPDATE timetable_invites SET expires_at=? WHERE owner_id=? AND accepted_by IS NULL AND expires_at>?',[now,who.profileId,now]),
  ]);return {stopped:true};
}
