import { mkdir, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Vault, backupKey, tableSummary } from './snapshot.mjs';
import { normalizeSource, quote } from './convert.mjs';

const directory=process.argv[2];
if(!directory||!process.env.DATABASE_URL)throw new Error('Usage: export.mjs PRIVATE_DIRECTORY; DATABASE_URL and BACKUP_ENCRYPTION_KEY are required');
const key=backupKey();
const sourceURL=new URL(process.env.DATABASE_URL);
if(!['postgres:','postgresql:'].includes(sourceURL.protocol))throw new Error('DATABASE_URL must be a PostgreSQL connection URL');
const {Client,types}=await import('pg');
// Keep PostgreSQL microseconds and exact decimal/integer strings until conversion.
types.setTypeParser(1184,value=>value);types.setTypeParser(1114,value=>value);types.setTypeParser(1082,value=>value);
const client=new Client({connectionString:process.env.DATABASE_URL,connectionTimeoutMillis:15000,application_name:'myleafy-migration-export'});
const id=randomUUID(),vault=new Vault(resolve(directory,id),key,id);
await mkdir(resolve(directory,id),{recursive:true,mode:0o700});
const mapping=JSON.parse(await readFile(new URL('../../contracts/table-mapping.json',import.meta.url),'utf8'));
const tables=Object.entries(mapping).map(([target,meta])=>({source:meta.source,target,primaryKey:meta.primaryKey}));
tables.push({source:'auth.users',target:'source_auth_users',primaryKey:['id']},{source:'auth.identities',target:'source_auth_identities',primaryKey:['id']},{source:'storage.buckets',target:'source_storage_buckets',primaryKey:['id']},{source:'storage.objects',target:'source_storage_objects',primaryKey:['id']});
const manifest={version:1,id,created_at:new Date().toISOString(),complete:false,source_host:sourceURL.hostname,tables:{},schema:null,postgres_snapshot:null};
await client.connect();
try{
  await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  await client.query("SET LOCAL statement_timeout='120s'");
  const {rows:[snapshot]}=await client.query('SELECT pg_export_snapshot() AS id');
  manifest.postgres_snapshot=snapshot.id;
  // Export schema from the same snapshot without putting credentials in argv.
  const schema=await new Promise((fulfill,reject)=>{
    const child=spawn(process.env.PG_DUMP_BIN||'pg_dump',['--schema-only','--no-owner',`--snapshot=${snapshot.id}`],{shell:false,env:{...process.env,PGHOST:sourceURL.hostname,PGPORT:sourceURL.port||'5432',PGUSER:decodeURIComponent(sourceURL.username),PGPASSWORD:decodeURIComponent(sourceURL.password),PGDATABASE:sourceURL.pathname.slice(1),PGSSLMODE:sourceURL.searchParams.get('sslmode')||'verify-full',PGSSLROOTCERT:sourceURL.searchParams.get('sslrootcert')||process.env.PGSSLROOTCERT||'system'},stdio:['ignore','pipe','pipe']});
    const chunks=[];let size=0;
    child.stdout.on('data',chunk=>{size+=chunk.length;if(size>64*1024*1024){child.kill();reject(new Error('Schema dump exceeds safety bound'));}else chunks.push(chunk);});
    // pg_dump errors may echo connection details; report only the exit status.
    child.stderr.resume();child.on('error',()=>reject(new Error('pg_dump is unavailable; set PG_DUMP_BIN')));
    child.on('close',code=>code===0?fulfill(Buffer.concat(chunks)):reject(new Error(`Schema export failed (pg_dump exit ${code})`)));
  });
  manifest.schema=await vault.put('schema.sql',schema);
  for(const table of tables){
    const [schema,name]=table.source.split('.');
    if(!schema||!name)throw new Error('Invalid source table mapping');
    await client.query(`DECLARE leafy_export NO SCROLL CURSOR FOR SELECT * FROM ${quote(schema)}.${quote(name)} ORDER BY ${table.primaryKey.map(quote).join(',')}`);
    const chunks=[];let count=0,index=0;
    while(true){
      const result=await client.query('FETCH FORWARD 250 FROM leafy_export');if(!result.rows.length)break;
      const rows=result.rows.map(normalizeSource);
      const chunk=await vault.putJSON(`${table.target}-${String(index++).padStart(8,'0')}`,rows);
      chunks.push({...chunk,row_summary:tableSummary(rows,table.primaryKey)});count+=rows.length;
      console.log(JSON.stringify({table:table.source,exported_rows:count}));
    }
    await client.query('CLOSE leafy_export');
    manifest.tables[table.target]={...table,count,chunks};
    await vault.putJSON('manifest',manifest);
  }
  await client.query('COMMIT');manifest.complete=true;
  await vault.putJSON('manifest',manifest);
  console.log(JSON.stringify({backup_id:id,directory:resolve(directory,id),complete:true,note:'Database snapshot only; Storage bytes must be exported and verified separately.'}));
}catch(error){
  await client.query('ROLLBACK').catch(()=>{});
  await vault.putJSON('manifest',manifest);
  // Do not reuse partially exported tables after reconnect: the snapshot is gone.
  throw error;
}finally{await client.end();}
