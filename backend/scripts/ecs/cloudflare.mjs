import {readFile} from 'node:fs/promises';
import {cloudflareToken,cloudflareRequest} from '../migration/cloudflare-auth.mjs';
export async function source(environment){
  if(!['staging','production'].includes(environment))throw new Error('Invalid environment');
  const config=JSON.parse(await readFile(new URL('../../wrangler.jsonc',import.meta.url),'utf8'));
  const selected=config.env[environment];
  const base=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}`;
  async function request(path,options={}){
    const response=await cloudflareRequest(base+path,{...options,headers:{Authorization:`Bearer ${await cloudflareToken()}`,...options.headers}});
    if(!response.ok)throw new Error(`Cloudflare request failed (${response.status}); credentials and response body omitted`);
    return response;
  }
  async function query(sql,params=[]){
    const body=await (await request(`/d1/database/${selected.d1_databases[0].database_id}/query`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sql,params})})).json();
    if(!body.success||body.result.some(r=>!r.success))throw new Error('D1 query failed; response omitted');
    return body.result[0].results;
  }
  return {config,selected,query,request};
}
