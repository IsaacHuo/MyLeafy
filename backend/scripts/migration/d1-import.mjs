import {createHash,randomUUID} from 'node:crypto';
import {cloudflareToken,cloudflareRequest} from './cloudflare-auth.mjs';
import {backupKey,Vault} from './snapshot.mjs';

/** Uses the same documented init/upload/ingest/poll protocol as Wrangler. */
export async function importSQL(config,environment,sql){
  const endpoint=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}/d1/database/${config.env[environment].d1_databases[0].database_id}/import`;
  const bytes=Buffer.from(sql),etag=createHash('md5').update(bytes).digest('hex');
  async function failure(payload){
    const id=randomUUID(),directory=new URL(`../../.local/import-diagnostics/${id}/`,import.meta.url).pathname;
    await new Vault(directory,backupKey(),id).putJSON('cloudflare-error',payload);
    const message=JSON.stringify(payload);
    const reason=['FOREIGN KEY constraint','UNIQUE constraint','CHECK constraint','no such table','syntax error','too large'].find(term=>message.includes(term))??'remote_error';
    throw new Error(`D1 import failed (${reason}); encrypted diagnostic ${id}; keep the target frozen`);
  }
  async function call(body){
    const response=await cloudflareRequest(endpoint,{method:'POST',headers:{Authorization:`Bearer ${await cloudflareToken()}`,'Content-Type':'application/json'},body:JSON.stringify(body),timeoutMs:300000});
    const payload=await response.json();
    if(!response.ok||!payload.success)return failure(payload);
    return payload.result;
  }
  let state=await call({action:'init',etag});
  if(state.upload_url){
    const destination=new URL(state.upload_url);
    if(destination.protocol!=='https:'||!destination.hostname.endsWith('.r2.cloudflarestorage.com'))throw new Error('Unexpected D1 upload destination');
    console.log(JSON.stringify({event:'d1_sql_upload',bytes:bytes.length}));
    const uploaded=await cloudflareRequest(destination,{method:'PUT',headers:{'Content-Length':String(bytes.length)},body:bytes,redirect:'error',timeoutMs:300000});
    if(!uploaded.ok||uploaded.headers.get('etag')?.replaceAll('"','')!==etag)throw new Error(`D1 SQL upload was not verified (HTTP ${uploaded.status})`);
    console.log(JSON.stringify({event:'d1_sql_uploaded',verified:true}));
    state=await call({action:'ingest',filename:state.filename,etag});
  }
  const deadline=Date.now()+30*60*1000;
  while(true){
    if(!state.success||state.status==='error')return failure(state);
    if(state.status==='complete'){
      console.log(JSON.stringify({event:'d1_import_complete',queries:state.result?.num_queries}));return;
    }
    if(Date.now()>deadline)throw new Error('D1 import still running; keep target frozen and inspect its import status');
    console.log(JSON.stringify({event:'d1_import_pending',status:state.status}));
    await new Promise(resolve=>setTimeout(resolve,2000));
    state=await call({action:'poll',current_bookmark:state.at_bookmark});
  }
}
