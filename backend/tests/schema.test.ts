import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { describe,it,expect } from 'vitest';

function database() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_business.sql',import.meta.url),'utf8'));
  db.exec("INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北京林业大学','北林','北京林业大学','qiangzhi');");
  return db;
}
describe('PostgreSQL to SQLite invariants',()=>{
  it('creates all tables with valid foreign keys',()=>{
    const db=database();
    expect(db.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    db.close();
  });
  it('preserves identity uniqueness independently of replaceable auth users',()=>{
    const db=database();
    db.exec("INSERT INTO profiles(id,edu_id,nickname,campus_id) VALUES('p1','123','甲','bjfu');");
    expect(()=>db.exec("INSERT INTO profiles(id,edu_id,nickname,campus_id) VALUES('p2','123','乙','bjfu');")).toThrow();
    expect(()=>db.exec("INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES('missing','p1','bjfu','123');")).toThrow();
    db.close();
  });
  it('preserves historical NOT VALID rows while enforcing all future writes',()=>{
    const db=database();
    db.exec("INSERT INTO profiles(id,edu_id,nickname,campus_id) VALUES('p1','123','甲','bjfu');");
    const insert="INSERT INTO posts(id,author_id,title,body,campus_id) VALUES('post1','p1','','','bjfu')";
    expect(()=>db.exec(insert)).toThrow();
    db.exec('UPDATE migration_control SET importing=1 WHERE id=1');
    db.exec(insert);
    db.exec('UPDATE migration_control SET importing=0 WHERE id=1');
    expect(()=>db.exec("UPDATE posts SET title='新标题' WHERE id='post1'")).toThrow();
    db.exec("UPDATE posts SET title='新标题',body='已修正文案' WHERE id='post1'");
    db.close();
  });
  it('keeps a single active semester and rejects invalid JSON',()=>{
    const db=database();
    const insert=db.prepare('INSERT INTO semester_runtime_configs(id,campus_id,semester_id,semester_start_date,graduate_timetable_term_code,is_active) VALUES(?,?,?,?,?,1)');
    insert.run('s1','bjfu','2026-2027-1','2026-09-07','2026-2027-1');
    expect(()=>insert.run('s2','bjfu','2026-2027-2','2027-03-01','2026-2027-2')).toThrow();
    expect(()=>db.exec("UPDATE semester_runtime_configs SET calendar_events='invalid' WHERE id='s1'")).toThrow();
    db.close();
  });
  it('keeps trigram search consistent after updates and deletes',()=>{
    const db=database();
    db.exec("INSERT INTO profiles(id,edu_id,nickname,campus_id) VALUES('p1','123','甲','bjfu'); INSERT INTO posts(id,author_id,title,body,campus_id) VALUES('post1','p1','北京林业大学','校园新消息','bjfu');");
    expect(db.prepare("SELECT rowid FROM posts_search WHERE posts_search MATCH '林业大学'").all()).toHaveLength(1);
    db.exec("UPDATE posts SET title='新的标题' WHERE id='post1'");
    expect(db.prepare("SELECT rowid FROM posts_search WHERE posts_search MATCH '林业大学'").all()).toHaveLength(0);
    db.exec("DELETE FROM posts WHERE id='post1'");
    expect(db.prepare("SELECT rowid FROM posts_search WHERE posts_search MATCH '新的标题'").all()).toHaveLength(0);
    db.close();
  });
});
