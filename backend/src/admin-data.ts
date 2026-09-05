import mapping from '../contracts/table-mapping.json';
import type { BackendEnv } from './auth';
import { adminGuard, type AdminContext, type AdminRole } from './admin-auth';
import { decode, rows, type Bind, type Row } from './db';
import { ApiError, integer, text } from './http';

type Resource={table:string;search:string[];role?:AdminRole;campusColumn?:string;order?:string};
export const adminLists:Record<string,Resource>={
  listCampuses:{table:'campuses',search:['display_name','short_name'],order:'display_name'},
  listCampusRequests:{table:'campus_membership_requests',search:['school_name','admin_note'],campusColumn:'approved_campus_id'},
  listPosts:{table:'posts',search:['title','body','category']},
  listPolls:{table:'community_polls',search:['question','detail']},
  listPostPins:{table:'community_post_pins',search:['category','reason']},
  listComments:{table:'comments',search:['body']},
  listModerationReports:{table:'community_reports',search:['reason','detail','resolution_note']},
  listProfiles:{table:'profiles',search:['nickname','display_name','edu_id','bound_email'],campusColumn:'community_campus_id'},
  listFeedback:{table:'feedback_submissions',search:['body','contact','issue_type']},
  listAnnouncements:{table:'site_announcements',search:['title','body']},
  listCommunityBanners:{table:'community_banners',search:['title','subtitle']},
  listPostgraduateSources:{table:'postgraduate_sources',search:['search_text']},
  listPostgraduateSuggestions:{table:'postgraduate_source_suggestions',search:['school','title','note']},
  listCatalogSuggestions:{table:'catalog_suggestions',search:['name','unit','category','location','note']},
  listTeachers:{table:'teachers',search:['search_text'],order:'rating_average'},
  listCourses:{table:'course_catalog',search:['search_text'],order:'rating_average'},
  listDishes:{table:'dish_catalog',search:['search_text'],order:'rating_average'},
  listTeacherRatings:{table:'teacher_ratings',search:[]},
  listDishRatings:{table:'dish_ratings',search:[]},
  listSemesterRuntimeConfigs:{table:'semester_runtime_configs',search:['semester_id'],order:'updated_at'},
  listNationalCalendarRuntimeConfigs:{table:'national_calendar_runtime_configs',search:[],order:'year'},
  listAdmins:{table:'admin_accounts',search:['username','display_name'],role:'super_admin'},
  listAdminSessions:{table:'admin_sessions',search:[],role:'super_admin'},
  listAuditLogs:{table:'admin_audit_logs',search:['action','target_type','target_id'],role:'super_admin'},
};
const metadata:Record<string,{columns:{name:string}[];primaryKey:string[]}> = mapping;
const profileColumns=['id','community_campus_id','community_access_status','community_school_name','nickname','display_name','avatar_path','bio','is_profile_complete','muted_until','muted_reason','muted_at','created_at','updated_at'];
export function profileForAdmin(record:Row,context:AdminContext){
  const projected=context.role==='super_admin'?record:Object.fromEntries(profileColumns.filter(k=>k in record).map(k=>[k,record[k]]));
  return decode('profiles',projected);
}
function dateBoundary(value:unknown,offset:number,end=false){
  if(value==null||value==='')return null;
  const string=text(value,40),dateOnly=/^\d{4}-\d{2}-\d{2}$/.test(string);
  const parsed=Date.parse(dateOnly?`${string}T00:00:00Z`:string);
  if(!Number.isFinite(parsed))throw new ApiError(400,'bad_request','日期无效。');
  return new Date(parsed+(dateOnly?offset*60000+(end?86400000:0):0)).toISOString().replace('Z','000Z');
}
export async function adminHydrate(env:BackendEnv,context:AdminContext,table:string,records:Row[]){
  if(!records.length)return [];
  const profileIds=[...new Set(records.flatMap(row=>['author_id','user_id','requester_profile_id','reporter_id','reported_user_id'].map(key=>row[key]).filter((id):id is string=>typeof id==='string')))];
  const profiles=new Map<string,Row>();
  for(let start=0;start<profileIds.length;start+=80){
    const ids=profileIds.slice(start,start+80);
    for(const profile of await rows(env.DB,`SELECT * FROM profiles WHERE id IN(${ids.map(()=>'?').join(',')})`,ids))profiles.set(profile.id as string,profileForAdmin(profile,context));
  }
  const output=records.map(record=>{
    let row=decode(table,record);
    if(table==='profiles')row=profileForAdmin(record,context);
    if(table==='admin_accounts')delete row.password_hash;
    if(row.author_id)row.author=profiles.get(row.author_id as string)??null;
    if(row.user_id)row.user=profiles.get(row.user_id as string)??null;
    if(row.requester_profile_id)row.requester=profiles.get(row.requester_profile_id as string)??null;
    if(row.reporter_id)row.reporter=profiles.get(row.reporter_id as string)??null;
    if(row.reported_user_id)row.reported_user=profiles.get(row.reported_user_id as string)??null;
    if(table==='admin_sessions'){row.id=row.token_hash;row.is_current=row.token_hash===context.tokenHash;delete row.token_hash;}
    if(table==='teacher_ratings'||table==='dish_ratings')row.id=`${row.teacher_id??row.dish_id}:${row.user_id}`;
    return row;
  });
  if(table==='profiles'){
    const ids=records.map(r=>r.id as string);
    const posts=await rows(env.DB,`SELECT author_id,count(*) AS n FROM posts WHERE author_id IN(${ids.map(()=>'?').join(',')}) GROUP BY author_id`,ids);
    const comments=await rows(env.DB,`SELECT author_id,count(*) AS n FROM comments WHERE author_id IN(${ids.map(()=>'?').join(',')}) GROUP BY author_id`,ids);
    for(const row of output){row.post_count=posts.find(p=>p.author_id===row.id)?.n??0;row.comment_count=comments.find(c=>c.author_id===row.id)?.n??0;row.is_muted=typeof row.muted_until==='string'&&Date.parse(row.muted_until)>Date.now();}
  }
  if(table==='posts'){
    const ids=records.map(r=>r.id as string);
    const images=await rows(env.DB,`SELECT * FROM post_images WHERE post_id IN(${ids.map(()=>'?').join(',')}) ORDER BY sort_order,id`,ids);
    const attachments=await rows(env.DB,`SELECT * FROM post_attachments WHERE post_id IN(${ids.map(()=>'?').join(',')}) ORDER BY sort_order,id`,ids);
    for(const row of output){row.images=images.filter(i=>i.post_id===row.id);row.attachments=attachments.filter(a=>a.post_id===row.id);}
  }
  if(table==='comments'||table==='community_reports'){
    const ids=[...new Set(records.map(r=>r.post_id as string).filter(Boolean))];
    const posts=ids.length?await rows(env.DB,`SELECT id,title,status,campus_id FROM posts WHERE id IN(${ids.map(()=>'?').join(',')})`,ids):[];
    for(const row of output)row.post=posts.find(p=>p.id===row.post_id)??null;
  }
  return output;
}
export async function adminList(env:BackendEnv,context:AdminContext,action:string,params:Row){
  const resource=adminLists[action];if(!resource)throw new ApiError(400,'bad_request','未知列表操作。');
  adminGuard(env,context,resource.role??'viewer');
  const columns=new Set(metadata[resource.table].columns.map(c=>c.name)),where:string[]=[],bind:Bind[]=[];
  const page=integer(params.page,0,100000,0),pageSize=integer(params.pageSize??params.page_size,1,100,20);
  const equal=(column:string,value:unknown)=>{
    if(value==null||value===''||value==='all'||!columns.has(column))return;
    if(typeof value!=='string'&&typeof value!=='number'&&typeof value!=='boolean')throw new ApiError(400,'bad_request','筛选值无效。');
    where.push(`t.${column}=?`);bind.push(typeof value==='boolean'?(value?1:0):value);
  };
  const status=params.status??(resource.table==='community_polls'||resource.table==='campus_membership_requests'?'pending':null);
  if(resource.table==='community_polls'&&status==='pending')where.push("(t.status='pending_review' OR t.deletion_status='pending')");
  else equal('status',status);
  for(const [key,column] of Object.entries({authorID:'author_id',userID:'user_id',postID:'post_id',adminID:'admin_id',category:'category',location:'location',kind:'kind',role:'role',active:'active',complete:'is_profile_complete',targetType:'target_type',requestType:'request_type',deletionStatus:'deletion_status'}))equal(column,params[key]);
  const campus=params.campusID??params.campus_id;
  if(typeof campus==='string'&&campus&&campus!=='all'){
    const column=resource.campusColumn??'campus_id';
    if(columns.has(column))equal(column,campus);
    else if(resource.table==='comments'||resource.table==='community_reports'){where.push('t.post_id IN(SELECT id FROM posts WHERE campus_id=?)');bind.push(campus);}
    else if(resource.table.endsWith('_ratings')){const target=resource.table==='teacher_ratings'?'teachers':'dish_catalog',key=resource.table==='teacher_ratings'?'teacher_id':'dish_id';where.push(`t.${key} IN(SELECT id FROM ${target} WHERE campus_id=?)`);bind.push(campus);}
  }
  if(params.muted==='active'&&columns.has('muted_until')){where.push('t.muted_until>?');bind.push(new Date().toISOString().replace('Z','000Z'));}
  const offset=integer(params.timezoneOffsetMinutes,-840,840,0),start=dateBoundary(params.start??params.startAt??params.start_at,offset),end=dateBoundary(params.end??params.endAt??params.end_at,offset,true);
  if(start){where.push('t.created_at>=?');bind.push(start);}if(end){where.push('t.created_at<?');bind.push(end);}
  const search=text(params.search,200,false);
  const searchable=resource.search.filter(c=>columns.has(c)&&!(resource.table==='profiles'&&context.role!=='super_admin'&&!profileColumns.includes(c)));
  if(search&&searchable.length){where.push(`(${searchable.map(c=>`instr(lower(coalesce(t.${c},'')),lower(?))>0`).join(' OR ')})`);bind.push(...searchable.map(()=>search));}
  const requested=params.sortField??params.sort_field;
  const sort=typeof requested==='string'?requested:resource.order??'created_at';
  if(!columns.has(sort)||sort==='password_hash'||sort==='token_hash')throw new ApiError(400,'bad_request','不支持该排序字段。');
  const direction=String(params.sortOrder??params.sort_order??'DESC').toUpperCase();if(!['ASC','DESC'].includes(direction))throw new ApiError(400,'bad_request','排序方向无效。');
  const filter=where.length?' WHERE '+where.join(' AND '):'';
  const [data,count]=await Promise.all([rows(env.DB,`SELECT t.* FROM ${resource.table} t${filter} ORDER BY t.${sort} ${direction},${metadata[resource.table].primaryKey.map(key=>`t.${key}`).join(',')} LIMIT ? OFFSET ?`,[...bind,pageSize,page*pageSize]),rows(env.DB,`SELECT count(*) AS n FROM ${resource.table} t${filter}`,bind)]);
  return {items:await adminHydrate(env,context,resource.table,data),total:count[0].n,page,pageSize};
}
export async function adminGet(env:BackendEnv,context:AdminContext,action:string,params:Row){
  const table=({getPost:'posts',getProfile:'profiles',getPoll:'community_polls',getModerationReport:'community_reports'} as Record<string,string>)[action];
  if(!table)throw new ApiError(400,'bad_request','未知详情操作。');
  const id=text(params.id,100),found=await rows(env.DB,`SELECT * FROM ${table} WHERE id=?`,[id]);
  if(!found.length)throw new ApiError(404,'not_found','记录不存在。');
  const [record]=await adminHydrate(env,context,table,found);
  if(table==='profiles')return {profile:record,recentPosts:(await adminList(env,context,'listPosts',{authorID:id,pageSize:8})).items,recentComments:(await adminList(env,context,'listComments',{authorID:id,pageSize:8})).items,auditLogs:context.role==='super_admin'?await rows(env.DB,"SELECT * FROM admin_audit_logs WHERE target_type='profile' AND target_id=? ORDER BY created_at DESC LIMIT 8",[id]):[]};
  if(table==='posts')return {post:record,comments:(await adminList(env,context,'listComments',{postID:id,pageSize:20})).items,reports:(await adminList(env,context,'listModerationReports',{postID:id,pageSize:20})).items};
  if(table==='community_polls')return {poll:{...record,options:await rows(env.DB,'SELECT * FROM community_poll_options WHERE poll_id=? ORDER BY sort_order,id',[id])}};
  return {report:record};
}
