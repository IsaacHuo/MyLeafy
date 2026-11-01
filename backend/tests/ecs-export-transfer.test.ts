import {expect,it,vi} from 'vitest';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {downloadObject,validateResume,verifyCachedObject} from '../scripts/ecs/export-objects.mjs';
import {encrypt} from '../scripts/migration/snapshot.mjs';
import {sha} from '../scripts/ecs/snapshot.mjs';
it('retries a truncated response body after successful headers',async()=>{
 const error=Object.assign(new TypeError('terminated'),{cause:{code:'UND_ERR_SOCKET'}});
 const request=vi.fn().mockResolvedValueOnce({arrayBuffer:()=>Promise.reject(error)}).mockResolvedValueOnce(new Response('retained bytes'));
 const result=await downloadObject({request},'/private-object',14,{pause:vi.fn()});
 expect(result.bytes.toString()).toBe('retained bytes');expect(request).toHaveBeenCalledTimes(2);
});
it('rejects a changed size without retrying a logically changed object',async()=>{
 const request=vi.fn().mockResolvedValue(new Response('short'));
 await expect(downloadObject({request},'/private-object',14,{pause:vi.fn()})).rejects.toThrow('size changed');expect(request).toHaveBeenCalledTimes(1);
});
it('resumes only the same frozen environment and verified table prefix',()=>{
 const schema=[{type:'table',name:'kept',sql:'CREATE TABLE kept(id TEXT)',tbl_name:'kept'}];
 const snapshot={version:1,environment:'production',consistent:true,complete:false,createdAt:'2026-11-01T15:10:00Z',schema,tables:[{name:'kept',rows:[],sha256:sha('[]')}],objects:[]};
 expect(()=>validateResume(snapshot,'production',schema,'2026-11-01T15:09:00Z')).not.toThrow();
 for(const invalid of [{...snapshot,consistent:false},{...snapshot,complete:true},{...snapshot,environment:'staging'},{...snapshot,tables:[{...snapshot.tables[0],rows:[1]}]}])expect(()=>validateResume(invalid,'production',schema,'2026-11-01T15:09:00Z')).toThrow();
 expect(()=>validateResume(snapshot,'production',schema,'2026-11-01T15:11:00Z')).toThrow();
});
it('reuses encrypted objects only after authenticating their bytes and checksum',async()=>{
 const directory=await mkdtemp(join(tmpdir(),'leafy-export-')),path=join(directory,'object.enc'),key=Buffer.alloc(32,1),bytes=Buffer.from('retained');
 const object={id:'safe-object',size:bytes.length,sha256:sha(bytes)};
 try{
  const encrypted=encrypt(bytes,key,'ecs-object:'+object.id);await writeFile(path,encrypted);
  await expect(verifyCachedObject(path,key,object)).resolves.toBeUndefined();
  await expect(verifyCachedObject(path,key,{...object,sha256:'0'.repeat(64)})).rejects.toThrow('integrity');
  encrypted[encrypted.length-1]^=1;await writeFile(path,encrypted);
  await expect(verifyCachedObject(path,key,object)).rejects.toThrow();
 }finally{await rm(directory,{recursive:true,force:true});}
});
