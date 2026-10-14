import { afterEach, expect, it, vi } from "vitest";
vi.mock('../src/signals', () => ({ ChangeSignals: class {} }));
vi.mock('../src/admin-entrypoint', () => ({ AdminAPI: class {} }));
import { LocalD1 } from "./d1-local";
import type { Actor, BackendEnv } from "../src/auth";
import type { AdminContext } from "../src/admin-auth";
import { dateBoundary, utc } from "../src/admin-dates";
import { adminList } from "../src/admin-data";
import {
  dataQuality,
  operationalHealth,
  diagnosticList,
  workQueue,
} from "../src/admin-insights";
import { deleteRating } from "../src/admin-operations";
import { overview } from "../src/admin-overview";
import { app } from "../src/index";
const databases: LocalD1[] = [];
afterEach(() => databases.splice(0).forEach((db) => db.close()));
function fixture() {
  const db = new LocalD1();
  databases.push(db);
  const now = Date.now(),
    who: Actor = {
      authId: crypto.randomUUID(),
      profileId: crypto.randomUUID(),
      campusId: "bjfu",
      identityCampus: "bjfu",
      sessionId: crypto.randomUUID(),
      sessionExpires: now + 3600000,
    };
  db.sqlite.exec(
    "UPDATE backend_control SET mode='active'; INSERT INTO campuses(id,display_name,short_name,normalized_name,connector_kind) VALUES('bjfu','北林','北林','北林','qiangzhi');",
  );
  db.sqlite
    .prepare(
      "INSERT INTO identity_user(id,name,email,emailVerified,createdAt,updatedAt,isAnonymous) VALUES(?,?,?,0,?,?,1)",
    )
    .run(who.authId, "test", `${who.authId}@anonymous.invalid`, now, now);
  db.sqlite
    .prepare(
      "INSERT INTO identity_session(id,expiresAt,token,createdAt,updatedAt,userId) VALUES(?,?,?,?,?,?)",
    )
    .run(who.sessionId, who.sessionExpires, "test-token", now, now, who.authId);
  db.sqlite
    .prepare(
      "INSERT INTO profiles(id,campus_id,edu_id,nickname,is_profile_complete,community_campus_id) VALUES(?,'bjfu','studio-test','测试',1,'bjfu')",
    )
    .run(who.profileId);
  db.sqlite
    .prepare(
      "INSERT INTO profile_auth_links(auth_user_id,profile_id,campus_id,edu_id) VALUES(?,?,'bjfu','studio-test')",
    )
    .run(who.authId, who.profileId);
  const admin = crypto.randomUUID(),
    token = "f".repeat(64);
  db.sqlite
    .prepare(
      "INSERT INTO admin_accounts(id,username,password_hash,display_name,role) VALUES(?,'test','test','test','super_admin')",
    )
    .run(admin);
  db.sqlite
    .prepare(
      "INSERT INTO admin_sessions(token_hash,admin_id,expires_at) VALUES(?,?,?)",
    )
    .run(token, admin, utc(new Date(now + 3600000)));
  const context = {
    id: admin,
    role: "super_admin",
    tokenHash: token,
    expiresAt: utc(new Date(now + 3600000)),
    requestId: "test",
    userAgent: null,
    ip: "192.0.2.1",
  } as AdminContext;
  return {
    db,
    who,
    env: { DB: db.binding(), ENVIRONMENT: "staging" } as BackendEnv,
    context,
  };
}
const event = (at = new Date()) => ({
  id: crypto.randomUUID(),
  occurredAt: at.toISOString(),
  platform: "ios",
  appVersion: "3.2.5",
});
it("removed telemetry cannot ingest events and business overview still works", async () => {
  const { db, env, context } = fixture();
  const response = await app.request('/v1/activity', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }, env);
  expect(response.status).toBe(404);
  const result = await overview(env, context, { days: 7 });
  expect(result.summary.operations).toMatchObject({ totalProfiles: 1, completeProfiles: 1 });
  expect(result.summary.operations).not.toHaveProperty('activity');
  expect(result.analyticsMeta.moderationStartedAt).toBe(db.sqlite.prepare('SELECT started_at FROM moderation_collection').get()!.started_at);
});
it("natural days use IANA rules across both DST transitions and validate calendar dates", () => {
  expect(dateBoundary("2026-03-08", "America/New_York")).toBe(
    "2026-03-08T05:00:00.000000Z",
  );
  expect(dateBoundary("2026-03-08", "America/New_York", true)).toBe(
    "2026-03-09T04:00:00.000000Z",
  );
  expect(dateBoundary("2026-11-01", "America/New_York", true)).toBe(
    "2026-11-02T05:00:00.000000Z",
  );
  expect(dateBoundary("2026-10-13", "Asia/Shanghai")).toBe(
    "2026-10-12T16:00:00.000000Z",
  );
  expect(() => dateBoundary("2026-02-30", "Asia/Shanghai")).toThrow();
});
it("feedback type, audit action, session validity and rating filters change result sets", async () => {
  const { db, env, context, who } = fixture();
  db.sqlite
    .prepare(
      "INSERT INTO feedback_submissions(id,user_id,campus_id,issue_type,body) VALUES(?,?,'bjfu','bug','问题')",
    )
    .run(crypto.randomUUID(), who.profileId);
  expect(
    (await adminList(env, context, "listFeedback", { issueType: "bug" })).total,
  ).toBe(1);
  expect(
    (await adminList(env, context, "listFeedback", { issueType: "other" }))
      .total,
  ).toBe(0);
  expect(
    (await adminList(env, context, "listAdminSessions", { status: "active" }))
      .total,
  ).toBe(1);
  expect(
    (await adminList(env, context, "listAdminSessions", { status: "revoked" }))
      .total,
  ).toBe(0);
  db.sqlite
    .prepare(
      "INSERT INTO admin_audit_logs(admin_id,action,target_type) VALUES(?,'testAction','test')",
    )
    .run(context.id);
  expect(
    (await adminList(env, context, "listAuditLogs", { action: "testAction" }))
      .total,
  ).toBe(1);
  expect(
    (await adminList(env, context, "listAuditLogs", { action: "other" })).total,
  ).toBe(0);
  db.sqlite.exec(
    "INSERT INTO course_catalog(id,name,unit,category,campus_id) VALUES(42,'课程','学院','必修','bjfu')",
  );
  db.sqlite
    .prepare(
      "INSERT INTO course_ratings(course_id,user_id,stars) VALUES(42,?,4)",
    )
    .run(who.profileId);
  const matched = await adminList(env, context, "listCourseRatings", {
    courseID: 42,
    stars: 4,
  });
  expect(matched.total).toBe(1);
  expect(matched.items[0].course).toMatchObject({ name: "课程" });
  expect(
    (await adminList(env, context, "listCourseRatings", { courseID: 43 }))
      .total,
  ).toBe(0);
  expect(
    (await adminList(env, context, "listCourseRatings", { stars: 2 })).total,
  ).toBe(0);
  await deleteRating(
    env,
    context,
    { courseID: 42, userID: who.profileId },
    "course",
  );
  expect((await adminList(env, context, "listCourseRatings", {})).total).toBe(
    0,
  );
});
it("diagnostics reject lower roles and show actual queues without fabricating logs", async () => {
  const { db, env, context } = fixture();
  await expect(
    operationalHealth(env, { ...context, role: "operator" }),
  ).rejects.toMatchObject({ status: 403 });
  await expect(
    dataQuality(env, { ...context, role: "viewer" }, {}),
  ).rejects.toMatchObject({ status: 403 });
  db.sqlite.exec(
    "INSERT INTO scheduled_runs(id,job,started_at,status,error_code) VALUES('failed','media','2026-10-13T00:00:00Z','failed','job_failed'); INSERT INTO change_outbox(id,room) VALUES('pending','bjfu'); INSERT INTO file_delete_jobs(bucket,path,attempts,last_error_code) VALUES('files','failed',2,'file_delete_failed')",
  );
  const health = await operationalHealth(env, context);
  expect(health.requestLogs).toBeNull();
  expect(health.signals.pending).toBe(1);
  expect(health.media.failed).toBe(1);
  expect(
    (await diagnosticList(env, context, { kind: "tasks", status: "failed" }))
      .total,
  ).toBe(1);
  expect(
    (await diagnosticList(env, context, { kind: "tasks", status: "succeeded" }))
      .total,
  ).toBe(0);
  expect((await dataQuality(env, context, {})).checks.length).toBe(8);
  expect((await workQueue(env, context, {})).groups.length).toBe(7);
});
it("school selection preserves global school approval work and its drilldown scope", async () => {
  const { db, env, context, who } = fixture();
  db.sqlite
    .prepare(
      "INSERT INTO campus_membership_requests(id,requester_profile_id,school_name,normalized_school_name) VALUES(?,?,?,?)",
    )
    .run(crypto.randomUUID(), who.profileId, "New school", "new school");
  const group = (
    await workQueue(env, context, { campusID: "bjfu" })
  ).groups.find((g) => g.resource === "campus-requests")!;
  expect(group.global).toBe(true);
  expect(group.total).toBe(1);
  expect(group.items).toHaveLength(1);
});
it("counts repeated hide transitions without confusing current hidden inventory with actions", async () => {
  const { env, who, db, context } = fixture();
  const post = crypto.randomUUID();
  db.sqlite
    .prepare(
      "INSERT INTO posts(id,author_id,title,body,status,campus_id) VALUES(?,?,'测试','正文','published','bjfu')",
    )
    .run(post, who.profileId);
  db.sqlite
    .prepare(
      "UPDATE posts SET status='hidden',moderated_by=?,moderated_at=? WHERE id=?",
    )
    .run(context.id, utc(new Date()), post);
  db.sqlite.prepare("UPDATE posts SET status='published' WHERE id=?").run(post);
  db.sqlite.prepare("UPDATE posts SET status='hidden' WHERE id=?").run(post);
  expect(
    db.sqlite
      .prepare("SELECT count(*) n FROM moderation_events WHERE target_id=?")
      .get(post)!.n,
  ).toBe(2);
  expect(
    db.sqlite
      .prepare("SELECT count(*) n FROM posts WHERE status='hidden'")
      .get()!.n,
  ).toBe(1);
});
it("publication exceptions can be hidden but incomplete media cannot be restored", async () => {
  const { env, who, db, context } = fixture();
  const id = crypto.randomUUID();
  db.sqlite
    .prepare(
      "INSERT INTO posts(id,author_id,title,body,status,campus_id,expected_image_count,expected_attachment_count) VALUES(?,?,'未完成','内容','pending_review','bjfu',1,0)",
    )
    .run(id, who.profileId);
  const { moderate } = await import("../src/admin-write");
  await moderate(env, context, "moderatePost", { id, status: "hidden" });
  expect(
    db.sqlite.prepare("SELECT status FROM posts WHERE id=?").get(id)!.status,
  ).toBe("hidden");
  await expect(
    moderate(env, context, "moderatePost", { id, status: "published" }),
  ).rejects.toMatchObject({ status: 409 });
  expect(
    db.sqlite.prepare("SELECT status FROM posts WHERE id=?").get(id)!.status,
  ).toBe("hidden");
});
