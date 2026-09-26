import { readFile, writeFile, mkdir, unlink } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { backupKey, tableSummary, Vault } from './snapshot.mjs';
import { quote } from './convert.mjs';

// Supported fallback when local PostgreSQL TCP connections are unavailable:
// one Management API SQL statement captures every table under one MVCC snapshot.
// Catalog definitions and deployed migration history are retained alongside rows.
const directory=process.argv[2];if(!directory)throw new Error('Usage: export-linked.mjs PRIVATE_BACKUP_DIRECTORY');
const key=backupKey(),id=randomUUID(),vault=new Vault(resolve(directory,id),key,id);
const mapping=JSON.parse(await readFile(new URL('../../contracts/table-mapping.json',import.meta.url),'utf8'));
const tables=Object.entries(mapping).map(([target,meta])=>({target,source:meta.source,primaryKey:meta.primaryKey,columns:meta.columns}));
tables.push(...[
  ['auth.users','source_auth_users'],['auth.identities','source_auth_identities'],
  ['storage.buckets','source_storage_buckets'],['storage.objects','source_storage_objects'],
  ['auth.sessions','source_auth_sessions'],['auth.refresh_tokens','source_auth_refresh_tokens'],
  ['auth.mfa_factors','source_auth_mfa_factors'],
].map(([source,target])=>({source,target,primaryKey:['id']})));
const datasets=tables.map(table=>{
  const [schema,name]=table.source.split('.');
  const columns=table.columns?.map(c=>['bigint','numeric'].includes(c.type)?`${quote(c.name)}::text AS ${quote(c.name)}`:quote(c.name)).join(',')??'*';
  return `'${table.target}',coalesce((SELECT jsonb_agg(to_jsonb(t)) FROM(SELECT ${columns} FROM ${quote(schema)}.${quote(name)} ORDER BY ${table.primaryKey.map(quote).join(',')}) t),'[]'::jsonb)`;
});
const dataParts=[];for(let i=0;i<datasets.length;i+=20)dataParts.push(`jsonb_build_object(${datasets.slice(i,i+20).join(',')})`);
const catalog=`jsonb_build_object(
  'columns',(SELECT jsonb_agg(to_jsonb(c)) FROM information_schema.columns c WHERE table_schema IN('public','private','auth','storage')),
  'constraints',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',con.conname,'definition',pg_get_constraintdef(con.oid))) FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','auth','storage')),
  'indexes',(SELECT jsonb_agg(to_jsonb(i)) FROM pg_indexes i WHERE schemaname IN('public','private','auth','storage')),
  'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname IN('public','private','auth','storage')),
  'functions',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'definition',pg_get_functiondef(p.oid))) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','private','auth','storage') AND p.prokind='f'),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid))) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN('public','private','auth','storage')),
  'grants',(SELECT jsonb_agg(to_jsonb(g)) FROM information_schema.role_table_grants g WHERE table_schema IN('public','private','auth','storage')),
  'migrations',(SELECT jsonb_agg(to_jsonb(m)) FROM supabase_migrations.schema_migrations m),
  'cron',(SELECT jsonb_agg(to_jsonb(j)) FROM cron.job j),
  'realtime',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_publication_tables p WHERE pubname='supabase_realtime')
)`;
const sql=`SELECT jsonb_build_object('captured_at',now(),'snapshot',pg_current_snapshot()::text,'data',${dataParts.join('||')},'catalog',${catalog}) AS backup;`;
const privateDir=new URL('../../.local/',import.meta.url);await mkdir(privateDir,{recursive:true,mode:0o700});
const queryPath=new URL(`export-${id}.sql`,privateDir);await writeFile(queryPath,sql,{mode:0o600,flag:'wx'});
try{
  const stdout=await new Promise((fulfill,reject)=>{
    const child=spawn('supabase',['db','query','--linked','--output','json','--file',queryPath.pathname],{cwd:new URL('../../../',import.meta.url).pathname,shell:false,env:process.env,stdio:['ignore','pipe','pipe']});
    const chunks=[];let size=0;
    const timer=setTimeout(()=>{child.kill();reject(new Error('Linked snapshot export timed out'));},120000);
    child.stdout.on('data',chunk=>{size+=chunk.length;if(size>128*1024*1024){child.kill();reject(new Error('Use the streaming PostgreSQL export for snapshots over 128 MB'));}else chunks.push(chunk);});
    child.stderr.resume();child.on('error',()=>{clearTimeout(timer);reject(new Error('Supabase CLI could not start'));});
    child.on('close',code=>{clearTimeout(timer);code===0?fulfill(Buffer.concat(chunks).toString('utf8')):reject(new Error(`Linked snapshot export failed (exit ${code}); raw data diagnostics suppressed`));});
  });
  const parsed=JSON.parse(stdout),backup=parsed.rows?.[0]?.backup;
  if(!backup?.data||!backup?.catalog)throw new Error('Incomplete Management API snapshot response');
  const manifest={version:1,id,created_at:backup.captured_at,complete:false,source:'supabase-linked-management-api',postgres_snapshot:backup.snapshot,schema_format:'postgres-catalog-with-deployed-migrations',tables:{},schema:await vault.putJSON('schema-catalog.json',backup.catalog)};
  for(const table of tables){
    const records=backup.data[table.target];if(!Array.isArray(records))throw new Error(`Missing source table: ${table.source}`);
    tableSummary(records,table.primaryKey);const chunks=[];
    for(let offset=0;offset<records.length;offset+=250){
      const rows=records.slice(offset,offset+250),name=`${table.target}-${String(offset/250).padStart(8,'0')}`;
      chunks.push({...await vault.putJSON(name,rows),row_summary:tableSummary(rows,table.primaryKey)});
    }
    manifest.tables[table.target]={source:table.source,target:table.target,primaryKey:table.primaryKey,count:records.length,chunks};
    console.log(JSON.stringify({table:table.source,backed_up_rows:records.length}));
  }
  manifest.complete=true;await vault.putJSON('manifest',manifest);
  console.log(JSON.stringify({backup_id:id,directory:resolve(directory,id),database_snapshot_complete:true,schema_format:manifest.schema_format,files_backed_up:false}));
}finally{await unlink(queryPath);}
