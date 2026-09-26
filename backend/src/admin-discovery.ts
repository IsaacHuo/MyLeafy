import { selectFeedRecords } from './community';
import type { BackendEnv } from './auth';
import type { AdminContext } from './admin-auth';
import { adminList, adminHydrate } from './admin-data';
import { rows, type Row, type Bind } from './db';
import { ApiError, integer, text } from './http';

export async function globalSearch(env:BackendEnv,context:AdminContext,params:Row){
  const query=text(params.query??params.search,100);
  if(query.length<2)throw new ApiError(400,'bad_request','搜索至少需要两个字符。');
  const resources={posts:'listPosts',comments:'listComments',profiles:'listProfiles',feedback:'listFeedback',teachers:'listTeachers',courses:'listCourses',dishes:'listDishes',postgraduate:'listPostgraduateSources'};
  const selected=Array.isArray(params.resources)?new Set(params.resources):null;
  const results=await Promise.all(Object.entries(resources).filter(([name])=>!selected||selected.has(name)).map(async([resource,action])=>{
    const {items}=await adminList(env,context,action,{search:query,page:0,pageSize:8,status:'all',...(resource==='postgraduate'?{}:{campusID:params.campusID??params.campus_id})});
    return items.map(row=>({resource,id:String(row.id),path:`/admin/${resource}?filter=${encodeURIComponent(JSON.stringify({search:String(row.title||row.name||row.nickname||row.body||query).slice(0,100)}))}`,title:String(row.title||row.name||row.nickname||row.display_name||row.body||'未命名').slice(0,120),
      subtitle:row.category||row.unit||row.location||row.community_campus_id||row.issue_type||row.source_kind||'',
      status:row.status??(row.is_muted?'muted':'active'),updated_at:row.updated_at??row.created_at}));
  }));
  return results.flat().slice(0,40);
}
export async function previewCommunityFeed(env:BackendEnv,context:AdminContext,params:Row){
  const campus=text(params.campusID??params.campus_id??'bjfu',64),limit=integer(params.limit,1,50,20);
  const category=text(params.category,100,false),search=text(params.search,200,false),date=new Date().toISOString().replace('Z','000Z');
  const url=new URL('https://admin.internal/feed');
  url.searchParams.set('limit',String(limit));
  if(category)url.searchParams.set('category',category);
  if(search)url.searchParams.set('search',search);
  const selected=await selectFeedRecords(env,campus,null,url);
  const posts=await adminHydrate(env,context,'posts',selected.posts);
  return {generated_at:date,source:'cloudflare',query:{category:category||null,campusID:campus,search:search||null,limit},total:posts.length,posts};
}
