import type { BackendEnv } from './auth';
import { adminGuard, type AdminContext } from './admin-auth';
import { adminHydrate } from './admin-data';
import { choice, commitAdmin, dateValue, insertStatement, updateStatement } from './admin-write';
import { decode, guard, outbox, rows, statement, type Bind, type Row } from './db';
import { ApiError, integer, text, uuid } from './http';

const now=()=>new Date().toISOString().replace('Z','000Z');
const sourceKinds=['admission_notice','major_catalog','score_line','enrollment_plan','bibliography','retest','registration','other'];
function httpsURL(value:unknown){
  let url:URL;try{url=new URL(text(value,2048));}catch{throw new ApiError(400,'bad_request','请输入有效 HTTPS 来源网址。');}
  if(url.protocol!=='https:'||!url.hostname||url.username||url.password)throw new ApiError(400,'bad_request','来源网址只允许 HTTPS。');
  return url.toString();
}
export function postgraduatePayload(params:Row):Row{
  const payload:Row={title:text(params.title,180),summary:text(params.summary,1200,false),source_url:httpsURL(params.source_url??params.sourceURL??params.sourceUrl),
    source_kind:choice(params.source_kind??params.sourceKind,sourceKinds,'other'),trust_level:choice(params.trust_level??params.trustLevel,['official','curated','verified_user'],'curated'),
    status:choice(params.status,['published','hidden','archived'],'published'),school:text(params.school,200,false)||null,unit:text(params.unit,200,false)||null,major:text(params.major,200,false)||null,
    exam_year:(params.exam_year??params.examYear)==null?null:integer(Number(params.exam_year??params.examYear),2000,2100),verified_at:('verified_at' in params||'verifiedAt' in params)?dateValue(params.verified_at??params.verifiedAt):now()};
  if('published_at' in params||'publishedAt' in params)payload.published_at=dateValue(params.published_at??params.publishedAt);
  return payload;
}
async function pending(env:BackendEnv,table:string,id:string,status:string){
  const [record]=await rows(env.DB,`SELECT * FROM ${table} WHERE id=?`,[id]);
  if(!record)throw new ApiError(404,'not_found','申请或建议不存在。');
  if(record.status!==status)throw new ApiError(409,'state_conflict','该申请或建议已被处理，请刷新。');return record;
}
function pendingGuard(env:BackendEnv,table:string,row:Row,status:string){return guard(env.DB,`EXISTS(SELECT 1 FROM ${table} WHERE id=? AND status=? AND updated_at=?)`,[row.id as string,status,row.updated_at as string]);}

