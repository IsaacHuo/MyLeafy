import {afterEach,expect,it,vi} from 'vitest';
import {LocalD1} from './d1-local';
import type {BackendEnv} from '../src/auth';
import type {AdminContext} from '../src/admin-auth';
import {registerAndroidCandidate,requestAndroidPublication,claimAndroidPublication,reconcileAndroidPublications,downloadAndroidCandidate} from '../src/android-candidates';
import {latestAndroidRelease,releaseMetadata} from '../src/android-releases';

const databases:LocalD1[]=[];
afterEach(()=>{vi.unstubAllGlobals();for(const db of databases.splice(0))db.close();});
function fixture(){
  const db=new LocalD1();databases.push(db);
  const now=new Date().toISOString(),admin='release-admin',session='d'.repeat(64);
  db.sqlite.prepare('INSERT INTO admin_accounts(id,username,password_hash,display_name) VALUES(?,?,?,?)').run(admin,admin,'test-only','测试管理员');
  db.sqlite.prepare('INSERT INTO admin_sessions(token_hash,admin_id,expires_at) VALUES(?,?,?)').run(session,admin,'2099-01-01T00:00:00.000Z');
  const context:AdminContext={id:admin,role:'super_admin',tokenHash:session,requestId:'test-request',ip:'192.0.2.1',userAgent:null,expiresAt:'2099-01-01T00:00:00.000Z'};
  const env={DB:db.binding(),ENVIRONMENT:'staging',API_ORIGIN:'https://api-staging.myleafy.space',GITHUB_RELEASE_TOKEN:'test-only-github',RELEASE_PUBLISH_TOKEN:'test-only-publisher-at-least-32-characters',ANDROID_SIGNING_CERTIFICATE_SHA256:'c'.repeat(64)} as BackendEnv;
  const body={packageName:'com.myleafy.android',channel:'official',versionCode:6,versionName:'1.2.2',minSdk:29,releaseNotes:'候选测试',commit:'a'.repeat(40),artifactKey:'android/official/6/MyLeafy-Android-1.2.2.apk',sizeBytes:7,sha256:'b'.repeat(64),certificateSha256:'c'.repeat(64),githubReleaseUrl:'https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.2',githubReleaseId:1,githubAssetId:2,preparationRunId:3};
  const request=new Request(env.API_ORIGIN,{headers:{Authorization:`Bearer ${env.RELEASE_PUBLISH_TOKEN}`}});
  const draft={draft:true,tag_name:'android-candidate-6',target_commitish:body.commit,assets:[{id:2,name:'MyLeafy-Android-1.2.2.apk',size:7}]};
  const fetchMock=vi.fn(async(url:unknown)=>{
    const path=String(url);
    if(path.endsWith('/releases/1'))return Response.json(draft);
    if(path.includes('/check-runs'))return Response.json({check_runs:[{name:'CI result',conclusion:'success',app:{slug:'github-actions'}}]});
    if(path.endsWith('/actions/runs/3'))return Response.json({head_sha:body.commit,head_branch:'main',event:'workflow_run',path:'.github/workflows/android-prepare.yml'});
    if(path.endsWith('/dispatches'))return new Response(null,{status:204});
    if(path.endsWith('/releases/assets/2'))return new Response(null,{status:302,headers:{location:'https://release-assets.githubusercontent.com/test.apk'}});
    if(path.includes('release-assets.githubusercontent.com'))return new Response('1234567');
    const op=db.sqlite.prepare('SELECT id FROM android_release_operations ORDER BY approved_at DESC LIMIT 1').get();
    return Response.json({id:4,status:'in_progress',head_branch:'main',event:'workflow_dispatch',path:'.github/workflows/android-release.yml',display_title:`Android publication ${op?.id}`});
  });vi.stubGlobal('fetch',fetchMock);
  return {db,env,context,body,request,draft,fetchMock,now};
}
it('preparation is private and identical registration can resume without rewriting metadata',async()=>{
  const {env,body,request,db}=fixture();await registerAndroidCandidate(env,request,body);await registerAndroidCandidate(env,request,body);
  expect(await latestAndroidRelease(env)).toEqual({release:null});
  expect(db.sqlite.prepare('SELECT count(*) n FROM android_release_candidates').get()!.n).toBe(1);
  await expect(registerAndroidCandidate(env,request,{...body,releaseNotes:'changed'})).rejects.toMatchObject({status:409});
});
it('only accepted super-admin requests authorize the exact candidate; duplicate clicks reuse one operation',async()=>{
  const {env,body,request,context,db,fetchMock}=fixture();await registerAndroidCandidate(env,request,body);
  await expect(requestAndroidPublication(env,{...context,role:'operator'},{id:releaseMetadata(body).id,accepted:true})).rejects.toMatchObject({status:403});
  await expect(requestAndroidPublication(env,context,{id:releaseMetadata(body).id})).rejects.toMatchObject({code:'acceptance_required'});
  const first=await requestAndroidPublication(env,context,{id:releaseMetadata(body).id,accepted:true});
  const again=await requestAndroidPublication(env,context,{id:releaseMetadata(body).id,accepted:true});expect(again.operationId).toBe(first.operationId);
  expect(db.sqlite.prepare('SELECT count(*) n FROM android_release_operations').get()!.n).toBe(1);
  expect(fetchMock.mock.calls.filter(([url])=>String(url).endsWith('/dispatches')).length).toBe(1);
  expect(await claimAndroidPublication(env,request,first.operationId,{runId:4})).toMatchObject({sha256:body.sha256});
  await expect(claimAndroidPublication(env,request,first.operationId,{runId:5})).rejects.toMatchObject({status:409});
});
it('ambiguous dispatch is preserved, then a failed task is reconciled and retried with a new authorization',async()=>{
  const {env,body,request,context,db,fetchMock}=fixture();await registerAndroidCandidate(env,request,body);
  const normal=fetchMock.getMockImplementation()!;
  fetchMock.mockImplementation(async url=>{if(String(url).endsWith('/dispatches'))throw new Error('network');return normal(url);});
  await expect(requestAndroidPublication(env,context,{id:releaseMetadata(body).id,accepted:true})).rejects.toMatchObject({code:'github_unavailable'});
  const op=db.sqlite.prepare('SELECT * FROM android_release_operations').get()!;expect(op.status).toBe('pending');
  fetchMock.mockImplementation(normal);await claimAndroidPublication(env,request,String(op.id),{runId:4});
  fetchMock.mockImplementation(async url=>String(url).endsWith('/actions/runs/4')?Response.json({id:4,status:'completed',conclusion:'cancelled'}):normal(url));
  await reconcileAndroidPublications(env);
  expect(db.sqlite.prepare('SELECT status FROM android_release_operations').get()!.status).toBe('failed');
  const retry=await requestAndroidPublication(env,context,{id:releaseMetadata(body).id,accepted:true});expect(retry.operationId).not.toBe(op.id);
  await expect(claimAndroidPublication(env,request,String(op.id),{runId:4})).rejects.toMatchObject({status:409});
});
it('candidate download streams bytes without exposing GitHub credentials; changed drafts cannot be published',async()=>{
  const {env,body,request,context,draft}=fixture();await registerAndroidCandidate(env,request,body);
  const response=await downloadAndroidCandidate(env,context,releaseMetadata(body).id);
  expect(await response.text()).toBe('1234567');expect(response.headers.get('cache-control')).toBe('private, no-store');
  draft.draft=false;
  await expect(requestAndroidPublication(env,context,{id:releaseMetadata(body).id,accepted:true})).rejects.toMatchObject({status:409});
});
it('untrusted signing certificates and failed CI cannot register a candidate',async()=>{
  const {env,body,request,fetchMock}=fixture();
  await expect(registerAndroidCandidate(env,request,{...body,certificateSha256:'e'.repeat(64)})).rejects.toMatchObject({code:'certificate_mismatch'});
  const normal=fetchMock.getMockImplementation()!;
  fetchMock.mockImplementation(async url=>String(url).includes('check-runs')?Response.json({check_runs:[]}):normal(url));
  await expect(registerAndroidCandidate(env,request,body)).rejects.toMatchObject({code:'unverified_candidate'});
});
