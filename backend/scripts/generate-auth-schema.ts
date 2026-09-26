import { DatabaseSync } from 'node:sqlite';
import { getMigrations } from 'better-auth/db/migration';
import { authSchema } from '../src/auth-schema.ts';
import { writeFile } from 'node:fs/promises';
const db=new DatabaseSync(':memory:');
try{
  const migration=await getMigrations({...authSchema(async()=>{throw new Error('Schema generation does not send email');}),database:db});
  const sql=await migration.compileMigrations();
  await writeFile(new URL('../migrations/0002_identity.sql',import.meta.url),'-- Generated from the pinned Better Auth schema.\n'+sql+'\n');
  console.log(JSON.stringify({created:migration.toBeCreated.map(t=>t.table)}));
}finally{db.close();}
