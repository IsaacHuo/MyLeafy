import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const environment = process.argv[2];
if (!['staging','production'].includes(environment)) throw new Error('Usage: provision.ts staging|production');
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const token = process.env.CLOUDFLARE_API_TOKEN;
if (!account || !token) throw new Error('CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are required');
const path = resolve(import.meta.dirname,'../wrangler.jsonc');
const config = JSON.parse(await readFile(path,'utf8')) as Record<string,any>;
if(config.account_id && config.account_id!==account)throw new Error('Cloudflare account does not match this project');
async function api<T>(path: string, body?: object): Promise<T> {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/${path}`, {
    method: body ? 'POST' : 'GET', headers: { Authorization: `Bearer ${token}`, 'Content-Type':'application/json' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30_000),
  });
  const result = await response.json() as { success: boolean; result: T; errors: { code: number; message: string }[] };
  if (!response.ok || !result.success) throw new Error(`Cloudflare ${path}: ${response.status} ${result.errors.map(e => `${e.code}: ${e.message}`).join('; ')}`);
  return result.result;
}
const name = `myleafy-${environment}`;
const databases = await api<{uuid: string;name: string}[]>('d1/database');
const database = databases.find(d => d.name === name) ?? await api<{uuid: string;name: string}>('d1/database',{name,primary_location_hint:'apac'});
const buckets = await api<{buckets:{name:string}[]}>('r2/buckets');
const bucket = `${name}-files`;
if (!buckets.buckets.some(b => b.name === bucket)) await api('r2/buckets',{name:bucket,locationHint:'apac'});
const envs = config.env as Record<string, any>;
const previous=envs[environment]??{};
const subdomain=environment==='staging'?await api<{subdomain:string}>('workers/subdomain'):null;
const apiOrigin=environment==='staging'?`https://myleafy-api-staging.${subdomain!.subdomain}.workers.dev`:'https://api.myleafy.space';
envs[environment] = {
  ...previous,
  name:`myleafy-api-${environment}`,workers_dev:environment==='staging',
  vars:{...previous.vars,ENVIRONMENT:environment,API_ORIGIN:apiOrigin,SITE_ORIGIN:previous.vars?.SITE_ORIGIN??(environment==='staging'?'http://localhost:5173':'https://myleafy.space')},
  d1_databases:[{binding:'DB',database_name:name,database_id:database.uuid,migrations_dir:'migrations'}],
  r2_buckets:[{binding:'FILES',bucket_name:bucket}],
  durable_objects:{bindings:[{name:'SIGNALS',class_name:'ChangeSignals'}]},
  migrations:[{tag:'v1',new_sqlite_classes:['ChangeSignals']}],
  triggers:{crons:[...new Set([...(previous.triggers?.crons??[]),'* * * * *','17 * * * *','20 17 * * *','35 18 * * *'])]},
  ...(environment==='production'?{routes:previous.routes??[{pattern:'api.myleafy.space',custom_domain:true}]}:{}),
};
await writeFile(path,JSON.stringify(config,null,2)+'\n');
console.log(JSON.stringify({environment,database:database.uuid,bucket}));
