import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, relative } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
async function files(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const groups = await Promise.all(entries.filter(e => !['node_modules', 'build', '.git'].includes(e.name)).map(e =>
    e.isDirectory() ? files(resolve(dir, e.name)) : Promise.resolve([resolve(dir, e.name)])));
  return groups.flat();
}
const roots = ['leafy', 'android/app/src/main', 'supabase/functions', 'site/functions', 'site/src/admin'];
const calls = [];
const dynamicCalls: {file:string;line:number;kind:string;expression:string}[] = [];
const authCalls: {file:string;line:number;method:string}[] = [];
for (const directory of roots) {
  for (const path of await files(resolve(root, directory))) {
    if (!/\.(swift|kt|ts|js|tsx)$/.test(path)) continue;
    const source = await readFile(path, 'utf8');
    for (const match of source.matchAll(/\.auth\.([A-Za-z_][A-Za-z_0-9]*)/g)) {
      authCalls.push({file:relative(root,path).replaceAll('\\','/'),line:source.slice(0,match.index).split('\n').length,method:match[1]});
    }
    for (const match of source.matchAll(/\.(from|rpc|invoke)\(\s*([^"'\s][^,\n)]*)/g)) {
      dynamicCalls.push({file:relative(root,path).replaceAll('\\','/'),line:source.slice(0,match.index).split('\n').length,kind:match[1],expression:match[2].trim().slice(0,200)});
    }
    for (const match of source.matchAll(/\.(from|rpc|invoke)\(\s*["']([\w-]+)["']/g)) {
      calls.push({ file: relative(root, path).replaceAll('\\', '/'), line: source.slice(0, match.index).split('\n').length, kind: match[1], name: match[2] });
    }
    for (const match of source.matchAll(/\.from\s*<[^>]+>\(\s*["']([\w-]+)["']/g)) {
      calls.push({ file: relative(root, path).replaceAll('\\', '/'), line: source.slice(0, match.index).split('\n').length, kind: 'from', name: match[1] });
    }
  }
}
const migrationNames = (await readdir(resolve(root, 'supabase/migrations'))).filter(n => n.endsWith('.sql')).sort();
const edgeFunctions = (await readdir(resolve(root, 'supabase/functions'), { withFileTypes: true })).filter(e => e.isDirectory() && e.name !== '_shared').map(e => e.name).sort();
const adminSource=await readFile(resolve(root,'site/src/admin/registry.ts'),'utf8');
const adminActions=[...adminSource.matchAll(/^\s*"([A-Za-z]+)",?$/gm)].map(match=>match[1]);
const manifest = { source: 'Repository call sites including dynamic calls, Auth and the admin registry. Production drift must be verified separately.', migrations: migrationNames, edgeFunctions, calls, dynamicCalls, authCalls, adminActions,
  weather: {ios:'Direct WeatherKit (AppDependencies.live)',android:'Direct Open-Meteo (WeatherRepository)',legacy:'campus-weather remains on the retiring Supabase backend; not a new required weather provider'} };
await mkdir(resolve(root, 'backend/contracts'), { recursive: true });
await writeFile(resolve(root, 'backend/contracts/source-calls.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ migrations: migrationNames.length, edgeFunctions: edgeFunctions.length, callSites: calls.length, dynamicCalls:dynamicCalls.length,authCalls:authCalls.length,adminActions:adminActions.length,rpcNames: [...new Set(calls.filter(c => c.kind === 'rpc').map(c => c.name))].sort() }));
