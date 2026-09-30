import {afterEach,expect,it,vi} from 'vitest';
vi.mock('../src/signals',()=>({ChangeSignals:class {}}));
vi.mock('../src/admin-entrypoint',()=>({AdminAPI:class {}}));
import {LocalD1} from './d1-local';
import type {BackendEnv} from '../src/auth';
import {app} from '../src/index';
import {publishAndroidRelease,getAndroidRelease,releaseMetadata,uploadReleaseArtifact} from '../src/android-releases';

const databases:LocalD1[]=[];
afterEach(()=>{vi.unstubAllGlobals();for(const db of databases.splice(0))db.close();});
function setup(){
  const db=new LocalD1();databases.push(db);
  const objects=new Map<string,{size:number;customMetadata:{sha256:string}}>();
  const env={DB:db.binding(),ENVIRONMENT:'staging',API_ORIGIN:'https://api-staging.myleafy.space',SITE_ORIGIN:'https://site.test.invalid',RELEASE_PUBLISH_TOKEN:'test-only-publish-secret-at-least-32-characters',RELEASES:{
    head:async(key:string)=>objects.get(key)??null,
    put:async(key:string,_body:unknown,options:any)=>{if(objects.has(key))return null;const object={size:7,customMetadata:options.customMetadata};objects.set(key,object);return object;},
  }} as unknown as BackendEnv;
  const body={packageName:'com.myleafy.android',channel:'official',versionCode:4,versionName:'1.2.0',minSdk:29,releaseNotes:'测试版本',commit:'a'.repeat(40),artifactKey:'android/official/4/MyLeafy-Android-1.2.0.apk',sizeBytes:7,sha256:'b'.repeat(64),certificateSha256:'c'.repeat(64),githubReleaseUrl:'https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.0'};
  objects.set(body.artifactKey,{size:7,customMetadata:{sha256:body.sha256}});
  db.sqlite.prepare('INSERT INTO admin_accounts(id,username,password_hash,display_name) VALUES(?,?,?,?)').run('release-admin','release-admin','test-only','测试管理员');
  db.sqlite.prepare('INSERT INTO android_release_candidates(id,metadata,version_code,github_release_id,github_asset_id,preparation_run_id,created_at,operation_id) VALUES(?,?,?,?,?,?,?,?)')
    .run('com.myleafy.android-4',JSON.stringify(releaseMetadata(body)),4,1,2,3,new Date().toISOString(),'approved-test');
  db.sqlite.prepare("INSERT INTO android_release_operations(id,candidate_id,approved_by,approved_at,status,run_id,updated_at) VALUES(?,?,?,?,'running',?,?)")
    .run('approved-test','com.myleafy.android-4','release-admin',new Date().toISOString(),4,new Date().toISOString());
  const request=()=>new Request(`${env.API_ORIGIN}/v1/releases/android/publish?operation=approved-test`,{method:'POST',headers:{Authorization:`Bearer ${env.RELEASE_PUBLISH_TOKEN}`}});
  return {db,env,body,request,objects};
}
it('public anonymous updates and release-only publishing work during community maintenance',async()=>{
  const {env,body,request}=setup();await publishAndroidRelease(env,request(),body);
  const response=await app.request('/v1/releases/android/latest',{},env);
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({release:{versionCode:4,apkUrl:`https://downloads-staging.myleafy.space/${body.artifactKey}`}});
});
it('identical retries are idempotent; metadata changes and lower versions cannot publish',async()=>{
  const {env,body,request,db}=setup();await publishAndroidRelease(env,request(),body);await publishAndroidRelease(env,request(),body);
  expect(db.sqlite.prepare('SELECT count(*) n FROM release_audit').get()!.n).toBe(1);
  await expect(publishAndroidRelease(env,request(),{...body,releaseNotes:'different'})).rejects.toMatchObject({status:409});
  env.RELEASES.head=async()=>({size:7,customMetadata:{sha256:body.sha256}} as unknown as R2Object);
  await expect(publishAndroidRelease(env,request(),{...body,versionCode:3,artifactKey:'android/official/3/MyLeafy-Android-1.2.0.apk'})).rejects.toMatchObject({status:409});
  expect(db.sqlite.prepare('SELECT count(*) n FROM android_releases').get()!.n).toBe(1);
});
it('withdrawal blocks lookup and republication, and removes latest-version prompts',async()=>{
  const {env,body,request,db}=setup();await publishAndroidRelease(env,request(),body);db.sqlite.prepare("UPDATE android_releases SET status='revoked'").run();
  await expect(getAndroidRelease(env,'com.myleafy.android-4')).rejects.toMatchObject({status:410});
  await expect(publishAndroidRelease(env,request(),body)).rejects.toMatchObject({status:409});
  expect(await (await app.request('/v1/releases/android/latest',{},env)).json()).toEqual({release:null});
});
it('invalid credentials, unverified files, invalid paths and disabled publishing fail visibly',async()=>{
  const {env,body,request,db,objects}=setup();
  await expect(publishAndroidRelease(env,new Request(env.API_ORIGIN),body)).rejects.toMatchObject({status:401});
  objects.clear();await expect(publishAndroidRelease(env,request(),body)).rejects.toMatchObject({status:409});
  db.sqlite.prepare('UPDATE release_control SET writable=0').run();await expect(publishAndroidRelease(env,request(),body)).rejects.toMatchObject({status:503});
  expect(()=>releaseMetadata({...body,artifactKey:'../private'})).toThrow();
});
it('immutable artifact retries accept only identical hash and size',async()=>{
  const {env,body}=setup();
  const upload=(hash:string)=>new Request(env.API_ORIGIN+'?operation=approved-test',{method:'PUT',headers:{Authorization:`Bearer ${env.RELEASE_PUBLISH_TOKEN}`,'content-length':'7','x-artifact-sha256':hash},body:'1234567'});
  await expect(uploadReleaseArtifact(env,upload(body.sha256),body.artifactKey)).resolves.toMatchObject({sha256:body.sha256});
  await expect(uploadReleaseArtifact(env,upload('d'.repeat(64)),body.artifactKey)).rejects.toMatchObject({status:409});
});
it('CI token alone cannot publish or upload an official APK',async()=>{
  const {env,body}=setup();
  const request=new Request(env.API_ORIGIN,{method:'POST',headers:{Authorization:`Bearer ${env.RELEASE_PUBLISH_TOKEN}`}});
  await expect(publishAndroidRelease(env,request,body)).rejects.toMatchObject({status:403,code:'approval_required'});
  await expect(uploadReleaseArtifact(env,request,body.artifactKey)).rejects.toMatchObject({status:403});
});
