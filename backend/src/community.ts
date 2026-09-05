import type { Actor, BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, outbox, rows, statement, type Bind, type Row } from './db';
import { ApiError, canonical, integer, text, uuid } from './http';
import { signedMediaURL } from './media-tickets';

export const termsVersion='leafy-community-eula-2026-05-08';
const rejectedWords=['约炮','裸聊','黄片','色情','卖淫','嫖娼','援交','开盒','人肉搜索','身份证号','去死','弄死','杀了你','自杀教程','炸弹','恐怖袭击','毒品','大麻','冰毒','fuck','porn','nude','kill yourself','terrorist','bomb','doxx','doxxing','drug dealer'];
export function safeContent(value:string){
  if(rejectedWords.some(word=>value.toLowerCase().includes(word)))throw new ApiError(400,'COMMUNITY_CONTENT_REJECTED','内容包含不允许发布的词语。');
  return value;
}
export function requireCommunity(who:Actor):string{
  if(!who.campusId)throw new ApiError(403,'community_unavailable','当前身份尚未获得校园社区访问权限。');
  return who.campusId;
}
export function publishingGuard(db:D1Database,who:Actor){
  return guard(db,`EXISTS(SELECT 1 FROM profiles p WHERE p.id=? AND p.is_profile_complete=1 AND length(trim(p.nickname))>0
    AND (p.muted_until IS NULL OR p.muted_until<=?) AND EXISTS(SELECT 1 FROM community_terms_acceptances t WHERE t.user_id=p.id AND t.terms_version=?))`,
    [who.profileId,new Date().toISOString().replace('Z','000Z'),termsVersion]);
}
export function postAccessSQL(alias='p'){
  return `${alias}.campus_id=? AND (${alias}.status='published' OR (${alias}.author_id=? AND ${alias}.status IN ('pending_review','hidden')))
    AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=${alias}.author_id)`;
}
function accessParams(who:Actor):Bind[]{return [requireCommunity(who),who.profileId,who.profileId];}

export function publicProfile(row:Row,viewer:string,anonymous=false):Row{
  if(row.id===viewer&&!anonymous)return decode('profiles',row);
  const allowed=['id','campus_id','nickname','display_name','avatar_path','major','grade','bio','cover_path','is_profile_complete','created_at','updated_at','shows_edu_verification_badge'];
  const result:Row=Object.fromEntries(allowed.map(key=>[key,row[key]??null]));
  // Preserve the DTO shape without exposing identifiers or notification email.
  result.edu_id='';result.bound_email=null;result.pending_bound_email=null;result.email_verification_sent_at=null;result.profile_edited_at=null;
  if(anonymous){result.nickname='匿名同学';result.display_name='匿名同学';result.avatar_path=null;result.cover_path=null;result.major=null;result.grade=null;result.bio=null;result.shows_edu_verification_badge=0;}
  return decode('profiles',result);
}

export async function hydratePosts(env:BackendEnv,who:Actor,posts:Row[]):Promise<Row[]>{
  if(!posts.length)return [];
  const ids=posts.map(p=>p.id as string), slots=ids.map(()=>'?').join(',');
  const [profiles,images,attachments,likes,favorites]=await Promise.all([
    rows(env.DB,`SELECT * FROM profiles WHERE id IN(SELECT author_id FROM posts WHERE id IN(${slots}))`,ids),
    rows(env.DB,`SELECT * FROM post_images WHERE post_id IN(${slots}) ORDER BY sort_order,id`,ids),
    rows(env.DB,`SELECT * FROM post_attachments WHERE post_id IN(${slots}) ORDER BY sort_order,id`,ids),
    rows(env.DB,`SELECT post_id FROM post_likes WHERE user_id=? AND post_id IN(${slots})`,[who.profileId,...ids]),
    rows(env.DB,`SELECT post_id FROM post_favorites WHERE user_id=? AND post_id IN(${slots})`,[who.profileId,...ids]),
  ]);
  return Promise.all(posts.map(async record=>{
    const profile=profiles.find(p=>p.id===record.author_id);
    const author=profile?publicProfile(profile,who.profileId,record.is_anonymous===1):null;
    if(author?.avatar_path)author.signed_avatar_url=await signedMediaURL(env,who,'community-images',author.avatar_path as string);
    const postImages=await Promise.all(images.filter(i=>i.post_id===record.id).map(async i=>{
      const full=await signedMediaURL(env,who,'community-images',i.path as string),thumb=await signedMediaURL(env,who,'community-images',(i.thumbnail_path??i.path) as string);
      return {...decode('post_images',i),signedURL:full,thumbnail_url:thumb,full_url:full};
    }));
    return {...decode('posts',record),author,
      images:postImages,
      attachments:attachments.filter(a=>a.post_id===record.id).map(a=>decode('post_attachments',a)),
      viewer_has_liked:likes.some(l=>l.post_id===record.id),viewer_has_favorited:favorites.some(f=>f.post_id===record.id),pin:record.pin_json?JSON.parse(record.pin_json as string):null};
  }));
}

