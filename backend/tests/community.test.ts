import { afterEach, describe, expect, it } from 'vitest';
import { LocalD1 } from './d1-local';
import type { Actor, BackendEnv } from '../src/auth';
import { createPost, createComment, feed, termsVersion } from '../src/community';
import { actorGuard, atomic, statement } from '../src/db';

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
