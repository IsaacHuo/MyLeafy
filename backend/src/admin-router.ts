import type { BackendEnv } from './auth';
import { adminGuard, adminLogin, adminLogout, adminMe, authenticateAdmin, audit, type AdminContext } from './admin-auth';
import { adminGet, adminList, adminLists } from './admin-data';
import { exportAdminData } from './admin-export';
import { overview } from './admin-overview';
import { moderate, mute, retryPostPublish, reviewPollDeletion, setCatalogStatus, updateAdminAccount, upsertCatalog, upsertRuntime } from './admin-write';
import { ApiError, readJSON, text } from './http';
import { requireWritable, type Row } from './db';
import { announcement, deleteRating, pinPost, resolveModerationReport, revokeAdminSession, unpinPost, updateFeedback } from './admin-operations';

type Handler=(env:BackendEnv,context:AdminContext,params:Row)=>Promise<unknown>;
const mutations:Record<string,Handler>={
  updateFeedback,pinPost,unpinPost,resolveModerationReport,revokeAdminSession,
  createAnnouncement:(env,context,params)=>announcement(env,context,params,true),
  updateAnnouncement:announcement,
  deleteTeacherRating:(env,context,params)=>deleteRating(env,context,params),
  deleteDishRating:(env,context,params)=>deleteRating(env,context,params,true),
  ...Object.fromEntries(['upsertTeacher','upsertCourse','upsertDish'].map(action=>[action,(env:BackendEnv,context:AdminContext,params:Row)=>upsertCatalog(env,context,action,params)])),
  ...Object.fromEntries(['setTeacherStatus','setCourseStatus','setDishStatus','setPostgraduateSourceStatus'].map(action=>[action,(env:BackendEnv,context:AdminContext,params:Row)=>setCatalogStatus(env,context,action,params)])),
  ...Object.fromEntries(['moderatePost','bulkModeratePosts','moderateComment','bulkModerateComments','moderatePoll'].map(action=>[action,(env:BackendEnv,context:AdminContext,params:Row)=>moderate(env,context,action,params)])),
  ...Object.fromEntries(['createAdmin','updateAdmin','disableAdmin'].map(action=>[action,(env:BackendEnv,context:AdminContext,params:Row)=>updateAdminAccount(env,context,action,params)])),
  retryPostPublish,reviewPollDeletion,
  muteProfile:(env,context,params)=>mute(env,context,params,true),
  unmuteProfile:(env,context,params)=>mute(env,context,params,false),
  upsertSemesterRuntimeConfig:(env,context,params)=>upsertRuntime(env,context,params),
  upsertNationalCalendarRuntimeConfig:(env,context,params)=>upsertRuntime(env,context,params,true),
};

/** Invoked only by the dedicated AdminAPI service-binding entrypoint. */
export async function handleAdminRequest(request:Request,env:BackendEnv):Promise<Response>{
  const requested=request.headers.get('x-request-id')??'';
  const requestId=/^[A-Za-z0-9_-]{1,128}$/.test(requested)?requested:crypto.randomUUID(),started=Date.now();
  const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Request-ID':requestId,'X-Content-Type-Options':'nosniff'}});
  try{
    const path=new URL(request.url).pathname;
    if(!['/admin/login','/admin/me','/admin/logout','/admin/actions','/admin/export'].includes(path))throw new ApiError(404,'not_found','管理接口不存在。');
    if(request.method!==(path==='/admin/me'?'GET':'POST'))throw new ApiError(405,'method_not_allowed','请求方法无效。');
    if(path==='/admin/login'){await requireWritable(env.DB);return json(await adminLogin(env,request));}
    const context=await authenticateAdmin(env,request);context.requestId=requestId;
    if(path==='/admin/me')return json(await adminMe(env,context));
    if(path==='/admin/logout'){await requireWritable(env.DB);return json(await adminLogout(env,context));}
    const body=await readJSON(request);
    if(path==='/admin/export'){await requireWritable(env.DB);return exportAdminData(env,context,body);}
    const action=text(body.action,100),params=body.params??{};
    if(!params||typeof params!=='object'||Array.isArray(params))throw new ApiError(400,'bad_request','管理操作参数必须是对象。');
    let data:unknown;
    if(action==='overview')data=await overview(env,context,params as Row);
    else if(adminLists[action])data=await adminList(env,context,action,params as Row);
    else if(['getPost','getProfile','getPoll','getModerationReport'].includes(action))data=await adminGet(env,context,action,params as Row);
    else if(mutations[action]){
      await requireWritable(env.DB);adminGuard(env,context,['createAdmin','updateAdmin','disableAdmin'].includes(action)?'super_admin':'operator');
      data=await mutations[action](env,context,params as Row);
    }else throw new ApiError(400,'bad_request','未知管理操作。');
    let auditLogged=Boolean(mutations[action]);
    if(!auditLogged){
      const state=await env.DB.prepare('SELECT mode FROM backend_control WHERE id=1').first<{mode:string}>();
      if(state?.mode==='active'){await audit(env,context,action,'read',null).run();auditLogged=true;}
    }
    return json({data,meta:{request_id:requestId,audit_logged:auditLogged,duration_ms:Date.now()-started}});
  }catch(error){
    const known=error instanceof ApiError,status=known?error.status:500,code=known?error.code:'internal_error',message=known?error.message:'管理请求失败，请稍后重试。';
    console.error(JSON.stringify({event:'admin_api_error',request_id:requestId,status,code}));
    return json({error:message,errorEnvelope:{code,message,retryable:known?error.retryable:true,details:{request_id:requestId}}},status);
  }
}