export async function feed(env:BackendEnv,who:Actor,url:URL){
  const campus=requireCommunity(who), category=text(url.searchParams.get('category'),8,false)||null;
  const search=text(url.searchParams.get('search'),200,false);
  const limit=integer(url.searchParams.has('limit')?Number(url.searchParams.get('limit')):20,1,50);
  const hot=url.searchParams.get('mode')==='hot';
  const days=integer(url.searchParams.has('days')?Number(url.searchParams.get('days')):7,1,90);
  const now=new Date().toISOString().replace('Z','000Z');
  const cursor=url.searchParams.get('cursor');
  let after:{created_at:string;id:string}|null=null;
  if(cursor){
    try{after=JSON.parse(atob(cursor));if(!after||!Number.isFinite(Date.parse(after.created_at)))throw new Error();uuid(after.id);}
    catch{throw new ApiError(400,'invalid_cursor','分页位置无效。');}
  }
  if(hot&&after)throw new ApiError(400,'invalid_cursor','热门列表不支持此分页方式。');
  const params:Bind[]=[campus,who.profileId,category,category,search,search];
  const where=`p.campus_id=? AND p.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id)
    AND (? IS NULL OR p.category=?) AND (?='' OR instr(lower(coalesce(p.title,'')||' '||coalesce(p.body,'')||' '||coalesce(p.category,'')),lower(?))>0)`;
  const extra=hot?' AND p.created_at>=?':after?' AND (p.created_at<? OR (p.created_at=? AND p.id<?))':'';
  if(hot)params.push(new Date(Date.now()-days*86400000).toISOString().replace('Z','000Z'));
  else if(after)params.push(after.created_at,after.created_at,after.id);
  const count=hot?Math.min(limit,10):limit;
  const posts=await rows(env.DB,`SELECT p.* FROM posts p WHERE ${where}${extra} ORDER BY ${hot?'(p.like_count+p.comment_count*2) DESC,':''}p.created_at DESC,p.id DESC LIMIT ?`,[...params,count+1]);
  const hasMore=posts.length>count;posts.splice(count);
  const last=posts.at(-1);
  // Pins are an independent first-page section. They never influence the cursor.
  const pins=after||hot?[]:await rows(env.DB,`WITH ranked AS(SELECT pins.*,row_number() OVER(PARTITION BY post_id ORDER BY priority DESC,starts_at DESC,id DESC) AS n
    FROM community_post_pins pins WHERE campus_id=? AND status='active' AND starts_at<=? AND (ends_at IS NULL OR ends_at>?) AND (scope='global' OR (scope='category' AND category=?)))
    SELECT p.*,json_object('id',pins.id,'post_id',p.id,'scope',pins.scope,'category',pins.category,'priority',pins.priority,'starts_at',pins.starts_at,'ends_at',pins.ends_at,'status',pins.status,'reason',pins.reason,'created_at',pins.created_at) AS pin_json
    FROM ranked pins JOIN posts p ON p.id=pins.post_id WHERE pins.n=1 AND p.status='published' AND p.campus_id=? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id)
    ORDER BY pins.priority DESC,pins.starts_at DESC,pins.id DESC LIMIT 10`,[campus,now,now,category,campus,who.profileId]);
  const combined=[...pins,...posts.filter(p=>!pins.some(pin=>pin.id===p.id))];
  return {generated_at:now,posts:await hydratePosts(env,who,combined),next_cursor:!hot&&hasMore&&last?btoa(JSON.stringify({created_at:last.created_at,id:last.id})):null};
}

export async function postDetail(env:BackendEnv,who:Actor,id:string){
  const postId=uuid(id);
  const found=await rows(env.DB,`SELECT p.* FROM posts p WHERE p.id=? AND ${postAccessSQL()}`,[postId,...accessParams(who)]);
  if(!found.length)throw new ApiError(404,'not_found','帖子不存在或不可访问。');
  return (await hydratePosts(env,who,found))[0];
}

