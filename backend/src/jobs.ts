import type { BackendEnv } from './auth';
import { atomic, guard, rows, statement } from './db';

export async function deliverSignals(env:BackendEnv){
  const pending=await rows(env.DB,'SELECT id,room FROM change_outbox WHERE delivered_at IS NULL ORDER BY created_at,id LIMIT 50');
  for(const event of pending){
    const room=env.SIGNALS.get(env.SIGNALS.idFromName(event.room as string));
    const response=await room.fetch('https://signals.internal/publish',{method:'POST',body:JSON.stringify({id:event.id}),headers:{'Content-Type':'application/json'}});
    if(!response.ok)throw new Error('Signal delivery failed');
    await env.DB.prepare('UPDATE change_outbox SET delivered_at=? WHERE id=? AND delivered_at IS NULL').bind(new Date().toISOString().replace('Z','000Z'),event.id).run();
  }
  return pending.length;
}

export async function cleanMedia(env:BackendEnv){
  const now=new Date().toISOString().replace('Z','000Z'),yesterday=new Date(Date.now()-86400000).toISOString().replace('Z','000Z');
  await atomic(env.DB,[statement(env.DB,"UPDATE posts SET status='deleted',media_purge_after=?,updated_at=? WHERE status='pending_review' AND created_at<?",[now,now,yesterday])]);
  const candidates=await rows(env.DB,`SELECT f.bucket,f.path FROM file_objects f LEFT JOIN posts p ON p.id=f.post_id WHERE f.state<>'deleting' AND (
    (p.status='deleted' AND p.media_cleanup_hold=0 AND p.media_purge_after<=? AND NOT EXISTS(SELECT 1 FROM community_reports r WHERE r.post_id=p.id AND r.status IN('open','reviewed')))
    OR (f.post_id IS NULL AND f.created_at<? AND NOT EXISTS(SELECT 1 FROM profiles u WHERE u.avatar_path=f.path OR u.cover_path=f.path) AND NOT EXISTS(SELECT 1 FROM community_banners b WHERE b.image_path=f.path AND f.bucket='community-banner-assets'))) LIMIT 100`,[now,yesterday]);
  for(const file of candidates){
    await atomic(env.DB,[
      guard(env.DB,`EXISTS(SELECT 1 FROM file_objects f LEFT JOIN posts p ON p.id=f.post_id WHERE f.bucket=? AND f.path=? AND (
        (p.status='deleted' AND p.media_cleanup_hold=0 AND p.media_purge_after<=? AND NOT EXISTS(SELECT 1 FROM community_reports r WHERE r.post_id=p.id AND r.status IN('open','reviewed')))
        OR (f.post_id IS NULL AND f.created_at<? AND NOT EXISTS(SELECT 1 FROM profiles u WHERE u.avatar_path=f.path OR u.cover_path=f.path) AND NOT EXISTS(SELECT 1 FROM community_banners b WHERE b.image_path=f.path AND f.bucket='community-banner-assets'))))`,[file.bucket as string,file.path as string,now,yesterday]),
      statement(env.DB,"UPDATE file_objects SET state='deleting' WHERE bucket=? AND path=?",[file.bucket as string,file.path as string]),
      statement(env.DB,'INSERT INTO file_delete_jobs(bucket,path) VALUES(?,?) ON CONFLICT DO NOTHING',[file.bucket as string,file.path as string]),
    ]);
  }
  const jobs=await rows(env.DB,'SELECT bucket,path FROM file_delete_jobs ORDER BY created_at,bucket,path LIMIT 100');
  let failures=0;
  for(const job of jobs){
    try{
      await env.FILES.delete(`${job.bucket}/${job.path}`);
      await atomic(env.DB,[
        statement(env.DB,'DELETE FROM post_images WHERE path=? OR thumbnail_path=?',[job.path as string,job.path as string]),
        statement(env.DB,'DELETE FROM post_attachments WHERE path=?',[job.path as string]),
        statement(env.DB,'DELETE FROM file_objects WHERE bucket=? AND path=?',[job.bucket as string,job.path as string]),
        statement(env.DB,'DELETE FROM file_delete_jobs WHERE bucket=? AND path=?',[job.bucket as string,job.path as string]),
      ]);
    }catch{
      failures++;
      await env.DB.prepare("UPDATE file_delete_jobs SET attempts=attempts+1,last_error_code='file_delete_failed' WHERE bucket=? AND path=?").bind(job.bucket,job.path).run();
    }
  }
  await atomic(env.DB,[statement(env.DB,"UPDATE posts SET media_purged_at=?,updated_at=? WHERE status='deleted' AND media_purge_after<=? AND media_purged_at IS NULL AND media_cleanup_hold=0 AND NOT EXISTS(SELECT 1 FROM file_objects f WHERE f.post_id=posts.id) AND NOT EXISTS(SELECT 1 FROM community_reports r WHERE r.post_id=posts.id AND r.status IN('open','reviewed'))",[now,now,now])]);
  if(failures)throw new Error('One or more file deletions failed; durable jobs retained');
}

export async function scheduled(event:ScheduledController,env:BackendEnv){
  const state=await env.DB.prepare('SELECT mode FROM backend_control WHERE id=1').first<{mode:string}>();
  if(state?.mode!=='active')return;
  const jobs:Record<string,()=>Promise<unknown>>={
    '* * * * *':()=>deliverSignals(env),
    '17 * * * *':()=>atomic(env.DB,[statement(env.DB,'DELETE FROM timetable_invites WHERE expires_at<=? AND accepted_at IS NULL',[new Date().toISOString().replace('Z','000Z')])]),
    '20 17 * * *':()=>atomic(env.DB,[statement(env.DB,'DELETE FROM admin_login_attempts WHERE attempted_at<?',[new Date(Date.now()-90*86400000).toISOString().replace('Z','000Z')]),statement(env.DB,'DELETE FROM change_outbox WHERE delivered_at IS NOT NULL AND created_at<?',[new Date(Date.now()-7*86400000).toISOString().replace('Z','000Z')])]),
    '35 18 * * *':()=>cleanMedia(env),
  };
  const run=jobs[event.cron];if(!run)throw new Error('Unknown scheduled task');
  const id=`${event.cron}:${event.scheduledTime}`;
  const claimed=await env.DB.prepare("INSERT INTO scheduled_runs(id,job,started_at,status) VALUES(?,?,?,'running') ON CONFLICT(id) DO UPDATE SET started_at=excluded.started_at,status='running',error_code=NULL WHERE scheduled_runs.status='failed' OR (scheduled_runs.status='running' AND scheduled_runs.started_at<?) RETURNING id")
    .bind(id,event.cron,new Date().toISOString().replace('Z','000Z'),new Date(Date.now()-15*60000).toISOString().replace('Z','000Z')).all();
  if(!claimed.results.length)return;
  try{await run();await env.DB.prepare("UPDATE scheduled_runs SET status='succeeded',finished_at=? WHERE id=?").bind(new Date().toISOString().replace('Z','000Z'),id).run();}
  catch(error){
    await env.DB.prepare("UPDATE scheduled_runs SET status='failed',finished_at=?,error_code='job_failed' WHERE id=?").bind(new Date().toISOString().replace('Z','000Z'),id).run();
    console.error(JSON.stringify({event:'scheduled_job_failed',job:event.cron,run_id:id}));throw error;
  }
}
