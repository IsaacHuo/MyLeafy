import {readFile,lstat} from 'node:fs/promises';
import {resolve,relative} from 'node:path';
import {createHash} from 'node:crypto';
const [directory,commit]=process.argv.slice(2),root=resolve(directory??'.');
const manifest=JSON.parse(await readFile(resolve(root,'release-manifest.json'),'utf8'));
if(!/^[a-f0-9]{40}$/.test(commit??'')||manifest.version!==1||manifest.commit!==commit)throw new Error('Release identity mismatch');
for(const [name,hash] of Object.entries(manifest.files)){
 const path=resolve(root,name);if(!relative(root,path)||relative(root,path).startsWith('..')||(await lstat(path)).isSymbolicLink())throw new Error('Unsafe release path');
 if(createHash('sha256').update(await readFile(path)).digest('hex')!==hash)throw new Error('Release checksum mismatch');
}
console.log(JSON.stringify({commit,verified:true,files:Object.keys(manifest.files).length}));
