import SQLite from 'better-sqlite3';
import {readFile,readdir,open} from 'node:fs/promises';
const [path]=process.argv.slice(2);
if(!path)throw new Error('Usage: migrate.mjs DATABASE_PATH (service must be stopped)');
// New databases are explicit; a typo cannot silently create an empty production DB.
const handle=await open(path,'a',0o600);await handle.close();
const db=new SQLite(path);db.pragma('foreign_keys=ON');
try{
 db.exec('CREATE TABLE IF NOT EXISTS d1_migrations(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT UNIQUE,applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL)');
 const directory=new URL('../../migrations/',import.meta.url);
 for(const name of (await readdir(directory)).filter(n=>/^\d+.*\.sql$/.test(n)).sort()){
  if(db.prepare('SELECT 1 FROM d1_migrations WHERE name=?').get(name))continue;
  const sql=await readFile(new URL(name,directory),'utf8');
  db.transaction(()=>{db.exec(sql);db.prepare('INSERT INTO d1_migrations(name) VALUES(?)').run(name);})();
  console.log(JSON.stringify({migration:name,applied:true}));
 }
 if(db.pragma('foreign_key_check').length||db.pragma('integrity_check',{simple:true})!=='ok')throw new Error('Migration integrity check failed');
}finally{db.close();}
