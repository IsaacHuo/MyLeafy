import {expect,it} from 'vitest';
import SQLite from 'better-sqlite3';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {inspectSchema,selectRows,sha,restoreDatabase,verifyReferences} from '../scripts/ecs/snapshot.mjs';
it('restores exact int64, blobs, rowids, generated columns, triggers and FTS without source changes',()=>{
 const directory=mkdtempSync(join(tmpdir(),'leafy-snapshot-')),source=new SQLite(':memory:');
 try{
 source.exec(`CREATE TABLE posts(id TEXT PRIMARY KEY,body TEXT,n INTEGER,b BLOB,generated TEXT GENERATED ALWAYS AS (upper(body)) VIRTUAL);
 CREATE VIRTUAL TABLE search USING fts5(body,content='posts',content_rowid='rowid',tokenize='trigram');
 CREATE TRIGGER search_insert AFTER INSERT ON posts BEGIN INSERT INTO search(rowid,body) VALUES(new.rowid,new.body); END;
 CREATE TABLE sequence_test(id INTEGER PRIMARY KEY AUTOINCREMENT);INSERT INTO sequence_test VALUES(97);DELETE FROM sequence_test;
 CREATE TABLE links(id TEXT PRIMARY KEY,post TEXT REFERENCES posts(id));
 INSERT INTO posts(rowid,id,body,n,b) VALUES(71,'p','hello world',9223372036854775807,x'00FF');INSERT INTO links VALUES('l','p');`);
 const schema=source.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type,name").all();
 const tables=inspectSchema(schema).tables.map((table:any)=>{
 const columns=source.prepare(`PRAGMA table_xinfo("${table.name}")`).all().filter((c:any)=>c.hidden===0),rows=source.prepare(selectRows(table.name,columns)).all().map((r:any)=>JSON.parse(r.snapshot_row));
 return {name:table.name,columns,rows,sha256:sha(JSON.stringify(rows)),withoutRowid:false};});
 const snapshot={version:1,complete:true,schema,tables,sequences:source.prepare('SELECT name,CAST(seq AS TEXT) seq FROM sqlite_sequence ORDER BY name').all()},path=join(directory,'db.sqlite');restoreDatabase(snapshot,path);
 const target=new SQLite(path);try{
 expect(target.prepare("SELECT rowid,generated,CAST(n AS TEXT) n,hex(b) b FROM posts").get()).toEqual({rowid:71,generated:'HELLO WORLD',n:'9223372036854775807',b:'00FF'});
 target.prepare('INSERT INTO sequence_test DEFAULT VALUES').run();expect(target.prepare('SELECT id FROM sequence_test').get()).toEqual({id:98});
 expect(target.prepare("SELECT rowid FROM search WHERE search MATCH 'hello'").all()).toEqual([{rowid:71}]);
 target.prepare("INSERT INTO posts(id,body) VALUES('q','another word')").run();expect(target.prepare("SELECT count(*) n FROM search WHERE search MATCH 'another'").get()).toEqual({n:1});
 expect(()=>restoreDatabase(snapshot,path)).toThrow('Destination must be empty');
 }finally{target.close();}
 expect(source.prepare('SELECT count(*) n FROM posts').get()).toEqual({n:1});
 }finally{source.close();rmSync(directory,{recursive:true,force:true});}
});

it('requires attached media and retained release bytes to match the database',()=>{
 const table={name:'file_objects',columns:['bucket','path','state','sha256','byte_size'].map(name=>({name})),rows:[{values:['community-images','a.jpg','attached','abc','7'].map(v=>({v}))}]};
 const snapshot={tables:[table],objects:[{store:'files',key:'community-images/a.jpg',sha256:'abc',size:7}]};
 expect(verifyReferences(snapshot)).toEqual({referencesVerified:true});
 expect(()=>verifyReferences({...snapshot,objects:[]})).toThrow('Attached media reference');
 expect(()=>verifyReferences({...snapshot,objects:[{...snapshot.objects[0],size:8}]})).toThrow('Attached media reference');
});
