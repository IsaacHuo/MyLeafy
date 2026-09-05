import { auth, actor, type BackendEnv } from './auth';
import { actorGuard, atomic, decode, guard, rows, sessionGuard, statement, type Bind } from './db';
import { ApiError, readJSON, text } from './http';

export async function bootstrap(env:BackendEnv,request:Request){
  const session=await auth(env).api.getSession({headers:request.headers,query:{disableRefresh:true}});
  if(!session)throw new ApiError(401,'unauthenticated','请重新登录。');
  const body=await readJSON(request);
  let campus=body.campus_id==='bjfu'||body.campus_id==null?'bjfu':'general';
  const eduId=text(body.edu_id,128);
  // General-campus identifiers belong to the authenticated email account. BJFU
  // retains the existing school identity contract, as explicitly requested.
  if(campus==='general'&&(session.user.isAnonymous||!session.user.emailVerified||eduId.toLowerCase()!==session.user.id.toLowerCase())){
    throw new ApiError(403,'identity_mismatch','登录身份与当前账号不一致。');
  }
  // Selecting a general-campus community changes profiles.campus_id in the
  // existing schema. Follow this account's established link on future launches.
  const established=campus==='general'?await env.DB.prepare("SELECT p.id,p.campus_id FROM profile_auth_links l JOIN profiles p ON p.id=l.profile_id WHERE l.auth_user_id=? AND lower(p.edu_id)=? AND p.campus_id<>'bjfu'").bind(session.user.id,eduId.toLowerCase()).first<{id:string;campus_id:string}>():null;
  if(established)campus=established.campus_id;
  const displayName=text(body.display_name,128,false)||eduId;
  const proposedId=crypto.randomUUID();
  const now=new Date().toISOString().replace('Z','000Z');
  const results=await atomic(env.DB,[
    sessionGuard(env.DB,session.user.id,session.session.id),
    ...(established?[guard(env.DB,'EXISTS(SELECT 1 FROM profile_auth_links l JOIN profiles p ON p.id=l.profile_id WHERE l.auth_user_id=? AND p.id=? AND p.campus_id=?)',[session.user.id,established.id,campus])]:[]),
    statement(env.DB,`INSERT INTO profiles(id,campus_id,edu_id,nickname,display_name,community_campus_id,community_access_status,community_school_name,is_profile_complete)
      VALUES(?,?,?,'',?,?,?,?,0) ON CONFLICT(campus_id,edu_id) DO NOTHING`,
      [proposedId,campus,eduId,displayName,campus==='bjfu'?'bjfu':null,campus==='bjfu'?'approved':'general',campus==='bjfu'?'北京林业大学':null]),
    // Rebinding is explicit and only changes this device's link. Revocation is
    // done here, after proving the session, rather than in an unconditional trigger.
    statement(env.DB,`DELETE FROM identity_session WHERE userId=? AND id<>? AND EXISTS(SELECT 1 FROM profile_auth_links l JOIN profiles p ON p.id=l.profile_id WHERE l.auth_user_id=? AND (p.campus_id<>? OR p.edu_id<>?))`,[session.user.id,session.session.id,session.user.id,campus,eduId]),
    statement(env.DB,`INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id,last_seen_at)
      SELECT ?,id,campus_id,edu_id,? FROM profiles WHERE campus_id=? AND edu_id=?
      ON CONFLICT(auth_user_id) DO UPDATE SET profile_id=excluded.profile_id,campus_id=excluded.campus_id,edu_id=excluded.edu_id,last_seen_at=excluded.last_seen_at`,
      [session.user.id,now,campus,eduId]),
    statement(env.DB,'SELECT * FROM profiles WHERE campus_id=? AND edu_id=?',[campus,eduId]),
  ]);
  const profile=results[results.length-2].results[0];
  if(!profile)throw new Error('Committed profile missing');
  return {profile:decode('profiles',profile),is_new_user:profile.id===proposedId,is_profile_complete:profile.is_profile_complete===1};
}

