import {source,quote} from './cloudflare.mjs';
import {inspectSchema,selectRows,sha,verifyReferences} from './snapshot.mjs';
import {backupKey,encrypt} from '../migration/snapshot.mjs';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const [environment,directory,mode]=process.argv.slice(2);
if(!directory||!['--rehearsal','--quiesced'].includes(mode))throw new Error('Usage: export.mjs staging|production PRIVATE_DIRECTORY --rehearsal|--quiesced');
const key=backupKey(),remote=await source(environment);
if(mode==='--quiesced'){
 if(!process.env.SOURCE_FREEZE_REPORT)throw new Error('SOURCE_FREEZE_REPORT is required');
 const report=JSON.parse(await readFile(process.env.SOURCE_FREEZE_REPORT,'utf8'));
 const deployed=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
 if(!report.complete||!report.allEntrypointsBlocked||report.environment!==environment||report.worker!==remote.selected.name||report.database!==remote.selected.d1_databases[0].database_id||deployed?.length!==1||deployed[0].percentage!==100||deployed[0].version_id!==report.freezeVersion)throw new Error('Authenticated source freeze evidence does not match active deployment');
}
await mkdir(resolve(directory),{mode:0o700}); // refuses an existing/incomplete directory
const snapshot={version:1,environment,createdAt:new Date().toISOString(),consistent:mode==='--quiesced',complete:false,schema:[],tables:[],objects:[]};
const save=async()=>writeFile(resolve(directory,'snapshot.enc'),encrypt(Buffer.from(JSON.stringify(snapshot)),key,'ecs-snapshot-v1'),{mode:0o600});
await save();
snapshot.schema=await remote.query("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name");
snapshot.sequences=await remote.query('SELECT name,CAST(seq AS TEXT) seq FROM sqlite_sequence ORDER BY name');
for(const table of inspectSchema(snapshot.schema).tables){
 const columns=(await remote.query(`PRAGMA table_xinfo(${quote(table.name)})`)).filter(c=>c.hidden===0);
 const withoutRowid=/WITHOUT\s+ROWID/i.test(table.sql),rows=[];
 for(let offset=0;;offset+=200){const batch=await remote.query(`${selectRows(table.name,columns,withoutRowid)} LIMIT 200 OFFSET ${offset}`);rows.push(...batch.map(r=>JSON.parse(r.snapshot_row)));if(batch.length<200)break;}
 snapshot.tables.push({name:table.name,columns,withoutRowid,rows,sha256:sha(JSON.stringify(rows))});await save();
}
// R2's authenticated object API preserves binary bodies and object metadata.
for(const binding of remote.selected.r2_buckets){
 let cursor='';
 do{
  const base=`/r2/buckets/${binding.bucket_name}/objects`;
  const listed=await (await remote.request(`${base}?per_page=100${cursor?'&cursor='+encodeURIComponent(cursor):''}`)).json();
  if(!listed.success||!Array.isArray(listed.result))throw new Error('R2 inventory failed');
  for(const object of listed.result){
   const response=await remote.request(`${base}/${object.key.split('/').map(encodeURIComponent).join('/')}`);
   const bytes=Buffer.from(await response.arrayBuffer()),hash=sha(bytes);
   if(bytes.length!==Number(object.size))throw new Error('R2 object size changed during snapshot');
   const id=sha(`${binding.binding}/${object.key}`);
   await writeFile(resolve(directory,id+'.enc'),encrypt(bytes,key,'ecs-object:'+id),{mode:0o600,flag:'wx'});
   snapshot.objects.push({store:binding.binding==='FILES'?'files':'releases',key:object.key,size:bytes.length,sha256:hash,id,httpEtag:response.headers.get('etag'),httpMetadata:{contentType:response.headers.get('content-type')??'application/octet-stream',cacheControl:response.headers.get('cache-control')??undefined,contentDisposition:response.headers.get('content-disposition')??undefined,contentEncoding:response.headers.get('content-encoding')??undefined,contentLanguage:response.headers.get('content-language')??undefined},customMetadata:{...object.custom_metadata,sha256:hash}});
  }
  cursor=listed.result_info?.is_truncated?listed.result_info.cursor:'';await save();
 }while(cursor);
}
verifyReferences(snapshot);snapshot.complete=true;await save();
console.log(JSON.stringify({environment,complete:true,consistent:snapshot.consistent,tables:snapshot.tables.length,objects:snapshot.objects.length}));
