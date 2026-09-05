import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { quote, targetTable, primaryKey, type Column, type SourceSchema } from './schema-model.ts';

const root = resolve(import.meta.dirname, '..');
const source = JSON.parse(await readFile(resolve(root, 'contracts/source-schema.json'), 'utf8')) as SourceSchema;
const now = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
const uuid = "lower(hex(randomblob(4))||'-'||hex(randomblob(2))||'-4'||substr(hex(randomblob(2)),2)||'-'||substr('89ab',abs(random()%4)+1,1)||substr(hex(randomblob(2)),2)||'-'||hex(randomblob(6)))";

// This converter is deliberately limited to the inspected schema. Unknown syntax is a hard failure.
export function expression(value: string): string {
  let sql = value.replace(/::(?:text|jsonb|numeric|boolean|integer|bigint|date|uuid|regconfig)\b/g, '')
    .replace(/\b(btrim)\(/gi, 'trim(').replace(/\bchar_length\(/gi, 'length(')
    .replace(/\bjsonb_typeof\(/g, 'json_type(').replace(/\btrue\b/gi, '1').replace(/\bfalse\b/gi, '0')
    .replace(/= ANY \(ARRAY\[([^\]]+)\]\)/g, 'IN ($1)')
    .replace(/\bnow\(\)/g, now).replace(/ NOT VALID$/, '');
  if (/::|\bARRAY\[|\bANY\s*\(|~|\bto_tsvector\(/.test(sql)) throw new Error(`Unconverted SQL expression: ${value}`);
  return sql;
}
function columnType(column: Column): string {
  if (['uuid', 'text', 'timestamp with time zone', 'jsonb', 'inet', 'date'].includes(column.data_type)) return 'TEXT';
  if (['bigint', 'integer', 'boolean'].includes(column.data_type)) return 'INTEGER';
  if (['numeric', 'double precision'].includes(column.data_type)) return 'REAL';
  throw new Error(`Unmapped type ${column.data_type} in ${column.table_name}.${column.column_name}`);
}
function defaultSQL(column: Column): string {
  const value = column.column_default;
  if (!value || value.startsWith('nextval(') || value.includes('current_profile_campus_id()')) return '';
  if (value === 'gen_random_uuid()') return ` DEFAULT (${uuid})`;
  if (value.includes('::interval')) {
    if (value !== "(now() + '00:10:00'::interval)") throw new Error(`Unmapped interval: ${value}`);
    return " DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now','+10 minutes'))";
  }
  return ` DEFAULT (${expression(value)})`;
}
const sql: string[] = [
  '-- Generated from contracts/source-schema.json by npm run schema:convert.',
  '-- Source RLS/functions are ported separately; this DDL does not grant client access.',
  // Durable identity anchor preserves every legacy auth.users FK, independently of auth-library sessions.
  `CREATE TABLE auth_users (id TEXT PRIMARY KEY NOT NULL, email TEXT, email_verified INTEGER NOT NULL DEFAULT 0 CHECK(email_verified IN (0,1)), is_anonymous INTEGER NOT NULL DEFAULT 0 CHECK(is_anonymous IN (0,1)), banned_until TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);`,
];
const tables = [...new Set(source.columns.map(c => `${c.table_schema}.${c.table_name}`))];
const manifest: Record<string, unknown> = {};
const legacyChecks: { table: string; name: string; check: string }[] = [];
for (const table of tables) {
  const [schema, name] = table.split('.');
  const target = targetTable(schema, name);
  const cols = source.columns.filter(c => c.table_schema === schema && c.table_name === name);
  const keys = primaryKey(source, schema, name);
  const constraints = source.constraints.filter(c => c.schema === schema && c.table_name === name);
  const autoKey = keys.length === 1 && cols.some(c => c.column_name === keys[0] && (c.is_identity === 'YES' || c.column_default?.startsWith('nextval(')));
  const definitions = cols.map(c => {
    const q = quote(c.column_name);
    if (autoKey && c.column_name === keys[0]) return `${q} INTEGER PRIMARY KEY AUTOINCREMENT`;
    if (c.is_generated !== 'NEVER') return `${q} ${columnType(c)} GENERATED ALWAYS AS (${expression(c.generation_expression!)}) STORED`;
    return `${q} ${columnType(c)}${c.is_nullable === 'NO' ? ' NOT NULL' : ''}${defaultSQL(c)}${c.data_type === 'boolean' ? ` CHECK (${q} IN (0,1))` : ''}${c.data_type === 'jsonb' ? ` CHECK (${q} IS NULL OR json_valid(${q}))` : ''}`;
  });
  for (const c of constraints) {
    if (c.type === 'p' && autoKey) continue;
    let value = c.definition;
    if (c.name === 'admin_accounts_username_format') value = "CHECK(length(username) BETWEEN 3 AND 64 AND username NOT GLOB '*[^a-z0-9_.-]*')";
    if (c.name === 'post_attachments_sha256_check') value = "CHECK(length(sha256)=64 AND sha256 NOT GLOB '*[^0-9a-f]*')";
    if (value.endsWith(' NOT VALID')) {
      // PostgreSQL NOT VALID checks grandfather existing rows but enforce future writes.
      // Preserve that behavior using INSERT/UPDATE triggers, with import-only suspension.
      legacyChecks.push({ table: target, name: c.name, check: expression(value).replace(/^CHECK\s*\((.*)\)$/s, '$1') });
      continue;
    }
    value = value.replace(/REFERENCES (?:((?:auth|public|private))\.)?([a-z_]+)\(/g, (_, refSchema: string | undefined, refName: string) => `REFERENCES ${quote(targetTable(refSchema ?? 'public', refName))}(`);
    definitions.push(`CONSTRAINT ${quote(c.name)} ${expression(value)}`);
  }
  sql.push(`CREATE TABLE ${quote(target)} (\n  ${definitions.join(',\n  ')}\n);`);
  manifest[target] = { source: table, primaryKey: keys, columns: cols.map(c => ({ name: c.column_name, type: c.data_type, generated: c.is_generated !== 'NEVER', nullable: c.is_nullable === 'YES' })) };
}
sql.push(`CREATE TABLE migration_control (id INTEGER PRIMARY KEY CHECK(id=1), importing INTEGER NOT NULL CHECK(importing IN (0,1)));`,
  `INSERT INTO migration_control VALUES(1,0);`);
for (const c of legacyChecks) {
  const columns = source.columns.filter(x => targetTable(x.table_schema, x.table_name) === c.table).map(x => x.column_name).sort((a,b) => b.length-a.length);
  // Tokenize literals separately so column identifiers inside string literals are never rewritten.
  const condition = c.check.split(/('(?:[^']|'')*')/).map((part,i) => i % 2 ? part : part.replace(new RegExp(`\\b(${columns.join('|')})\\b`, 'g'), 'NEW."$1"')).join('');
  for (const op of ['INSERT', 'UPDATE']) sql.push(`CREATE TRIGGER ${quote(`${c.name}_${op.toLowerCase()}`)} BEFORE ${op} ON ${quote(c.table)} WHEN (SELECT importing FROM migration_control WHERE id=1)=0 AND NOT (${condition}) BEGIN SELECT RAISE(ABORT,'${c.name}'); END;`);
}
for (const index of source.indexes) {
  if (source.constraints.some(c => c.schema === index.schemaname && c.table_name === index.tablename && c.name === index.indexname && ['u','p'].includes(c.type))) continue;
  if (index.indexdef.includes(' USING gin ')) continue; // Replaced by explicit FTS tables below.
  let value = index.indexdef.replace(`ON ${index.schemaname}.${index.tablename} USING btree`, `ON ${quote(targetTable(index.schemaname,index.tablename))}`);
  sql.push(`${expression(value)};`);
}
// FTS indexes are internal and never exposed through the client API, including profile/email indexes.
const searchColumns: Record<string, string[]> = {
  posts:['title','body','category'],comments:['body'],profiles:['nickname','display_name','edu_id','bound_email'],
  teachers:['search_text'],course_catalog:['search_text'],dish_catalog:['search_text'],
  postgraduate_sources:['search_text'],campuses:['display_name','short_name'],site_announcements:['title','body'],
  feedback_submissions:['body','contact','issue_type'],
};
for (const [table, columns] of Object.entries(searchColumns)) {
  const fts = `${table}_search`;
  sql.push(`CREATE VIRTUAL TABLE ${quote(fts)} USING fts5(${columns.map(quote).join(',')},content='${table}',content_rowid='rowid',tokenize='trigram');`);
  const names = columns.map(quote).join(',');
  const oldValues = columns.map(c => `OLD.${quote(c)}`).join(',');
  const newValues = columns.map(c => `NEW.${quote(c)}`).join(',');
  sql.push(`CREATE TRIGGER ${quote(`${fts}_insert`)} AFTER INSERT ON ${quote(table)} BEGIN INSERT INTO ${quote(fts)}(rowid,${names}) VALUES(NEW.rowid,${newValues}); END;`);
  sql.push(`CREATE TRIGGER ${quote(`${fts}_delete`)} AFTER DELETE ON ${quote(table)} BEGIN INSERT INTO ${quote(fts)}(${quote(fts)},rowid,${names}) VALUES('delete',OLD.rowid,${oldValues}); END;`);
  sql.push(`CREATE TRIGGER ${quote(`${fts}_update`)} AFTER UPDATE ON ${quote(table)} BEGIN INSERT INTO ${quote(fts)}(${quote(fts)},rowid,${names}) VALUES('delete',OLD.rowid,${oldValues}); INSERT INTO ${quote(fts)}(rowid,${names}) VALUES(NEW.rowid,${newValues}); END;`);
}
await mkdir(resolve(root,'migrations'),{recursive:true});
await writeFile(resolve(root,'migrations/0001_business.sql'), sql.join('\n\n')+'\n');
await writeFile(resolve(root,'contracts/table-mapping.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({tables:tables.length,legacyWriteChecks:legacyChecks.length,ftsTables:Object.keys(searchColumns).length}));
