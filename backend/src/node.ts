import { serve } from '@hono/node-server';
import { WebSocketServer } from 'ws';
import cron from 'node-cron';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { SqliteDatabase } from './runtime/database';
import { LocalObjectStore } from './runtime/files';
import { createHandler } from './runtime/server';
import { drainBackground, defer } from './runtime/background';
import { ChangeSignals } from './signals';
import { scheduled } from './jobs';
import type { BackendEnv, Secrets } from './auth';

const environment=process.env.ENVIRONMENT;
if(environment!=='staging'&&environment!=='production')throw new Error('ENVIRONMENT must be staging or production');
const required=(name:string)=>{const value=process.env[name];if(!value)throw new Error(`Missing ${name}`);return value;};
const root=resolve(required('DATA_DIRECTORY')),db=new SqliteDatabase(join(root,'database.sqlite'));
const secrets:Secrets={};
for(const name of ['AUTH_SECRET','MEDIA_SIGNING_SECRET','EMAIL_API_KEY','EMAIL_FROM','TEST_EMAIL_RECIPIENT','RELEASE_PUBLISH_TOKEN','GITHUB_RELEASE_TOKEN','ANDROID_SIGNING_CERTIFICATE_SHA256'] as const)secrets[name]=process.env[name];
for(const name of ['AUTH_SECRET','MEDIA_SIGNING_SECRET'] as const)if((secrets[name]?.length??0)<32)throw new Error(`${name} must retain the existing secret (at least 32 characters)`);
const env:BackendEnv={...secrets,DB:db,FILES:new LocalObjectStore(join(root,'files')),RELEASES:new LocalObjectStore(join(root,'releases')),SIGNALS:new ChangeSignals({DB:db}),ENVIRONMENT:environment,API_ORIGIN:required('API_ORIGIN'),SITE_ORIGIN:required('SITE_ORIGIN'),DEPLOY_COMMIT:required('DEPLOY_COMMIT')};
const maintenanceFile=join(root,'maintenance');
const wss=new WebSocketServer({noServer:true,maxPayload:1024});
const server=serve({hostname:'127.0.0.1',port:Number(process.env.PORT??(environment==='production'?3100:3101)),fetch:createHandler(env,maintenanceFile),websocket:{server:wss}},()=>console.log(JSON.stringify({event:'listening',environment,commit:env.DEPLOY_COMMIT})));
const jobs=['* * * * *','17 * * * *','20 17 * * *','35 18 * * *'].map(expression=>cron.schedule(expression,async(context)=>{
  if(!existsSync(maintenanceFile)){const run=scheduled({cron:expression,scheduledTime:context.date.getTime()},env);defer(run);await run;}
},{timezone:'UTC',noOverlap:true}));
let stopping=false;
async function shutdown(){
  if(stopping)return;stopping=true;
  for(const job of jobs)await job.stop();
  env.SIGNALS.close();wss.close();
  await new Promise<void>((done,reject)=>server.close(error=>error?reject(error):done()));
  await drainBackground();db.close();
}
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{void shutdown().catch(()=>{console.error(JSON.stringify({event:'shutdown_failed'}));process.exitCode=1;});});
