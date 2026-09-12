import { afterEach, describe, expect, it } from 'vitest';
import { LocalD1 } from './d1-local';
import type { Actor, BackendEnv } from '../src/auth';
import { createPost, createComment, feed, termsVersion } from '../src/community';
import { actorGuard, atomic, statement } from '../src/db';
import { commentThreads } from '../src/comment-threads';
import { profileStats, activityPosts } from '../src/community-reads';
import { announcements, announcementRead, notificationSettings } from '../src/notices';
import { setPostReaction, toggleCommentLike } from '../src/interactions';

const databases:LocalD1[]=[];
function setup(){
  const db=new LocalD1();databases.push(db);
  const who:Actor={authId:crypto.randomUUID(),profileId:crypto.randomUUID(),campusId:'bjfu',identityCampus:'bjfu',sessionId:crypto.randomUUID(),sessionExpires:Date.now()+3600000};
  db.sqlite.exec("UPDATE backend_control SET mode='active'; INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  const now=Date.now();
  db.sqlite.prepare('INSERT INTO identity_user(id,name,email,emailVerified,createdAt,updatedAt,isAnonymous) VALUES(?,?,?,0,?,?,1)').run(who.authId,'test',`${who.authId}@anonymous.invalid`,now,now);
  db.sqlite.prepare('INSERT INTO identity_session(id,expiresAt,token,createdAt,updatedAt,userId) VALUES(?,?,?,?,?,?)').run(who.sessionId,who.sessionExpires,'test-token',now,now,who.authId);
  db.sqlite.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id,community_access_status) VALUES(?,'bjfu','123','测试',1,'bjfu','approved')").run(who.profileId);
  db.sqlite.prepare("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES(?,?,'bjfu','123')").run(who.authId,who.profileId);
  db.sqlite.prepare('INSERT INTO community_terms_acceptances(user_id,terms_version) VALUES(?,?)').run(who.profileId,termsVersion);
  return {db,who,env:{DB:db.binding()} as BackendEnv};
}
afterEach(()=>{for(const db of databases.splice(0))db.close();});
describe('community transactional authorization',()=>{
  it('profile statistics never count anonymous posts and private activity cannot be queried by another user',async()=>{
    const {env,who}=setup();
    await createPost(env,who,{id:crypto.randomUUID(),title:'公开',body:'正文'});
    await createPost(env,who,{id:crypto.randomUUID(),title:'匿名',body:'正文',is_anonymous:true});
    const stats=await profileStats(env,who,{profile_ids:[who.profileId]});
    expect(stats.profiles[0]).toMatchObject({public_post_count:1,activity_score:3,title:'初入林园'});
    expect(await activityPosts(env,who,new URL(`https://api.invalid/?kind=public&user_id=${who.profileId}`))).toHaveLength(1);
    await expect(activityPosts(env,who,new URL(`https://api.invalid/?kind=favorited&user_id=${crypto.randomUUID()}`))).rejects.toMatchObject({status:403});
  });
  it('announcement dismissals use auth identity and cannot be undone by a read request',async()=>{
    const {env,who,db}=setup(),id=crypto.randomUUID();
    db.sqlite.prepare("INSERT INTO site_announcements(id,title,body,status,published_at,created_by,campus_id) VALUES(?,'公告','正文','published','2020-01-01T00:00:00.000000Z','admin','bjfu')").run(id);
    expect(await announcements(env,who,new URL('https://api.invalid/'))).toHaveLength(1);
    await announcementRead(env,who,id,true);await announcementRead(env,who,id);
    expect(await announcements(env,who,new URL('https://api.invalid/'))).toHaveLength(0);
    expect(db.sqlite.prepare('SELECT user_id FROM site_announcement_reads').get()!.user_id).toBe(who.authId);
    await expect(notificationSettings(env,who,{muted_all:'false'})).rejects.toMatchObject({status:400});
    expect(await notificationSettings(env,who,{muted_all:true})).toMatchObject({muted_all:true});
  });
  it('reaction toggles preserve counts and comment request replay does not toggle twice',async()=>{
    const {env,who,db}=setup(),author=crypto.randomUUID(),post=crypto.randomUUID(),comment=crypto.randomUUID();
    db.sqlite.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,community_campus_id) VALUES(?,'bjfu','other-react','作者','bjfu')").run(author);
    db.sqlite.prepare("INSERT INTO posts(id,author_id,title,body,status,campus_id) VALUES(?,?,'标题','正文','published','bjfu')").run(post,author);
    db.sqlite.prepare('INSERT INTO comments(id,post_id,author_id,body) VALUES(?,?,?,?)').run(comment,post,author,'评论');
    expect(await setPostReaction(env,who,post,'like','toggle')).toMatchObject({like_count:1,viewer_has_liked:true});
    expect(await setPostReaction(env,who,post,'like','toggle')).toMatchObject({like_count:0,viewer_has_liked:false});
    const request={request_id:crypto.randomUUID()};
    expect(await toggleCommentLike(env,who,comment,request)).toMatchObject({like_count:1,viewer_has_liked:true});
    expect(await toggleCommentLike(env,who,comment,request)).toMatchObject({like_count:1,viewer_has_liked:true});
    expect(await toggleCommentLike(env,who,comment,{request_id:crypto.randomUUID()})).toMatchObject({like_count:0,viewer_has_liked:false});
    expect(db.sqlite.prepare('SELECT count(*) n FROM comment_likes').get()!.n).toBe(0);
  });
  it('paginates roots with replies intact and blanks deleted or blocked roots',async()=>{
    const {env,who,db}=setup(),post=crypto.randomUUID(),root=crypto.randomUUID(),reply=crypto.randomUUID(),next=crypto.randomUUID();
    await createPost(env,who,{id:post,title:'标题',body:'正文'});
    await createComment(env,who,{id:root,post_id:post,body:'根评论'});
    await createComment(env,who,{id:reply,post_id:post,body:'回复',parent_comment_id:root,reply_to_comment_id:root});
    await createComment(env,who,{id:next,post_id:post,body:'第二线程'});
    db.sqlite.prepare('UPDATE comments SET created_at=? WHERE id=?').run('2026-01-01T00:00:00.000001Z',root);
    db.sqlite.prepare('UPDATE comments SET created_at=? WHERE id=?').run('2026-01-02T00:00:00.000001Z',next);
    db.sqlite.prepare("UPDATE comments SET status='deleted' WHERE id=?").run(root);
    const first=await commentThreads(env,who,post,new URL('https://api.invalid/?limit=1'));
    expect(first.has_more).toBe(true);expect(first.comments).toHaveLength(2);
    expect(first.comments[0]).toMatchObject({id:root,body:'',is_deleted_placeholder:true,author:null});
    expect(first.comments[1]).toMatchObject({id:reply,reply_target_is_visible:false,reply_to_author_id:null});
    const second=await commentThreads(env,who,post,new URL(`https://api.invalid/?limit=1&after_created_at=${first.next_cursor_created_at}&after_id=${first.next_cursor_id}`));
    expect(second.comments.map(r=>r.id)).toEqual([next]);expect(second.has_more).toBe(false);
    await expect(commentThreads(env,who,post,new URL(`https://api.invalid/?after_id=${root}`))).rejects.toMatchObject({status:400});
  });
  it('creates a post idempotently, preserves counts, and rejects changed request reuse',async()=>{
    const {env,who,db}=setup(),body={id:crypto.randomUUID(),title:'标题',body:'正文'};
    const first=await createPost(env,who,body);
    expect((await createPost(env,who,body)).id).toBe(first.id);
    expect(db.sqlite.prepare('SELECT count(*) AS n FROM posts').get()!.n).toBe(1);
    await expect(createPost(env,who,{...body,body:'另一个正文'})).rejects.toMatchObject({code:'COMMUNITY_CREATE_REQUEST_REUSED'});
  });
  it('rejects expired sessions inside the write transaction',async()=>{
    const {env,who,db}=setup();
    db.sqlite.prepare('DELETE FROM identity_session WHERE id=?').run(who.sessionId);
    await expect(createPost(env,who,{id:crypto.randomUUID(),title:'标题',body:'正文'})).rejects.toMatchObject({status:409});
    expect(db.sqlite.prepare('SELECT count(*) AS n FROM posts').get()!.n).toBe(0);
  });
  it('maintenance prevents writes even if checked before the mode changed',async()=>{
    const {env,who,db}=setup();db.sqlite.exec("UPDATE backend_control SET mode='read_only'");
    await expect(atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,"UPDATE profiles SET nickname='changed' WHERE id=?",[who.profileId])])).rejects.toMatchObject({status:409});
    expect(db.sqlite.prepare('SELECT nickname FROM profiles').get()!.nickname).toBe('测试');
  });
  it('comment replay does not increment count again and invalid reply targets roll back',async()=>{
    const {env,who,db}=setup(),postId=crypto.randomUUID();
    await createPost(env,who,{id:postId,title:'标题',body:'正文'});
    const body={id:crypto.randomUUID(),post_id:postId,body:'回复'};
    await createComment(env,who,body);await createComment(env,who,body);
    expect(db.sqlite.prepare('SELECT comment_count FROM posts').get()!.comment_count).toBe(1);
    await expect(createComment(env,who,{...body,id:crypto.randomUUID(),parent_comment_id:crypto.randomUUID(),reply_to_comment_id:crypto.randomUUID()})).rejects.toMatchObject({status:409});
    expect(db.sqlite.prepare('SELECT count(*) AS n FROM comments').get()!.n).toBe(1);
  });
  it('feed ignores a caller-provided campus and filters blocked authors',async()=>{
    const {env,who,db}=setup();await createPost(env,who,{id:crypto.randomUUID(),title:'标题',body:'正文'});
    expect((await feed(env,who,new URL('https://api.invalid/v1/community/feed?campus_id=other'))).posts).toHaveLength(1);
    const other=crypto.randomUUID();db.sqlite.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname) VALUES(?,'bjfu','456','其他人')").run(other);
    db.sqlite.prepare('INSERT INTO community_blocks(blocker_id,blocked_id) VALUES(?,?)').run(other,who.profileId);
    expect((await feed(env,{...who,profileId:other},new URL('https://api.invalid/v1/community/feed'))).posts).toHaveLength(0);
  });
});
