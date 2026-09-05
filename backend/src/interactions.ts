import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, outbox, rows, statement, type Row } from './db';
import { ApiError, text, uuid } from './http';
import { publicProfile, publishingGuard, requireCommunity, safeContent } from './community';

export async function setPostReaction(env:BackendEnv,who:Actor,id:string,kind:'like'|'favorite',enabled:boolean){
  const postId=uuid(id),campus=requireCommunity(who),table=kind==='like'?'post_likes':'post_favorites',now=new Date().toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,`EXISTS(SELECT 1 FROM posts p WHERE p.id=? AND p.campus_id=? AND p.status='published' ${kind==='like'&&enabled?'AND p.author_id<>?':''} AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id))`,[postId,campus,...(kind==='like'&&enabled?[who.profileId]:[]),who.profileId]),
    ...(enabled&&kind==='like'?[publishingGuard(env.DB,who)]:[]),
    enabled?statement(env.DB,`INSERT INTO ${table}(post_id,user_id) VALUES(?,?) ON CONFLICT DO NOTHING`,[postId,who.profileId]):statement(env.DB,`DELETE FROM ${table} WHERE post_id=? AND user_id=?`,[postId,who.profileId]),
    ...(enabled&&kind==='like'?[statement(env.DB,`INSERT INTO community_notifications(id,recipient_id,actor_id,post_id,type,title,body)
      SELECT ?,p.author_id,?,p.id,'like','有人赞了你的帖子',p.title FROM posts p WHERE p.id=? AND changes()=1 AND p.author_id<>? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=p.author_id AND b.blocked_id=?) AND NOT EXISTS(SELECT 1 FROM community_notification_settings n WHERE n.user_id=p.author_id AND n.muted_all=1)`,[crypto.randomUUID(),who.profileId,postId,who.profileId,who.profileId]),
      statement(env.DB,"INSERT INTO change_outbox(id,room) SELECT ?,'profile:'||author_id FROM posts WHERE id=?",[crypto.randomUUID(),postId])]:[]),
    kind==='like'?statement(env.DB,'UPDATE posts SET like_count=(SELECT count(*) FROM post_likes WHERE post_id=?),updated_at=? WHERE id=? RETURNING like_count',[postId,now,postId]):statement(env.DB,'SELECT like_count FROM posts WHERE id=?',[postId]),
    ...(kind==='like'?[outbox(env.DB,`campus:${campus}`)]:[]),
  ]);
  const counts=result.flatMap(r=>r.results).find(r=>'like_count' in r);
  if(!counts)throw new Error('Committed reaction count missing');
  return {post_id:postId,like_count:counts.like_count,...(kind==='like'?{viewer_has_liked:enabled}:{viewer_has_favorited:enabled})};
}

export async function deleteOwnContent(env:BackendEnv,who:Actor,id:string,comment=false){
  uuid(id);const now=new Date().toISOString().replace('Z','000Z');
  const target=comment?'comments':'posts';
  await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,`EXISTS(SELECT 1 FROM ${target} WHERE id=? AND author_id=?)`,[id,who.profileId]),
    statement(env.DB,`UPDATE ${target} SET status='deleted',updated_at=?${comment?'':",media_cleanup_hold=0,media_purge_after=coalesce(media_purge_after,?)"} WHERE id=?`,[now,...(comment?[]:[new Date(Date.now()+30*86400000).toISOString().replace('Z','000Z')]),id]),
    ...(comment?[statement(env.DB,"UPDATE posts SET comment_count=(SELECT count(*) FROM comments c WHERE c.post_id=posts.id AND c.status='published'),updated_at=? WHERE id=(SELECT post_id FROM comments WHERE id=?)",[now,id])]:[]),
    outbox(env.DB,`campus:${requireCommunity(who)}`),
  ]);return {deleted:true};
}

export async function setBlock(env:BackendEnv,who:Actor,id:string,enabled:boolean){
  uuid(id);if(id===who.profileId)throw new ApiError(400,'invalid_request','不能屏蔽自己。');
  await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,"EXISTS(SELECT 1 FROM profiles WHERE id=? AND CASE WHEN campus_id='bjfu' THEN 'bjfu' ELSE community_campus_id END=?)",[id,requireCommunity(who)]),
    enabled?statement(env.DB,'INSERT INTO community_blocks(blocker_id,blocked_id) VALUES(?,?) ON CONFLICT DO NOTHING',[who.profileId,id]):statement(env.DB,'DELETE FROM community_blocks WHERE blocker_id=? AND blocked_id=?',[who.profileId,id]),
    outbox(env.DB,`profile:${who.profileId}`),
  ]);return {blocked:enabled};
}

export async function report(env:BackendEnv,who:Actor,body:Row){
  const kind=body.target_type;if(!['post','comment','user'].includes(kind as string))throw new ApiError(400,'invalid_request','举报类型无效。');
  const reason=text(body.reason,100),detail=text(body.detail,2000,false)||null,id=uuid(body.target_id),reportId=crypto.randomUUID();
  const source=kind==='post'?'SELECT author_id AS user_id,id AS post_id,NULL AS comment_id FROM posts WHERE id=? AND campus_id=?':
    kind==='comment'?'SELECT c.author_id AS user_id,c.post_id,c.id AS comment_id FROM comments c JOIN posts p ON p.id=c.post_id WHERE c.id=? AND p.campus_id=?':
    "SELECT id AS user_id,NULL AS post_id,NULL AS comment_id FROM profiles WHERE id=? AND CASE WHEN campus_id='bjfu' THEN 'bjfu' ELSE community_campus_id END=?";
  const result=await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,`EXISTS(${source})`,[id,requireCommunity(who)]),
    statement(env.DB,`INSERT INTO community_reports(id,reporter_id,reported_user_id,target_type,post_id,comment_id,reason,detail) SELECT ?,?,user_id,?,post_id,comment_id,?,? FROM (${source}) RETURNING id`,[reportId,who.profileId,kind as string,reason,detail,id,requireCommunity(who)]),
  ]);
  // Reports do not alter publication state. Moderation is a distinct admin action.
  return {id:result[result.length-2].results[0].id,submitted:true};
}

