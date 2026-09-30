import {execFileSync} from 'node:child_process';
import {platform} from './deployment-platform.mjs';
import assert from 'node:assert/strict';

const projects=await platform('pages/projects');
const production=projects.find(p=>p.name==='leafy');
assert(production?.source?.config?.production_deployments_enabled===false,'Disable leafy automatic production deployment before configuring delivery');
let staging=projects.find(p=>p.name==='myleafy-site-staging');
if(!staging)staging=await platform('pages/projects',{name:'myleafy-site-staging',production_branch:'main'});
assert(!staging.source||staging.source.config.production_deployments_enabled===false,'Staging Pages must use controlled deployments');
async function gh(args,input){
  for(let attempt=0;attempt<3;attempt++){
    try{return execFileSync('gh',args,{encoding:'utf8',input,stdio:['pipe','pipe','pipe'],timeout:30000});}
    catch(error){
      if(attempt===2||!/handshake|timeout|connection reset/i.test(String(error.stderr)))throw new Error(`GitHub configuration failed: ${args.slice(0,3).join(' ')}`);
      await new Promise(r=>setTimeout(r,1000*(attempt+1)));
    }
  }
}
for(const [environment,project] of [['staging',staging],['production',production]]){
  await gh(['secret','set','CLOUDFLARE_API_TOKEN','--env',environment],process.env.CLOUDFLARE_API_TOKEN);
  const path=`repos/IsaacHuo/MyLeafy/environments/${environment}/variables`;
  const existing=JSON.parse(await gh(['api',path])).variables.find(v=>v.name==='CLOUDFLARE_PAGES_PROJECT');
  await gh(['api',existing?path+'/CLOUDFLARE_PAGES_PROJECT':path,'-X',existing?'PATCH':'POST','-f','name=CLOUDFLARE_PAGES_PROJECT','-f',`value=${project.name}`]);
  console.log(JSON.stringify({environment,pagesProject:project.name,site:`https://${project.subdomain}`,credentialConfigured:true}));
}
