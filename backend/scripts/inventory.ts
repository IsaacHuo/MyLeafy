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
for (const directory of roots) {
  for (const path of await files(resolve(root, directory))) {
    if (!/\.(swift|kt|ts|js|tsx)$/.test(path)) continue;
    const source = await readFile(path, 'utf8');
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
const manifest = { source: 'Repository call sites; production drift must be verified separately', migrations: migrationNames, edgeFunctions, calls };
await mkdir(resolve(root, 'backend/contracts'), { recursive: true });
await writeFile(resolve(root, 'backend/contracts/source-calls.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ migrations: migrationNames.length, edgeFunctions: edgeFunctions.length, callSites: calls.length, rpcNames: [...new Set(calls.filter(c => c.kind === 'rpc').map(c => c.name))].sort() }));
