import {test} from 'node:test';
import assert from 'node:assert/strict';
import {currentDeployment,deploymentTarget,account,waitForDeploymentJSON,stagingBase} from '../scripts/deployment-platform.mjs';

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

test('verification waits for a warming Pages edge or previous Worker, then checks the selected commit',async()=>{
  const original=globalThis.fetch;let calls=0;
  const expected={environment:'staging',commit:'selected'};
  try{
    globalThis.fetch=async()=>{calls++;return calls===1?new Response(null,{status:522}):Response.json(calls===2?{environment:'staging',commit:'previous'}:expected);};
    assert.deepEqual(await waitForDeploymentJSON('https://test.pages.dev/release.json',expected,{attempts:3,intervalMs:0}),expected);
    assert.equal(calls,3);
  }finally{globalThis.fetch=original;}
});

test('a transient verification timeout can recover within the attempt limit',async()=>{
  const original=globalThis.fetch;let calls=0;const expected={environment:'staging',commit:'selected'};
  try{
    globalThis.fetch=async()=>{calls++;if(calls===1)throw new DOMException('Timed out','TimeoutError');return Response.json(expected);};
    assert.deepEqual(await waitForDeploymentJSON('https://test.pages.dev/release.json',expected,{attempts:2,intervalMs:0}),expected);
    assert.equal(calls,2);
  }finally{globalThis.fetch=original;}
});

test('propagation timeout remains a failure with the expected and observed commit',async()=>{
  const original=globalThis.fetch;let calls=0;
  try{
    globalThis.fetch=async()=>{calls++;return Response.json({environment:'staging',commit:'previous'});};
    await assert.rejects(waitForDeploymentJSON('https://test.pages.dev/release.json',{environment:'staging',commit:'selected'},{attempts:2,intervalMs:0}),/expected commit selected, observed commit previous/);
    assert.equal(calls,2);
  }finally{globalThis.fetch=original;}
});

test('wrong environments and authorization failures stop immediately',async()=>{
  const original=globalThis.fetch;let calls=0;
  try{
    globalThis.fetch=async()=>{calls++;return Response.json({environment:'production',commit:'selected'});};
    await assert.rejects(waitForDeploymentJSON('https://test.pages.dev/release.json',{environment:'staging',commit:'selected'},{intervalMs:0}),/environment mismatch/);
    assert.equal(calls,1);
    globalThis.fetch=async()=>{calls++;return new Response(null,{status:403});};
    await assert.rejects(waitForDeploymentJSON('https://test.pages.dev/release.json',{environment:'staging',commit:'selected'},{intervalMs:0}),/HTTP 403/);
    assert.equal(calls,2);
  }finally{globalThis.fetch=original;}
});

test('staging change selection includes incomplete website deployments and rejects cross-environment evidence',async()=>{
  const original=globalThis.fetch,token=process.env.CLOUDFLARE_API_TOKEN,configuredAccount=process.env.CLOUDFLARE_ACCOUNT_ID;
  process.env.CLOUDFLARE_API_TOKEN='synthetic-test-only';process.env.CLOUDFLARE_ACCOUNT_ID=account;
  const commit='a'.repeat(40);let website=null;
  try{
    globalThis.fetch=async url=>{
      if(String(url).includes('api.cloudflare.com'))return Response.json({success:true,result:String(url).includes('/pages/')
        ?{production_branch:'main',subdomain:'actual-staging.pages.dev'}
        :{deployments:[{versions:[{percentage:100,version_id:'current-worker'}]}]}});
      if(String(url).endsWith('/health'))return Response.json({status:'ok',environment:'staging',commit});
      assert.equal(String(url),'https://actual-staging.pages.dev/release.json');
      return website?Response.json(website):new Response(null,{status:404});
    };
    assert.equal(await stagingBase('test'),'0'.repeat(40));
    website={environment:'staging',commit:'b'.repeat(40)};
    assert.equal(await stagingBase('test'),'0'.repeat(40));
    website={commit};assert.equal(await stagingBase('test'),'0'.repeat(40));
    website={environment:'staging',commit};assert.equal(await stagingBase('test'),commit);
    website={environment:'production',commit};await assert.rejects(stagingBase('test'),/environment mismatch/);
  }finally{globalThis.fetch=original;if(token===undefined)delete process.env.CLOUDFLARE_API_TOKEN;else process.env.CLOUDFLARE_API_TOKEN=token;if(configuredAccount===undefined)delete process.env.CLOUDFLARE_ACCOUNT_ID;else process.env.CLOUDFLARE_ACCOUNT_ID=configuredAccount;}
});
