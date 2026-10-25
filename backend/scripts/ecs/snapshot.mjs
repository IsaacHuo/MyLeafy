import {createHash} from 'node:crypto';
import SQLite from 'better-sqlite3';
import {quote} from './cloudflare.mjs';
export const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
// Integers and blobs are strings in the wire snapshot: no JSON int64 precision loss.
export function selectRows(name,columns,withoutRowid=false){
 const fields=columns.map(c=>`json_object('t',typeof(${quote(c.name)}),'v',CASE typeof(${quote(c.name)}) WHEN 'blob' THEN hex(${quote(c.name)}) WHEN 'integer' THEN CAST(${quote(c.name)} AS TEXT) ELSE ${quote(c.name)} END)`);
 const order=withoutRowid?columns.filter(c=>c.pk).sort((a,b)=>a.pk-b.pk).map(c=>quote(c.name)).join(','):'rowid';
 if(!order)throw new Error('Snapshot requires deterministic order');
 return `SELECT json_object('rowid',${withoutRowid?'NULL':'CAST(rowid AS TEXT)'},'values',json_array(${fields.join(',')})) AS snapshot_row FROM ${quote(name)} ORDER BY ${order}`;
}
export function inspectSchema(schema){
 const virtual=schema.filter(s=>s.type==='table'&&/^CREATE VIRTUAL TABLE/i.test(s.sql));
 const tables=schema.filter(s=>s.type==='table'&&!virtual.some(v=>s.name===v.name||s.name.startsWith(v.name+'_')));
 return {tables,virtual,other:schema.filter(s=>s.type!=='table')};
}
export function restoreDatabase(snapshot,path){
 if(!snapshot.complete)throw new Error('Incomplete snapshot');
 const db=new SQLite(path,{fileMustExist:false});
 try{
  if(db.prepare('SELECT count(*) n FROM sqlite_schema').get().n)throw new Error('Destination must be empty');
  db.pragma('foreign_keys=OFF');
  db.transaction(()=>{
   const schema=inspectSchema(snapshot.schema);
   for(const table of schema.tables)db.exec(table.sql);
   for(const table of snapshot.tables){
    if(sha(JSON.stringify(table.rows))!==table.sha256)throw new Error('Table snapshot checksum mismatch');
    const columns=table.columns.map(c=>quote(c.name));
    const names=[...(!table.withoutRowid?['rowid']:[]),...columns];
    const statement=db.prepare(`INSERT INTO ${quote(table.name)}(${names.join(',')}) VALUES(${names.map(()=>'?').join(',')})`);
    for(const row of table.rows)statement.run(...(!table.withoutRowid?[BigInt(row.rowid)]:[]),...row.values.map(c=>c.t==='integer'?BigInt(c.v):c.t==='blob'?Buffer.from(c.v,'hex'):c.v));
   }
   if(snapshot.sequences){db.exec('DELETE FROM sqlite_sequence');const sequence=db.prepare('INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)');for(const row of snapshot.sequences)sequence.run(row.name,BigInt(row.seq));}
   for(const table of schema.virtual){db.exec(table.sql);db.exec(`INSERT INTO ${quote(table.name)}(${quote(table.name)}) VALUES('rebuild')`);}
   for(const item of schema.other.filter(s=>s.type==='index'))db.exec(item.sql);
   for(const item of schema.other.filter(s=>s.type==='view'))db.exec(item.sql);
   for(const item of schema.other.filter(s=>s.type==='trigger'))db.exec(item.sql);
  })();
  db.pragma('foreign_keys=ON');verifyDatabase(snapshot,db);
 }finally{db.close();}
}
export function verifyDatabase(snapshot,db){
 if(db.pragma('integrity_check',{simple:true})!=='ok'||db.pragma('foreign_key_check').length)throw new Error('Database integrity check failed');
 for(const table of snapshot.tables){
  const rows=db.prepare(selectRows(table.name,table.columns,table.withoutRowid)).all().map(r=>JSON.parse(r.snapshot_row));
  if(sha(JSON.stringify(rows))!==table.sha256)throw new Error(`Table verification failed: ${table.name}`);
 }
 if(snapshot.sequences){const actual=db.prepare('SELECT name,CAST(seq AS TEXT) seq FROM sqlite_sequence ORDER BY name').all();if(JSON.stringify(actual)!==JSON.stringify(snapshot.sequences))throw new Error('Sequence verification failed');}
 return {tables:snapshot.tables.length,rows:snapshot.tables.reduce((n,t)=>n+t.rows.length,0)};
}
