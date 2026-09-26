import { readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { supportedAdminActions } from '../src/admin-router';

const root=resolve(import.meta.dirname,'../..');
const registry=await readFile(resolve(root,'site/src/admin/registry.ts'),'utf8');
const actions=[...registry.split('] as const')[0].matchAll(/"([a-zA-Z]+)"/g)].map(m=>m[1]);
const missing=actions.filter(action=>!supportedAdminActions.has(action));
if(missing.length)throw new Error(`Unimplemented admin actions: ${missing.join(', ')}`);
async function scan(directory:string):Promise<string[]>{
  const result:string[]=[];
  for(const entry of await readdir(directory,{withFileTypes:true})){
    const path=resolve(directory,entry.name);
    if(entry.isDirectory())result.push(...await scan(path));
    else if(entry.name.endsWith('.swift'))result.push(path);
  }
  return result;
}
const forbidden=/^import Supabase\b|LeafySupabase\b|SupabaseClient\b|storage\/v1\/|rest\/v1\//m;
const remaining=[];
for(const path of await scan(resolve(root,'leafy')))if(forbidden.test(await readFile(path,'utf8')))remaining.push(path.slice(root.length+1));
if(remaining.length)throw new Error(`Retired backend runtime remains: ${remaining.join(', ')}`);
console.log(JSON.stringify({admin_actions:actions.length,missing:0,ios_supabase_runtime_references:0}));
