import { afterEach, expect, it } from 'vitest';
import { hash } from 'bcryptjs';
import { LocalD1 } from './d1-local';
import type { BackendEnv } from '../src/auth';
import { adminGuard, adminLogin, adminLogout, adminMe, authenticateAdmin } from '../src/admin-auth';
import { atomic, statement, type Row } from '../src/db';
import { updateAdminAccount, upsertCatalog, upsertRuntime } from '../src/admin-write';
import { adminList } from '../src/admin-data';
import { handleAdminRequest } from '../src/admin-router';
import { overview } from '../src/admin-overview';
import { announcement, deleteRating, pinPost, resolveModerationReport, revokeAdminSession } from '../src/admin-operations';
import { moderate } from '../src/admin-write';

const databases:LocalD1[]=[];
afterEach(()=>{for(const db of databases.splice(0))db.close();});
async function fixture(role='super_admin'){
  const db=new LocalD1();databases.push(db);db.sqlite.exec("UPDATE backend_control SET mode='active'");
  const id=crypto.randomUUID();
  db.sqlite.prepare('INSERT INTO admin_accounts(id,username,password_hash,display_name,role) VALUES(?,?,?,?,?)').run(id,'test-admin',await hash('test-password-only',4),'测试管理员',role);
  const env={DB:db.binding()} as BackendEnv;
  const login=(password='test-password-only')=>new Request('https://admin.internal/login',{method:'POST',headers:{'Content-Type':'application/json','x-leafy-client-ip':'192.0.2.1'},body:JSON.stringify({username:'test-admin',password})});
  return {db,env,id,login};
}
it('migrated bcrypt admin credentials work and private fields are never returned',async()=>{
  const {env,login}=await fixture();
  const result=await adminLogin(env,login());expect(result.admin).not.toHaveProperty('password_hash');
  const context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${result.token}`}}));
  expect((await adminMe(env,context)).admin).not.toHaveProperty('password_hash');
  await adminLogout(env,context);
  await expect(authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${result.token}`}}))).rejects.toMatchObject({status:401});
});
it('login budget cannot be bypassed by concurrent attempts and limited requests do not extend failure count',async()=>{
  const {env,login,db}=await fixture();
  for(let i=0;i<5;i++)await expect(adminLogin(env,login('wrong'))).rejects.toMatchObject({status:401});
  await expect(adminLogin(env,login())).rejects.toMatchObject({status:429});
  expect(db.sqlite.prepare("SELECT count(*) AS n FROM admin_login_attempts WHERE error_code='invalid_credentials'").get()!.n).toBe(5);
});
it('viewer writes and revoked session writes are rejected before mutation',async()=>{
  const {env,login,db,id}=await fixture('viewer');
  const result=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${result.token}`}}));
  expect(()=>adminGuard(env,context,'operator')).toThrow();
  db.sqlite.prepare('UPDATE admin_sessions SET revoked_at=? WHERE admin_id=?').run(new Date().toISOString(),id);
  await expect(atomic(env.DB,[adminGuard(env,context),statement(env.DB,"UPDATE admin_accounts SET display_name='should-not-change' WHERE id=?",[id])])).rejects.toMatchObject({status:409});
  expect(db.sqlite.prepare('SELECT display_name FROM admin_accounts').get()!.display_name).toBe('测试管理员');
});
it('cannot disable the last super admin and never returns password hashes from account changes',async()=>{
  const {env,login,id}=await fixture();
  const result=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${result.token}`}}));
  await expect(updateAdminAccount(env,context,'disableAdmin',{id})).rejects.toMatchObject({status:409});
  const renamed=await updateAdminAccount(env,context,'updateAdmin',{id,displayName:'新名称'});
  expect(renamed.display_name).toBe('新名称');expect(renamed).not.toHaveProperty('password_hash');
});
it('runtime activation is atomic, permits an early semester, and catalog credit keeps PostgreSQL scale',async()=>{
  const {db,env,login}=await fixture();
  db.sqlite.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  const result=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${result.token}`}}));
  const fields={campusID:'bjfu',semesterID:'2026-2027-1',semesterStartDate:'2026-09-07',graduateTimetableTermCode:'2026-2027-1',isActive:true,calendarEvents:[]};
  await upsertRuntime(env,context,fields);
  await upsertRuntime(env,context,{...fields,semesterID:'2026-2027-2',semesterStartDate:'2027-03-01'});
  expect(db.sqlite.prepare('SELECT count(*) AS n FROM semester_runtime_configs WHERE is_active=1').get()!.n).toBe(1);
  await expect(upsertRuntime(env,context,{...fields,semesterStartDate:'2026-99-99'})).rejects.toMatchObject({status:400});
  const course=await upsertCatalog(env,context,'upsertCourse',{campusID:'bjfu',name:'课程',unit:'学院',credit:1.25});
  expect(course.credit).toBe(1.3);
  const list=await adminList(env,context,'listCourses',{page:0,pageSize:20});expect(list.items).toHaveLength(1);
});
it('private admin router preserves login/action contracts and rejects invalid routes',async()=>{
  const {env}=await fixture();
  const login=await handleAdminRequest(new Request('https://binding.internal/admin/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'test-admin',password:'test-password-only'})}),env);
  expect(login.status).toBe(200);
  const identity=await login.json() as {token:string};
  const response=await handleAdminRequest(new Request('https://binding.internal/admin/actions',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${identity.token}`},body:JSON.stringify({action:'listAdmins',params:{page:0,pageSize:20}})}),env);
  const result=await response.json() as {data:{items:Row[]};meta:{audit_logged:boolean}};
  expect(response.status).toBe(200);expect(result.data.items).toHaveLength(1);expect(result.data.items[0]).not.toHaveProperty('password_hash');expect(result.meta.audit_logged).toBe(true);
  expect((await handleAdminRequest(new Request('https://binding.internal/admin/raw-sql'),env)).status).toBe(404);
});
it('dashboard computes real scoped counts and complete day/hour buckets',async()=>{
  const {db,env,login}=await fixture();
  db.sqlite.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi'); INSERT INTO profiles(id,edu_id,nickname,campus_id,community_campus_id) VALUES('profile-dashboard','dashboard','测试','bjfu','bjfu'); INSERT INTO posts(id,author_id,title,body,status,campus_id) VALUES('post-dashboard','profile-dashboard','标题','正文','published','bjfu');");
  const signedIn=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${signedIn.token}`}}));
  const result=await overview(env,context,{days:7,campusID:'bjfu',timezone:'Asia/Shanghai'});
  expect(result.cards.profiles.total).toBe(1);expect(result.cards.posts.total).toBe(1);
  expect(result.analytics.daily).toHaveLength(7);expect(result.analytics.heatmap).toHaveLength(168);
  expect(result.analytics.daily.reduce((sum,row)=>sum+row.posts,0)).toBe(1);
  expect(result.analytics.topPosts).toHaveLength(1);
  await expect(overview(env,context,{timezone:'invalid-timezone'})).rejects.toMatchObject({status:400});
});
it('pinning and moderation preserve publication and rating aggregates',async()=>{
  const {db,env,login}=await fixture();
  const author=crypto.randomUUID(),post=crypto.randomUUID();
  db.sqlite.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  db.sqlite.prepare("INSERT INTO profiles(id,edu_id,nickname,campus_id,community_campus_id) VALUES(?,'operations','测试','bjfu','bjfu')").run(author);
  db.sqlite.prepare("INSERT INTO posts(id,author_id,title,body,status,campus_id) VALUES(?,?,'标题','正文','published','bjfu')").run(post,author);
  const signedIn=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${signedIn.token}`}}));
  const pin=await pinPost(env,context,{postID:post,scope:'global'});expect(pin.post_id).toBe(post);
  await pinPost(env,context,{postID:post,scope:'global',priority:5});
  expect(db.sqlite.prepare("SELECT count(*) n FROM community_post_pins WHERE status='active'").get()!.n).toBe(1);
  await moderate(env,context,'moderatePost',{id:post,status:'hidden'});
  expect(db.sqlite.prepare("SELECT count(*) n FROM community_post_pins WHERE status='active'").get()!.n).toBe(0);
  await expect(pinPost(env,context,{postID:post,scope:'global'})).rejects.toMatchObject({status:409});
  db.sqlite.exec("INSERT INTO teachers(id,name,unit,campus_id,rating_count,rating_average,rating_5_count) VALUES(1,'老师','学院','bjfu',1,5,1)");
  db.sqlite.prepare('INSERT INTO teacher_ratings(teacher_id,user_id,stars) VALUES(1,?,5)').run(author);
  await deleteRating(env,context,{teacherID:1,userID:author});
  expect(db.sqlite.prepare('SELECT rating_count,rating_average,rating_5_count FROM teachers WHERE id=1').get()).toEqual({rating_count:0,rating_average:0,rating_5_count:0});
});
it('report resolution is atomic and rejects repeated resolution',async()=>{
  const {db,env,login}=await fixture();
  const author=crypto.randomUUID(),post=crypto.randomUUID(),report=crypto.randomUUID();
  db.sqlite.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  db.sqlite.prepare("INSERT INTO profiles(id,edu_id,nickname,campus_id,community_campus_id) VALUES(?,'report-test','测试','bjfu','bjfu')").run(author);
  db.sqlite.prepare("INSERT INTO posts(id,author_id,title,body,status,campus_id) VALUES(?,?,'标题','正文','published','bjfu')").run(post,author);
  db.sqlite.prepare("INSERT INTO community_reports(id,reporter_id,reported_user_id,target_type,post_id,reason) VALUES(?,?,?,'post',?,'举报')").run(report,author,author,post);
  const signedIn=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${signedIn.token}`}}));
  await expect(resolveModerationReport(env,context,{id:report,status:'resolved',hideContent:true,muteUser:true,mutedUntil:'2000-01-01'})).rejects.toMatchObject({status:400});
  expect(db.sqlite.prepare('SELECT status FROM posts WHERE id=?').get(post)!.status).toBe('published');
  await resolveModerationReport(env,context,{id:report,status:'resolved',hideContent:true,muteUser:true});
  expect(db.sqlite.prepare('SELECT status FROM posts WHERE id=?').get(post)!.status).toBe('hidden');
  expect(db.sqlite.prepare('SELECT muted_until FROM profiles WHERE id=?').get(author)!.muted_until).toBeTruthy();
  await expect(resolveModerationReport(env,context,{id:report,status:'rejected'})).rejects.toMatchObject({status:409});
});
it('announcement edits validate windows and session revocation requires super admin',async()=>{
  const {env,login,db}=await fixture();
  db.sqlite.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');");
  const signedIn=await adminLogin(env,login()),context=await authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${signedIn.token}`}}));
  const item=await announcement(env,context,{title:'标题',body:'公告',status:'published'},true);
  expect(item.published_at).toBeTruthy();
  await expect(announcement(env,context,{id:item.id,expiresAt:'2000-01-01'})).rejects.toMatchObject({status:400});
  await expect(revokeAdminSession(env,{...context,role:'operator'},{id:context.tokenHash})).rejects.toMatchObject({status:403});
  await revokeAdminSession(env,context,{id:context.tokenHash});
  await expect(authenticateAdmin(env,new Request('https://admin.internal/me',{headers:{Authorization:`Bearer ${signedIn.token}`}}))).rejects.toMatchObject({status:401});
});