export async function upsertPostgraduateSource(env:BackendEnv,context:AdminContext,params:Row){
  const id=params.id==null?crypto.randomUUID():uuid(params.id),payload={...postgraduatePayload(params),updated_by:context.id,updated_at:now()};
  const result=await commitAdmin(env,context,'upsertPostgraduateSource','postgraduate_sources',id,params.id==null?
    [insertStatement(env,'postgraduate_sources',{...payload,id,created_by:context.id})]:[guard(env.DB,'EXISTS(SELECT 1 FROM postgraduate_sources WHERE id=?)',[id]),updateStatement(env,'postgraduate_sources',id,payload)]);
  return decode('postgraduate_sources',result[0]);
}
export async function reviewPostgraduateSuggestion(env:BackendEnv,context:AdminContext,params:Row,approved:boolean){
  adminGuard(env,context,'operator');const id=uuid(params.id),record=await pending(env,'postgraduate_source_suggestions',id,'open'),date=now(),sourceId=crypto.randomUUID();
  const operations=[pendingGuard(env,'postgraduate_source_suggestions',record,'open')];
  if(approved)operations.push(insertStatement(env,'postgraduate_sources',{id:sourceId,...postgraduatePayload({...record,summary:params.summary??record.note??'',trust_level:'verified_user',status:'published'}),created_by:context.id,updated_by:context.id}));
  operations.push(updateStatement(env,'postgraduate_source_suggestions',id,{status:approved?'approved':'rejected',...(approved?{approved_source_id:sourceId}:{}),admin_note:text(params.adminNote??params.admin_note,2000,false)||null,reviewed_by:context.id,reviewed_at:date,updated_at:date}));
  const result=await commitAdmin(env,context,approved?'approvePostgraduateSuggestion':'rejectPostgraduateSuggestion','postgraduate_source_suggestions',id,operations);
  return (await adminHydrate(env,context,'postgraduate_source_suggestions',result.filter(row=>row.id===id)))[0];
}
export async function reviewCatalogSuggestion(env:BackendEnv,context:AdminContext,params:Row,approved:boolean){
  adminGuard(env,context,'operator');const id=uuid(params.id),record=await pending(env,'catalog_suggestions',id,'open'),date=now();
  const operations=[pendingGuard(env,'catalog_suggestions',record,'open')];
  let approvedColumn:string|null=null,targetSQL='',targetParams:Bind[]=[];
  if(approved){
    const kind=choice(record.suggestion_type,['teacher','course','dish']),table=kind==='teacher'?'teachers':kind==='course'?'course_catalog':'dish_catalog',rating=kind==='teacher'?'teacher_ratings':kind==='course'?'course_ratings':'dish_ratings',fk=`${kind}_id`;
    const campus=text(record.campus_id,64),name=text(record.name,200),unit=text(record.unit,200),category=text(record.category,100,false)||'公选课';
    const natural=`campus_id=? AND lower(trim(name))=lower(?) AND lower(trim(${kind==='dish'?'location':'unit'}))=lower(?)${kind==='course'?' AND lower(trim(category))=lower(?)':''}`;
    targetParams=[campus,name,unit,...(kind==='course'?[category]:[])];targetSQL=`SELECT id FROM ${table} WHERE ${natural} ORDER BY id LIMIT 1`;approvedColumn=`approved_${kind}_id`;
    operations.push(guard(env.DB,"? IS NULL OR EXISTS(SELECT 1 FROM profiles WHERE id=? AND community_campus_id=? AND community_access_status='approved')",[record.user_id as string|null,record.user_id as string|null,campus]));
    operations.push(statement(env.DB,`INSERT INTO ${table}(campus_id,name,${kind==='dish'?'location':'unit'},${kind==='course'?'category,credit,':''}status) SELECT ?,?,?,${kind==='course'?'?,?,':''}'published' WHERE NOT EXISTS(${targetSQL})`,[campus,name,unit,...(kind==='course'?[category,(record.credit??0) as number]:[]),...targetParams]));
    operations.push(statement(env.DB,`UPDATE ${table} SET status='published',updated_at=?${kind==='course'?',credit=coalesce(?,credit)':''} WHERE id=(${targetSQL})`,[date,...(kind==='course'?[record.credit as number|null]:[]),...targetParams]));
    if(record.user_id&&record.initial_stars!=null){
      const stars=integer(Number(record.initial_stars),1,5);
      operations.push(statement(env.DB,`INSERT INTO ${rating}(${fk},user_id,stars) SELECT id,?,? FROM ${table} WHERE id=(${targetSQL}) ON CONFLICT(${fk},user_id) DO UPDATE SET stars=excluded.stars,updated_at=?`,[record.user_id as string,stars,...targetParams,date]));
      operations.push(statement(env.DB,`UPDATE ${table} SET rating_count=(SELECT count(*) FROM ${rating} WHERE ${fk}=${table}.id),rating_average=coalesce((SELECT ((sum(stars)*20+count(*))/(2*count(*)))/10.0 FROM ${rating} WHERE ${fk}=${table}.id),0),${[1,2,3,4,5].map(star=>`rating_${star}_count=(SELECT count(*) FROM ${rating} WHERE ${fk}=${table}.id AND stars=${star})`).join(',')} WHERE id=(${targetSQL})`,targetParams));
    }
  }
  operations.push(statement(env.DB,`UPDATE catalog_suggestions SET status=?,admin_note=?,reviewed_by=?,reviewed_at=?,updated_at=?${approvedColumn?`,${approvedColumn}=(${targetSQL})`:''} WHERE id=? RETURNING *`,[approved?'approved':'rejected',text(params.adminNote??params.admin_note,2000,false)||null,context.id,date,date,...(approvedColumn?targetParams:[]),id]));
  const result=await commitAdmin(env,context,approved?'approveCatalogSuggestion':'rejectCatalogSuggestion','catalog_suggestions',id,operations);
  return (await adminHydrate(env,context,'catalog_suggestions',result))[0];
}