export async function myProfile(env:BackendEnv,request:Request){
  const who=await actor(env,request);
  const [profile]=await rows(env.DB,'SELECT * FROM profiles WHERE id=?',[who.profileId]);
  if(!profile)throw new ApiError(404,'not_found','资料不存在。');
  return decode('profiles',profile);
}

export async function updateProfile(env:BackendEnv,request:Request){
  const who=await actor(env,request), body=await readJSON(request);
  const fields:Record<string,number>={nickname:40,display_name:128,bio:500,major:100,grade:40};
  const keys=Object.keys(body);
  if(!keys.length||keys.some(key=>!(key in fields)&&key!=='shows_edu_verification_badge'))throw new ApiError(400,'invalid_request','包含不可修改的资料字段。');
  const values:Bind[]=keys.map(key=>{
    if(key==='shows_edu_verification_badge'){
      if(typeof body[key]!=='boolean')throw new ApiError(400,'invalid_request','字段类型无效。');
      return body[key]?1:0;
    }
    return body[key]===null&&key!=='nickname'?null:text(body[key],fields[key],key==='nickname');
  });
  const now=new Date().toISOString().replace('Z','000Z');
  const result=await atomic(env.DB,[
    sessionGuard(env.DB,who.authId,who.sessionId),
    guard(env.DB,'EXISTS(SELECT 1 FROM profile_auth_links WHERE auth_user_id=? AND profile_id=?)',[who.authId,who.profileId]),
    statement(env.DB,`UPDATE profiles SET ${keys.map(key=>`${key}=?`).join(',')},updated_at=?,profile_edited_at=? WHERE id=?`,[...values,now,now,who.profileId]),
    statement(env.DB,"UPDATE profiles SET is_profile_complete=CASE WHEN length(trim(nickname))>0 THEN 1 ELSE 0 END WHERE id=? RETURNING *",[who.profileId]),
  ]);
  return decode('profiles',result[result.length-2].results[0]);
}

