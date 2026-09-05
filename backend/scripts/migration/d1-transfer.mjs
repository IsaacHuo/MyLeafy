import { DatabaseSync } from 'node:sqlite';
import { readFile, writeFile, chmod, unlink } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { digest, difference, tableSummary } from './snapshot.mjs';
import { literal, quote } from './convert.mjs';

export function rowSQL(table,row,primaryKey=[]){
  const columns=Object.keys(row),setup=[],values=[];
  for(const column of columns){
    const value=row[column];
    if(typeof value==='string'&&Buffer.byteLength(value)>12000){
      const id=digest(`${table}/${column}/${value}`),characters=[...value];let n=0;
      for(let offset=0;offset<characters.length;offset+=4000)setup.push(`INSERT INTO _leafy_migration_values(id,ordinal,value) VALUES('${id}',${n++},${literal(characters.slice(offset,offset+4000).join(''))});`);
      values.push(`(SELECT group_concat(value,'') FROM (SELECT value FROM _leafy_migration_values WHERE id='${id}' ORDER BY ordinal))`);
    }else values.push(literal(value));
  }
  const changed=columns.filter(c=>!primaryKey.includes(c));
  const conflict=primaryKey.length?` ON CONFLICT(${primaryKey.map(quote).join(',')}) ${changed.length?'DO UPDATE SET '+changed.map(c=>`${quote(c)}=excluded.${quote(c)}`).join(','):'DO NOTHING'}`:'';
  return [...setup,`INSERT INTO ${quote(table)}(${columns.map(quote).join(',')}) VALUES(${values.join(',')})${conflict};`,'DELETE FROM _leafy_migration_values;'];
}

export async function deltaSQL(beforePath,afterPath){
  const before=new DatabaseSync(beforePath,{readOnly:true}),after=new DatabaseSync(afterPath,{readOnly:true});
  try{
    const {summaries}=await transferSQL(afterPath),baseline={},changes={};
    const lines=['PRAGMA defer_foreign_keys=ON;',"UPDATE backend_control SET mode='importing' WHERE id=1;",'UPDATE migration_control SET importing=1 WHERE id=1;','CREATE TABLE _leafy_migration_values(id TEXT NOT NULL,ordinal INTEGER NOT NULL,value TEXT NOT NULL,PRIMARY KEY(id,ordinal));'];
    for(const [table,meta] of Object.entries(summaries)){
      const select=`SELECT ${meta.columns.map(quote).join(',')} FROM ${quote(table)}`;
      const previous=before.prepare(select).all().map(row=>({...row})),current=after.prepare(select).all().map(row=>({...row}));
      baseline[table]={...meta,...tableSummary(previous,meta.primaryKey)};
      changes[table]=difference(previous,current,meta.primaryKey);
    }
    // Deletions run before updates to free unique values. Explicitly detach reply
    // references only when that comment is absent from the authoritative snapshot.
    for(const row of changes.comments.deleted)lines.push(`UPDATE comments SET parent_comment_id=NULL,reply_to_comment_id=NULL WHERE parent_comment_id=${literal(row.id)};`);
    for(const table of Object.keys(changes).reverse())for(const row of changes[table].deleted)lines.push(`DELETE FROM ${quote(table)} WHERE ${summaries[table].primaryKey.map(key=>`${quote(key)}=${literal(row[key])}`).join(' AND ')};`);
    for(const [table,delta] of Object.entries(changes)){
      for(const row of [...delta.inserted,...delta.updated.map(change=>change.after)])lines.push(...rowSQL(table,row,summaries[table].primaryKey));
    }
    for(const [table,summary] of Object.entries(summaries))lines.push(`INSERT INTO mutation_assertions(ok) SELECT CASE WHEN (SELECT count(*) FROM ${quote(table)})=${summary.count} THEN 1 ELSE 0 END;`);
    lines.push('INSERT INTO mutation_assertions(ok) SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM pragma_foreign_key_check) THEN 1 ELSE 0 END;','DELETE FROM mutation_assertions;','DROP TABLE _leafy_migration_values;','UPDATE migration_control SET importing=0 WHERE id=1;',"UPDATE backend_control SET mode='read_only',generation=generation+1 WHERE id=1;");
    return {sql:lines.join('\n')+'\n',summaries,baseline,counts:Object.fromEntries(Object.entries(changes).map(([table,d])=>[table,{inserted:d.inserted.length,updated:d.updated.length,deleted:d.deleted.length}]))};
  }finally{before.close();after.close();}
}

