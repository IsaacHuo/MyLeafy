import { basename, resolve } from 'node:path';
import { backupKey, digest, Vault } from './snapshot.mjs';

const directory=process.argv[2];
if(!directory||!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)throw new Error('Usage: files.mjs BACKUP_DIRECTORY; Supabase operator credentials and BACKUP_ENCRYPTION_KEY are required');
const vault=new Vault(directory,backupKey(),basename(resolve(directory)));
const manifest=await vault.getJSON('manifest');
if(!manifest.complete)throw new Error('Database snapshot is incomplete');
const metadata=manifest.tables.source_storage_objects;
if(!metadata)throw new Error('Storage metadata is missing from backup');
let files;
try{files=await vault.getJSON('files-manifest');}
catch(error){if(error.code!=='ENOENT')throw error;files={version:1,backup_id:manifest.id,complete:false,objects:{}};}
if(files.backup_id!==manifest.id)throw new Error('File manifest belongs to another backup');
for(const chunk of metadata.chunks){
  for(const object of await vault.getJSON(chunk.name,chunk)){
    const name=`object-${digest(`${object.bucket_id}/${object.name}`)}`;
    const existing=files.objects[name];
    if(existing){await vault.get(existing.chunk.name,existing.chunk);continue;}
    const objectPath=[object.bucket_id,...object.name.split('/')].map(encodeURIComponent).join('/');
    const url=`${process.env.SUPABASE_URL.replace(/\/$/,'')}/storage/v1/object/authenticated/${objectPath}`;
    const response=await fetch(url,{headers:{apikey:process.env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`},signal:AbortSignal.timeout(60000)});
    if(!response.ok)throw new Error(`Storage download failed (HTTP ${response.status}); no object is silently skipped`);
    const expected=Number(object.metadata?.size??object.metadata?.contentLength);
    const length=Number(response.headers.get('content-length'));
    if(expected>128*1024*1024||length>128*1024*1024)throw new Error('Object exceeds the bounded export size');
    const reader=response.body.getReader(),parts=[];let bytes=0;
    while(true){
      const part=await reader.read();if(part.done)break;
      bytes+=part.value.length;
      if(bytes>128*1024*1024){await reader.cancel();throw new Error('Object exceeds the bounded export size');}
      parts.push(part.value);
    }
    if(Number.isFinite(expected)&&expected!==bytes)throw new Error('Storage object changed since metadata snapshot; take a new snapshot after freezing source writes');
    const content=Buffer.concat(parts),saved=await vault.put(name,content);
    files.objects[name]={bucket:object.bucket_id,path:object.name,source_id:object.id,source_version:object.version??null,content_type:response.headers.get('content-type')??object.metadata?.mimetype??'application/octet-stream',chunk:saved};
    await vault.putJSON('files-manifest',files);
    console.log(JSON.stringify({objects:Object.keys(files.objects).length,total_objects:metadata.count}));
  }
}
if(Object.keys(files.objects).length!==metadata.count)throw new Error('File inventory count mismatch');
files.complete=true;await vault.putJSON('files-manifest',files);
console.log(JSON.stringify({backup_id:manifest.id,files_complete:true,objects:metadata.count}));
