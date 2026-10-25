import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, rename, rm, stat, writeFile, open } from 'node:fs/promises';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { ApiError } from '../http';
import type { ObjectMetadata, ObjectStore, StoredObject } from './types';
type Metadata = ObjectMetadata & { key: string };
export class LocalObjectStore implements ObjectStore {
  constructor(readonly root: string) {}
  private directory(key: string) {
    if (!key || key.startsWith('/') || key.includes('\\') || key.split('/').some(p => !p || p === '.' || p === '..') || /[\x00-\x1f\x7f]/.test(key)) throw new ApiError(400,'invalid_path','Invalid object key');
    return join(this.root, createHash('sha256').update(key).digest('hex'));
  }
  async head(key: string): Promise<Metadata | null> {
    const directory = this.directory(key);
    try {
      const metadata = JSON.parse(await readFile(join(directory,'metadata.json'),'utf8')) as Metadata;
      if (metadata.key !== key || (await stat(join(directory,'data'))).size !== metadata.size) throw new Error('Object metadata mismatch');
      return metadata;
    } catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null; throw error; }
  }
  async put(key: string, body: Uint8Array | ReadableStream<Uint8Array> | null, options: Parameters<ObjectStore['put']>[2]) {
    const destination = this.directory(key);
    await mkdir(this.root,{recursive:true,mode:0o700});
    const temporary = join(this.root,`.pending-${randomUUID()}`);
    await mkdir(temporary,{mode:0o700});
    try {
      const file = await open(join(temporary,'data'),'wx',0o600);
      const digest = createHash('sha256'); let size = 0;
      try {
        const chunks = body instanceof Uint8Array ? [body] : body ? Readable.fromWeb(body as never) : [];
        for await (const chunk of chunks) {
          const bytes = Buffer.from(chunk); size += bytes.length;
          if (size > 100_000_000) throw new ApiError(413,'payload_too_large','Object is too large');
          digest.update(bytes); await file.writeFile(bytes);
        }
        await file.sync();
      } finally { await file.close(); }
      const hash = digest.digest('hex');
      if (options.sha256 && options.sha256 !== hash || options.customMetadata?.sha256 && options.customMetadata.sha256 !== hash) throw new ApiError(422,'file_integrity','Object checksum mismatch');
      const metadata: Metadata = { key, size, httpEtag:`"${hash}"`, customMetadata:{...options.customMetadata,sha256:hash},httpMetadata:options.httpMetadata ?? {} };
      await writeFile(join(temporary,'metadata.json'),JSON.stringify(metadata),{mode:0o600});
      try { await rename(temporary,destination); }
      catch(error) { if (['EEXIST','ENOTEMPTY'].includes((error as NodeJS.ErrnoException).code ?? '')) return null; throw error; }
      return metadata;
    } finally { await rm(temporary,{recursive:true,force:true}); }
  }
  async get(key: string, options?: {range?: Headers}): Promise<StoredObject | null> {
    const metadata = await this.head(key); if (!metadata) return null;
    const path = join(this.directory(key),'data');
    const header = options?.range?.get('range');
    let range: {offset:number;length:number} | undefined;
    if (header && !header.includes(',')) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(header);
      if (!match || (!match[1] && !match[2])) throw new ApiError(416,'invalid_range','Invalid byte range');
      const offset = match[1] ? Number(match[1]) : Math.max(0,metadata.size-Number(match[2]));
      const end = match[1] && match[2] ? Math.min(metadata.size-1,Number(match[2])) : metadata.size-1;
      if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(end) || offset > end || offset >= metadata.size) throw new ApiError(416,'invalid_range','Unsatisfiable byte range');
      range = {offset,length:end-offset+1};
    }
    const stream = createReadStream(path,range ? {start:range.offset,end:range.offset+range.length-1} : {});
    const body=Readable.toWeb(stream) as ReadableStream<Uint8Array>;
    return {...metadata,range,body,arrayBuffer:async()=> {
      await body.cancel();
      const bytes = await readFile(path); return bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength) as ArrayBuffer;
    }};
  }
  async delete(key: string) { await rm(this.directory(key),{recursive:true,force:true}); }
}
