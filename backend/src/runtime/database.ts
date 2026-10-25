import SQLite from 'better-sqlite3';
import type { Database, SQLStatement, SQLValue, SQLResult, SQLRow } from './types';

export class SqliteDatabase implements Database {
  readonly native: SQLite.Database;
  readonly authNative: SQLite.Database;
  constructor(path: string) {
    this.native = new SQLite(path, { fileMustExist: path !== ':memory:' });
    this.authNative = path === ':memory:' ? this.native : new SQLite(path,{fileMustExist:true});
    for(const connection of new Set([this.native,this.authNative])){
      connection.pragma('foreign_keys = ON');connection.pragma('journal_mode = WAL');connection.pragma('busy_timeout = 5000');
    }
  }
  prepare(sql: string): SQLStatement { return new Statement(this, sql); }
  async batch<T = SQLRow>(statements: SQLStatement[]): Promise<SQLResult<T>[]> {
    return this.native.transaction(() => statements.map(s => {
      if (!(s instanceof Statement) || s.database !== this) throw new Error('Foreign database statement');
      return s.execute<T>();
    })).immediate();
  }
  close() { if(this.authNative!==this.native)this.authNative.close();this.native.close(); }
}
class Statement implements SQLStatement {
  constructor(readonly database: SqliteDatabase, private sql: string, private values: unknown[] = []) {}
  bind(...values: unknown[]) { return new Statement(this.database, this.sql, values); }
  execute<T>(): SQLResult<T> {
    const statement = this.database.native.prepare(this.sql);
    const values = this.values.map(v => v instanceof ArrayBuffer ? Buffer.from(v) : v);
    let results: T[] = [], changes = 0, lastID = 0;
    if (statement.reader) {
      results = statement.all(...values) as T[];
      // changes() also handles INSERT/UPDATE ... RETURNING.
      changes = Number((this.database.native.prepare('SELECT changes() n').get() as {n:number}).n);
    } else {
      const result = statement.run(...values); changes = result.changes; lastID = Number(result.lastInsertRowid);
    }
    return { results, success: true, meta: { changes, last_row_id: lastID } };
  }
  async all<T = SQLRow>() { return this.execute<T>(); }
  async run<T = SQLRow>() { return this.execute<T>(); }
  async first<T = SQLRow>(column?: string): Promise<T | null> {
    const row = this.execute<Record<string, unknown>>().results[0];
    return (column ? row?.[column] ?? null : row ?? null) as T | null;
  }
}
