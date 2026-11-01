import {readFile} from 'node:fs/promises';
import {decrypt} from '../migration/snapshot.mjs';
import {sha} from './snapshot.mjs';
import {inspectSchema} from './sql.mjs';

export function validateResume(snapshot,environment,schema,frozenAt){
 if(snapshot.version!==1||snapshot.environment!==environment||!snapshot.consistent||snapshot.complete||!Number.isFinite(Date.parse(frozenAt))||!Number.isFinite(Date.parse(snapshot.createdAt))||Date.parse(snapshot.createdAt)<Date.parse(frozenAt))throw new Error('Snapshot is not eligible for frozen-source resume');
 if(JSON.stringify(snapshot.schema)!==JSON.stringify(schema))throw new Error('Source schema changed since export');
 const names=inspectSchema(schema).tables.map(t=>t.name);
 if(snapshot.tables.length>names.length||snapshot.tables.some((table,i)=>table.name!==names[i]||sha(JSON.stringify(table.rows))!==table.sha256))throw new Error('Table checkpoint is invalid');
 const seen=new Set();
 for(const object of snapshot.objects){
  if(!['files','releases'].includes(object.store)||object.id!==sha(`${object.store==='files'?'FILES':'RELEASES'}/${object.key}`)||seen.has(object.id))throw new Error('Object checkpoint is invalid');
  seen.add(object.id);
 }
}

export async function verifyCachedObject(path,key,object){
 const bytes=decrypt(await readFile(path),key,'ecs-object:'+object.id);
 if(bytes.length!==object.size||sha(bytes)!==object.sha256)throw new Error('Cached object integrity failed');
}

export async function downloadObject(remote,path,expectedSize,{pause=ms=>new Promise(done=>setTimeout(done,ms))}={}){
 for(let attempt=0;attempt<4;attempt++){
  try{
   const response=await remote.request(path,{timeoutMs:300000});
   // A successful header does not prove the full body arrived. Retry the whole
   // immutable GET if the connection closes while consuming the body.
   const bytes=Buffer.from(await response.arrayBuffer());
   if(bytes.length!==Number(expectedSize))throw new Error('R2 object size changed during snapshot');
   return {response,bytes};
  }catch(error){
   const transient=['UND_ERR_CONNECT_TIMEOUT','UND_ERR_SOCKET','ECONNRESET','ETIMEDOUT','EAI_AGAIN'].includes(error.cause?.code)||['AbortError','TimeoutError'].includes(error.name);
   if(!transient||attempt===3)throw error;
   console.log(JSON.stringify({event:'object_body_retry',attempt:attempt+1}));
   await pause(1000*2**attempt);
  }
 }
 throw new Error('Object download retry budget exhausted');
}
