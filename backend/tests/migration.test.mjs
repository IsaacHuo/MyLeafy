import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, rm, readFile, readdir } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { canonical, difference, applyDifference, reverseDifference, tableSummary, encrypt, decrypt, Vault } from '../scripts/migration/snapshot.mjs';
import { encodeRow, identityRows, timestamp, upsertSQL } from '../scripts/migration/convert.mjs';
import { materialize } from '../scripts/migration/materialize.mjs';
import { rowSQL, transferSQL } from '../scripts/migration/d1-transfer.mjs';

test('full comparison detects hard deletes and changes with unchanged timestamps; reverse preserves all rows', () => {
  const before = [{ id: 'a', body: '甲', updated_at: 'same' }, { id: 'b', body: '乙' }];
  const after = [{ id: 'a', body: '修改', updated_at: 'same' }, { id: 'c', body: '新用户内容' }];
  const delta = difference(before, after, ['id']);
  assert.equal(delta.inserted.length, 1); assert.equal(delta.updated.length, 1); assert.equal(delta.deleted.length, 1);
  const applied = applyDifference(before, delta, ['id']);
  assert.deepEqual(tableSummary(applied, ['id']), tableSummary(after, ['id']));
  assert.deepEqual(tableSummary(applyDifference(applied, delta, ['id']), ['id']), tableSummary(after, ['id']));
  assert.deepEqual(tableSummary(applyDifference(applied, reverseDifference(delta), ['id']), ['id']), tableSummary(before, ['id']));
});

test('destination conflicts fail rather than overwrite acknowledged writes', () => {
  const delta = difference([{ id: 'a', n: 1 }], [{ id: 'a', n: 2 }], ['id']);
  assert.throws(() => applyDifference([{ id: 'a', n: 3 }], delta, ['id']), /conflicts/);
});

test('canonical checksums ignore object and row order, preserve arrays, and reject unsafe numbers', () => {
  assert.equal(canonical({ b: 2, a: 1 }), canonical({ a: 1, b: 2 }));
  assert.notEqual(canonical([1, 2]), canonical([2, 1]));
  assert.throws(() => canonical(Number.MAX_SAFE_INTEGER + 1), /Unsafe/);
  assert.throws(() => canonical(undefined), /non-JSON/);
  assert.deepEqual(tableSummary([{ a: 1, b: 2 }, { a: 2, b: 1 }], ['a', 'b']), tableSummary([{ b: 1, a: 2 }, { b: 2, a: 1 }], ['a', 'b']));
  assert.throws(() => tableSummary([{ id: 'a' }, { id: 'a' }], ['id']), /Duplicate/);
});

test('backup encryption rejects tampering, wrong keys and swapped chunk names', () => {
  const key = randomBytes(32), bytes = Buffer.from('sensitive identity data');
  const sealed = encrypt(bytes, key, 'backup/chunk');
  assert.deepEqual(decrypt(sealed, key, 'backup/chunk'), bytes);
  assert.throws(() => decrypt(sealed, key, 'backup/other'));
  assert.throws(() => decrypt(sealed, randomBytes(32), 'backup/chunk'));
  sealed[sealed.length - 1] ^= 1;
  assert.throws(() => decrypt(sealed, key, 'backup/chunk'));
});

