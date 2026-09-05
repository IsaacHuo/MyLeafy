import { afterEach, expect, it } from 'vitest';
import { LocalD1 } from './d1-local';
import type { Actor, BackendEnv } from '../src/auth';
import { acceptInvite, invite, publishTimetable, revokeShare, shareMembers, timetables } from '../src/sharing';
import { rate, catalog } from '../src/catalog';
import { createPost, termsVersion } from '../src/community';
import { createPoll, report, requestPollDeletion, setPostReaction, vote } from '../src/interactions';

const dbs:LocalD1[]=[];
afterEach(()=>{for(const db of dbs.splice(0))db.close();});
function setup(){
  const db=new LocalD1();dbs.push(db);
  db.sqlite.exec("UPDATE backend_control SET mode='active'; INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  const user=(edu:string):Actor=>{
    const authId=crypto.randomUUID(),profileId=crypto.randomUUID(),sessionId=crypto.randomUUID(),now=Date.now();
    db.sqlite.prepare('INSERT INTO identity_user(id,name,email,emailVerified,createdAt,updatedAt,isAnonymous) VALUES(?,?,?,0,?,?,1)').run(authId,'test',`${authId}@anonymous.invalid`,now,now);
    db.sqlite.prepare('INSERT INTO identity_session(id,expiresAt,token,createdAt,updatedAt,userId) VALUES(?,?,?,?,?,?)').run(sessionId,now+3600000,crypto.randomUUID(),now,now,authId);
    db.sqlite.prepare("INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id,community_access_status) VALUES(?,'bjfu',?,'测试',1,'bjfu','approved')").run(profileId,edu);
    db.sqlite.prepare("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES(?,?,'bjfu',?)").run(authId,profileId,edu);
    db.sqlite.prepare('INSERT INTO community_terms_acceptances(user_id,terms_version) VALUES(?,?)').run(profileId,termsVersion);
    return {authId,profileId,sessionId,campusId:'bjfu',identityCampus:'bjfu',sessionExpires:now+3600000};
  };
  return {db,env:{DB:db.binding()} as BackendEnv,owner:user('owner'),viewer:user('viewer'),other:user('other')};
}
const course=()=>({id:crypto.randomUUID(),course_name:'课程',teacher:'教师',room:'101',location:'教学楼',day_of_week:1,weeks:[1,2],duration:[1,2]});
it('single-use invite grants read-only access and revocation removes access immediately',async()=>{
  const {env,owner,viewer,other}=setup(),url=new URL('https://api.invalid/v1/timetables');
  await publishTimetable(env,owner,{semester_id:'2026-2027-1',courses:[course()]});
  expect(await timetables(env,viewer,url)).toHaveLength(0);
  const token=await invite(env,owner);
  expect(token).not.toHaveProperty('code_hash');
  await acceptInvite(env,viewer,{code:token.code});
  expect(await timetables(env,viewer,url)).toHaveLength(1);
  await expect(acceptInvite(env,other,{code:token.code})).rejects.toMatchObject({status:409});
  const [member]=await shareMembers(env,owner);
  await expect(revokeShare(env,other,member.id as string)).rejects.toMatchObject({status:409});
  await revokeShare(env,owner,member.id as string);
  expect(await timetables(env,viewer,url)).toHaveLength(0);
});
it('sharing rejects non-course private data',async()=>{
  const {env,owner}=setup();
  await expect(publishTimetable(env,owner,{semester_id:'2026-2027-1',courses:[{...course(),grade:90}]})).rejects.toMatchObject({status:400});
});
it('ratings update histogram atomically and reject foreign-campus catalogs',async()=>{
  const {db,env,owner,viewer}=setup();
  db.sqlite.exec("INSERT INTO teachers(id,name,unit,campus_id,status) VALUES(1,'测试教师','学院','bjfu','published')");
  await rate(env,owner,'teachers',1,5);await rate(env,viewer,'teachers',1,3);
  let [teacher]=await catalog(env,owner,'teachers',new URL('https://api.invalid?search=测试教'));
  expect(teacher.rating_count).toBe(2);expect(teacher.rating_average).toBe(4);expect(teacher.rating_5_count).toBe(1);
  await rate(env,owner,'teachers',1,null);
  [teacher]=await catalog(env,viewer,'teachers',new URL('https://api.invalid?search=教'));
  expect(teacher.rating_count).toBe(1);expect(teacher.rating_average).toBe(3);
  await expect(rate(env,{...viewer,campusId:'elsewhere'},'teachers',1,5)).rejects.toMatchObject({status:409});
});
it('like retries create one notification; favorites do not create false feed updates; reporting does not hide',async()=>{
  const {db,env,owner,viewer}=setup(),id=crypto.randomUUID();
  await createPost(env,owner,{id,title:'帖子',body:'正文'});
  await expect(setPostReaction(env,owner,id,'like',true)).rejects.toMatchObject({status:409});
  await setPostReaction(env,viewer,id,'like',true);await setPostReaction(env,viewer,id,'like',true);
  expect(db.sqlite.prepare('SELECT like_count FROM posts').get()!.like_count).toBe(1);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM community_notifications').get()!.n).toBe(1);
  const before=db.sqlite.prepare('SELECT count(*) AS n FROM change_outbox').get()!.n;
  await setPostReaction(env,viewer,id,'favorite',true);
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM change_outbox').get()!.n).toBe(before);
  await report(env,viewer,{target_type:'post',target_id:id,reason:'其他'});
  expect(db.sqlite.prepare('SELECT status FROM posts').get()!.status).toBe('published');
});
it('poll vote replay and option changes preserve totals; deletion requires author and moderation',async()=>{
  const {db,env,owner,viewer}=setup(),id=crypto.randomUUID();
  const created=await createPoll(env,owner,{id,question:'测试问题',options:['选项甲','选项乙']});
  expect(created.status).toBe('pending_review');
  db.sqlite.prepare("UPDATE community_polls SET status='published' WHERE id=?").run(id);
  const options=db.sqlite.prepare('SELECT id FROM community_poll_options WHERE poll_id=? ORDER BY sort_order').all(id);
  await vote(env,viewer,id,options[0].id as string);await vote(env,viewer,id,options[0].id as string);
  const result=await vote(env,viewer,id,options[1].id as string);
  expect(result.total_vote_count).toBe(1);
  expect(result.options.map(option=>option.vote_count)).toEqual([0,1]);
  await expect(requestPollDeletion(env,viewer,id,'删除')).rejects.toMatchObject({status:409});
  const request=await requestPollDeletion(env,owner,id,'删除');
  expect(request.deletion_status).toBe('pending');expect(request.status).toBe('published');
});
