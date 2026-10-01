import assert from 'node:assert/strict';

export const account='be7d850d4b5046381fb909251b4df675';
export function deploymentTarget(environment,project){
  assert(['staging','production'].includes(environment)&&/^[a-z0-9-]+$/.test(project??''),'Explicit environment and Pages project required');
  return {environment,project,worker:`myleafy-api-${environment}`,
    api:environment==='production'?'https://api.myleafy.space':'https://api-staging.myleafy.space',
    site:environment==='production'?'https://myleafy.space':`https://${project}.pages.dev`};
}
export async function platform(path,body,method=body===undefined?'GET':'POST'){
  assert.equal(process.env.CLOUDFLARE_ACCOUNT_ID,account,'Cloudflare account mismatch');
  assert(process.env.CLOUDFLARE_API_TOKEN,'Cloudflare API token is missing');
  const response=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/${path}`,{
    method,headers:{Authorization:`Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,'Content-Type':'application/json'},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});
  const result=await response.json();
  assert(response.ok&&result.success,`Cloudflare ${path}: HTTP ${response.status}`);
  return result.result;
}
export async function verifyWorkerDomain(target){
  const hostname=new URL(target.api).hostname;
  const domains=await platform(`workers/domains?hostname=${encodeURIComponent(hostname)}`);
  assert(domains.some(domain=>domain.hostname===hostname&&domain.service===target.worker&&domain.environment==='production'),
    `Configure ${hostname} on ${target.worker} before publishing code; this workflow does not change domains`);
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

// Deploy/rollback completion can precede propagation to the HTTP edge we read.
export async function waitForDeploymentJSON(url,expected,{attempts=20,intervalMs=3000}={}){
  let observed='no response';
  for(let attempt=0;attempt<attempts;attempt++){
    const response=await fetch(url,{signal:AbortSignal.timeout(5000)});
    observed=`HTTP ${response.status}`;
    if(response.ok){
      const data=await response.json();
      assert(!data.environment||data.environment===expected.environment,'Deployment environment mismatch');
      assert(data.status!=='error','Deployed service reported unhealthy');
      if(Object.entries(expected).every(([key,value])=>data[key]===value))return data;
      observed=`commit ${data.commit??'unavailable'}`;
    }else{
      await response.body?.cancel();
      assert([404,502,503,504].includes(response.status),`Deployment verification: ${observed}`);
    }
    console.log(JSON.stringify({event:'deployment_propagation_pending',url,attempt:attempt+1,observed}));
    if(attempt+1<attempts)await new Promise(resolve=>setTimeout(resolve,intervalMs));
  }
  throw new Error(`Deployment did not propagate: ${url}, expected commit ${expected.commit}, observed ${observed}`);
}
