import {cloudflareToken} from './migration/cloudflare-auth.mjs';
const account=process.env.CLOUDFLARE_ACCOUNT_ID;
if(!account)throw new Error('CLOUDFLARE_ACCOUNT_ID is required');
const response=await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/pages/projects`,{headers:{Authorization:`Bearer ${await cloudflareToken()}`}});
if(!response.ok)throw new Error(`Pages inventory failed (${response.status})`);
const data=await response.json();
console.log(JSON.stringify(data.result.map(p=>({name:p.name,subdomain:p.subdomain,production_branch:p.production_branch,
  source:p.source,bindings:{production:p.deployment_configs?.production?.services,preview:p.deployment_configs?.preview?.services}})),null,2));
