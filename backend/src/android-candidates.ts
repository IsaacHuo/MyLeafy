import type {BackendEnv} from './auth';
import {adminGuard, audit, type AdminContext} from './admin-auth';
import {guard} from './db';
import {ApiError, integer, text} from './http';
import {releaseMetadata, releasePublisher, type AndroidRelease} from './android-releases';

const repository='IsaacHuo/MyLeafy';
type Candidate={id:string;metadata:string;version_code:number;github_release_id:number;github_asset_id:number;preparation_run_id:number;created_at:string;operation_id:string|null};
type Operation={id:string;candidate_id:string;approved_by:string;approved_at:string;status:'pending'|'running'|'failed'|'succeeded';run_id:number|null;error_code:string|null;updated_at:string};
type GitHubRelease={draft:boolean;tag_name:string;target_commitish:string;assets:{id:number;name:string;size:number}[]};

async function github(env:BackendEnv,path:string,init:RequestInit={}){
  if(!env.GITHUB_RELEASE_TOKEN)throw new ApiError(503,'github_unavailable','GitHub 发行权限尚未配置。');
  try{
    const response=await fetch(`https://api.github.com/repos/${repository}/${path}`,{...init,
      headers:{Authorization:`Bearer ${env.GITHUB_RELEASE_TOKEN}`,Accept:'application/vnd.github+json','User-Agent':'MyLeafyRelease','X-GitHub-Api-Version':'2022-11-28','Content-Type':'application/json',...init.headers},
      signal:AbortSignal.timeout(20000)});
    if(!response.ok&&!(init.redirect==='manual'&&response.status===302)){await response.body?.cancel();throw new ApiError(502,'github_unavailable',`GitHub 发行请求失败（${response.status}）。`,true);}
    return response;
  }catch(error){if(error instanceof ApiError)throw error;throw new ApiError(502,'github_unavailable','无法连接 GitHub 发行服务。',true);}
}
async function candidate(env:BackendEnv,id:string){
  const row=await env.DB.prepare('SELECT * FROM android_release_candidates WHERE id=?').bind(id).first<Candidate>();
  if(!row)throw new ApiError(404,'not_found','候选版本不存在。');return row;
}
async function operation(env:BackendEnv,id:string){
  const row=await env.DB.prepare('SELECT * FROM android_release_operations WHERE id=?').bind(id).first<Operation>();
  if(!row)throw new ApiError(404,'not_found','发布授权不存在。');return row;
}
async function checkDraft(env:BackendEnv,row:Candidate){
  const info=JSON.parse(row.metadata) as AndroidRelease;
  const draft=await (await github(env,`releases/${row.github_release_id}`)).json() as GitHubRelease;
  const asset=draft.assets.find(asset=>asset.id===row.github_asset_id);
  if(!draft.draft||draft.tag_name!==`android-candidate-${info.versionCode}`||draft.target_commitish!==info.commit||!asset||asset.name!==`MyLeafy-Android-${info.versionName}.apk`||asset.size!==info.sizeBytes)
    throw new ApiError(409,'candidate_changed','GitHub 候选包已改变，不能下载或发布。');
  return info;
}
export async function registerAndroidCandidate(env:BackendEnv,request:Request,body:Record<string,unknown>){
  await releasePublisher(env,request);
  const info=releaseMetadata(body);
  if(info.packageName!=='com.myleafy.android')throw new ApiError(400,'bad_request','候选必须使用正式包名。');
  const previous=await env.DB.prepare('SELECT metadata FROM android_releases ORDER BY version_code DESC LIMIT 1').first<{metadata:string}>();
  const certificate=previous?JSON.parse(previous.metadata).certificateSha256:env.ANDROID_SIGNING_CERTIFICATE_SHA256;
  if(!certificate||certificate!==info.certificateSha256)throw new ApiError(409,'certificate_mismatch','候选包必须沿用已经确认的正式签名。');
  const row:Candidate={id:info.id,metadata:JSON.stringify(info),version_code:info.versionCode,
    github_release_id:integer(body.githubReleaseId,1,Number.MAX_SAFE_INTEGER),github_asset_id:integer(body.githubAssetId,1,Number.MAX_SAFE_INTEGER),
    preparation_run_id:integer(body.preparationRunId,1,Number.MAX_SAFE_INTEGER),created_at:new Date().toISOString(),operation_id:null};
  await checkDraft(env,row);
  const run=await (await github(env,`actions/runs/${row.preparation_run_id}`)).json() as {head_sha:string;event:string;path:string;head_branch:string};
  if(run.head_branch!=='main'||!['workflow_run','workflow_dispatch'].includes(run.event)||run.path!=='.github/workflows/android-prepare.yml')
    throw new ApiError(409,'unverified_candidate','候选必须来自主线的准备工作流。');
  const checks=await (await github(env,`actions/workflows/ci.yml/runs?head_sha=${info.commit}&per_page=100`)).json() as {workflow_runs:{head_sha:string;head_branch:string;conclusion:string|null;path:string}[]};
  if(!checks.workflow_runs.some(run=>run.head_sha===info.commit&&run.head_branch==='main'&&run.path==='.github/workflows/ci.yml'&&run.conclusion==='success'))throw new ApiError(409,'unverified_candidate','该提交尚未通过主线 CI 总检查。');
  const existing=await env.DB.prepare('SELECT * FROM android_release_candidates WHERE id=?').bind(info.id).first<Candidate>();
  if(existing){if(existing.metadata!==row.metadata||existing.github_asset_id!==row.github_asset_id||existing.github_release_id!==row.github_release_id)throw new ApiError(409,'candidate_conflict','同一版本不能覆盖不同候选包。');return {id:info.id};}
  const highest=await env.DB.prepare('SELECT max(version_code) code FROM android_releases').first<{code:number|null}>();
  if(highest?.code!=null&&highest.code>=info.versionCode)throw new ApiError(409,'release_conflict','候选版本号必须高于已有发行。');
  await env.DB.prepare('INSERT INTO android_release_candidates(id,metadata,version_code,github_release_id,github_asset_id,preparation_run_id,created_at) VALUES(?,?,?,?,?,?,?)')
    .bind(row.id,row.metadata,row.version_code,row.github_release_id,row.github_asset_id,row.preparation_run_id,row.created_at).run();
  return {id:info.id};
}
export async function requestAndroidPublication(env:BackendEnv,context:AdminContext,params:Record<string,unknown>){
  if(context.role!=='super_admin')throw new ApiError(403,'forbidden','只有超级管理员可以发布版本。');
  if(params.accepted!==true)throw new ApiError(400,'acceptance_required','请先确认已完成候选包验收。');
  const row=await candidate(env,text(params.id,120));await checkDraft(env,row);
  const released=await env.DB.prepare('SELECT status FROM android_releases WHERE id=?').bind(row.id).first();
  if(released)throw new ApiError(409,'release_conflict','该版本已经发布或撤回。');
  if(row.operation_id){const current=await operation(env,row.operation_id);if(['pending','running'].includes(current.status))return {id:row.id,operationId:current.id,status:'publishing'};}
  const id=crypto.randomUUID(),now=new Date().toISOString();
  try{await env.DB.batch([adminGuard(env,context,'super_admin'),
    guard(env.DB,"EXISTS(SELECT 1 FROM release_control WHERE writable=1) AND NOT EXISTS(SELECT 1 FROM android_releases WHERE version_code>=?)",[row.version_code]),
    env.DB.prepare("INSERT INTO android_release_operations(id,candidate_id,approved_by,approved_at,status,updated_at) VALUES(?,?,?,?,'pending',?)").bind(id,row.id,context.id,now,now),
    env.DB.prepare('UPDATE android_release_candidates SET operation_id=? WHERE id=?').bind(id,row.id),
    audit(env,context,'requestAndroidPublication','android_releases',row.id),env.DB.prepare('DELETE FROM mutation_assertions')]);
  }catch(error){if(/constraint|precondition/i.test(String(error)))throw new ApiError(409,'release_conflict','版本状态已改变，请刷新后重试。');throw error;}
  try{
    await github(env,'actions/workflows/android-release.yml/dispatches',{method:'POST',body:JSON.stringify({ref:'main',inputs:{operation:id}})});
  }catch(error){
    // An ambiguous network response remains pending: the accepted workflow may still start.
    await env.DB.prepare('UPDATE android_release_operations SET error_code=? WHERE id=? AND status=\'pending\'').bind('dispatch_unconfirmed',id).run();
    throw error;
  }
  return {id:row.id,operationId:id,status:'publishing'};
}
export async function reconcileAndroidPublications(env:BackendEnv){
  const active=(await env.DB.prepare("SELECT * FROM android_release_operations WHERE status IN('pending','running')").all<Operation>()).results;
  for(const current of active){
    let run:{id:number;status:string;conclusion:string|null}|undefined;
    if(current.run_id)run=await (await github(env,`actions/runs/${current.run_id}`)).json() as typeof run;
    else if(Date.now()-Date.parse(current.approved_at)>600000){
      const runs=await (await github(env,'actions/workflows/android-release.yml/runs?event=workflow_dispatch&per_page=100')).json() as {workflow_runs:{id:number;display_title:string;status:string;conclusion:string|null}[]};
      run=runs.workflow_runs.find(run=>run.display_title===`Android publication ${current.id}`);
      if(!run){await env.DB.prepare("UPDATE android_release_operations SET status='failed',error_code='dispatch_not_found',updated_at=? WHERE id=? AND status='pending'").bind(new Date().toISOString(),current.id).run();continue;}
    }
    if(run?.status==='completed'&&current.status!=='succeeded'){
      await env.DB.prepare("UPDATE android_release_operations SET status='failed',error_code='workflow_incomplete',updated_at=? WHERE id=? AND status IN('pending','running')")
        .bind(new Date().toISOString(),current.id).run();
    }
  }
}
export async function claimAndroidPublication(env:BackendEnv,request:Request,id:string,body:Record<string,unknown>){
  await releasePublisher(env,request);const op=await operation(env,id),row=await candidate(env,op.candidate_id);
  if(row.operation_id!==id||!['pending','running'].includes(op.status))throw new ApiError(409,'approval_expired','发布授权已失效。');
  const runId=integer(body.runId,1,Number.MAX_SAFE_INTEGER);
  const run=await (await github(env,`actions/runs/${runId}`)).json() as {head_branch:string;event:string;path:string;display_title:string};
  if(run.head_branch!=='main'||run.event!=='workflow_dispatch'||run.path!=='.github/workflows/android-release.yml'||run.display_title!==`Android publication ${id}`)
    throw new ApiError(403,'unverified_workflow','发布工作流身份无效。');
  if(op.run_id!==null&&op.run_id!==runId)throw new ApiError(409,'approval_expired','发布授权已失效。');
  const info=await checkDraft(env,row);
  const changed=await env.DB.prepare("UPDATE android_release_operations SET status='running',run_id=?,updated_at=? WHERE id=? AND status IN('pending','running') AND (run_id IS NULL OR run_id=?) AND EXISTS(SELECT 1 FROM android_release_candidates WHERE id=? AND operation_id=?) RETURNING id")
    .bind(runId,new Date().toISOString(),id,runId,row.id,id).first();
  if(!changed)throw new ApiError(409,'approval_expired','发布授权已失效。');
  return {...info,githubReleaseId:row.github_release_id,githubAssetId:row.github_asset_id};
}
export async function approvedAndroidArtifact(env:BackendEnv,request:Request){
  const id=new URL(request.url).searchParams.get('operation');
  if(!id)throw new ApiError(403,'approval_required','正式发行需要管理员授权。');
  const op=await operation(env,id),row=await candidate(env,op.candidate_id);
  if(row.operation_id!==id||!['running','succeeded'].includes(op.status))throw new ApiError(409,'approval_expired','发布授权已失效。');
  return {op,row,info:JSON.parse(row.metadata) as AndroidRelease};
}
export async function failAndroidPublication(env:BackendEnv,request:Request,id:string,body:Record<string,unknown>){
  await releasePublisher(env,request);const runId=integer(body.runId,1,Number.MAX_SAFE_INTEGER);
  await env.DB.prepare("UPDATE android_release_operations SET status='failed',error_code='publication_failed',updated_at=? WHERE id=? AND run_id=? AND status='running'").bind(new Date().toISOString(),id,runId).run();
  return {id};
}
export async function downloadAndroidCandidate(env:BackendEnv,context:AdminContext,id:string){
  const row=await candidate(env,id),info=await checkDraft(env,row);
  // The AdminAPI entrypoint authenticated this context; no secret or draft URL is returned to the browser.
  let response=await github(env,`releases/assets/${row.github_asset_id}`,{headers:{Accept:'application/octet-stream'},redirect:'manual'});
  if(response.status===302){
    const location=response.headers.get('location');if(!location)throw new ApiError(502,'github_unavailable','候选下载地址缺失。');
    const url=new URL(location);if(url.protocol!=='https:'||url.hostname!=='release-assets.githubusercontent.com')throw new ApiError(502,'github_unavailable','候选下载地址无效。');
    await response.body?.cancel();response=await fetch(url,{signal:AbortSignal.timeout(60000)});
  }
  if(!response.ok||response.headers.get('content-type')?.includes('json')){await response.body?.cancel();throw new ApiError(502,'github_unavailable','候选安装包下载失败。',true);}
  return new Response(response.body,{headers:{'Content-Type':'application/vnd.android.package-archive','Content-Disposition':`attachment; filename="MyLeafy-Android-${info.versionName}.apk"`,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
}
