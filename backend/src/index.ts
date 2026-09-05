import { Hono } from 'hono';
import { APIError as AuthAPIError } from 'better-auth/api';
import { ApiError } from './http';
import { readJSON } from './http';
import { actor, auth, type BackendEnv } from './auth';
import { requireWritable } from './db';
import { bootstrap, deleteAccount, myProfile, requestProfileEmail, updateProfile, verifyProfileEmail } from './identity';
import { comments, createComment, createPost, feed, notifications, postDetail, readNotifications, setTerms } from './community';
import { attach, readFile, setProfileImage, upload, validateAttachment, validateImages } from './media';
import { cleanMedia, deliverSignals, scheduled } from './jobs';
import { createPoll, deleteOwnContent, poll, report, requestPollDeletion, setBlock, setPostReaction, vote } from './interactions';
import { exchangeSession } from './session-exchange';
import { signedMediaURL, verifyMediaTicket } from './media-tickets';
import { postAccessSQL, requireCommunity } from './community';
import { acceptInvite, invite, publishTimetable, revokeShare, shareMembers, stopSharing, timetables } from './sharing';
import { catalog, rate } from './catalog';
import { currentMembership, requestMembership, runtimeConfiguration, searchCampuses, selectCampus } from './campus';
export { ChangeSignals } from './signals';

