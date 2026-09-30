import type { BackendEnv } from './auth';
import { ApiError, integer, text } from './http';
import type { AdminContext } from './admin-auth';
import { commitAdmin } from './admin-write';
import { guard } from './db';
import { timingSafeEqual } from 'node:crypto';

export type AndroidRelease = {
  id:string;packageName:string;channel:'official';versionCode:number;versionName:string;minSdk:number;
  releaseNotes:string;commit:string;artifactKey:string;sizeBytes:number;sha256:string;
  certificateSha256:string;githubReleaseUrl:string;
};
const hex=/^[a-f0-9]{64}$/;
const maxArtifactSize=64*1024*1024;
function downloadOrigin(env:BackendEnv){return env.ENVIRONMENT==='production'?'https://downloads.myleafy.space':'https://downloads-staging.myleafy.space';}
function packageName(value:unknown){
  const name=text(value,80);
  if(!['com.myleafy.android','com.myleafy.android.next'].includes(name))throw new ApiError(400,'bad_request','应用包名无效。');
  return name;
}
export function releaseMetadata(body:Record<string,unknown>):AndroidRelease {
  const versionName=text(body.versionName,40),sha256=text(body.sha256,64),certificateSha256=text(body.certificateSha256,64);
  if(!/^\d+\.\d+\.\d+$/.test(versionName)||!hex.test(sha256)||!hex.test(certificateSha256))throw new ApiError(400,'bad_request','版本或校验信息无效。');
  const pkg=packageName(body.packageName),code=integer(body.versionCode,1,2100000000),id=`${pkg}-${code}`;
  const artifactKey=`android/official/${code}/MyLeafy-Android-${versionName}.apk`;
  const githubReleaseUrl=`https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v${versionName}`;
  if(body.channel!=='official'||body.artifactKey!==artifactKey||body.githubReleaseUrl!==githubReleaseUrl||!/^[a-f0-9]{40}$/.test(String(body.commit)))throw new ApiError(400,'bad_request','发布信息无效。');
  return {id,packageName:pkg,channel:'official',versionCode:code,versionName,minSdk:integer(body.minSdk,29,100),
    releaseNotes:text(body.releaseNotes,20000),commit:body.commit as string,artifactKey,sizeBytes:integer(body.sizeBytes,1,maxArtifactSize),sha256,certificateSha256,githubReleaseUrl};
}
async function publisher(env:BackendEnv,request:Request){
  if(!env.RELEASE_PUBLISH_TOKEN||env.RELEASE_PUBLISH_TOKEN.length<32)throw new ApiError(503,'release_unavailable','版本发布尚未配置。');
  const digest=async(value:string)=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));
  const [a,b]=await Promise.all([digest(request.headers.get('authorization')??''),digest(`Bearer ${env.RELEASE_PUBLISH_TOKEN}`)]);
  if(!timingSafeEqual(a,b))throw new ApiError(401,'unauthenticated','发布凭据无效。');
  if((await env.DB.prepare('SELECT writable FROM release_control WHERE id=1').first<{writable:number}>())?.writable!==1)throw new ApiError(503,'maintenance','版本发布暂时关闭。');
}
export async function uploadReleaseArtifact(env:BackendEnv,request:Request,key:string){
  await publisher(env,request);
  if(!/^android\/official\/[1-9]\d*\/MyLeafy-Android-\d+\.\d+\.\d+\.apk(?:\.sha256|-build-info\.txt)?$/.test(key))throw new ApiError(400,'bad_request','发行路径无效。');
  const hash=request.headers.get('x-artifact-sha256')??'',length=Number(request.headers.get('content-length'));
  if(!hex.test(hash)||!Number.isInteger(length)||length<=0||length>maxArtifactSize)throw new ApiError(400,'bad_request','发行文件无效。');
  const existing=await env.RELEASES.head(key);
  if(existing){
    if(existing.size!==length||existing.customMetadata?.sha256!==hash)throw new ApiError(409,'artifact_conflict','已存在不同的发行文件，不能覆盖。');
    return {key,sha256:hash,sizeBytes:length};
  }
  const object=await env.RELEASES.put(key,request.body,{onlyIf:{etagDoesNotMatch:'*'},sha256:hash,customMetadata:{sha256:hash},
    httpMetadata:{contentType:key.endsWith('.apk')?'application/vnd.android.package-archive':'text/plain; charset=utf-8',cacheControl:'public, max-age=31536000, immutable'}});
  if(!object)throw new ApiError(409,'artifact_conflict','发行文件已由另一任务上传，请重试核对。');
  return {key,sha256:hash,sizeBytes:object.size};
}
function publicInfo(env:BackendEnv,info:AndroidRelease){return {...info,apkUrl:`${downloadOrigin(env)}/${info.artifactKey}`,apkName:info.artifactKey.split('/').at(-1)!};}
export async function publishAndroidRelease(env:BackendEnv,request:Request,body:Record<string,unknown>){
  await publisher(env,request);
  const info=releaseMetadata(body);
  if(env.ENVIRONMENT==='production'&&info.packageName!=='com.myleafy.android')throw new ApiError(400,'bad_request','生产仅发布正式包。');
  const object=await env.RELEASES.head(info.artifactKey);
  if(!object||object.size!==info.sizeBytes||object.customMetadata?.sha256!==info.sha256)throw new ApiError(409,'artifact_unverified','发行文件尚未上传或校验不一致。');
  const canonical=JSON.stringify(info),existing=await env.DB.prepare('SELECT metadata,status FROM android_releases WHERE id=?').bind(info.id).first<{metadata:string;status:string}>();
  if(existing){
    if(existing.metadata!==canonical||existing.status!=='published')throw new ApiError(409,'release_conflict','该版本已发布不同内容或已撤回。');
    return publicInfo(env,info);
  }
  const now=new Date().toISOString();
  try{await env.DB.batch([
    env.DB.prepare(`INSERT INTO android_releases(id,package_name,channel,version_code,artifact_key,metadata,status,published_at)
      SELECT ?,?,?,?,?,?,'published',? WHERE NOT EXISTS(SELECT 1 FROM android_releases WHERE package_name=? AND channel=? AND version_code>=?)`)
      .bind(info.id,info.packageName,info.channel,info.versionCode,info.artifactKey,canonical,now,info.packageName,info.channel,info.versionCode),
    guard(env.DB,"EXISTS(SELECT 1 FROM android_releases WHERE id=? AND metadata=? AND status='published')",[info.id,canonical]),
    env.DB.prepare('INSERT INTO release_audit VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),info.id,'github-actions','publish',now,JSON.stringify({commit:info.commit,sha256:info.sha256})),
    env.DB.prepare('DELETE FROM mutation_assertions'),
  ]);}catch(error){
    if(/constraint|precondition|release_writes_disabled/i.test(String(error)))throw new ApiError(409,'release_conflict','版本号必须高于已有版本，且发布必须处于启用状态。');
    throw error;
  }
  return publicInfo(env,info);
}
export async function latestAndroidRelease(env:BackendEnv,pkg:unknown='com.myleafy.android'){
  const row=await env.DB.prepare("SELECT metadata,published_at FROM android_releases WHERE package_name=? AND channel='official' AND status='published' ORDER BY version_code DESC LIMIT 1")
    .bind(packageName(pkg)).first<{metadata:string;published_at:string}>();
  return {release:row?{...publicInfo(env,JSON.parse(row.metadata)),publishedAt:row.published_at}:null};
}
export async function getAndroidRelease(env:BackendEnv,id:string){
  const row=await env.DB.prepare("SELECT metadata,published_at FROM android_releases WHERE id=? AND status='published'").bind(id).first<{metadata:string;published_at:string}>();
  if(!row)throw new ApiError(410,'release_withdrawn','该版本已撤回或不可用，请重新检查更新。');
  return {...publicInfo(env,JSON.parse(row.metadata)),publishedAt:row.published_at};
}
export async function listAndroidReleases(env:BackendEnv,params:Record<string,unknown>={}){
  const page=integer(params.page??0,0,100000),pageSize=integer(params.pageSize??20,1,100);
  const rows=(await env.DB.prepare('SELECT id,metadata,status,published_at,revoked_at FROM android_releases ORDER BY version_code DESC LIMIT ? OFFSET ?').bind(pageSize,page*pageSize).all<{id:string;metadata:string;status:string;published_at:string;revoked_at:string|null}>()).results;
  const total=(await env.DB.prepare('SELECT count(*) n FROM android_releases').first<{n:number}>())!.n;
  return {items:rows.map(row=>({...JSON.parse(row.metadata),status:row.status,published_at:row.published_at,revoked_at:row.revoked_at})),total,page,pageSize};
}
export async function revokeAndroidRelease(env:BackendEnv,context:AdminContext,params:Record<string,unknown>){
  const id=text(params.id,120),now=new Date().toISOString();
  await commitAdmin(env,context,'revokeAndroidRelease','android_releases',id,[
    guard(env.DB,"EXISTS(SELECT 1 FROM android_releases WHERE id=? AND status='published')",[id]),
    env.DB.prepare("UPDATE android_releases SET status='revoked',revoked_at=? WHERE id=? RETURNING id").bind(now,id),
    env.DB.prepare('INSERT INTO release_audit VALUES(?,?,?,?,?,?)').bind(crypto.randomUUID(),id,context.id,'revoke',now,'{}'),
  ]);
  return {id,status:'revoked'};
}