export async function reviewCampusRequest(env:BackendEnv,context:AdminContext,params:Row,approved:boolean){
  adminGuard(env,context,'operator');const id=uuid(params.id),record=await pending(env,'campus_membership_requests',id,'pending'),date=now(),profile=uuid(record.requester_profile_id),change=record.request_type==='school_change';
  const note=text(params.note??params.adminNote??params.admin_note,2000,false)||null,operations=[pendingGuard(env,'campus_membership_requests',record,'pending')];
  let campus:string|null=null;
  if(approved){
    campus=change?text(record.requested_campus_id,64):text(params.campusID??params.campus_id,64,false).toLowerCase();
    if(!campus||campus==='new'){
      const display=text(params.displayName??params.display_name??record.school_name,100),normalized=display.toLowerCase().replace(/\s+/g,'');
      if(['北京林业大学','北林'].includes(normalized))throw new ApiError(400,'bad_request','该学校不能通过通用学校申请创建。');
      const existing=await rows(env.DB,'SELECT id FROM campuses WHERE normalized_name=?',[normalized]);
      campus=existing[0]?.id as string??text(params.newCampusID??params.new_campus_id??`campus-${id.replaceAll('-','')}`,64).toLowerCase();
      if(!/^[a-z0-9][a-z0-9-]{1,63}$/.test(campus)||['bjfu','general','guest'].includes(campus))throw new ApiError(400,'bad_request','学校标识无效。');
      if(!existing.length)operations.push(statement(env.DB,"INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind,status,is_community_enabled,is_system) VALUES(?,?,?,?,'custom','active',1,0)",[campus,display,text(params.shortName??params.short_name,100,false)||[...display].slice(0,6).join(''),normalized]));
    }
    if(['general','guest'].includes(campus)||(!change&&campus==='bjfu'))throw new ApiError(400,'bad_request','目标学校无效。');
    operations.push(guard(env.DB,"EXISTS(SELECT 1 FROM campuses WHERE id=? AND status='active' AND is_community_enabled=1)",[campus]));
    operations.push(statement(env.DB,"UPDATE profiles SET campus_id=?,community_campus_id=?,community_access_status='approved',community_school_name=(SELECT display_name FROM campuses WHERE id=?),community_rejection_reason=NULL,community_request_id=?,updated_at=? WHERE id=?",[campus,campus,campus,id,date,profile]));
    operations.push(statement(env.DB,'UPDATE profile_auth_links SET campus_id=?,last_seen_at=? WHERE profile_id=?',[campus,date,profile]));
  }else if(change){operations.push(statement(env.DB,'UPDATE profiles SET community_request_id=NULL,community_rejection_reason=?,updated_at=? WHERE id=?',[note??'学校更换申请未通过。',date,profile]));}
  else{
    operations.push(statement(env.DB,"UPDATE profiles SET campus_id='general',community_campus_id=NULL,community_access_status='rejected',community_school_name=?,community_rejection_reason=?,community_request_id=?,updated_at=? WHERE id=?",[record.school_name as string,note??'学校申请未通过。',id,date,profile]));
    operations.push(statement(env.DB,"UPDATE profile_auth_links SET campus_id='general',last_seen_at=? WHERE profile_id=?",[date,profile]));
  }
  operations.push(updateStatement(env,'campus_membership_requests',id,{status:approved?'approved':'rejected',approved_campus_id:campus,admin_note:note,reviewed_by:context.id,reviewed_at:date,updated_at:date}),outbox(env.DB,`profile:${profile}`));
  const result=await commitAdmin(env,context,approved?'approveCampusRequest':'rejectCampusRequest','campus_membership_requests',id,operations);
  return decode('campus_membership_requests',result[0]);
}
