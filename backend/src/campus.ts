import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, rows, statement, type Row } from './db';
import { ApiError, integer, sha256, text } from './http';

export async function runtimeConfiguration(env:BackendEnv,url:URL,calendar=false){
  const campus=text(url.searchParams.get('campus_id')??'bjfu',64);
  const result=calendar?await rows(env.DB,'SELECT * FROM national_calendar_runtime_configs WHERE is_active=1 ORDER BY updated_at DESC LIMIT 1'):
    await rows(env.DB,'SELECT * FROM semester_runtime_configs WHERE campus_id=? AND is_active=1 ORDER BY updated_at DESC LIMIT 1',[campus]);
  const table=calendar?'national_calendar_runtime_configs':'semester_runtime_configs';
  const body=JSON.stringify(result.map(row=>decode(table,row)));
  return {body,etag:`"${await sha256(body)}"`};
}
export async function searchCampuses(env:BackendEnv,url:URL){
  const query=text(url.searchParams.get('search'),100,false),normalized=query.toLowerCase().replace(/\s+/g,'');
  const limit=integer(url.searchParams.has('limit')?Number(url.searchParams.get('limit')):20,1,50);
  return rows(env.DB,`SELECT id,display_name,short_name FROM campuses WHERE status='active' AND is_community_enabled=1 AND id NOT IN('bjfu','general') AND (?='' OR instr(normalized_name,?)>0 OR instr(lower(display_name),lower(?))>0 OR instr(lower(short_name),lower(?))>0) ORDER BY CASE WHEN normalized_name=? THEN 0 WHEN instr(normalized_name,?)=1 THEN 1 ELSE 2 END,display_name,id LIMIT ?`,[normalized,normalized,query,query,normalized,normalized,limit]);
}
export async function currentMembership(env:BackendEnv,who:Actor){
  const found=await rows(env.DB,'SELECT * FROM campus_membership_requests WHERE requester_profile_id=? ORDER BY created_at DESC,id DESC LIMIT 1',[who.profileId]);
  return found[0]?decode('campus_membership_requests',found[0]):null;
}
export async function selectCampus(env:BackendEnv,who:Actor,body:Row){
  const campus=text(body.campus_id,64).toLowerCase();
  if(['bjfu','general'].includes(campus)||who.identityCampus==='bjfu')throw new ApiError(400,'COMMUNITY_CAMPUS_NOT_SELECTABLE','该校园不能通过通用账号选择。');
  const now=new Date().toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[actorGuard(env.DB,who),
    guard(env.DB,"EXISTS(SELECT 1 FROM campuses WHERE id=? AND status='active' AND is_community_enabled=1)",[campus]),
    guard(env.DB,"EXISTS(SELECT 1 FROM profiles WHERE id=? AND (community_access_status<>'approved' OR community_campus_id IS NULL)) AND NOT EXISTS(SELECT 1 FROM campus_membership_requests WHERE requester_profile_id=? AND status='pending')",[who.profileId,who.profileId]),
    statement(env.DB,"UPDATE profiles SET campus_id=?,community_campus_id=?,community_access_status='approved',community_school_name=(SELECT display_name FROM campuses WHERE id=?),community_rejection_reason=NULL,community_request_id=NULL,updated_at=? WHERE id=? RETURNING *",[campus,campus,campus,now,who.profileId]),
    statement(env.DB,'UPDATE profile_auth_links SET campus_id=?,last_seen_at=? WHERE profile_id=?',[campus,now,who.profileId]),
  ]);return decode('profiles',result[result.length-3].results[0]);
}
export async function requestMembership(env:BackendEnv,who:Actor,body:Row,change=false){
  if(who.identityCampus==='bjfu')throw new ApiError(403,'forbidden','北林身份不通过通用学校申请流程变更。');
  const id=crypto.randomUUID(),now=new Date().toISOString().replace('Z','000Z');
  const campus=change?text(body.campus_id,64).toLowerCase():null;
  if(campus&&['bjfu','general',who.campusId].includes(campus))throw new ApiError(400,'COMMUNITY_CAMPUS_NOT_SELECTABLE','目标校园无效。');
  const school=change?null:text(body.school_name,100),normalized=school?.toLowerCase().replace(/\s+/g,'')??null;
  const result=await atomic(env.DB,[actorGuard(env.DB,who),
    guard(env.DB,"NOT EXISTS(SELECT 1 FROM campus_membership_requests WHERE requester_profile_id=? AND status='pending')",[who.profileId]),
    guard(env.DB,`EXISTS(SELECT 1 FROM profiles WHERE id=? AND ${change?"community_access_status='approved' AND community_campus_id IS NOT NULL":"(community_access_status<>'approved' OR community_campus_id IS NULL)"})`,[who.profileId]),
    ...(change?[guard(env.DB,"EXISTS(SELECT 1 FROM campuses WHERE id=? AND status='active' AND is_community_enabled=1)",[campus])]:[]),
    change?statement(env.DB,`INSERT INTO campus_membership_requests(id,requester_profile_id,requester_auth_user_id,school_name,normalized_school_name,request_type,requested_campus_id,from_campus_id)
      SELECT ?,?,?,display_name,normalized_name,'school_change',id,? FROM campuses WHERE id=? RETURNING *`,[id,who.profileId,who.authId,who.campusId,campus]):
      statement(env.DB,"INSERT INTO campus_membership_requests(id,requester_profile_id,requester_auth_user_id,school_name,normalized_school_name,request_type) VALUES(?,?,?,?,?,'initial_new_school') RETURNING *",[id,who.profileId,who.authId,school,normalized]),
    statement(env.DB,`UPDATE profiles SET community_request_id=?,community_rejection_reason=NULL,updated_at=?${change?'':",campus_id='general',community_campus_id=NULL,community_access_status='pending',community_school_name=?"} WHERE id=?`,[id,now,...(change?[]:[school]),who.profileId]),
    ...(!change?[statement(env.DB,"UPDATE profile_auth_links SET campus_id='general',last_seen_at=? WHERE profile_id=?",[now,who.profileId])]:[]),
  ]);
  const request=result.flatMap(r=>r.results).find(r=>r.id===id);if(!request)throw new Error('Committed membership request missing');return decode('campus_membership_requests',request);
}
