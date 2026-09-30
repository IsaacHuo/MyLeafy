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
