import {createHash} from 'node:crypto';
import {quote,inspectSchema} from './sql.mjs';
export const fenceTable='_ecs_source_freeze';
const prefix='ecs_source_fence_';
export function fenceSQL(schema){
 if(schema.some(item=>item.name===fenceTable||item.name.startsWith(prefix)))throw new Error('Existing source fence requires operator inspection');
 const statements=[`CREATE TABLE ${quote(fenceTable)}(id INTEGER PRIMARY KEY CHECK(id=1),frozen INTEGER NOT NULL CHECK(frozen IN(0,1)))`,`INSERT INTO ${quote(fenceTable)} VALUES(1,0)`],triggers=[];
 const {tables}=inspectSchema(schema);
 for(const table of tables)for(const action of ['INSERT','UPDATE','DELETE']){
  const name=prefix+createHash('sha256').update(table.name+':'+action).digest('hex').slice(0,24);triggers.push(name);
  statements.push(`CREATE TRIGGER ${quote(name)} BEFORE ${action} ON ${quote(table.name)} WHEN (SELECT frozen FROM ${quote(fenceTable)} WHERE id=1)=1 BEGIN SELECT RAISE(ABORT,'ecs_source_frozen'); END`);
 }
 statements.push(`UPDATE ${quote(fenceTable)} SET frozen=1 WHERE id=1`);
 return {statements,triggers};
}
export function removeRestoredFence(db){
 const exists=db.prepare("SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?").get(fenceTable);
 if(!exists)return false;
 if(db.prepare(`SELECT frozen FROM ${quote(fenceTable)} WHERE id=1`).get()?.frozen!==1)throw new Error('Unexpected source fence state in snapshot');
 db.transaction(()=>{
  for(const row of db.prepare("SELECT name FROM sqlite_schema WHERE type='trigger' AND name GLOB 'ecs_source_fence_*'").all()){
   if(!/^ecs_source_fence_[a-f0-9]{24}$/.test(row.name))throw new Error('Unrecognized migration fence trigger');
   db.exec(`DROP TRIGGER ${quote(row.name)}`);
  }
  db.exec(`DROP TABLE ${quote(fenceTable)}`);
 })();
 return true;
}