test('encrypted vault writes verified resumable chunks and rejects traversal', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'leafy-backup-test-'));
  try {
    const vault = new Vault(dir, randomBytes(32), 'test');
    const row = { id: 'a', password_hash: 'synthetic-test-hash' };
    const chunk = await vault.putJSON('auth-0001', [row]);
    assert.deepEqual(await vault.getJSON(chunk.name, chunk), [row]);
    await assert.rejects(vault.getJSON(chunk.name, { ...chunk, bytes: 1 }), /verification/);
    await assert.rejects(vault.putJSON('../escape', {}), /Invalid/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('schema conversion fails on lossy IDs, invalid booleans and unknown columns',()=>{
  const meta={columns:[{name:'id',type:'bigint',nullable:false},{name:'active',type:'boolean',nullable:false},{name:'data',type:'jsonb',nullable:false}]};
  assert.deepEqual(encodeRow(meta,{id:'123',active:true,data:{a:1}}),{id:123,active:1,data:'{"a":1}'});
  assert.throws(()=>encodeRow(meta,{id:'9007199254740993',active:true,data:{}}),/precision/);
  assert.throws(()=>encodeRow(meta,{id:'1',active:'false',data:{}}),/boolean/);
  assert.throws(()=>encodeRow(meta,{id:'1',active:false,data:{},secret:'unexpected'}),/Unmapped/);
});

test('SQL export encodes hostile text as data and rejects untrusted identifiers',()=>{
  const sql=upsertSQL('posts',{id:'a',body:"'; DROP TABLE profiles; --"},['id']);
  assert.equal(sql.includes('DROP TABLE'),false);
  assert.throws(()=>upsertSQL('posts; DROP TABLE profiles',{id:'a'},['id']),/identifier/);
});

test('identity conversion keeps UUID, password hash, verified email and ban; rejects collisions',()=>{
  const user={id:'existing-user',email:'TEST@example.com',encrypted_password:'$2a$10$testonly',email_confirmed_at:'2026-01-01T00:00:00Z',banned_until:'2027-01-01T00:00:00Z',created_at:'2026-01-01T00:00:00Z',is_anonymous:false};
  const converted=identityRows([user],[{user_id:user.id,provider:'email'}]);
  assert.equal(converted.identity_user[0].id,user.id);
  assert.equal(converted.identity_user[0].email,'test@example.com');
  assert.equal(converted.identity_account[0].password,user.encrypted_password);
  assert.equal(converted.auth_users[0].banned_until,'2027-01-01T00:00:00.000000Z');
  assert.throws(()=>identityRows([user,{...user,id:'another'}],[]),/collision/);
  assert.throws(()=>identityRows([user],[{user_id:user.id,provider:'apple'}]),/Unsupported/);
});

test('timestamp conversion preserves PostgreSQL microseconds across timezone offsets and sorts consistently',()=>{
  assert.equal(timestamp('2026-09-05 16:00:00.123456+08'),'2026-09-05T08:00:00.123456Z');
  assert.equal(timestamp('2026-09-05T08:00:00.123Z'),'2026-09-05T08:00:00.123000Z');
  assert.ok(timestamp('2026-09-05T08:00:00.123Z')<timestamp('2026-09-05T08:00:00.123001Z'));
});

test('a complete encrypted synthetic backup converts all business tables and validates foreign keys',async()=>{
  const root=await mkdtemp(join(tmpdir(),'leafy-convert-test-')),id='synthetic-backup',key=randomBytes(32),vault=new Vault(join(root,id),key,id);
  const source=new DatabaseSync(':memory:');
  try{
    const migrations=new URL('../migrations/',import.meta.url);
    for(const name of (await readdir(migrations)).filter(n=>n.endsWith('.sql')).sort())source.exec(await readFile(new URL(name,migrations),'utf8'));
    source.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi'); INSERT INTO profiles(id,campus_id,edu_id,nickname) VALUES('profile-test','bjfu','test','合成资料');");
    const mapping=JSON.parse(await readFile(new URL('../contracts/table-mapping.json',import.meta.url),'utf8'));
    const manifest={id,version:1,complete:true,tables:{},schema:await vault.put('schema.sql',Buffer.from('-- synthetic fixture schema'))};
    for(const [table,meta] of Object.entries(mapping)){
      const records=source.prepare(`SELECT * FROM "${table}"`).all().map(row=>Object.fromEntries(meta.columns.map(c=>[c.name,row[c.name]===null?null:c.type==='boolean'?row[c.name]===1:c.type==='jsonb'?JSON.parse(row[c.name]):row[c.name]])));
      const saved=await vault.putJSON(table,records);
      manifest.tables[table]={source:meta.source,primaryKey:meta.primaryKey,count:records.length,chunks:[{...saved,row_summary:tableSummary(records,meta.primaryKey)}]};
    }
    for(const table of ['source_auth_users','source_auth_identities','source_storage_objects','source_storage_buckets'])manifest.tables[table]={primaryKey:['id'],count:0,chunks:[]};
    await vault.putJSON('manifest',manifest);await vault.putJSON('files-manifest',{backup_id:id,complete:true,objects:{}});
    const output=join(root,'converted.sqlite');
    const report=await materialize(join(root,id),output,key);assert.equal(report.tables.profiles.count,1);
    const converted=new DatabaseSync(output,{readOnly:true});
    try{assert.equal(converted.prepare('SELECT nickname FROM profiles').get().nickname,'合成资料');assert.deepEqual(converted.prepare('PRAGMA foreign_key_check').all(),[]);}
    finally{converted.close();}
    const transfer=await transferSQL(output);
    source.exec('BEGIN;'+transfer.sql+'COMMIT;');
    assert.equal(source.prepare('SELECT nickname FROM profiles').get().nickname,'合成资料');
    assert.equal(source.prepare('SELECT mode FROM backend_control').get().mode,'read_only');
  }finally{source.close();await rm(root,{recursive:true,force:true});}
});

test('large D1 string values are reconstructed losslessly without overlong SQL statements',()=>{
  const db=new DatabaseSync(':memory:');
  try{
    db.exec('CREATE TABLE data(id TEXT PRIMARY KEY,value TEXT); CREATE TABLE _leafy_migration_values(id TEXT,ordinal INTEGER,value TEXT,PRIMARY KEY(id,ordinal));');
    const value='📚课程'.repeat(12000),statements=rowSQL('data',{id:'row',value});
    assert.ok(statements.every(sql=>Buffer.byteLength(sql)<95000));db.exec(statements.join('\n'));
    assert.equal(db.prepare('SELECT value FROM data').get().value,value);
  }finally{db.close();}
});
