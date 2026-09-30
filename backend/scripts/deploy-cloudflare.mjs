import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {deploymentTarget,currentDeployment,platform,waitForDeploymentJSON} from './deployment-platform.mjs';

const environment=process.argv[2],sha=process.env.RELEASE_COMMIT,project=process.env.CLOUDFLARE_PAGES_PROJECT;
assert(['staging','production'].includes(environment)&&/^[a-f0-9]{40}$/.test(sha??'')&&/^[a-z0-9-]+$/.test(project??''),'Explicit environment, commit and Pages project are required');
const root=resolve(import.meta.dirname,'../..');
function command(executable,args,cwd=root){return execFileSync(executable,args,{cwd,encoding:'utf8',stdio:['ignore','pipe','inherit'],env:{...process.env,WRANGLER_SEND_METRICS:'false'},maxBuffer:10*1024*1024});}
const wrangler=resolve(root,'backend/node_modules/wrangler/bin/wrangler.js');
function wrangle(args,cwd=resolve(root,'backend')){const output=command(process.execPath,[wrangler,...args],cwd);process.stdout.write(output);return output;}
assert.equal(command('git',['rev-parse','HEAD']).trim(),sha);
command('git',['merge-base','--is-ancestor',sha,'origin/main']);
const report={environment,commit:sha,startedAt:new Date().toISOString(),pagesProject:project,checks:[]};
if(environment==='production'){
  const acceptance=JSON.parse(readFileSync(resolve(root,'acceptance/deployment.json'),'utf8'));
  assert.equal(acceptance.environment,'staging');assert.equal(acceptance.commit,sha);assert.equal(acceptance.success,true);
}
const target=deploymentTarget(environment,project);
report.previous=await currentDeployment(target);
const previousHealth=await fetch(target.api+'/health',{signal:AbortSignal.timeout(20000)});assert(previousHealth.ok);
const previousInfo=await previousHealth.json();assert.equal(previousInfo.environment,environment);
report.previous.commit=previousInfo.commit??null;
// Bookmark records an independent database recovery point, never an automatic rollback instruction.
report.bookmark=wrangle(['d1','time-travel','info',`myleafy-${environment}`,'--env',environment,'--json']).trim();
mkdirSync(resolve(root,'deployment-report'),{recursive:true});
const reportPath=resolve(root,'deployment-report/deployment.json');
writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
wrangle(['d1','migrations','list',`myleafy-${environment}`,'--env',environment,'--remote']);
wrangle(['d1','migrations','apply',`myleafy-${environment}`,'--env',environment,'--remote']);
const siteOrigin=target.site;
wrangle(['deploy','--env',environment,'--var',`DEPLOY_COMMIT:${sha}`,'--var',`SITE_ORIGIN:${siteOrigin}`]);
const api=target.api;
await waitForDeploymentJSON(api+'/health',{status:'ok',environment,commit:sha});report.checks.push('worker-health-and-commit');
if(environment==='staging'){
  command(process.execPath,['backend/scripts/staging-smoke.mjs']);report.checks.push('isolated-community-smoke');
}
writeFileSync(resolve(root,'site/dist/release.json'),JSON.stringify({commit:sha,environment})+'\n');
report.pagesOutput=wrangle(['pages','deploy','dist','--config',`wrangler.${environment}.jsonc`,'--project-name',project,'--branch','main','--commit-hash',sha],resolve(root,'site'));
report.current=await currentDeployment(target);
const deployedPage=await platform(`pages/projects/${project}/deployments/${report.current.pagesDeployment}`);
assert.equal(deployedPage.deployment_trigger.metadata.commit_hash,sha);
await waitForDeploymentJSON(siteOrigin+'/release.json',{commit:sha,environment});report.checks.push('site-commit');
const denied=await fetch(siteOrigin+'/api/admin/me',{headers:{Origin:siteOrigin,'X-Leafy-Admin-CSRF':'1'},signal:AbortSignal.timeout(20000)});assert.equal(denied.status,401);report.checks.push('admin-unauthenticated-denied');
const latest=await fetch(api+'/v1/releases/android/latest',{signal:AbortSignal.timeout(20000)});assert(latest.ok);const catalogue=await latest.json();assert('release' in catalogue);report.checks.push('android-catalogue');
const websiteLatest=await fetch(siteOrigin+'/api/releases/android/latest',{signal:AbortSignal.timeout(20000)});assert(websiteLatest.ok);assert.deepEqual(await websiteLatest.json(),catalogue);report.checks.push('website-android-environment-binding');
report.success=true;report.completedAt=new Date().toISOString();writeFileSync(reportPath,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({environment,commit:sha,success:true,checks:report.checks}));
