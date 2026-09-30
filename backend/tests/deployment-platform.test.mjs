import {test} from 'node:test';
import assert from 'node:assert/strict';
import {currentDeployment,deploymentTarget,account} from '../scripts/deployment-platform.mjs';

test('Pages permission and automatic-deployment failures stop before Worker operations',async()=>{
  const original=globalThis.fetch,token=process.env.CLOUDFLARE_API_TOKEN,configuredAccount=process.env.CLOUDFLARE_ACCOUNT_ID;
  process.env.CLOUDFLARE_API_TOKEN='synthetic-test-only';process.env.CLOUDFLARE_ACCOUNT_ID=account;
  const calls=[];
  try{
    globalThis.fetch=async url=>{calls.push(String(url));return Response.json({success:false},{status:403});};
    await assert.rejects(currentDeployment(deploymentTarget('production','leafy')),/HTTP 403/);
    assert.equal(calls.length,1);assert(calls[0].endsWith('/pages/projects/leafy'));
    globalThis.fetch=async url=>{calls.push(String(url));return Response.json({success:true,result:{production_branch:'main',subdomain:'leafy-1j2.pages.dev',source:{config:{production_deployments_enabled:true}}}});};
    await assert.rejects(currentDeployment(deploymentTarget('production','leafy')),/Disable Pages/);
    assert.equal(calls.length,2);assert(calls.every(url=>url.includes('/pages/')));
  }finally{globalThis.fetch=original;if(token===undefined)delete process.env.CLOUDFLARE_API_TOKEN;else process.env.CLOUDFLARE_API_TOKEN=token;if(configuredAccount===undefined)delete process.env.CLOUDFLARE_ACCOUNT_ID;else process.env.CLOUDFLARE_ACCOUNT_ID=configuredAccount;}
});

test('staging uses the actual Pages subdomain and records exact prior deployment identities',async()=>{
  const original=globalThis.fetch,token=process.env.CLOUDFLARE_API_TOKEN,configuredAccount=process.env.CLOUDFLARE_ACCOUNT_ID;
  process.env.CLOUDFLARE_API_TOKEN='synthetic-test-only';process.env.CLOUDFLARE_ACCOUNT_ID=account;
  try{
    globalThis.fetch=async url=>Response.json({success:true,result:String(url).includes('/pages/')
      ?{production_branch:'main',subdomain:'test-unique.pages.dev',canonical_deployment:{id:'previous-site'}}
      :{deployments:[{versions:[{percentage:100,version_id:'previous-worker'}]}]}});
    const target=deploymentTarget('staging','test');
    assert.deepEqual(await currentDeployment(target),{workerVersion:'previous-worker',pagesDeployment:'previous-site',siteOrigin:'https://test-unique.pages.dev'});
    assert.equal(target.site,'https://test-unique.pages.dev');
  }finally{globalThis.fetch=original;if(token===undefined)delete process.env.CLOUDFLARE_API_TOKEN;else process.env.CLOUDFLARE_API_TOKEN=token;if(configuredAccount===undefined)delete process.env.CLOUDFLARE_ACCOUNT_ID;else process.env.CLOUDFLARE_ACCOUNT_ID=configuredAccount;}
});