export const app=new Hono<{Bindings:BackendEnv;Variables:{requestId:string}}>();
app.use('*',async(c,next)=>{
  const id=crypto.randomUUID();c.set('requestId',id);
  c.header('X-Request-ID',id);c.header('X-Content-Type-Options','nosniff');c.header('Cache-Control','no-store');
  const origin=c.req.header('origin');
  if(origin&&origin!==c.env.SITE_ORIGIN&&origin!==c.env.API_ORIGIN)throw new ApiError(403,'forbidden','Origin is not allowed');
  if(origin){c.header('Access-Control-Allow-Origin',origin);c.header('Vary','Origin');c.header('Access-Control-Allow-Credentials','true');}
  if(c.req.method==='OPTIONS'){c.header('Access-Control-Allow-Methods','GET,POST,PUT,PATCH,DELETE,OPTIONS');c.header('Access-Control-Allow-Headers','Content-Type,Authorization,X-Leafy-Admin-CSRF');return c.body(null,204);}
  await next();
});
app.get('/health',async c=>{
  const check=await c.env.DB.prepare('SELECT 1 AS ok').first<{ok:number}>();
  return c.json({status:check?.ok===1?'ok':'error',environment:c.env.ENVIRONMENT});
});
app.use('/v1/*',async(c,next)=>{
  const state=await c.env.DB.prepare('SELECT mode FROM backend_control WHERE id=1').first<{mode:string}>();
  if(!state||state.mode==='importing')throw new ApiError(503,'maintenance','服务维护中，请稍后重试。',true);
  if(!['GET','HEAD','OPTIONS'].includes(c.req.method))await requireWritable(c.env.DB);
  await next();
  if(!['GET','HEAD','OPTIONS'].includes(c.req.method)&&c.res.ok)c.executionCtx.waitUntil(deliverSignals(c.env).catch(()=>console.error(JSON.stringify({event:'signal_delivery_pending',request_id:c.get('requestId')}))));
});
app.on(['GET','POST'],'/v1/auth/*',async c=>{
  await requireWritable(c.env.DB);
  return auth(c.env).handler(c.req.raw);
});
app.post('/v1/profile/bootstrap',async c=>c.json(await bootstrap(c.env,c.req.raw)));
app.delete('/v1/account',async c=>{
  const result=await deleteAccount(c.env,c.req.raw);
  c.executionCtx.waitUntil(cleanMedia(c.env).catch(()=>console.error(JSON.stringify({event:'account_file_deletion_pending',request_id:c.get('requestId')}))));
  return c.json(result);
});
app.post('/v1/session/exchange',async c=>c.json(await exchangeSession(c.env,await readJSON(c.req.raw))));
app.get('/v1/runtime/:kind',async c=>{
  const kind=c.req.param('kind');if(kind!=='semester'&&kind!=='calendar')throw new ApiError(404,'not_found','配置不存在。');
  const config=await runtimeConfiguration(c.env,new URL(c.req.url),kind==='calendar');
  const headers={'Content-Type':'application/json','ETag':config.etag,'Cache-Control':'public, max-age=60, must-revalidate'};
  return new Response(c.req.header('if-none-match')===config.etag?null:config.body,{status:c.req.header('if-none-match')===config.etag?304:200,headers});
});
app.get('/v1/campuses',async c=>{await actor(c.env,c.req.raw);return c.json(await searchCampuses(c.env,new URL(c.req.url)));});
app.get('/v1/campus/membership',async c=>c.json(await currentMembership(c.env,await actor(c.env,c.req.raw))));
app.post('/v1/campus/select',async c=>c.json(await selectCampus(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/campus/membership',async c=>c.json(await requestMembership(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/campus/change',async c=>c.json(await requestMembership(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw),true)));
app.get('/v1/catalog/:kind',async c=>c.json(await catalog(c.env,await actor(c.env,c.req.raw),c.req.param('kind'),new URL(c.req.url))));
app.put('/v1/catalog/:kind/:id/rating',async c=>{const body=await readJSON(c.req.raw);return c.json(await rate(c.env,await actor(c.env,c.req.raw),c.req.param('kind'),Number(c.req.param('id')),body.stars as number));});
app.delete('/v1/catalog/:kind/:id/rating',async c=>c.json(await rate(c.env,await actor(c.env,c.req.raw),c.req.param('kind'),Number(c.req.param('id')),null)));
app.get('/v1/timetables',async c=>c.json(await timetables(c.env,await actor(c.env,c.req.raw),new URL(c.req.url))));
app.put('/v1/timetables',async c=>c.json(await publishTimetable(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/timetables/invites',async c=>c.json(await invite(c.env,await actor(c.env,c.req.raw))));
app.post('/v1/timetables/invites/accept',async c=>c.json(await acceptInvite(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.get('/v1/timetables/members',async c=>c.json(await shareMembers(c.env,await actor(c.env,c.req.raw))));
app.delete('/v1/timetables/members/:id',async c=>c.json(await revokeShare(c.env,await actor(c.env,c.req.raw),c.req.param('id'))));
app.post('/v1/timetables/members/:id/leave',async c=>c.json(await revokeShare(c.env,await actor(c.env,c.req.raw),c.req.param('id'),true)));
app.post('/v1/timetables/stop',async c=>c.json(await stopSharing(c.env,await actor(c.env,c.req.raw))));
app.get('/v1/profile',async c=>c.json(await myProfile(c.env,c.req.raw)));
app.patch('/v1/profile',async c=>c.json(await updateProfile(c.env,c.req.raw)));
app.post('/v1/profile/email/request',async c=>c.json(await requestProfileEmail(c.env,c.req.raw)));
app.post('/v1/profile/email/verify',async c=>c.json(await verifyProfileEmail(c.env,c.req.raw)));
app.post('/v1/profile/image',async c=>c.json(await setProfileImage(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/files/upload',async c=>c.json(await upload(c.env,await actor(c.env,c.req.raw),c.req.raw)));
app.get('/v1/files/read',async c=>readFile(c.env,await actor(c.env,c.req.raw),c.req.query('bucket')??'',c.req.query('path')??'',c.req.raw));
app.get('/v1/files/download',async c=>{const claim=await verifyMediaTicket(c.env,c.req.query('ticket')??'');return readFile(c.env,claim.who,claim.bucket,claim.path,c.req.raw);});
app.post('/v1/files/attachment-download',async c=>{
  const who=await actor(c.env,c.req.raw),body=await readJSON(c.req.raw);
  const file=await c.env.DB.prepare(`SELECT a.* FROM post_attachments a JOIN posts p ON p.id=a.post_id WHERE a.id=? AND ${postAccessSQL()}`).bind(String(body.attachment_id),requireCommunity(who),who.profileId,who.profileId).first<{path:string;display_name:string;content_type:string;byte_size:number}>();
  if(!file)throw new ApiError(404,'not_found','附件不存在或无权访问。');
  return c.json({url:await signedMediaURL(c.env,who,'community-attachments',file.path),display_name:file.display_name,content_type:file.content_type,byte_size:file.byte_size,expires_in:600});
});
app.post('/v1/files/validate-images',async c=>c.json(await validateImages(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/files/validate-attachment',async c=>c.json(await validateAttachment(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/files/attach-image',async c=>c.json(await attach(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw),'image')));
app.post('/v1/files/attach-attachment',async c=>c.json(await attach(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw),'attachment')));
app.get('/v1/community/feed',async c=>c.json(await feed(c.env,await actor(c.env,c.req.raw),new URL(c.req.url))));
app.get('/v1/community/posts/:id',async c=>c.json(await postDetail(c.env,await actor(c.env,c.req.raw),c.req.param('id'))));
app.post('/v1/community/posts',async c=>c.json(await createPost(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.get('/v1/community/posts/:id/comments',async c=>c.json(await comments(c.env,await actor(c.env,c.req.raw),c.req.param('id'),new URL(c.req.url))));
app.post('/v1/community/comments',async c=>c.json(await createComment(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.delete('/v1/community/posts/:id',async c=>c.json(await deleteOwnContent(c.env,await actor(c.env,c.req.raw),c.req.param('id'))));
app.delete('/v1/community/comments/:id',async c=>c.json(await deleteOwnContent(c.env,await actor(c.env,c.req.raw),c.req.param('id'),true)));
app.put('/v1/community/posts/:id/like',async c=>c.json(await setPostReaction(c.env,await actor(c.env,c.req.raw),c.req.param('id'),'like',true)));
app.delete('/v1/community/posts/:id/like',async c=>c.json(await setPostReaction(c.env,await actor(c.env,c.req.raw),c.req.param('id'),'like',false)));
app.put('/v1/community/posts/:id/favorite',async c=>c.json(await setPostReaction(c.env,await actor(c.env,c.req.raw),c.req.param('id'),'favorite',true)));
app.delete('/v1/community/posts/:id/favorite',async c=>c.json(await setPostReaction(c.env,await actor(c.env,c.req.raw),c.req.param('id'),'favorite',false)));
app.put('/v1/community/blocks/:id',async c=>c.json(await setBlock(c.env,await actor(c.env,c.req.raw),c.req.param('id'),true)));
app.delete('/v1/community/blocks/:id',async c=>c.json(await setBlock(c.env,await actor(c.env,c.req.raw),c.req.param('id'),false)));
app.post('/v1/community/reports',async c=>c.json(await report(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.post('/v1/community/polls',async c=>c.json(await createPoll(c.env,await actor(c.env,c.req.raw),await readJSON(c.req.raw))));
app.get('/v1/community/polls/:id',async c=>c.json(await poll(c.env,await actor(c.env,c.req.raw),c.req.param('id'))));
app.put('/v1/community/polls/:id/vote',async c=>{const body=await readJSON(c.req.raw);return c.json(await vote(c.env,await actor(c.env,c.req.raw),c.req.param('id'),String(body.option_id)));});
app.post('/v1/community/polls/:id/deletion-request',async c=>{const body=await readJSON(c.req.raw);return c.json(await requestPollDeletion(c.env,await actor(c.env,c.req.raw),c.req.param('id'),body.reason));});
app.post('/v1/community/terms',async c=>c.json(await setTerms(c.env,await actor(c.env,c.req.raw),true)));
app.delete('/v1/community/terms',async c=>c.json(await setTerms(c.env,await actor(c.env,c.req.raw),false)));
app.get('/v1/notifications',async c=>c.json(await notifications(c.env,await actor(c.env,c.req.raw))));
app.post('/v1/notifications/read-all',async c=>c.json(await readNotifications(c.env,await actor(c.env,c.req.raw),null)));
app.post('/v1/notifications/:id/read',async c=>c.json(await readNotifications(c.env,await actor(c.env,c.req.raw),c.req.param('id'))));
app.get('/v1/events/:scope',async c=>{
  const who=await actor(c.env,c.req.raw),scope=c.req.param('scope');
  if(scope!=='feed'&&scope!=='notifications')throw new ApiError(404,'not_found','订阅不存在。');
  if(scope==='feed'&&!who.campusId)throw new ApiError(403,'forbidden','当前身份不能订阅校园内容。');
  if(c.req.header('upgrade')?.toLowerCase()!=='websocket')throw new ApiError(426,'upgrade_required','需要 WebSocket 连接。');
  const room=scope==='feed'?`campus:${who.campusId}`:`profile:${who.profileId}`;
  return c.env.SIGNALS.get(c.env.SIGNALS.idFromName(room)).fetch('https://signals.internal/connect',{headers:{Upgrade:'websocket','x-session-expires':String(who.sessionExpires),'x-session-id':who.sessionId,'x-profile-id':who.profileId,'x-campus-id':who.campusId??'','x-subscription-scope':scope}});
});
app.notFound(c=>c.json({error:'API route not found',errorEnvelope:{code:'not_found',message:'API route not found',retryable:false},request_id:c.get('requestId')},404));
app.onError((error,c)=>{
  if(error instanceof AuthAPIError){
    const message=error.body?.message??'Authentication failed',code=error.body?.code??'authentication_failed';
    return c.json({error:message,errorEnvelope:{code,message,retryable:error.statusCode>=500},request_id:c.get('requestId')},error.statusCode as 400);
  }
  const known=error instanceof ApiError;
  console.error(JSON.stringify({event:'api_error',request_id:c.get('requestId'),code:known?error.code:'internal_error',status:known?error.status:500}));
  return new Response(JSON.stringify({error:known?error.message:'Request failed',errorEnvelope:{code:known?error.code:'internal_error',message:known?error.message:'Request failed',retryable:known?error.retryable:true},request_id:c.get('requestId')}),{status:known?error.status:500,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Request-ID':c.get('requestId')}});
});
export default {fetch:app.fetch,scheduled};
