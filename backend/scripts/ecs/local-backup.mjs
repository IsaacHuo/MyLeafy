import {inspectSchema} from './sql.mjs';
import SQLite from 'better-sqlite3';
import {readFile,readdir,mkdir,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {parseEnv} from 'node:util';
import {spawnSync} from 'node:child_process';
import {backupKey,encrypt} from '../migration/snapshot.mjs';
import {selectRows,sha,verifyReferences} from './snapshot.mjs';
const [root,backupRoot,envFile,environment]=process.argv.slice(2);
if(!root||!backupRoot||!envFile||!['staging','production'].includes(environment))throw new Error('Usage: local-backup.mjs STOPPED_DATA_DIRECTORY BACKUP_DIRECTORY ENV_FILE staging|production');
const configuration=parseEnv(await readFile(envFile,'utf8'));
if(configuration.ENVIRONMENT!==environment||resolve(configuration.DATA_DIRECTORY??'')!==resolve(root))throw new Error('Backup environment and data directory must match protected runtime configuration');
const key=backupKey(),id='snapshot-'+new Date().toISOString().replace(/[:.]/g,'-');
await mkdir(backupRoot,{recursive:true,mode:0o700});
const directory=join(backupRoot,id+'.partial');await mkdir(directory,{mode:0o700});
const snapshot={version:1,environment,createdAt:new Date().toISOString(),consistent:true,complete:false,schema:[],tables:[],objects:[]};
const save=()=>writeFile(join(directory,'snapshot.enc'),encrypt(Buffer.from(JSON.stringify(snapshot)),key,'ecs-snapshot-v1'),{mode:0o600});
await save();
const db=new SQLite(join(root,'database.sqlite'),{readonly:true,fileMustExist:true});
try{
 snapshot.schema=db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY type,name").all();
 snapshot.sequences=db.prepare('SELECT name,CAST(seq AS TEXT) seq FROM sqlite_sequence ORDER BY name').all();
 for(const table of inspectSchema(snapshot.schema).tables){
  const columns=db.prepare(`PRAGMA table_xinfo("${table.name.replaceAll('"','""')}")`).all().filter(c=>c.hidden===0),withoutRowid=/WITHOUT\s+ROWID/i.test(table.sql);
  const rows=db.prepare(selectRows(table.name,columns,withoutRowid)).all().map(r=>JSON.parse(r.snapshot_row));
  snapshot.tables.push({name:table.name,columns,withoutRowid,rows,sha256:sha(JSON.stringify(rows))});
 }
}finally{db.close();}
for(const store of ['files','releases']){
 for(const entry of await readdir(join(root,store),{withFileTypes:true})){
  if(entry.isDirectory()&&/^\.pending-[a-f0-9-]{36}$/.test(entry.name)){await rm(join(root,store,entry.name),{recursive:true});continue;}
  if(!entry.isDirectory()||!/^\w{64}$/.test(entry.name))throw new Error('Unexpected object-store entry');
  const path=join(root,store,entry.name),metadata=JSON.parse(await readFile(join(path,'metadata.json'),'utf8')),bytes=await readFile(join(path,'data'));
  if(bytes.length!==metadata.size||sha(bytes)!==metadata.customMetadata.sha256)throw new Error('Backup object integrity failed');
  const objectID=sha(`${store==='files'?'FILES':'RELEASES'}/${metadata.key}`);
  await writeFile(join(directory,objectID+'.enc'),encrypt(bytes,key,'ecs-object:'+objectID),{mode:0o600,flag:'wx'});
  snapshot.objects.push({...metadata,store,id:objectID,sha256:sha(bytes)});
 }
}
await writeFile(join(directory,'runtime-config.enc'),encrypt(await readFile(envFile),key,'ecs-runtime-env-v1'),{mode:0o600});
verifyReferences(snapshot);snapshot.complete=true;await save();
const archive=join(resolve(backupRoot),id+'.tar');
const tar=spawnSync('tar',['-C',directory,'-cf',archive,'.'],{stdio:'ignore'});
if(tar.status!==0)throw new Error('Encrypted snapshot archive failed');
const hash=sha(await readFile(archive));
await writeFile(archive+'.sha256',hash+'  '+id+'.tar\n',{mode:0o600});
if(spawnSync('tar',['-tf',archive],{stdio:'ignore'}).status!==0)throw new Error('Encrypted snapshot archive verification failed');
// The verified archive is the durable copy; restore extracts it before running restore.ts.
await rm(directory,{recursive:true,force:true});
console.log(JSON.stringify({complete:true,archive,sha256:hash,tables:snapshot.tables.length,objects:snapshot.objects.length}));
// Retain archives newer than 3 days; a stale extraction directory is removed together with its snapshot.
for(const name of await readdir(backupRoot)){
 const match=name.match(/^(snapshot-\d{4}-\d{2}-\d{2}T(\d\d)-(\d\d)-(\d\d)-(\d{3})Z)(?:\.tar(?:\.sha256)?)?$/);
 if(!match)continue;
 const [,base,hour,minute,second,millis]=match;
 const createdAt=Date.parse(base.slice('snapshot-'.length,'snapshot-YYYY-MM-DD'.length)+'T'+hour+':'+minute+':'+second+'.'+millis+'Z');
 if(Date.now()-createdAt<=3*86400000)continue;
 await rm(join(backupRoot,base),{recursive:true,force:true});
 await rm(join(backupRoot,base+'.tar'),{force:true});
 await rm(join(backupRoot,base+'.tar.sha256'),{force:true});
}
