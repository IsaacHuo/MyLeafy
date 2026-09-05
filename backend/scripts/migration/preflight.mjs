import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export async function requestJSON(url,headers={},options={}){
  const response=await fetch(url,{...options,headers:{...headers,...options.headers},signal:AbortSignal.timeout(20000)});
  if(!response.ok)throw new Error(`Remote request failed with HTTP ${response.status}`);
  return response.json();
}
export async function preflight(){
  const required=['CLOUDFLARE_ACCOUNT_ID','CLOUDFLARE_API_TOKEN','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY'];
  for(const name of required)if(!process.env[name])throw new Error(`Missing ${name}`);
  const config=JSON.parse(await readFile(new URL('../../wrangler.jsonc',import.meta.url),'utf8'));
  if(config.account_id!==process.env.CLOUDFLARE_ACCOUNT_ID)throw new Error('Cloudflare account does not match the checked-in staging configuration');
  const base=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}`;
  const headers={Authorization:`Bearer ${process.env.CLOUDFLARE_API_TOKEN}`};
  const report={generated_at:new Date().toISOString(),checks:{},configuration:{
    database_export:Boolean(process.env.DATABASE_URL),email_delivery:Boolean(process.env.EMAIL_API_KEY&&process.env.EMAIL_FROM&&process.env.TEST_EMAIL_RECIPIENT),
    encrypted_backups:Boolean(process.env.BACKUP_ENCRYPTION_KEY),
  }};
  const checks={
    cloudflare_d1:async()=>{
      const data=await requestJSON(`${base}/d1/database`,headers);
      if(!data.success)throw new Error('Cloudflare rejected the request');
      const expected=config.env.staging.d1_databases[0].database_id;
      if(!data.result.some(db=>db.uuid===expected))throw new Error('Configured staging D1 database is not accessible');
      return {database_id:expected};
    },
    cloudflare_r2:async()=>{
      const data=await requestJSON(`${base}/r2/buckets`,headers);
      const expected=config.env.staging.r2_buckets[0].bucket_name;
      if(!data.success||!data.result.buckets.some(bucket=>bucket.name===expected))throw new Error('Configured staging bucket is not accessible');
      return {bucket:expected};
    },
    supabase_schema:async()=>{
      const data=await requestJSON(`${process.env.SUPABASE_URL.replace(/\/$/,'')}/rest/v1/`,{apikey:process.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`});
      const expected=JSON.parse(await readFile(new URL('../../contracts/table-mapping.json',import.meta.url),'utf8'));
      const actual=Object.keys(data.definitions??{}).sort();
      const publicTables=Object.keys(expected).filter(name=>expected[name].source.startsWith('public.'));
      const missing=publicTables.filter(name=>!actual.includes(name));
      return {public_tables:actual,missing_tables:missing,complete:missing.length===0,note:'PostgREST only. Database access is still required to inspect private/Auth schemas, grants, policies and password hashes.'};
    },
  };
  await Promise.all(Object.entries(checks).map(async([name,check])=>{
    try{report.checks[name]={ok:true,...await check()};}
    catch(error){report.checks[name]={ok:false,error:error instanceof Error?error.message:'Remote check failed'};}
  }));
  return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  try{
    const report=await preflight();
    const directory=new URL('../../.local/',import.meta.url);await mkdir(directory,{recursive:true,mode:0o700});
    await writeFile(new URL('preflight.json',directory),JSON.stringify(report,null,2)+'\n',{mode:0o600});
    console.log(JSON.stringify(report,null,2));
    if(Object.values(report.checks).some(check=>!check.ok))process.exitCode=1;
  }catch(error){console.error(error instanceof Error?error.message:'Preflight failed');process.exitCode=1;}
}
