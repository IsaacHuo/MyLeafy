import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';

/** SQLite-backed test database. Remote D1 tests remain a separate acceptance step. */
export class LocalD1 {
  readonly sqlite=new DatabaseSync(':memory:');
  constructor(){
    const directory=new URL('../migrations/',import.meta.url);
    for(const name of readdirSync(directory).filter(n=>n.endsWith('.sql')).sort())this.sqlite.exec(readFileSync(new URL(name,directory),'utf8'));
  }
  prepare(sql:string){return new LocalStatement(this,sql);}
  async exec(sql:string){this.sqlite.exec(sql);return {count:0,duration:0};}
  async batch(statements:LocalStatement[]){
    this.sqlite.exec('BEGIN');
    try{const result=statements.map(statement=>statement.execute());this.sqlite.exec('COMMIT');return result;}
    catch(error){this.sqlite.exec('ROLLBACK');throw error;}
  }
  close(){this.sqlite.close();}
  binding(){return this as unknown as D1Database;}
}
class LocalStatement {
  constructor(private db:LocalD1,private sql:string,private values:any[]=[]){ }
  bind(...values:any[]){return new LocalStatement(this.db,this.sql,values);}
  execute(){
    const statement=this.db.sqlite.prepare(this.sql);
    const before=this.db.sqlite.prepare('SELECT total_changes() AS n').get()!.n as number;
    const results=statement.all(...this.values);
    const after=this.db.sqlite.prepare('SELECT total_changes() AS n').get()!.n as number;
    return {results,success:true,meta:{changes:after-before,last_row_id:Number(this.db.sqlite.prepare('SELECT last_insert_rowid() AS n').get()!.n),duration:0,rows_read:results.length,rows_written:after-before}};
  }
  async all(){return this.execute();}
  async run(){return this.execute();}
  async first(column?:string){const row=this.execute().results[0];return column?row?.[column]??null:row??null;}
  async raw(){return this.execute().results.map(row=>Object.values(row));}
}