async function existingRequest(env:BackendEnv,who:Actor,requestId:string,kind:string,payload:Row){
  const existing=await env.DB.prepare('SELECT * FROM private_community_create_requests WHERE actor_id=? AND request_id=?').bind(who.profileId,requestId).first<Row>();
  if(!existing)return null;
  if(existing.mutation_kind!==kind||canonical(JSON.parse(existing.request_payload as string))!==canonical(payload))throw new ApiError(409,'COMMUNITY_CREATE_REQUEST_REUSED','同一请求标识不能用于不同内容。');
  const table=kind==='post'?'posts':'comments';
  const record=await env.DB.prepare(`SELECT * FROM ${table} WHERE id=? AND author_id=?`).bind(existing.resource_id,who.profileId).first<Row>();
  if(!record)throw new ApiError(409,'COMMUNITY_CREATE_REQUEST_RESULT_MISSING','原请求对应的内容已不存在。');
  return decode(table,record);
}

export async function createPost(env:BackendEnv,who:Actor,body:Row){
  const campus=requireCommunity(who),id=uuid(body.id),requestId=uuid(body.request_id??body.id);
  const title=safeContent(text(body.title,80)),content=safeContent(text(body.body,10000));
  const category=text(body.category,8,false)||null;
  if(body.is_anonymous!=null&&typeof body.is_anonymous!=='boolean')throw new ApiError(400,'invalid_request','匿名状态无效。');
  const anonymous=body.is_anonymous===true,images=integer(body.image_count,0,4,0),attachments=integer(body.attachment_count,0,2,0);
  const payload={post_id:id,title,body:content,category,is_anonymous:anonymous,image_count:images,attachment_count:attachments};
  const previous=await existingRequest(env,who,requestId,'post',payload);if(previous)return previous;
  const now=new Date().toISOString().replace('Z','000Z');
  try{
    const result=await atomic(env.DB,[actorGuard(env.DB,who,true),publishingGuard(env.DB,who),
      guard(env.DB,'(SELECT count(*) FROM posts WHERE author_id=? AND created_at>=?)<2',[who.profileId,new Date(Date.now()-3600000).toISOString().replace('Z','000Z')]),
      statement(env.DB,`INSERT INTO private_community_create_requests(actor_id,request_id,mutation_kind,resource_id,request_payload) VALUES(?,?,'post',?,?)`,[who.profileId,requestId,id,canonical(payload)]),
      statement(env.DB,`INSERT INTO posts(id,author_id,title,body,category,is_anonymous,status,campus_id,expected_image_count,expected_attachment_count,image_upload_completed_at,attachment_upload_completed_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?) RETURNING *`,[id,who.profileId,title,content,category,anonymous?1:0,images+attachments>0?'pending_review':'published',campus,images,attachments,images===0?now:null,attachments===0?now:null]),
      outbox(env.DB,`campus:${campus}`),
    ]);
    return decode('posts',result[result.length-3].results[0]);
  }catch(error){
    if(error instanceof ApiError&&error.status===409){const replay=await existingRequest(env,who,requestId,'post',payload);if(replay)return replay;}
    throw error;
  }
}

