// Read-only staging workload. Only timing/status/byte counts are retained.
import https from 'node:https';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
const [secondsText,destination]=process.argv.slice(2),seconds=Number(secondsText);
if(!Number.isInteger(seconds)||seconds<30||seconds>3600||!destination||existsSync(destination))throw new Error('Usage: monitoring-benchmark.mjs SECONDS NEW_REPORT_PATH');
const units=['myleafy-prometheus.service','myleafy-node-exporter.service','myleafy-monitor@production.service','myleafy-monitor@staging.service'];
const started=Date.now(),durations=[],statuses={},samples=[],scenarios=[['api-staging.myleafy.space','/health'],['api-staging.myleafy.space','/v1/releases/android/latest'],['staging.myleafy.space','/']];
const agent=new https.Agent({keepAlive:true,maxSockets:2});let requests=0,bytes=0;
function sample(){
  const rows=units.map(unit=>{
    const fields=Object.fromEntries(execFileSync('systemctl',['show',unit,'-p','MainPID','-p','CPUUsageNSec','-p','ActiveState','-p','NRestarts'],{encoding:'utf8'}).trim().split('\n').map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
    let rss=null;try{rss=Number(readFileSync(`/proc/${fields.MainPID}/statm`,'utf8').split(' ')[1])*4096;}catch{}
    return {unit,active:fields.ActiveState,pid:Number(fields.MainPID)||null,restarts:Number(fields.NRestarts)||0,cpuNSec:/^\d+$/.test(fields.CPUUsageNSec)?Number(fields.CPUUsageNSec):null,rss};
  });
  samples.push({at:Date.now(),units:rows});
}
async function probe(host,path){
  const begin=performance.now();
  await new Promise(resolve=>{
    const request=https.request({hostname:host,path,agent,lookup:(_host,options,callback)=>options.all?callback(null,[{address:'127.0.0.1',family:4}]):callback(null,'127.0.0.1',4),headers:{'User-Agent':'MyLeafy-Benchmark/1'}},response=>{
      statuses[response.statusCode]=(statuses[response.statusCode]??0)+1;
      response.on('data',data=>{bytes+=data.length;});response.on('end',()=>{if(Date.now()-started>10_000)durations.push(performance.now()-begin);resolve();});response.on('error',resolve);
    });
    request.setTimeout(5000,()=>request.destroy());request.on('error',()=>{statuses.transport_error=(statuses.transport_error??0)+1;resolve();});request.end();
  });
}
function report(){
  const sorted=[...durations].sort((a,b)=>a-b),percentile=p=>sorted[Math.floor((sorted.length-1)*p)]??null;
  const cpu=[];
  for(let i=1;i<samples.length;i++){
    const prior=samples[i-1],current=samples[i];let delta=0;
    for(const row of current.units){const old=prior.units.find(x=>x.unit===row.unit);if(row.cpuNSec!==null&&old?.cpuNSec!==null&&row.pid===old?.pid)delta+=Math.max(0,row.cpuNSec-old.cpuNSec);}
    cpu.push(delta/1e6/(current.at-prior.at)/2*100);
  }
  return {startedAt:new Date(started).toISOString(),checkedAt:new Date().toISOString(),elapsedSeconds:(Date.now()-started)/1000,requests,bytes,statuses,p50ms:percentile(.5),p95ms:percentile(.95),p99ms:percentile(.99),meanCpuPercent:cpu.length?cpu.reduce((a,b)=>a+b,0)/cpu.length:null,peakMonitorRSS:Math.max(0,...samples.map(s=>s.units.reduce((sum,u)=>sum+(u.rss??0),0))),samples,complete:Date.now()-started>=seconds*1000};
}
sample();
while(Date.now()-started<seconds*1000){const index=requests++%scenarios.length;await probe(...scenarios[index]);if(Date.now()-(samples.at(-1)?.at??0)>=30_000){sample();writeFileSync(destination,JSON.stringify(report(),null,2)+'\n',{mode:0o600});}await new Promise(resolve=>setTimeout(resolve,250));}
sample();agent.destroy();writeFileSync(destination,JSON.stringify(report(),null,2)+'\n',{mode:0o600});console.log(JSON.stringify({...report(),samples:undefined}));
