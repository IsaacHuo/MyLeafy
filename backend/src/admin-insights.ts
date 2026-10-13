import { calendarRecords } from "./admin-calendar";
import type { BackendEnv } from "./auth";
import { adminGuard, type AdminContext } from "./admin-auth";
import { adminList } from "./admin-data";
import { rows, type Row } from "./db";
import { integer, text, ApiError } from "./http";
import { dateBoundary, utc } from "./admin-dates";

export async function workQueue(
  env: BackendEnv,
  context: AdminContext,
  params: Row,
) {
  const definitions = [
    [
      "reports",
      "举报",
      "listModerationReports",
      { status: "all", pending: true },
    ],
    ["feedback", "反馈", "listFeedback", { status: "all", pending: true }],
    ["polls", "投票审核 / 删除", "listPolls", { status: "pending" }],
    ["posts", "帖子发布异常", "listPosts", { status: "pending_review" }],
    [
      "campus-requests",
      "学校申请",
      "listCampusRequests",
      { status: "pending" },
    ],
    ["suggestions", "名录建议", "listCatalogSuggestions", { status: "open" }],
    [
      "postgraduate-suggestions",
      "考研线索",
      "listPostgraduateSuggestions",
      { status: "open" },
    ],
  ] as const;
  return {
    generatedAt: utc(new Date()),
    groups: await Promise.all(
      definitions.map(async ([resource, label, action, filters]) => {
        const global = ["campus-requests", "postgraduate-suggestions"].includes(
          resource,
        );
        const result = await adminList(env, context, action, {
          ...params,
          ...filters,
          ...(global ? { campusID: "all", campus_id: "all" } : {}),
          page: 0,
          pageSize: 5,
          sortField: "created_at",
          sortOrder: "ASC",
        });
        return {
          resource,
          global,
          label,
          total: result.total,
          oldestAt: result.items[0]?.created_at ?? null,
          items: result.items,
          filters,
        };
      }),
    ),
  };
}
export async function operationalHealth(
  env: BackendEnv,
  context: AdminContext,
) {
  adminGuard(env, context, "super_admin");
  const [control, tasks, signals, media] = await Promise.all([
    rows(env.DB, "SELECT mode FROM backend_control WHERE id=1"),
    rows(
      env.DB,
      "SELECT r.* FROM scheduled_runs r WHERE r.started_at=(SELECT max(s.started_at) FROM scheduled_runs s WHERE s.job=r.job) ORDER BY job",
    ),
    rows(
      env.DB,
      "SELECT count(*) pending,min(created_at) oldest_at FROM change_outbox WHERE delivered_at IS NULL",
    ),
    rows(
      env.DB,
      "SELECT count(*) pending,min(created_at) oldest_at,coalesce(sum(attempts>0),0) failed FROM file_delete_jobs",
    ),
  ]);
  return {
    generatedAt: utc(new Date()),
    environment: env.ENVIRONMENT,
    commit: env.DEPLOY_COMMIT ?? null,
    mode: control[0].mode,
    tasks,
    signals: signals[0],
    media: media[0],
    requestLogs: null,
    performance: null,
  };
}
export async function diagnosticList(
  env: BackendEnv,
  context: AdminContext,
  params: Row,
) {
  adminGuard(env, context, "super_admin");
  const kind = text(params.kind ?? "tasks", 30),
    table = (
      {
        tasks: "scheduled_runs",
        signals: "change_outbox",
        media: "file_delete_jobs",
      } as Record<string, string>
    )[kind];
  if (!table) throw new ApiError(400, "bad_request", "未知诊断类型。");
  const page = integer(params.page, 0, 100000, 0),
    pageSize = integer(params.pageSize, 1, 100, 20),
    conditions: string[] = [],
    bindings: (string | number)[] = [];
  if (kind === "tasks" && params.status && params.status !== "all") {
    conditions.push("status=?");
    bindings.push(text(params.status, 30));
  }
  if (kind === "tasks" && params.job) {
    conditions.push("job=?");
    bindings.push(text(params.job, 100));
  }
  if (kind === "signals") conditions.push("delivered_at IS NULL");
  if (kind === "media" && params.failed === true) conditions.push("attempts>0");
  const date = kind === "tasks" ? "started_at" : "created_at";
  for (const [name, operator] of [
    ["start", ">="],
    ["end", "<"],
  ] as const) {
    if (params[name]) {
      conditions.push(`${date}${operator}?`);
      bindings.push(
        dateBoundary(
          params[name],
          String(params.timezone ?? "Asia/Shanghai"),
          name === "end",
        )!,
      );
    }
  }
  const where = conditions.length ? ` WHERE ${conditions.join(" AND ")}` : "";
  const [items, total] = await Promise.all([
    rows(
      env.DB,
      `SELECT * FROM ${table}${where} ORDER BY ${date} DESC LIMIT ? OFFSET ?`,
      [...bindings, pageSize, page * pageSize],
    ),
    rows(env.DB, `SELECT count(*) n FROM ${table}${where}`, bindings),
  ]);
  return {
    items: items.map((r) => ({ ...r, id: r.id ?? `${r.bucket}:${r.path}` })),
    total: total[0].n,
    page,
    pageSize,
  };
}
export async function profileActivity(
  env: BackendEnv,
  context: AdminContext,
  params: Row,
) {
  adminGuard(env, context);
  const id = text(params.id, 100),
    profile = await adminList(env, context, "listProfiles", {
      id,
      pageSize: 1,
    });
  if (!profile.items.length)
    throw new ApiError(404, "not_found", "用户不存在。");
  return {
    items: await rows(
      env.DB,
      "SELECT id,occurred_at,platform,app_version FROM app_activity WHERE profile_id=? ORDER BY occurred_at DESC LIMIT 100",
      [id],
    ),
    collection: await rows(
      env.DB,
      "SELECT started_at FROM activity_collection WHERE id=1",
    ),
  };
}
export async function dataQuality(
  env: BackendEnv,
  context: AdminContext,
  params: Row,
) {
  adminGuard(env, context, "super_admin");
  const campus = text(params.campusID ?? "all", 64),
    scoped = campus !== "all",
    checks: { key: string; label: string; sql: string }[] = [];
  for (const [table, ratings, key] of [
    ["teachers", "teacher_ratings", "teacher_id"],
    ["course_catalog", "course_ratings", "course_id"],
    ["dish_catalog", "dish_ratings", "dish_id"],
  ]) {
    checks.push({
      key: table,
      label: `${({ teachers: "教师", course_catalog: "课程", dish_catalog: "菜品" } as Record<string, string>)[table]}评分聚合`,
      sql: `SELECT t.id FROM ${table} t WHERE ${scoped ? "t.campus_id=? AND " : ""}(t.rating_count<>(SELECT count(*) FROM ${ratings} r WHERE r.${key}=t.id) OR abs(t.rating_average-coalesce((SELECT round(avg(stars),1) FROM ${ratings} r WHERE r.${key}=t.id),0))>0.051 OR ${[1, 2, 3, 4, 5].map((n) => `t.rating_${n}_count<>(SELECT count(*) FROM ${ratings} r WHERE r.${key}=t.id AND stars=${n})`).join(" OR ")})`,
    });
  }
  checks.push(
    {
      key: "post_counts",
      label: "帖子互动计数",
      sql: `SELECT p.id FROM posts p WHERE ${scoped ? "p.campus_id=? AND " : ""}(p.comment_count<>(SELECT count(*) FROM comments c WHERE c.post_id=p.id AND c.status='published') OR p.like_count<>(SELECT count(*) FROM post_likes l WHERE l.post_id=p.id))`,
    },
    {
      key: "post_media",
      label: "已发布帖子媒体完整性",
      sql: `SELECT p.id FROM posts p WHERE ${scoped ? "p.campus_id=? AND " : ""}p.status='published' AND ((SELECT count(*) FROM post_images i WHERE i.post_id=p.id)<>p.expected_image_count OR (SELECT count(*) FROM post_attachments a WHERE a.post_id=p.id)<>p.expected_attachment_count)`,
    },
    {
      key: "active_semesters",
      label: "学校当前学期唯一性",
      sql: `SELECT campus_id id FROM semester_runtime_configs WHERE ${scoped ? "campus_id=? AND " : ""}is_active=1 GROUP BY campus_id HAVING count(*)>1`,
    },
    {
      key: "orphan_comments",
      label: "评论关联完整性",
      sql: `SELECT c.id FROM comments c LEFT JOIN posts p ON p.id=c.post_id LEFT JOIN profiles u ON u.id=c.author_id WHERE ${scoped ? "p.campus_id=? AND " : ""}(p.id IS NULL OR u.id IS NULL)`,
    },
  );
  const results = await Promise.all(
    checks.map(async (check) => {
      const bind = scoped ? [campus] : [];
      const [counts, samples] = await Promise.all([
        rows(env.DB, `SELECT count(*) n FROM (${check.sql})`, bind),
        rows(env.DB, `${check.sql} LIMIT 20`, bind),
      ]);
      return {
        key: check.key,
        label: check.label,
        count: Number(counts[0].n),
        samples,
      };
    }),
  );

  const [semesters, national] = await Promise.all([
    rows(
      env.DB,
      `SELECT id,calendar_events FROM semester_runtime_configs ${scoped ? "WHERE campus_id=?" : ""} LIMIT 1001`,
      scoped ? [campus] : [],
    ),
    rows(
      env.DB,
      "SELECT id,holidays,solar_terms FROM national_calendar_runtime_configs LIMIT 1001",
    ),
  ]);
  if (semesters.length > 1000 || national.length > 1000)
    throw new ApiError(413, "quality_range_too_large", "请缩小配置检查范围。");
  const invalid: Row[] = [];
  for (const config of semesters)
    try {
      calendarRecords(config.calendar_events, "semester");
    } catch {
      invalid.push({ id: config.id });
    }
  for (const config of national)
    try {
      calendarRecords(config.holidays, "holidays");
      calendarRecords(config.solar_terms, "solar");
    } catch {
      invalid.push({ id: config.id });
    }
  results.push({
    key: "configuration_shape",
    label: "校历客户端字段与日期",
    count: invalid.length,
    samples: invalid.slice(0, 20),
  });
  const unknown = Number(
    (
      await rows(
        env.DB,
        `SELECT count(*) n FROM posts WHERE status='published' AND (expected_image_count IS NULL OR expected_attachment_count IS NULL) ${scoped ? "AND campus_id=?" : ""}`,
        scoped ? [campus] : [],
      )
    )[0].n,
  );
  return {
    generatedAt: utc(new Date()),
    checks: results.map((c) => ({
      ...c,
      unknownCount: c.key === "post_media" ? unknown : 0,
    })),
  };
}
