// Local schema reconstruction only. Never connects to production or handles real credentials.
import EmbeddedPostgres from 'embedded-postgres';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { randomBytes } from 'node:crypto';

const root = resolve(import.meta.dirname, '../..');
const run = resolve(root, 'backend/.local', `source-${Date.now()}`);
await mkdir(run, { recursive: true });
const instance = new EmbeddedPostgres({ databaseDir: resolve(run, 'pg'), port: 55439, user: 'postgres', password: randomBytes(24).toString('hex'), persistent: true,
  onLog: () => {}, onError: () => {} });
await instance.initialise();
await instance.start();
const client = instance.getPgClient();
await client.connect();
try {
  await client.query(await readFile(resolve(root, 'backend/tests/fixtures/supabase-platform.sql'), 'utf8'));
  const names = (await readdir(resolve(root, 'supabase/migrations'))).filter(n => n.endsWith('.sql')).sort();
  for (const name of names) {
    const source = await readFile(resolve(root, 'supabase/migrations', name), 'utf8');
    // Native cron/network extensions are replaced ONLY by the explicit local platform fixture.
    const sql = source.replace(/create extension if not exists (pg_cron|pg_net)(?:\s+with\s+schema\s+\w+)?\s*;/gi, '');
    try { await client.query(sql); } catch (error) { throw new Error(`Source migration failed: ${name}`, { cause: error }); }
    console.log(`replayed ${name}`);
  }
  const queries: Record<string, string> = {
    columns: `SELECT table_schema,table_name,column_name,ordinal_position,data_type,udt_name,is_nullable,column_default,is_identity,is_generated,generation_expression FROM information_schema.columns WHERE table_schema IN ('public','private','community_private') ORDER BY table_schema,table_name,ordinal_position`,
    constraints: `SELECT n.nspname AS schema,c.relname AS table_name,con.conname AS name,con.contype AS type,pg_get_constraintdef(con.oid) AS definition FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private','community_private') ORDER BY 1,2,3`,
    indexes: `SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes WHERE schemaname IN ('public','private','community_private') ORDER BY 1,2,3`,
    policies: `SELECT * FROM pg_policies WHERE schemaname IN ('public','storage') ORDER BY schemaname,tablename,policyname`,
    functions: `SELECT n.nspname AS schema,p.proname AS name,pg_get_function_identity_arguments(p.oid) AS args,pg_get_functiondef(p.oid) AS definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private','community_private') AND p.prokind='f' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') ORDER BY 1,2,3`,
    triggers: `SELECT event_object_schema,event_object_table,trigger_name,event_manipulation,action_statement FROM information_schema.triggers WHERE event_object_schema IN ('public','private') ORDER BY 1,2,3`,
    cron: `SELECT jobname,schedule,command FROM cron.job ORDER BY jobname`,
    buckets: `SELECT id,name,public,file_size_limit,allowed_mime_types FROM storage.buckets ORDER BY id`,
    realtime: `SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY 1,2`,
  };
  const snapshot: Record<string, unknown> = { provenance: 'Empty local PostgreSQL 17 replay of repository migrations; NOT a production export', migrations: names };
  for (const [key, query] of Object.entries(queries)) snapshot[key] = (await client.query(query)).rows;
  await mkdir(resolve(root, 'backend/contracts'), { recursive: true });
  await writeFile(resolve(root, 'backend/contracts/source-schema.json'), JSON.stringify(snapshot, null, 2) + '\n');
  console.log('Schema snapshot written. Production drift remains a required verification.');
} finally {
  await client.end();
  await instance.stop();
}
