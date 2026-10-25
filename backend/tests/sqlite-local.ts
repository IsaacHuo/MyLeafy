import { readFileSync, readdirSync } from 'node:fs';
import { SqliteDatabase } from '../src/runtime/database';
/** Existing business fixtures use the same SQLite implementation as ECS. */
export class TestDatabase extends SqliteDatabase {
  readonly sqlite;
  constructor() {
    super(':memory:');this.sqlite={prepare:(sql:string)=>this.native.prepare<unknown[],Record<string,any>>(sql),exec:(sql:string)=>this.native.exec(sql)};
    const directory=new URL('../migrations/',import.meta.url);
    for(const name of readdirSync(directory).filter(n=>n.endsWith('.sql')).sort())this.sqlite.exec(readFileSync(new URL(name,directory),'utf8'));
  }
  async exec(sql:string){this.sqlite.exec(sql);return {count:0,duration:0};}
}
