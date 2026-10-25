import {readFile,mkdir,writeFile,rm} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {backupKey,decrypt} from '../migration/snapshot.mjs';
import {restoreDatabase,sha,verifyReferences} from './snapshot.mjs';
import {LocalObjectStore} from '../../src/runtime/files';
const [directory,destination,mode]=process.argv.slice(2);
if(!directory||!destination||!['--rehearsal','--production'].includes(mode))throw new Error('Usage: restore.ts SNAPSHOT_DIRECTORY EMPTY_DESTINATION --rehearsal|--production');
const key=backupKey(),snapshot=JSON.parse(decrypt(await readFile(join(directory,'snapshot.enc')),key,'ecs-snapshot-v1').toString());
if(!snapshot.complete||snapshot.version!==1||mode==='--production'&&(!snapshot.consistent||snapshot.environment!=='production'))throw new Error('Snapshot not eligible for target');
verifyReferences(snapshot);
await mkdir(resolve(destination),{mode:0o700});
for(const store of ['files','releases'])await mkdir(join(destination,store),{mode:0o700});
await writeFile(join(destination,'maintenance'),'Restore is not yet accepted\n',{mode:0o600,flag:'wx'});
try{
 const databaseRestore=restoreDatabase(snapshot,join(destination,'database.sqlite'));
 for(const object of snapshot.objects){
  if(!['files','releases'].includes(object.store)||object.id!==sha(`${object.store==='files'?'FILES':'RELEASES'}/${object.key}`))throw new Error('Invalid object manifest');
  const bytes=decrypt(await readFile(join(directory,object.id+'.enc')),key,'ecs-object:'+object.id);
  if(bytes.length!==object.size||sha(bytes)!==object.sha256)throw new Error('Object verification failed');
  const store=new LocalObjectStore(join(destination,object.store));
  if(!await store.put(object.key,bytes,{sha256:object.sha256,customMetadata:object.customMetadata,httpMetadata:object.httpMetadata}))throw new Error('Object unexpectedly exists');
  const path=join(store.root,createHash('sha256').update(object.key).digest('hex'),'metadata.json');
  // Preserve old ETags as well as SHA-256 so conditional reads survive migration.
  if(object.httpEtag){const metadata=JSON.parse(await readFile(path,'utf8'));metadata.httpEtag=object.httpEtag;await writeFile(path,JSON.stringify(metadata),{mode:0o600});}
  const restored=await store.get(object.key);if(!restored||sha(Buffer.from(await restored.arrayBuffer()))!==object.sha256)throw new Error('Object readback failed');await restored.body.cancel();
 }
 await writeFile(join(destination,'restore-report.json'),JSON.stringify({sourceCreatedAt:snapshot.createdAt,environment:snapshot.environment,consistent:snapshot.consistent,verified:true,sourceFreezeRemoved:databaseRestore.sourceFreezeRemoved,tables:snapshot.tables.length,objects:snapshot.objects.length}),{mode:0o600});
 console.log(JSON.stringify({verified:true,maintenance:true,tables:snapshot.tables.length,objects:snapshot.objects.length}));
}catch(error){await writeFile(join(destination,'restore-failed'),'Do not activate incomplete restore\n',{mode:0o600});throw error;}
