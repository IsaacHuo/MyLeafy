import type { BackendEnv } from './auth';
import { audit, type AdminContext } from './admin-auth';
import { adminList } from './admin-data';
import { roleCanExport } from './admin-permissions';
import { toCSV } from './admin-csv';
import { exportColumns } from './admin-export-columns';
import { ApiError, text } from './http';
import type { Row } from './db';

const actions:Record<string,string>={posts:'listPosts',polls:'listPolls',comments:'listComments',reports:'listModerationReports',announcements:'listAnnouncements',postgraduate:'listPostgraduateSources',suggestions:'listCatalogSuggestions',teachers:'listTeachers',courses:'listCourses',dishes:'listDishes',profiles:'listProfiles',feedback:'listFeedback',admins:'listAdmins',sessions:'listAdminSessions','audit-logs':'listAuditLogs',ratings:'listTeacherRatings'};
export async function exportAdminData(env:BackendEnv,context:AdminContext,body:Row){
  const resource=text(body.resource,64);
  if(!actions[resource]||!exportColumns[resource])throw new ApiError(400,'bad_request','不支持该导出资源。');
  if(!roleCanExport(context.role,resource))throw new ApiError(403,'forbidden','无权导出该资源。');
  const filters=body.filters&&typeof body.filters==='object'&&!Array.isArray(body.filters)?body.filters as Row:{};
  const sort=body.sort&&typeof body.sort==='object'&&!Array.isArray(body.sort)?body.sort as Row:{};
  const action=resource==='ratings'&&filters.target==='dish'?'listDishRatings':actions[resource],all:Row[]=[];
  for(let page=0;page<50;page++){
    const result=await adminList(env,context,action,{...filters,sortField:sort.field,sortOrder:sort.order,page,pageSize:100});
    if(Number(result.total)>5000)throw new ApiError(413,'export_too_large','请缩小筛选范围后再导出，单次最多 5,000 条记录。');
    all.push(...result.items);if(all.length>=Number(result.total))break;
  }
  const columns=action==='listDishRatings'?exportColumns.ratings.map(c=>c==='teacher_id'?'dish_id':c):exportColumns[resource];
  // Preserve the historical CSV header while filling it from the actual field.
  if(resource==='profiles')for(const row of all)row.mute_reason=row.muted_reason;
  await audit(env,context,'exportResource','export',resource).run();
  return new Response(toCSV(columns,all),{headers:{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':`attachment; filename="leafy-${resource}-${new Date().toISOString().slice(0,10)}.csv"`,'Cache-Control':'no-store','X-Request-ID':context.requestId,'X-Audit-Logged':'true'}});
}
