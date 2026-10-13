import { actor, type Actor, type BackendEnv } from "./auth";
import { atomic, actorGuard, guard, statement, rows, type Row } from "./db";
import { ApiError, readJSON, text, uuid } from "./http";
import { dateBoundary, dayRange, utc } from "./admin-dates";

export async function recordActivity(env: BackendEnv, request: Request) {
  return ingestActivity(
    env,
    await actor(env, request),
    await readJSON(request),
  );
}
export async function ingestActivity(
  env: BackendEnv,
  who: Actor,
  body: Row,
  now = new Date(),
) {
  if (body.profileID != null && uuid(body.profileID) !== who.profileId)
    throw new ApiError(409, "activity_identity_changed", "活动身份已变化。");
  if (
    !Array.isArray(body.events) ||
    body.events.length < 1 ||
    body.events.length > 100
  )
    throw new ApiError(
      422,
      "invalid_activity",
      "每批活动应包含 1–100 条事件。",
    );
  const events = body.events.map((value) => {
    const event = value as Row;
    if (!event || typeof event !== "object" || Array.isArray(event))
      throw new ApiError(422, "invalid_activity", "活动格式无效。");
    const id = uuid(event.id),
      at = Date.parse(String(event.occurredAt));
    if (
      !Number.isFinite(at) ||
      at > now.getTime() + 300000 ||
      at < now.getTime() - 7 * 86400000
    )
      throw new ApiError(422, "invalid_activity", "活动时间超出允许范围。");
    if (event.platform !== "ios" && event.platform !== "android")
      throw new ApiError(422, "invalid_activity", "平台无效。");
    return {
      id,
      at: utc(new Date(at)),
      platform: event.platform,
      version: text(event.appVersion, 64),
    };
  });
  const inserts: D1PreparedStatement[] = [];
  for (let offset = 0; offset < events.length; offset += 20) {
    const batch = events.slice(offset, offset + 20);
    const selects = batch
      .map((_, i) =>
        i === 0
          ? "SELECT ? id,? occurred_at,? platform,? app_version"
          : "SELECT ?,?,?,?",
      )
      .join(" UNION ALL ");
    inserts.push(
      statement(
        env.DB,
        `INSERT INTO app_activity(id,profile_id,campus_id,occurred_at,received_at,platform,app_version)
      SELECT v.id,p.id,?,v.occurred_at,?,v.platform,v.app_version FROM (${selects}) v JOIN profiles p ON p.id=?
      WHERE p.is_demo=0 ON CONFLICT(id) DO NOTHING`,
        [
          who.campusId ?? who.identityCampus,
          utc(now),
          ...batch.flatMap((e) => [e.id, e.at, e.platform, e.version]),
          who.profileId,
        ],
      ),
    );
  }
  await atomic(env.DB, [
    actorGuard(env.DB, who),
    guard(
      env.DB,
      "NOT EXISTS(SELECT 1 FROM app_activity WHERE id IN(SELECT value FROM json_each(?)) AND profile_id<>?)",
      [JSON.stringify(events.map((e) => e.id)), who.profileId],
    ),
    ...inserts,
  ]);
  return { accepted: events.map((e) => e.id) };
}
export async function activitySummary(
  env: BackendEnv,
  campus: string | null,
  timezone: string,
  days: number,
  now = new Date(),
) {
  const range = dayRange(days, timezone, now);
  const collection = await env.DB.prepare(
    "SELECT started_at,(SELECT min(occurred_at) FROM app_activity) first_event_at FROM activity_collection WHERE id=1",
  ).first<{ started_at: string; first_event_at: string | null }>();
  if (!collection) throw new Error("Activity collection metadata missing");
  collection.started_at = [collection.started_at, collection.first_event_at]
    .filter((value): value is string => !!value)
    .sort()[0];
  const scoped = campus && campus !== "all";
  const count = async (n: number) => {
    const window = dayRange(n, timezone, now);
    if (collection.started_at > window.until) return null;
    return Number(
      (
        await rows(
          env.DB,
          `SELECT count(DISTINCT a.profile_id) n FROM app_activity a JOIN profiles p ON p.id=a.profile_id WHERE p.is_demo=0 AND a.occurred_at>=? AND a.occurred_at<=? ${scoped ? "AND a.campus_id=?" : ""}`,
          [window.since, window.until, ...(scoped ? [campus!] : [])],
        )
      )[0].n,
    );
  };
  const daily: { bucket_date: string; users: number | null }[] = [];
  // Count in indexed UTC intervals instead of loading heartbeats into Worker memory.
  for (let offset = 0; offset < days; offset += 30) {
    const windows = Array.from(
      { length: Math.min(30, days - offset) },
      (_, i) => {
        const date = new Date(
          Date.parse(`${range.startDate}T00:00:00Z`) + (offset + i) * 86400000,
        )
          .toISOString()
          .slice(0, 10);
        return {
          date,
          start: dateBoundary(date, timezone)!,
          end: dateBoundary(date, timezone, true)!,
        };
      },
    );
    const result = await rows(
      env.DB,
      `WITH windows(day,start,finish) AS (VALUES ${windows.map(() => "(?,?,?)").join(",")})
      SELECT w.day bucket_date,count(DISTINCT CASE WHEN p.id IS NOT NULL THEN a.profile_id END) users FROM windows w
      LEFT JOIN app_activity a ON a.occurred_at>=w.start AND a.occurred_at<w.finish AND a.occurred_at<=? ${scoped ? "AND a.campus_id=?" : ""}
      LEFT JOIN profiles p ON p.id=a.profile_id AND p.is_demo=0 GROUP BY w.day ORDER BY w.day`,
      [
        ...windows.flatMap((w) => [w.date, w.start, w.end]),
        range.until,
        ...(scoped ? [campus!] : []),
      ],
    );
    daily.push(
      ...result.map((r) => ({
        bucket_date: String(r.bucket_date),
        users:
          dateBoundary(String(r.bucket_date), timezone, true)! <=
          collection.started_at
            ? null
            : Number(r.users),
      })),
    );
  }
  const [today, sevenDays, thirtyDays, inRange] = await Promise.all([
    count(1),
    count(7),
    count(30),
    count(days),
  ]);
  return {
    today,
    sevenDays,
    thirtyDays,
    inRange,
    daily,
    startedAt: collection.started_at,
    coverage: "有 Cloudflare 身份的非演示用户；免登录、旧版客户端不计入",
    supportedVersions: { ios: "3.2.5", android: "1.2.5" },
    range,
  };
}
