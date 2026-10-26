// Read-only provider checks. Never sends email or dispatches a release.
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository='https://api.github.com/repos/IsaacHuo/MyLeafy';
export async function verifyCandidateAsset(asset,expected,headers,request=fetch){
 if(!Number.isSafeInteger(expected.sizeBytes)||expected.sizeBytes<=0||expected.sizeBytes>100_000_000||asset.size!==expected.sizeBytes||!Number.isSafeInteger(asset.id)||!/^[a-f0-9]{64}$/.test(expected.sha256))throw new Error('candidate_metadata');
 let response=await request(`${repository}/releases/assets/${asset.id}`,{redirect:'manual',headers:{...headers,Accept:'application/octet-stream'},signal:AbortSignal.timeout(300000)});
 if(response.status===302){
  const location=response.headers.get('location');await response.body?.cancel();
  if(!location)throw new Error('candidate_redirect');
  const url=new URL(location);
  if(url.protocol!=='https:'||url.hostname!=='release-assets.githubusercontent.com'||url.username||url.password)throw new Error('candidate_redirect');
  // Never log the temporary URL or forward the GitHub credential to it.
  response=await request(url,{redirect:'error',signal:AbortSignal.timeout(300000)});
 }
 if(response.status!==200||!response.body||response.headers.get('content-type')?.includes('json')){await response.body?.cancel();throw new Error('candidate_download');}
 const digest=createHash('sha256');let size=0;
 const reader=response.body.getReader();
 try{
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>expected.sizeBytes)throw new Error('candidate_size');digest.update(value);}
 }finally{await reader.cancel();reader.releaseLock();}
 if(size!==expected.sizeBytes||digest.digest('hex')!==expected.sha256)throw new Error('candidate_integrity');
 return {verified:true,sizeBytes:size,versionCode:expected.versionCode};
}

/**
 * @param {Record<string,string|undefined>} configuration
 * @param {{candidate?: {github_release_id:number,github_asset_id:number,metadata:string}, request?: typeof fetch}} options
 */
export async function checkServices(configuration,{candidate,request=fetch}={}){
 const result={checkedAt:new Date().toISOString(),environment:configuration.ENVIRONMENT,releaseDispatchAttempted:false,emailSent:false};
 try{
  const response=await request('https://api.resend.com/domains',{headers:{Authorization:`Bearer ${configuration.EMAIL_API_KEY??''}`},signal:AbortSignal.timeout(15000)});
  result.emailProviderHTTP=response.status;
  if(response.ok){
   const body=await response.json(),sender=configuration.EMAIL_FROM?.match(/@([^>\s]+)/)?.[1];
   result.configuredSenderDomain=sender??null;result.senderVerified=body.data?.some(d=>d.name===sender&&d.status==='verified')??false;
  }else await response.body?.cancel();
 }catch{result.emailProviderReachable=false;}
 result.githubCredentialConfigured=!!configuration.GITHUB_RELEASE_TOKEN;
 if(result.githubCredentialConfigured){
  const headers={'User-Agent':'MyLeafy-ECS-acceptance',Authorization:`Bearer ${configuration.GITHUB_RELEASE_TOKEN}`,'X-GitHub-Api-Version':'2022-11-28'};
  try{
   const workflow=await request(`${repository}/actions/workflows/android-release.yml`,{headers,signal:AbortSignal.timeout(15000)});
   result.githubHTTP=workflow.status;await workflow.body?.cancel();
   const releases=await request(`${repository}/releases?per_page=100`,{headers,signal:AbortSignal.timeout(15000)});
   result.githubReleasesHTTP=releases.status;
   if(releases.ok){
    const items=await releases.json();result.privateDraftsReadable=items.filter(item=>item.draft).length;
    if(candidate){
     const draft=items.find(item=>item.id===candidate.github_release_id),expected=JSON.parse(candidate.metadata);
     const asset=draft?.assets?.find(item=>item.id===candidate.github_asset_id);
     if(!draft?.draft||draft.tag_name!==`android-candidate-${expected.versionCode}`||draft.target_commitish!==expected.commit||!asset||asset.name!==`MyLeafy-Android-${expected.versionName}.apk`)throw new Error('candidate_metadata');
     result.candidateDownload=await verifyCandidateAsset(asset,expected,headers,request);
    }
   }else await releases.body?.cancel();
  }catch(error){
   result.githubCheckFailed=true;
   const safeCodes=['candidate_metadata','candidate_redirect','candidate_download','candidate_size','candidate_integrity'];
   result.githubError=safeCodes.includes(error?.message)?error.message:'github_request_failed';
  }
 }
 result.ok=result.emailProviderHTTP===200&&result.senderVerified===true&&result.githubHTTP===200&&result.githubReleasesHTTP===200&&!result.githubCheckFailed&&(!candidate||result.candidateDownload?.verified===true);
 return result;
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const args=process.argv.slice(2);let candidate;
 if(args.length){
  if(args.length!==2||args[0]!=='--candidate-database')throw new Error('Usage: check-services.mjs [--candidate-database REHEARSAL_DATABASE]');
  const {default:SQLite}=await import('better-sqlite3');
  const db=new SQLite(args[1],{readonly:true,fileMustExist:true});
  try{candidate=db.prepare('SELECT metadata,github_release_id,github_asset_id FROM android_release_candidates ORDER BY version_code DESC LIMIT 1').get();}finally{db.close();}
  if(!candidate)throw new Error('No retained candidate available for verification');
 }
 const report=await checkServices(process.env,{candidate});console.log(JSON.stringify(report));
 if(!report.ok)process.exitCode=1;
}
