import { mkdirSync,writeFileSync,renameSync,readFileSync,existsSync,statSync,chownSync } from 'node:fs';
import {randomUUID} from 'node:crypto';
const [environment,operation]=process.argv.slice(2);
if(!['production','staging'].includes(environment)||!['begin','end','backup-success','backup-failed'].includes(operation))throw new Error('Invalid monitoring maintenance operation');
const directory='/run/myleafy-monitor',path=`${directory}/${environment}.maintenance.json`;
mkdirSync(directory,{recursive:true,mode:0o755});
if(operation==='begin'||operation==='end'){
  const data={until:operation==='begin'?Date.now()+15*60_000:Date.now(),reason:'deployment_or_backup'};
  writeFileSync(path+'.new',JSON.stringify(data)+'\n',{mode:0o644});renameSync(path+'.new',path);
}else {
  const destination=`/var/lib/myleafy-monitor/backup/${environment}.json`;
  if(!existsSync(destination))process.exit(0); // Monitoring has not been installed yet.
  const old=JSON.parse(readFileSync(destination,'utf8'));
  // The directory is root-owned; the monitor can only read this status receipt.
  const temporary=destination+'.'+randomUUID(),group=statSync(destination).gid;
  writeFileSync(temporary,JSON.stringify({successAt:operation==='backup-success'?Date.now():old.successAt??null,failed:operation==='backup-failed'})+'\n',{mode:0o640,flag:'wx'});
  chownSync(temporary,0,group);renameSync(temporary,destination);
}
