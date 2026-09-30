import assert from 'node:assert/strict';

export const account='be7d850d4b5046381fb909251b4df675';
export function deploymentTarget(environment,project){
  assert(['staging','production'].includes(environment)&&/^[a-z0-9-]+$/.test(project??''),'Explicit environment and Pages project required');
  return {environment,project,worker:`myleafy-api-${environment}`,
    api:environment==='production'?'https://api.myleafy.space':'https://api-staging.myleafy.space',
    site:environment==='production'?'https://myleafy.space':`https://${project}.pages.dev`};
}
export async function platform(path,body){
  assert.equal(process.env.CLOUDFLARE_ACCOUNT_ID,account,'Cloudflare account mismatch');
  assert(process.env.CLOUDFLARE_API_TOKEN,'Cloudflare API token is missing');
  const response=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/${path}`,{
    method:body===undefined?'GET':'POST',headers:{Authorization:`Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,'Content-Type':'application/json'},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});
  const result=await response.json();
  assert(response.ok&&result.success,`Cloudflare ${path}: HTTP ${response.status}`);
  return result.result;
}
export async function currentDeployment(target){
  // Check Pages permission before any migration or Worker mutation.
  const project=await platform(`pages/projects/${target.project}`);
  assert.equal(project.production_branch,'main','Pages production branch must be main');
  assert(/^[a-z0-9-]+\.pages\.dev$/.test(project.subdomain),'Invalid Pages project subdomain');
  target.site=target.environment==='production'?'https://myleafy.space':`https://${project.subdomain}`;
  assert(!project.source||project.source.config?.production_deployments_enabled===false,'Disable Pages automatic production deployments first');
  const deployments=await platform(`workers/scripts/${target.worker}/deployments`);
  const versions=deployments.deployments[0]?.versions;
  assert(versions?.length===1&&versions[0].percentage===100,'Expected one active Worker version');
  return {workerVersion:versions[0].version_id,pagesDeployment:project.canonical_deployment?.id??null,siteOrigin:target.site};
}

export async function stagingBase(project){
  const target=deploymentTarget('staging',project);
  await currentDeployment(target);
  const health=await fetch(target.api+'/health',{signal:AbortSignal.timeout(20000)});assert(health.ok,'Staging health unavailable');
  const worker=await health.json();assert.equal(worker.environment,'staging');assert.equal(worker.status,'ok');
  const page=await fetch(target.site+'/release.json',{signal:AbortSignal.timeout(20000)});
  assert(page.ok||page.status===404,`Staging website verification: HTTP ${page.status}`);
  const website=page.ok&&page.headers.get('content-type')?.includes('application/json')?await page.json():null;
  if(website?.environment)assert.equal(website.environment,'staging','Staging website environment mismatch');
  if(/^[a-f0-9]{40}$/.test(worker.commit??'')&&website?.environment==='staging'&&website.commit===worker.commit)return worker.commit;
  // A half-finished deployment must be retried even if the Worker is already current.
  console.error(JSON.stringify({event:'staging_incomplete_prepare_again',workerCommit:worker.commit??null,websiteCommit:website?.commit??null}));
  return '0'.repeat(40);
}

// Deploy/rollback completion can precede propagation to the HTTP edge we read.
export async function waitForDeploymentJSON(url,expected,{attempts=20,intervalMs=3000}={}){
  let observed='no response';
  for(let attempt=0;attempt<attempts;attempt++){
    let response;
    try{response=await fetch(url,{signal:AbortSignal.timeout(5000)});}
    catch(error){
      if(!['TimeoutError','AbortError'].includes(error.name)&&!['UND_ERR_CONNECT_TIMEOUT','ECONNRESET','ETIMEDOUT','EAI_AGAIN'].includes(error.cause?.code))throw error;
      observed=error.cause?.code??error.name;
    }
    if(response)observed=`HTTP ${response.status}`;
    if(response?.ok){
      if(!response.headers.get('content-type')?.includes('application/json')){
        await response.body?.cancel();observed='HTTP 200 without deployment JSON';
      }else{
        const data=await response.json();
        assert(!data.environment||data.environment===expected.environment,'Deployment environment mismatch');
        assert(data.status!=='error','Deployed service reported unhealthy');
        if(Object.entries(expected).every(([key,value])=>data[key]===value))return data;
        observed=`commit ${data.commit??'unavailable'}`;
      }
    }else if(response){
      await response.body?.cancel();
      assert(response.status===404||response.status>=500,`Deployment verification: ${observed}`);
    }
    console.log(JSON.stringify({event:'deployment_propagation_pending',url,attempt:attempt+1,observed}));
    if(attempt+1<attempts)await new Promise(resolve=>setTimeout(resolve,intervalMs));
  }
  throw new Error(`Deployment did not propagate: ${url}, expected commit ${expected.commit}, observed ${observed}`);
}