export async function transferSQL(sourcePath){
  const db=new DatabaseSync(sourcePath,{readOnly:true});
  try{
    if(db.prepare('PRAGMA foreign_key_check').all().length)throw new Error('Source conversion has orphaned foreign keys');
    if(db.prepare('SELECT mode FROM backend_control').get()?.mode!=='read_only')throw new Error('Source conversion is not sealed for import');
    const mapping=JSON.parse(await readFile(new URL('../../contracts/table-mapping.json',import.meta.url),'utf8'));
    const tables=['auth_users','identity_user','identity_account',...Object.keys(mapping),'file_objects'];
    const lines=['PRAGMA defer_foreign_keys=ON;',"UPDATE backend_control SET mode='importing' WHERE id=1;",'UPDATE migration_control SET importing=1 WHERE id=1;',
      'CREATE TABLE _leafy_migration_values(id TEXT NOT NULL,ordinal INTEGER NOT NULL,value TEXT NOT NULL,PRIMARY KEY(id,ordinal));',
      'UPDATE comments SET parent_comment_id=NULL,reply_to_comment_id=NULL;',
      ...['legacy_session_exchanges','identity_session','identity_verification','identity_rate_limit','change_outbox','file_delete_jobs',...tables.slice().reverse()].map(table=>`DELETE FROM ${quote(table)};`)];
    const summaries={};
    for(const table of tables){
      const columns=db.prepare(`PRAGMA table_xinfo(${quote(table)})`).all().filter(c=>c.hidden===0).map(c=>c.name);
      const primaryKey=db.prepare(`PRAGMA table_info(${quote(table)})`).all().filter(c=>c.pk>0).sort((a,b)=>a.pk-b.pk).map(c=>c.name);
      const rows=db.prepare(`SELECT ${columns.map(quote).join(',')} FROM ${quote(table)}`).all().map(row=>({...row}));
      summaries[table]={...tableSummary(rows,primaryKey),columns,primaryKey};
      for(const row of rows)lines.push(...rowSQL(table,row));
    }
    for(const [table,summary] of Object.entries(summaries))lines.push(`INSERT INTO mutation_assertions(ok) SELECT CASE WHEN (SELECT count(*) FROM ${quote(table)})=${summary.count} THEN 1 ELSE 0 END;`);
    lines.push('INSERT INTO mutation_assertions(ok) SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM pragma_foreign_key_check) THEN 1 ELSE 0 END;','DELETE FROM mutation_assertions;','DROP TABLE _leafy_migration_values;','UPDATE migration_control SET importing=0 WHERE id=1;',"UPDATE backend_control SET mode='read_only',generation=generation+1 WHERE id=1;");
    for(const line of lines)if(Buffer.byteLength(line)>95000)throw new Error('Generated statement exceeds D1 SQL size bound');
    return {sql:lines.join('\n')+'\n',summaries};
  }finally{db.close();}
}

export async function remoteQuery(config,environment,sql,params=[]){
  const target=config.env[environment];
  const response=await fetch(`https://api.cloudflare.com/client/v4/accounts/${config.account_id}/d1/database/${target.d1_databases[0].database_id}/query`,{method:'POST',headers:{Authorization:`Bearer ${process.env.CLOUDFLARE_API_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({sql,params}),signal:AbortSignal.timeout(30000)});
  const data=await response.json();if(!response.ok||!data.success)throw new Error(`D1 request failed (HTTP ${response.status}); inspect the operator dashboard`);
  return data.result.flatMap(result=>result.results);
}
export async function verifyD1(config,environment,summaries){
  for(const [table,summary] of Object.entries(summaries)){
    const rows=[];let previous=null;
    while(true){
      const predicate=previous?` WHERE (${summary.primaryKey.map(quote).join(',')})>(${summary.primaryKey.map(()=>'?').join(',')})`:'';
      const page=await remoteQuery(config,environment,`SELECT ${summary.columns.map(quote).join(',')} FROM ${quote(table)}${predicate} ORDER BY ${summary.primaryKey.map(quote).join(',')} LIMIT 250`,previous??[]);
      if(!page.length)break;
      rows.push(...page);previous=summary.primaryKey.map(key=>page.at(-1)[key]);
    }
    const actual=tableSummary(rows,summary.primaryKey);
    if(actual.count!==summary.count||actual.sha256!==summary.sha256)throw new Error(`Remote data verification failed: ${table}`);
    console.log(JSON.stringify({table,verified:true,rows:actual.count}));
  }
  if((await remoteQuery(config,environment,'PRAGMA foreign_key_check')).length)throw new Error('Remote D1 foreign key check failed');
}

async function main(){
  const [environment,source,flag,baseline]=process.argv.slice(2);
  if(!['staging','production'].includes(environment)||!source||!['--replace-frozen-database','--delta-from'].includes(flag)||(flag==='--delta-from'&&!baseline))throw new Error('Usage: d1-transfer.mjs staging|production SEALED_SQLITE --replace-frozen-database | --delta-from BASELINE_SQLITE');
  const config=JSON.parse(await readFile(new URL('../../wrangler.jsonc',import.meta.url),'utf8'));
  if(config.account_id!==process.env.CLOUDFLARE_ACCOUNT_ID||!config.env[environment])throw new Error('Target account/environment is not provisioned');
  if(environment==='production'&&!process.env.CUTOVER_BACKUP_ID)throw new Error('CUTOVER_BACKUP_ID must identify the verified pre-cutover backup');
  const [state]=await remoteQuery(config,environment,'SELECT mode FROM backend_control WHERE id=1');
  if(state?.mode!=='read_only')throw new Error('Target must be frozen before transfer');
  const transfer=flag==='--delta-from'?await deltaSQL(baseline,source):await transferSQL(source),path=resolve(`${source}.${environment}.transfer.sql`);
  if(transfer.baseline)await verifyD1(config,environment,transfer.baseline);
  await writeFile(path,transfer.sql,{mode:0o600,flag:'wx'});await chmod(path,0o600);
  try{
    await new Promise((fulfill,reject)=>{
      const entry=process.env.WRANGLER_BIN||new URL('../../node_modules/wrangler/bin/wrangler.js',import.meta.url).pathname;
      const child=spawn(process.execPath,[entry,'d1','execute',config.env[environment].d1_databases[0].database_name,'--remote','--env',environment,'--config',new URL('../../wrangler.jsonc',import.meta.url).pathname,'--file',path,'--yes'],{shell:false,env:process.env,stdio:['ignore','pipe','pipe']});
      // CLI diagnostics can contain failing SQL and credential hashes. Keep them out of logs.
      child.stdout.resume();child.stderr.resume();child.on('error',()=>reject(new Error('Wrangler could not start')));
      child.on('close',code=>code===0?fulfill():reject(new Error(`D1 file import failed (exit ${code}); retain source backup and keep target frozen`)));
    });
    await verifyD1(config,environment,transfer.summaries);
    console.log(JSON.stringify({environment,verified:true,mode:'read_only',source:basename(source)}));
  }finally{await unlink(path);}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