export async function createComment(env:BackendEnv,who:Actor,body:Row){
  const campus=requireCommunity(who),id=uuid(body.id),requestId=uuid(body.request_id??body.id),postId=uuid(body.post_id);
  const content=safeContent(text(body.body,2000)),parent=body.parent_comment_id==null?null:uuid(body.parent_comment_id),reply=body.reply_to_comment_id==null?null:uuid(body.reply_to_comment_id);
  if((parent===null)!==(reply===null))throw new ApiError(400,'COMMUNITY_REPLY_TARGET_INVALID','回复目标无效。');
  if(body.is_anonymous!=null&&typeof body.is_anonymous!=='boolean')throw new ApiError(400,'invalid_request','匿名状态无效。');
  const anonymous=body.is_anonymous===true;
  const payload={post_id:postId,body:content,parent_comment_id:parent,reply_to_comment_id:reply,is_anonymous:anonymous};
  const previous=await existingRequest(env,who,requestId,'comment',payload);if(previous)return previous;
  const now=new Date().toISOString().replace('Z','000Z');
  try{
    const result=await atomic(env.DB,[actorGuard(env.DB,who,true),publishingGuard(env.DB,who),
      guard(env.DB,"EXISTS(SELECT 1 FROM posts p WHERE p.id=? AND p.campus_id=? AND p.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=p.author_id))",[postId,campus,who.profileId]),
      ...(parent?[guard(env.DB,"EXISTS(SELECT 1 FROM comments p JOIN comments r ON r.id=? WHERE p.id=? AND p.post_id=? AND r.post_id=p.post_id AND p.status='published' AND r.status='published' AND p.parent_comment_id IS NULL AND (r.id=p.id OR r.parent_comment_id=p.id))",[reply,parent,postId])]:[]),
      statement(env.DB,`INSERT INTO private_community_create_requests(actor_id,request_id,mutation_kind,resource_id,request_payload) VALUES(?,?,'comment',?,?)`,[who.profileId,requestId,id,canonical(payload)]),
      statement(env.DB,`INSERT INTO comments(id,post_id,author_id,body,is_anonymous,status,parent_comment_id,reply_to_comment_id) VALUES(?,?,?,?,?,'published',?,?) RETURNING *`,[id,postId,who.profileId,content,anonymous?1:0,parent,reply]),
      statement(env.DB,"UPDATE posts SET comment_count=(SELECT count(*) FROM comments WHERE post_id=? AND status='published'),updated_at=? WHERE id=?",[postId,now,postId]),
      statement(env.DB,`INSERT INTO community_notifications(id,recipient_id,actor_id,post_id,comment_id,type,title,body)
        SELECT ?,target.id,?,?,?,'comment',?,? FROM profiles target
        WHERE target.id=(CASE WHEN ? IS NULL THEN (SELECT author_id FROM posts WHERE id=?) ELSE (SELECT author_id FROM comments WHERE id=?) END)
        AND target.id<>? AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=target.id AND b.blocked_id=?)
        AND NOT EXISTS(SELECT 1 FROM community_notification_settings s WHERE s.user_id=target.id AND s.muted_all=1)`,
        [crypto.randomUUID(),who.profileId,postId,id,parent?'有人回复了你的评论':'有人回复了你的帖子',content.slice(0,120),reply,postId,reply,who.profileId,who.profileId]),
      statement(env.DB,`INSERT INTO change_outbox(id,room) SELECT ?,'profile:'||recipient_id FROM community_notifications WHERE comment_id=?`,[crypto.randomUUID(),id]),
      outbox(env.DB,`campus:${campus}`),
    ]);
    const record=result.flatMap(r=>r.results).find(r=>r.id===id&&r.post_id===postId);
    if(!record)throw new Error('Committed comment missing');
    return decode('comments',record);
  }catch(error){
    if(error instanceof ApiError&&error.status===409){const replay=await existingRequest(env,who,requestId,'comment',payload);if(replay)return replay;}
    throw error;
  }
}

export async function comments(env:BackendEnv,who:Actor,postId:string,url:URL){
  await postDetail(env,who,postId);
  const limit=integer(url.searchParams.has('limit')?Number(url.searchParams.get('limit')):50,1,100);
  const result=await rows(env.DB,`SELECT c.* FROM comments c WHERE c.post_id=? AND c.status='published' AND NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=c.author_id) ORDER BY c.created_at,c.id LIMIT ?`,[postId,who.profileId,limit]);
  if(!result.length)return [];
  const ids=[...new Set(result.map(c=>c.author_id as string))];
  const authors=await rows(env.DB,`SELECT * FROM profiles WHERE id IN(${ids.map(()=>'?').join(',')})`,ids);
  return result.map(c=>({...decode('comments',c),author:publicProfile(authors.find(p=>p.id===c.author_id)!,who.profileId,c.is_anonymous===1)}));
}

export async function setTerms(env:BackendEnv,who:Actor,accepted:boolean){
  await atomic(env.DB,[actorGuard(env.DB,who),accepted?
    statement(env.DB,'INSERT INTO community_terms_acceptances(user_id,terms_version) VALUES(?,?) ON CONFLICT(user_id,terms_version) DO UPDATE SET accepted_at=excluded.accepted_at',[who.profileId,termsVersion]):
    statement(env.DB,'DELETE FROM community_terms_acceptances WHERE user_id=?',[who.profileId])]);
  return {accepted,terms_version:termsVersion};
}

export async function notifications(env:BackendEnv,who:Actor){
  const list=await rows(env.DB,`SELECT n.* FROM community_notifications n WHERE recipient_id=? AND dismissed_at IS NULL AND (actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM community_blocks b WHERE b.blocker_id=? AND b.blocked_id=n.actor_id)) ORDER BY created_at DESC,id DESC LIMIT 100`,[who.profileId,who.profileId]);
  return list.map(n=>decode('community_notifications',n));
}

export async function readNotifications(env:BackendEnv,who:Actor,id:string|null){
  if(id)uuid(id);
  await atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,`UPDATE community_notifications SET is_read=1 WHERE recipient_id=?${id?' AND id=?':''}`,[who.profileId,...(id?[id]:[])]),outbox(env.DB,`profile:${who.profileId}`)]);
  return {updated:true};
}
