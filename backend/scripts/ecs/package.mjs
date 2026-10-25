import {execFileSync} from 'node:child_process';
import {cpSync,mkdirSync,readFileSync,readdirSync,writeFileSync,lstatSync} from 'node:fs';
import {resolve,join,relative} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'../../..'),[destination]=process.argv.slice(2);
if(!destination)throw new Error('Usage: package.mjs NEW_OUTPUT_DIRECTORY');
execFileSync('git',['diff','--exit-code','HEAD'],{cwd:root,stdio:'ignore'});
const commit=execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim();
const output=resolve(destination);mkdirSync(output,{mode:0o700});const tree=join(output,'release');mkdirSync(tree);
for(const path of ['backend/dist','backend/package.json','backend/package-lock.json','backend/migrations','backend/deploy','site/dist']){mkdirSync(resolve(tree,path,'..'),{recursive:true});cpSync(resolve(root,path),resolve(tree,path),{recursive:true});}
for(const path of ['backend/scripts/ecs','backend/scripts/migration'])mkdirSync(resolve(tree,path),{recursive:true});
for(const name of readdirSync(resolve(root,'backend/scripts/ecs')).filter(n=>n.endsWith('.mjs')))cpSync(resolve(root,'backend/scripts/ecs',name),resolve(tree,'backend/scripts/ecs',name));
for(const name of ['snapshot.mjs','cloudflare-auth.mjs'])cpSync(resolve(root,'backend/scripts/migration',name),resolve(tree,'backend/scripts/migration',name));
const files={};
function walk(directory){for(const name of readdirSync(directory)){const path=join(directory,name);if(lstatSync(path).isDirectory())walk(path);else files[relative(tree,path)]=createHash('sha256').update(readFileSync(path)).digest('hex');}}
walk(tree);writeFileSync(join(tree,'release-manifest.json'),JSON.stringify({version:1,commit,files},null,2));
const artifact=join(output,`myleafy-${commit}.tar.gz`);execFileSync('tar',['-C',tree,'-czf',artifact,'.'],{env:{...process.env,COPYFILE_DISABLE:'1'}});
writeFileSync(artifact+'.sha256',createHash('sha256').update(readFileSync(artifact)).digest('hex')+'\n');console.log(JSON.stringify({commit,artifact,files:Object.keys(files).length}));
