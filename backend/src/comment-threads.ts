import type { Actor, BackendEnv } from './auth';
import { publicProfile, requireCommunity } from './community';
import { decode, rows, type Row } from './db';
import { ApiError, integer, text, uuid } from './http';
import { signedMediaURL } from './media-tickets';

export async function hydrateComments(env:BackendEnv,who:Actor,records:Row[]):Promise<Row[]>{
  const ids=[...new Set(records.flatMap(r=>[r.author_id,r.reply_to_author_id]).filter((v):v is string=>typeof v==='string'))],profiles=new Map<string,Row>();
  for(let i=0;i<ids.length;i+=80){const batch=ids.slice(i,i+80);for(const row of await rows(env.DB,`SELECT * FROM profiles WHERE id IN(${batch.map(()=>'?').join(',')})`,batch))profiles.set(String(row.id),row);}
  return Promise.all(records.map(async r=>{
    const placeholder=r.is_deleted_placeholder===1||r.is_deleted_placeholder===true;
    const authorRow=profiles.get(String(r.author_id)),replyRow=profiles.get(String(r.reply_to_author_id));
    const author=placeholder||!authorRow?null:publicProfile(authorRow,who.profileId,r.is_anonymous===1);
    const reply=replyRow&&r.reply_target_is_visible?publicProfile(replyRow,who.profileId):null;
    for(const profile of [author,reply])if(profile?.avatar_path)profile.signed_avatar_url=await signedMediaURL(env,who,'community-images',String(profile.avatar_path));
    return {...decode('comments',r),body:placeholder?'':r.body,author,reply_to_author:reply,viewer_has_liked:Boolean(r.viewer_has_liked),reply_target_is_visible:Boolean(r.reply_target_is_visible),is_deleted_placeholder:placeholder};
  }));
}

export async function commentThreads(env:BackendEnv,who:Actor,postId:string,url:URL){
  uuid(postId);
  const post=await env.DB.prepare("SELECT id FROM posts p WHERE id=? AND campus_id=? AND status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id)").bind(postId,requireCommunity(who),who.profileId).first();
  if(!post)throw new ApiError(404,'not_found','帖子不存在或不可访问。');
  const limit=integer(Number(url.searchParams.get('limit')??20),1,50),after=text(url.searchParams.get('after_created_at'),40,false)||null,afterId=text(url.searchParams.get('after_id'),36,false)||null;
  if(Boolean(after)!==Boolean(afterId))throw new ApiError(400,'invalid_cursor','评论分页位置无效。');
  if(after){if(!Number.isFinite(Date.parse(after)))throw new ApiError(400,'invalid_cursor','评论分页日期无效。');uuid(afterId);}
  // A root is retained as a blank placeholder when its visible replies survive.
  // Hidden roots remain excluded, matching the moderation boundary.
  const roots=await rows(env.DB,`SELECT c.id,c.created_at FROM comments c WHERE c.post_id=? AND c.parent_comment_id IS NULL AND c.status<>'hidden'
    AND ((c.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=c.author_id))
      OR EXISTS(SELECT 1 FROM comments reply WHERE reply.parent_comment_id=c.id AND reply.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=reply.author_id)))
    AND (? IS NULL OR c.created_at>? OR (c.created_at=? AND c.id>?)) ORDER BY c.created_at,c.id LIMIT ?`,[postId,who.profileId,who.profileId,after,after,after,afterId,limit+1]);
  const hasMore=roots.length>limit;roots.splice(limit);const last=roots.at(-1);
  if(!roots.length)return {comments:[],has_more:false,next_cursor_created_at:null,next_cursor_id:null};
  const ids=roots.map(r=>r.id as string);
  const records=await rows(env.DB,`SELECT c.*,root.id AS thread_root_id,
    (c.status='deleted' OR EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=c.author_id)) AS is_deleted_placeholder,
    CASE WHEN target.is_anonymous=0 AND target.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=target.author_id) THEN target.author_id ELSE NULL END AS reply_to_author_id,
    (c.reply_to_comment_id IS NULL OR (target.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=target.author_id))) AS reply_target_is_visible,
    EXISTS(SELECT 1 FROM comment_likes l WHERE l.comment_id=c.id AND l.user_id=?) AS viewer_has_liked
    FROM comments root JOIN comments c ON c.id=root.id OR (c.parent_comment_id=root.id AND c.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=c.author_id))
    LEFT JOIN comments target ON target.id=c.reply_to_comment_id
    WHERE root.id IN(${ids.map(()=>'?').join(',')}) ORDER BY root.created_at,root.id,CASE WHEN c.id=root.id THEN 0 ELSE 1 END,c.created_at,c.id`,[who.profileId,who.profileId,who.profileId,who.profileId,who.profileId,...ids]);
  return {comments:await hydrateComments(env,who,records),has_more:hasMore,next_cursor_created_at:last?.created_at??null,next_cursor_id:last?.id??null};
}