export async function poll(env:BackendEnv,who:Actor,id:string):Promise<Row & {options:Row[]}>{
  uuid(id);
  const [record]=await rows(env.DB,"SELECT * FROM community_polls WHERE id=? AND campus_id=? AND (status='published' OR author_id=? OR EXISTS(SELECT 1 FROM community_poll_votes v WHERE v.poll_id=community_polls.id AND v.user_id=?)) AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=community_polls.author_id)",[id,requireCommunity(who),who.profileId,who.profileId,who.profileId]);
  if(!record)throw new ApiError(404,'not_found','投票不存在或不可访问。');
  const hidden=record.status!=='published'&&record.author_id!==who.profileId;
  const [options,authors,votes]=await Promise.all([rows(env.DB,'SELECT * FROM community_poll_options WHERE poll_id=? ORDER BY sort_order,id',[id]),rows(env.DB,'SELECT * FROM profiles WHERE id=?',[record.author_id as string]),rows(env.DB,'SELECT option_id FROM community_poll_votes WHERE poll_id=? AND user_id=?',[id,who.profileId])]);
  return {...decode('community_polls',record),question:hidden?'投票已下架':record.question,detail:hidden?null:record.detail,total_vote_count:hidden?0:record.total_vote_count,
    author:hidden?null:publicProfile(authors[0],who.profileId),options:hidden?[]:options,viewer_option_id:hidden?null:votes[0]?.option_id??null,
    deletion_reason:record.author_id===who.profileId?record.deletion_reason:null,deletion_review_reason:record.author_id===who.profileId?record.deletion_review_reason:null};
}
export async function createPoll(env:BackendEnv,who:Actor,body:Row){
  const question=safeContent(text(body.question,120)),detail=safeContent(text(body.detail,500,false))||null;
  if(!Array.isArray(body.options)||body.options.length<2||body.options.length>6)throw new ApiError(400,'invalid_poll','投票需要 2–6 个选项。');
  const options=body.options.map(value=>safeContent(text(value,80))),id=uuid(body.id);
  const closes=body.closes_at==null?null:new Date(text(body.closes_at,40));
  if(closes&&(!Number.isFinite(closes.getTime())||closes.getTime()<=Date.now()))throw new ApiError(400,'invalid_poll','结束时间无效。');
  await atomic(env.DB,[actorGuard(env.DB,who,true),publishingGuard(env.DB,who),
    statement(env.DB,"INSERT INTO community_polls(id,author_id,campus_id,question,detail,closes_at,status) VALUES(?,?,?,?,?,?,'pending_review')",[id,who.profileId,requireCommunity(who),question,detail,closes?.toISOString().replace('Z','000Z')??null]),
    ...options.map((option,i)=>statement(env.DB,'INSERT INTO community_poll_options(poll_id,text,sort_order) VALUES(?,?,?)',[id,option,i])),
  ]);return poll(env,who,id);
}
export async function vote(env:BackendEnv,who:Actor,id:string,optionId:string){
  uuid(id);uuid(optionId);const now=new Date().toISOString().replace('Z','000Z');
  await atomic(env.DB,[actorGuard(env.DB,who,true),publishingGuard(env.DB,who),
    guard(env.DB,"EXISTS(SELECT 1 FROM community_polls p JOIN community_poll_options o ON o.poll_id=p.id WHERE p.id=? AND p.campus_id=? AND p.status='published' AND (p.closes_at IS NULL OR p.closes_at>?) AND o.id=?)",[id,requireCommunity(who),now,optionId]),
    statement(env.DB,'INSERT INTO community_poll_votes(poll_id,option_id,user_id) VALUES(?,?,?) ON CONFLICT(poll_id,user_id) DO UPDATE SET option_id=excluded.option_id,updated_at=?',[id,optionId,who.profileId,now]),
    statement(env.DB,'UPDATE community_poll_options SET vote_count=(SELECT count(*) FROM community_poll_votes WHERE option_id=community_poll_options.id) WHERE poll_id=?',[id]),
    statement(env.DB,'UPDATE community_polls SET total_vote_count=(SELECT count(*) FROM community_poll_votes WHERE poll_id=?),updated_at=? WHERE id=?',[id,now,id]),
    outbox(env.DB,`campus:${requireCommunity(who)}`),
  ]);return poll(env,who,id);
}
export async function requestPollDeletion(env:BackendEnv,who:Actor,id:string,reason:unknown){
  uuid(id);const note=text(reason,300,false)||null;
  await atomic(env.DB,[actorGuard(env.DB,who,true),
    guard(env.DB,"EXISTS(SELECT 1 FROM community_polls WHERE id=? AND author_id=? AND status<>'deleted' AND deletion_status<>'pending')",[id,who.profileId]),
    statement(env.DB,"UPDATE community_polls SET deletion_status='pending',deletion_requested_at=?,deletion_reason=?,deletion_reviewed_at=NULL,deletion_reviewed_by=NULL,deletion_review_reason=NULL WHERE id=?",[new Date().toISOString().replace('Z','000Z'),note,id]),
  ]);return poll(env,who,id);
}
