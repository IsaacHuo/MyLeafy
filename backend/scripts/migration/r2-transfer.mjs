import { readFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { backupKey, digest, Vault } from './snapshot.mjs';
import { remoteQuery } from './d1-transfer.mjs';

const [environment,directory]=process.argv.slice(2);
if(!['staging','production'].includes(environment)||!directory)throw new Error('Usage: r2-transfer.mjs staging|production BACKUP_DIRECTORY');
const config=JSON.parse(await readFile(new URL('../../wrangler.jsonc',import.meta.url),'utf8'));
if(config.account_id!==process.env.CLOUDFLARE_ACCOUNT_ID||!config.env[environment])throw new Error('Target environment is not provisioned');
if(environment==='production'&&!process.env.CUTOVER_BACKUP_ID)throw new Error('CUTOVER_BACKUP_ID is required for a production transfer');
const [state]=await remoteQuery(config,environment,'SELECT mode FROM backend_control WHERE id=1');
if(state?.mode!=='read_only')throw new Error('Freeze the target before transferring objects');
const vault=new Vault(directory,backupKey(),basename(resolve(directory))),manifest=await vault.getJSON('files-manifest');
if(!manifest.complete)throw new Error('Source file backup is incomplete');
let progress;
try{progress=await vault.getJSON(`r2-${environment}-transfer`);}
catch(error){if(error.code!=='ENOENT')throw error;progress={complete:false,objects:{}};}
const base=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}/r2/buckets/${config.env[environment].r2_buckets[0].bucket_name}/objects/`;
// This is the same authenticated object API used by the pinned Wrangler R2 CLI.
async function object(path,method='GET',body,contentType){
  const response=await fetch(base+path.split('/').map(encodeURIComponent).join('/'),{method,headers:{Authorization:`Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,...(contentType?{'Content-Type':contentType}:{}),...(body?{'Content-Length':String(body.length)}:{})},body,signal:AbortSignal.timeout(60000)});
  if(response.status===404&&method==='GET')return null;
  if(!response.ok)throw new Error(`R2 ${method} failed (HTTP ${response.status})`);return response;
}
for(const [id,file] of Object.entries(manifest.objects)){
  const path=`${file.bucket}/${file.path}`,bytes=await vault.get(file.chunk.name,file.chunk);
  const current=await object(path),currentBytes=current?Buffer.from(await current.arrayBuffer()):null;
  if(currentBytes&&digest(currentBytes)===file.chunk.sha256){progress.objects[id]={...progress.objects[id],verified:true};await vault.putJSON(`r2-${environment}-transfer`,progress);continue;}
  if(!currentBytes&&!progress.objects[id]){progress.objects[id]={previous_absent:true};await vault.putJSON(`r2-${environment}-transfer`,progress);}
  if(currentBytes&&!progress.objects[id]?.previous){
    progress.objects[id]={previous:await vault.put(`r2-${environment}-previous-${id}`,currentBytes),previous_content_type:current.headers.get('content-type')};
    await vault.putJSON(`r2-${environment}-transfer`,progress);
  }
  await object(path,'PUT',bytes,file.content_type);
  const copied=await object(path);if(!copied||digest(Buffer.from(await copied.arrayBuffer()))!==file.chunk.sha256)throw new Error('R2 object verification failed');
  progress.objects[id]={...progress.objects[id],verified:true};await vault.putJSON(`r2-${environment}-transfer`,progress);
  console.log(JSON.stringify({verified_objects:Object.values(progress.objects).filter(value=>value.verified).length,total_objects:Object.keys(manifest.objects).length}));
}
progress.complete=true;await vault.putJSON(`r2-${environment}-transfer`,progress);
console.log(JSON.stringify({environment,verified:true,objects:Object.keys(manifest.objects).length,note:'Destination-only objects are retained for rollback; no unverified object is deleted.'}));
