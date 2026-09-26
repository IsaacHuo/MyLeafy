import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { resolve } from 'node:path';

export function canonical(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || (Number.isInteger(value) && !Number.isSafeInteger(value))) throw new Error('Unsafe JSON number');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  throw new Error('Snapshot contains a non-JSON value');
}

export const digest = value => createHash('sha256').update(value).digest('hex');
export const rowHash = row => digest(canonical(row));

export function keyOf(row, primaryKey) {
  if (!primaryKey.length || primaryKey.some(key => row[key] == null)) throw new Error('Missing primary key');
  return canonical(primaryKey.map(key => row[key]));
}

function indexed(rows, primaryKey) {
  const result = new Map();
  for (const row of rows) {
    const key = keyOf(row, primaryKey);
    if (result.has(key)) throw new Error('Duplicate primary key in snapshot');
    result.set(key, row);
  }
  return result;
}

export function tableSummary(rows, primaryKey) {
  const entries = [...indexed(rows, primaryKey)].map(([key, row]) => [key, rowHash(row)]);
  entries.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
  return { count: entries.length, sha256: rowHash(entries) };
}

/** Full primary-key comparison catches hard deletes and rows without updated_at. */
export function difference(before, after, primaryKey) {
  const previous = indexed(before, primaryKey);
  const current = indexed(after, primaryKey);
  const inserted = [], updated = [], deleted = [];
  for (const [key, row] of current) {
    const old = previous.get(key);
    if (!old) inserted.push(row);
    else if (rowHash(old) !== rowHash(row)) updated.push({ before: old, after: row });
  }
  for (const [key, row] of previous) if (!current.has(key)) deleted.push(row);
  return { inserted, updated, deleted };
}

export function applyDifference(rows, delta, primaryKey) {
  const result = indexed(rows, primaryKey);
  for (const row of delta.deleted) {
    const key = keyOf(row, primaryKey);
    if (result.has(key) && rowHash(result.get(key)) !== rowHash(row)) throw new Error('Delete conflicts with destination');
    result.delete(key);
  }
  for (const { before, after } of delta.updated) {
    const key = keyOf(before, primaryKey);
    if (key !== keyOf(after, primaryKey)) throw new Error('Primary key changes require delete and insert');
    const old = result.get(key);
    if (!old || (rowHash(old) !== rowHash(before) && rowHash(old) !== rowHash(after))) throw new Error('Update conflicts with destination');
    result.set(key, after);
  }
  for (const row of delta.inserted) {
    const key = keyOf(row, primaryKey), old = result.get(key);
    if (old && rowHash(old) !== rowHash(row)) throw new Error('Insert conflicts with destination');
    result.set(key, row);
  }
  return [...result.values()];
}

export function reverseDifference(delta) {
  return { inserted: delta.deleted, deleted: delta.inserted, updated: delta.updated.map(({ before, after }) => ({ before: after, after: before })) };
}

export function backupKey(value = process.env.BACKUP_ENCRYPTION_KEY) {
  if (!value || !/^[a-f0-9]{64}$/i.test(value)) throw new Error('BACKUP_ENCRYPTION_KEY must contain 32 random bytes encoded as hex');
  return Buffer.from(value, 'hex');
}

/** Envelope authentication binds each encrypted chunk to its backup and logical name. */
export function encrypt(bytes, key, context) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from(context));
  const ciphertext = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return Buffer.concat([Buffer.from('LEAFYBK1'), iv, cipher.getAuthTag(), ciphertext]);
}

export function decrypt(bytes, key, context) {
  if (bytes.length < 36 || bytes.subarray(0, 8).toString() !== 'LEAFYBK1') throw new Error('Unsupported encrypted backup');
  const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(8, 20));
  decipher.setAAD(Buffer.from(context));
  decipher.setAuthTag(bytes.subarray(20, 36));
  return Buffer.concat([decipher.update(bytes.subarray(36)), decipher.final()]);
}

function safeName(name) {
  if (!/^[a-zA-Z0-9_.-]+$/.test(name) || name === '.' || name === '..') throw new Error('Invalid backup chunk name');
  return name;
}

export class Vault {
  constructor(directory, key, backupId) {
    this.directory = resolve(directory);
    this.key = key;
    this.backupId = safeName(backupId);
  }
  async put(name, bytes) {
    safeName(name);
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    const encrypted = encrypt(bytes, this.key, `${this.backupId}/${name}`);
    const path = resolve(this.directory, `${name}.enc`);
    const temporary = `${path}.${randomBytes(6).toString('hex')}.tmp`;
    await writeFile(temporary, encrypted, { mode: 0o600, flag: 'wx' });
    await rename(temporary, path);
    return { name, bytes: bytes.length, sha256: digest(bytes) };
  }
  async get(name, expected) {
    safeName(name);
    const bytes = decrypt(await readFile(resolve(this.directory, `${name}.enc`)), this.key, `${this.backupId}/${name}`);
    if (expected && (bytes.length !== expected.bytes || digest(bytes) !== expected.sha256)) throw new Error('Backup chunk verification failed');
    return bytes;
  }
  async putJSON(name, value) { return this.put(name, Buffer.from(canonical(value))); }
  async getJSON(name, expected) { return JSON.parse((await this.get(name, expected)).toString('utf8')); }
}
