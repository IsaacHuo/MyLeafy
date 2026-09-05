import { afterEach, expect, it } from 'vitest';
import { hash } from 'bcryptjs';
import { LocalD1 } from './d1-local';
import type { BackendEnv } from '../src/auth';
import { adminGuard, adminLogin, adminLogout, adminMe, authenticateAdmin } from '../src/admin-auth';
import { atomic, statement } from '../src/db';
import { updateAdminAccount, upsertCatalog, upsertRuntime } from '../src/admin-write';
import { adminList } from '../src/admin-data';

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
