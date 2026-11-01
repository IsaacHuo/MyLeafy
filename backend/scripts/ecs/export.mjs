import {source} from './cloudflare.mjs';
import {quote,inspectSchema} from './sql.mjs';
import {selectRows,sha,verifyReferences} from './snapshot.mjs';
import {backupKey,encrypt,decrypt} from '../migration/snapshot.mjs';
import {validateResume,verifyCachedObject,downloadObject} from './export-objects.mjs';
import {mkdir,writeFile,readFile,rename,access} from 'node:fs/promises';
import {resolve} from 'node:path';
const [environment,directory,mode,resume]=process.argv.slice(2);
if(!directory||!['--rehearsal','--quiesced'].includes(mode)||resume&&resume!=='--resume'||resume&&mode!=='--quiesced')throw new Error('Usage: export.mjs staging|production PRIVATE_DIRECTORY --rehearsal|--quiesced [--resume (quiesced only)]');
const key=backupKey(),remote=await source(environment);
let freezeReport;
if(mode==='--quiesced'){
 if(!process.env.SOURCE_FREEZE_REPORT)throw new Error('SOURCE_FREEZE_REPORT is required');
 const report=JSON.parse(await readFile(process.env.SOURCE_FREEZE_REPORT,'utf8'));
 freezeReport=report;
 const deployed=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
 if(!report.complete||!report.databaseFrozen||!report.allEntrypointsBlocked||report.environment!==environment||report.worker!==remote.selected.name||report.database!==remote.selected.d1_databases[0].database_id||deployed?.length!==1||deployed[0].percentage!==100||deployed[0].version_id!==report.freezeVersion)throw new Error('Authenticated source freeze evidence does not match active deployment');
 const state=await remote.query('SELECT frozen FROM _ecs_source_freeze WHERE id=1');
 const triggers=await remote.query("SELECT name FROM sqlite_schema WHERE type='trigger' AND name GLOB 'ecs_source_fence_*'");
 if(state[0]?.frozen!==1||JSON.stringify(triggers.map(t=>t.name).sort())!==JSON.stringify(report.fenceTriggers.slice().sort()))throw new Error('Source database fence verification failed');
}
if(!resume)await mkdir(resolve(directory),{mode:0o700});
const snapshot=resume?JSON.parse(decrypt(await readFile(resolve(directory,'snapshot.enc')),key,'ecs-snapshot-v1')):{version:1,environment,createdAt:new Date().toISOString(),consistent:mode==='--quiesced',complete:false,schema:[],tables:[],objects:[]};
const save=async()=>{const temporary=resolve(directory,'snapshot.partial');await writeFile(temporary,encrypt(Buffer.from(JSON.stringify(snapshot)),key,'ecs-snapshot-v1'),{mode:0o600});await rename(temporary,resolve(directory,'snapshot.enc'));};
const schema=await remote.query("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name");
if(resume)validateResume(snapshot,environment,schema,freezeReport?.frozenAt);
else{snapshot.schema=schema;snapshot.sequences=await remote.query('SELECT name,CAST(seq AS TEXT) seq FROM sqlite_sequence ORDER BY name');await save();}
for(const table of inspectSchema(snapshot.schema).tables.slice(snapshot.tables.length)){
 const columns=(await remote.query(`PRAGMA table_xinfo(${quote(table.name)})`)).filter(c=>c.hidden===0);
 const withoutRowid=/WITHOUT\s+ROWID/i.test(table.sql),rows=[];
 for(let offset=0;;offset+=200){const batch=await remote.query(`${selectRows(table.name,columns,withoutRowid)} LIMIT 200 OFFSET ${offset}`);rows.push(...batch.map(r=>JSON.parse(r.snapshot_row)));if(batch.length<200)break;}
 snapshot.tables.push({name:table.name,columns,withoutRowid,rows,sha256:sha(JSON.stringify(rows))});await save();
}
// R2's authenticated object API preserves binary bodies and object metadata.
const cached=new Map(snapshot.objects.map(object=>[object.id,object])),seen=new Set();
for(const binding of remote.selected.r2_buckets){
 let cursor='';
 do{
  const base=`/r2/buckets/${binding.bucket_name}/objects`;
  const listed=await (await remote.request(`${base}?per_page=100${cursor?'&cursor='+encodeURIComponent(cursor):''}`)).json();
  if(!listed.success||!Array.isArray(listed.result))throw new Error('R2 inventory failed');
  for(const object of listed.result){
   const id=sha(`${binding.binding}/${object.key}`);
   if(seen.has(id))throw new Error('Duplicate source object');seen.add(id);
   const path=resolve(directory,id+'.enc'),previous=cached.get(id);
   if(previous){
    if(previous.size!==Number(object.size)||object.custom_metadata?.sha256&&previous.sha256!==object.custom_metadata.sha256)throw new Error('Source object changed since checkpoint');
    await verifyCachedObject(path,key,previous);continue;
   }
   const {response,bytes}=await downloadObject(remote,`${base}/${object.key.split('/').map(encodeURIComponent).join('/')}`,object.size),hash=sha(bytes);
   if(object.custom_metadata?.sha256&&object.custom_metadata.sha256!==hash)throw new Error('Source object checksum mismatch');
   let existing=false;try{await access(path);existing=true;}catch(error){if(error.code!=='ENOENT')throw error;}
   if(existing)await verifyCachedObject(path,key,{id,size:bytes.length,sha256:hash});
   else await writeFile(path,encrypt(bytes,key,'ecs-object:'+id),{mode:0o600,flag:'wx'});
   snapshot.objects.push({store:binding.binding==='FILES'?'files':'releases',key:object.key,size:bytes.length,sha256:hash,id,httpEtag:response.headers.get('etag'),httpMetadata:{contentType:response.headers.get('content-type')??'application/octet-stream',cacheControl:response.headers.get('cache-control')??undefined,contentDisposition:response.headers.get('content-disposition')??undefined,contentEncoding:response.headers.get('content-encoding')??undefined,contentLanguage:response.headers.get('content-language')??undefined},customMetadata:{...object.custom_metadata,sha256:hash}});
   await save();
  }
  cursor=listed.result_info?.is_truncated?listed.result_info.cursor:'';await save();
 }while(cursor);
}
if([...cached.keys()].some(id=>!seen.has(id)))throw new Error('Source object disappeared since checkpoint');
verifyReferences(snapshot);snapshot.complete=true;await save();
console.log(JSON.stringify({environment,complete:true,consistent:snapshot.consistent,tables:snapshot.tables.length,objects:snapshot.objects.length}));
