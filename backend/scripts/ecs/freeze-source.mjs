import {fenceSQL} from './source-fence.mjs';
// Explicit operator cutover only. Never invoked by staging/production deployment.
import {source} from './cloudflare.mjs';
import {cloudflareToken} from '../migration/cloudflare-auth.mjs';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
const [environment,reportPath,confirmation]=process.argv.slice(2);
if(!reportPath||confirmation!=='--accepted-cutover'||!['staging','production'].includes(environment))throw new Error('Usage: freeze-source.mjs staging|production NEW_REPORT_FILE --accepted-cutover (filing and owner acceptance required)');
const remote=await source(environment);
const previous=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
if(previous?.length!==1||previous[0].percentage!==100)throw new Error('Expected one active source version');
const root=resolve(import.meta.dirname,'../../..'),directory=resolve(root,'backend/.local/ecs/freeze-'+environment+'-'+Date.now());await mkdir(directory,{mode:0o700});
const config={...remote.config,main:resolve(root,'backend/cutover/maintenance.ts')};
for(const env of Object.values(config.env))for(const db of env.d1_databases??[])db.migrations_dir=resolve(root,'backend/migrations');
const configPath=resolve(directory,'wrangler.json');await writeFile(configPath,JSON.stringify(config),{mode:0o600,flag:'wx'});
const report={environment,worker:remote.selected.name,database:remote.selected.d1_databases[0].database_id,previousVersion:previous[0].version_id,freezeVersion:null,allEntrypointsBlocked:false,databaseFrozen:false,complete:false};
await writeFile(reportPath,JSON.stringify(report),{mode:0o600,flag:'wx'});
const cli=resolve(root,'backend/node_modules/wrangler/bin/wrangler.js'),env={...process.env,CLOUDFLARE_API_TOKEN:await cloudflareToken(),WRANGLER_SEND_METRICS:'false'};
// Do not echo CLI output: auth failures can include sensitive diagnostics.
try{
 const output=execFileSync(process.execPath,[cli,'versions','upload','--config',configPath,'--env',environment,'--message','MyLeafy accepted ECS cutover: all source entries frozen'],{env,encoding:'utf8',stdio:['ignore','pipe','pipe']});
 const id=output.match(/(?:Worker Version ID|Version ID):\s*([a-f0-9-]{36})/i)?.[1];if(!id)throw new Error('Freeze version ID unavailable; source was not deployed');
 report.freezeVersion=id;await writeFile(reportPath,JSON.stringify(report,null,2),{mode:0o600});
 execFileSync(process.execPath,[cli,'versions','deploy',id,'--config',configPath,'--env',environment,'--yes'],{env,stdio:['ignore','pipe','pipe']});
 const versions=(await (await remote.request(`/workers/scripts/${remote.selected.name}/deployments`)).json()).result?.deployments?.[0]?.versions;
 if(versions?.length!==1||versions[0].percentage!==100||versions[0].version_id!==id)throw new Error('Source freeze deployment not confirmed');
 report.freezeVersion=id;report.allEntrypointsBlocked=true;
 await writeFile(reportPath,JSON.stringify(report,null,2),{mode:0o600});
 const schema=await remote.query("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'");
 const fence=fenceSQL(schema);report.fenceTriggers=fence.triggers;
 await writeFile(reportPath,JSON.stringify(report,null,2),{mode:0o600});
 // Activate only after every trigger is installed. A failed setup never claims
 // a consistent snapshot; the maintenance Worker remains in place for inspection.
 for(const sql of fence.statements)await remote.query(sql);
 report.databaseFrozen=true;report.fenceTriggers=fence.triggers;
 report.complete=true;report.allEntrypointsBlocked=true;report.frozenAt=new Date().toISOString();
 await writeFile(reportPath,JSON.stringify(report,null,2),{mode:0o600});
 console.log(JSON.stringify({environment,frozen:true,version:id,previousVersion:report.previousVersion,note:'Drain in-flight requests and publication jobs before final export'}));
}catch{throw new Error('Source freeze failed; consult protected report and inspect active version before retrying. No database was changed.');}