export async function deleteAccount(env:BackendEnv,request:Request){
  const who=await actor(env,request),now=new Date().toISOString().replace('Z','000Z');
  const ratingTables=[['teachers','teacher_ratings','teacher_id'],['course_catalog','course_ratings','course_id'],['dish_catalog','dish_ratings','dish_id']];
  await atomic(env.DB,[actorGuard(env.DB,who),
    guard(env.DB,"EXISTS(SELECT 1 FROM profiles WHERE id=? AND lower(trim(edu_id))<>'review-demo')",[who.profileId]),
    statement(env.DB,'INSERT INTO file_delete_jobs(bucket,path) SELECT bucket,path FROM file_objects WHERE owner_id=? OR post_id IN(SELECT id FROM posts WHERE author_id=?) ON CONFLICT DO NOTHING',[who.profileId,who.profileId]),
    statement(env.DB,'DELETE FROM file_objects WHERE owner_id=? OR post_id IN(SELECT id FROM posts WHERE author_id=?)',[who.profileId,who.profileId]),
    statement(env.DB,'UPDATE comments SET parent_comment_id=NULL,reply_to_comment_id=NULL,updated_at=? WHERE author_id<>? AND parent_comment_id IN(SELECT id FROM comments WHERE author_id=?)',[now,who.profileId,who.profileId]),
    statement(env.DB,"UPDATE posts SET comment_count=(SELECT count(*) FROM comments c WHERE c.post_id=posts.id AND c.status='published' AND c.author_id<>?) WHERE id IN(SELECT post_id FROM comments WHERE author_id=?)",[who.profileId,who.profileId]),
    statement(env.DB,'UPDATE posts SET like_count=(SELECT count(*) FROM post_likes l WHERE l.post_id=posts.id AND l.user_id<>?) WHERE id IN(SELECT post_id FROM post_likes WHERE user_id=?)',[who.profileId,who.profileId]),
    statement(env.DB,'UPDATE comments SET like_count=(SELECT count(*) FROM comment_likes l WHERE l.comment_id=comments.id AND l.user_id<>?) WHERE id IN(SELECT comment_id FROM comment_likes WHERE user_id=?)',[who.profileId,who.profileId]),
    statement(env.DB,'UPDATE community_poll_options SET vote_count=(SELECT count(*) FROM community_poll_votes v WHERE v.option_id=community_poll_options.id AND v.user_id<>?) WHERE id IN(SELECT option_id FROM community_poll_votes WHERE user_id=?)',[who.profileId,who.profileId]),
    statement(env.DB,'UPDATE community_polls SET total_vote_count=(SELECT count(*) FROM community_poll_votes v WHERE v.poll_id=community_polls.id AND v.user_id<>?) WHERE id IN(SELECT poll_id FROM community_poll_votes WHERE user_id=?)',[who.profileId,who.profileId]),
    ...ratingTables.map(([table,ratings,key])=>statement(env.DB,`UPDATE ${table} SET rating_count=(SELECT count(*) FROM ${ratings} r WHERE r.${key}=${table}.id AND r.user_id<>?),rating_average=coalesce((SELECT ((sum(stars)*20+count(*))/(2*count(*)))/10.0 FROM ${ratings} r WHERE r.${key}=${table}.id AND r.user_id<>?),0),${[1,2,3,4,5].map(star=>`rating_${star}_count=(SELECT count(*) FROM ${ratings} r WHERE r.${key}=${table}.id AND r.user_id<>? AND stars=${star})`).join(',')} WHERE id IN(SELECT ${key} FROM ${ratings} WHERE user_id=?)`,Array(8).fill(who.profileId))),
    ...['feedback_submissions','catalog_suggestions','postgraduate_source_suggestions'].map(table=>statement(env.DB,`DELETE FROM ${table} WHERE user_id=?`,[who.profileId])),
    statement(env.DB,'DELETE FROM private_community_create_requests WHERE actor_id=?',[who.profileId]),
    statement(env.DB,'DELETE FROM private_community_identity_link_conflicts WHERE profile_id=?',[who.profileId]),
    statement(env.DB,'DELETE FROM identity_user WHERE id IN(SELECT auth_user_id FROM profile_auth_links WHERE profile_id=?)',[who.profileId]),
    statement(env.DB,'DELETE FROM profiles WHERE id=?',[who.profileId]),
  ]);
  return {deleted:true,profile_id:who.profileId};
}

export async function requestProfileEmail(env:BackendEnv,request:Request){
  const who=await actor(env,request),body=await readJSON(request),email=text(body.email,254).toLowerCase();
  const result=await auth(env).api.requestEmailChangeEmailOTP({headers:request.headers,body:{newEmail:email}});
  if(!result.success)throw new ApiError(502,'email_delivery_failed','验证码发送失败，请重试。',true);
  await atomic(env.DB,[actorGuard(env.DB,who),statement(env.DB,'UPDATE profiles SET pending_bound_email=?,email_verification_sent_at=? WHERE id=?',[email,new Date().toISOString().replace('Z','000Z'),who.profileId])]);
  return myProfile(env,request);
}

export async function verifyProfileEmail(env:BackendEnv,request:Request){
  const who=await actor(env,request),body=await readJSON(request),email=text(body.email,254).toLowerCase(),otp=text(body.otp,8);
  if(!/^\d{8}$/.test(otp))throw new ApiError(400,'invalid_otp','验证码应为 8 位数字。');
  const pending=await env.DB.prepare('SELECT pending_bound_email FROM profiles WHERE id=?').bind(who.profileId).first<{pending_bound_email:string|null}>();
  if(pending?.pending_bound_email!==email)throw new ApiError(409,'email_request_changed','待验证邮箱已更改，请重新获取验证码。');
  await auth(env).api.changeEmailEmailOTP({headers:request.headers,body:{newEmail:email,otp}});
  return myProfile(env,request);
}
