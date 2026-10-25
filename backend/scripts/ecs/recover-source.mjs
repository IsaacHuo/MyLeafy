// Explicit rollback before target writes. Never invoked automatically.
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {source} from './cloudflare.mjs';
import {quote} from './sql.mjs';
import {cloudflareToken} from '../migration/cloudflare-auth.mjs';
const [path,confirmation]=process.argv.slice(2);
if(!path||confirmation!=='--confirmed-no-target-writes')throw new Error('Usage: recover-source.mjs FREEZE_REPORT --confirmed-no-target-writes; stop the target first and protect any new data');
const report=JSON.parse(await readFile(path,'utf8')),remote=await source(report.environment);
if(report.worker!==remote.selected.name||report.database!==remote.selected.d1_databases[0].database_id||!/^[a-f0-9-]{36}$/.test(report.previousVersion??''))throw new Error('Source recovery identity mismatch');
const active=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
if(active?.length!==1||active[0].percentage!==100||active[0].version_id!==report.freezeVersion)throw new Error('Source active version changed; inspect before recovering');
const triggers=await remote.query("SELECT name FROM sqlite_schema WHERE type='trigger' AND name GLOB 'ecs_source_fence_*'");
for(const trigger of triggers)if(!report.fenceTriggers?.includes(trigger.name)||!/^ecs_source_fence_[a-f0-9]{24}$/.test(trigger.name))throw new Error('Unexpected source fence; no automatic removal');
for(const trigger of triggers)await remote.query(`DROP TRIGGER ${quote(trigger.name)}`);
await remote.query('DROP TABLE IF EXISTS _ecs_source_freeze');
const cli=resolve(import.meta.dirname,'../../node_modules/wrangler/bin/wrangler.js');
try{
 execFileSync(process.execPath,[cli,'versions','deploy',report.previousVersion,'--env',report.environment,'--yes'],{cwd:resolve(import.meta.dirname,'../..'),env:{...process.env,CLOUDFLARE_API_TOKEN:await cloudflareToken(),WRANGLER_SEND_METRICS:'false'},stdio:['ignore','pipe','pipe']});
}catch{throw new Error('Source code recovery not confirmed; inspect active version. Source data was retained.');}
const versions=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
if(versions?.length!==1||versions[0].percentage!==100||versions[0].version_id!==report.previousVersion)throw new Error('Source recovery verification failed');
await writeFile(path+'.recovered.json',JSON.stringify({environment:report.environment,worker:report.worker,version:report.previousVersion,recoveredAt:new Date().toISOString(),targetWritesConfirmedAbsent:true}),{mode:0o600,flag:'wx'});
console.log(JSON.stringify({environment:report.environment,sourceRecovered:true,note:'DNS recovery is separate; never route writes to both databases'}));
