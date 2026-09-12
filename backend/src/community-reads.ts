import type { Actor, BackendEnv } from './auth';
import { hydratePosts, postAccessSQL, publicProfile, requireCommunity, termsVersion } from './community';
import { hydrateComments } from './comment-threads';
import { poll } from './interactions';
import { rows, type Bind, type Row } from './db';
import { ApiError, integer, text, uuid } from './http';
import { signedMediaURL } from './media-tickets';

export async function profileWithMedia(env:BackendEnv,who:Actor,row:Row){
  const profile=publicProfile(row,who.profileId);
  for(const [path,url]of [['avatar_path','signed_avatar_url'],['cover_path','signed_cover_url']])if(profile[path])profile[url]=await signedMediaURL(env,who,'community-images',String(profile[path]));
  return profile;
}
export async function profileDetail(env:BackendEnv,who:Actor,id:string){
  uuid(id);
  const record=(await rows(env.DB,"SELECT p.* FROM profiles p WHERE p.id=? AND (p.id=? OR (CASE WHEN p.campus_id='bjfu' THEN 'bjfu' ELSE p.community_campus_id END=? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.id)))",[id,who.profileId,requireCommunity(who),who.profileId]))[0];
  if(!record)throw new ApiError(404,'not_found','资料不存在或不可访问。');
  return profileWithMedia(env,who,record);
}
export async function profileStats(env:BackendEnv,who:Actor,body:Row){
  if(!Array.isArray(body.profile_ids)||body.profile_ids.length>80)throw new ApiError(400,'bad_request','一次最多读取 80 份资料。');
  const ids=[...new Set(body.profile_ids.map(uuid))];if(!ids.length)return {profiles:[]};
  const data=await rows(env.DB,`SELECT u.id AS profile_id,count(p.id) AS public_post_count,coalesce(sum((SELECT count(*) FROM post_likes l WHERE l.post_id=p.id)),0) AS received_like_count,min(p.created_at) AS first_post_at,max(p.created_at) AS latest_post_at
    FROM profiles u LEFT JOIN posts p ON p.author_id=u.id AND p.status='published' AND p.is_anonymous=0 AND p.campus_id=?
    WHERE u.id IN(${ids.map(()=>'?').join(',')}) AND CASE WHEN u.campus_id='bjfu' THEN 'bjfu' ELSE u.community_campus_id END=? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=u.id) GROUP BY u.id`,[requireCommunity(who),...ids,requireCommunity(who),who.profileId]);
  return {generated_at:new Date().toISOString(),profiles:data.map(r=>{const score=Number(r.public_post_count)*3+Number(r.received_like_count);return {...r,activity_score:score,title:score>=150?'山水知己':score>=60?'松下常客':score>=20?'绿野熟人':score>=5?'林下伙伴':'初入林园'};})};
}
export async function activityPosts(env:BackendEnv,who:Actor,url:URL){
  const kind=text(url.searchParams.get('kind')??'authored',20),owner=url.searchParams.get('user_id')?uuid(url.searchParams.get('user_id')):who.profileId;
  if(!['authored','public','liked','favorited'].includes(kind))throw new ApiError(400,'bad_request','动态类型无效。');
  if(kind!=='public'&&owner!==who.profileId)throw new ApiError(403,'forbidden','不能读取其他用户的私人动态。');
  const limit=integer(Number(url.searchParams.get('limit')??50),1,80),bind:Bind[]=[requireCommunity(who),who.profileId,who.profileId];
  let filter:string;
  if(kind==='authored'||kind==='public'){filter='p.author_id=?';bind.push(owner);if(kind==='public')filter+=" AND p.status='published' AND p.is_anonymous=0";}
  else{filter=`EXISTS(SELECT 1 FROM ${kind==='liked'?'post_likes':'post_favorites'} r WHERE r.post_id=p.id AND r.user_id=?)`;bind.push(who.profileId);}
  return hydratePosts(env,who,await rows(env.DB,`SELECT p.* FROM posts p WHERE ${postAccessSQL()} AND ${filter} ORDER BY p.created_at DESC,p.id DESC LIMIT ?`,[...bind,limit]));
}
export async function activityComments(env:BackendEnv,who:Actor,url:URL){
  const limit=integer(Number(url.searchParams.get('limit')??50),1,80);
  return hydrateComments(env,who,await rows(env.DB,`SELECT c.*,coalesce(c.parent_comment_id,c.id) AS thread_root_id,p.title AS post_title,EXISTS(SELECT 1 FROM comment_likes l WHERE l.comment_id=c.id AND l.user_id=?) AS viewer_has_liked FROM comments c JOIN posts p ON p.id=c.post_id WHERE c.author_id=? AND c.status='published' AND ${postAccessSQL()} ORDER BY c.created_at DESC,c.id DESC LIMIT ?`,[who.profileId,who.profileId,requireCommunity(who),who.profileId,who.profileId,limit]));
}
export async function polls(env:BackendEnv,who:Actor,url:URL){
  const kind=text(url.searchParams.get('kind')??'feed',20),limit=integer(Number(url.searchParams.get('limit')??20),1,50);
  if(!['feed','authored','voted'].includes(kind))throw new ApiError(400,'bad_request','投票列表类型无效。');
  const filter=kind==='feed'?"p.status='published'":kind==='authored'?'p.author_id=?':'EXISTS(SELECT 1 FROM community_poll_votes v WHERE v.poll_id=p.id AND v.user_id=?)';
  const found=await rows(env.DB,`SELECT p.id FROM community_polls p WHERE p.campus_id=? AND ${filter} AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id) ORDER BY p.created_at DESC,p.id DESC LIMIT ?`,[requireCommunity(who),...(kind==='feed'?[]:[who.profileId]),who.profileId,limit]);
  return Promise.all(found.map(r=>poll(env,who,String(r.id))));
}
export async function getTerms(env:BackendEnv,who:Actor){
  const row=await env.DB.prepare('SELECT 1 FROM community_terms_acceptances WHERE user_id=? AND terms_version=?').bind(who.profileId,termsVersion).first();
  return {accepted:Boolean(row),terms_version:termsVersion};
}
