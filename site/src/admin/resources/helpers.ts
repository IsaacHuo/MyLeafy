import type { RowActionConfig } from "./config";
export function actionConfirmation(
  resource: string,
  record: Record<string, any>,
  action: RowActionConfig,
) {
  if (resource === "posts" && action.action === "retryPostPublish") {
    return {
      summary: `重新发布：${record.title || record.id || "异常帖子"}`,
      impact: "服务端会重新校验已登记图片数量；仅完整上传的帖子才会公开。",
    };
  }
  if (resource === "ratings") {
    const target =
      record.teacher?.name ||
      record.dish?.name ||
      record.course?.name ||
      `ID ${record.teacher_id ?? record.dish_id ?? record.course_id ?? "未知"}`;
    const user = record.user?.nickname || record.user_id || "未知用户";
    const time = record.updated_at
      ? new Date(record.updated_at).toLocaleString("zh-CN")
      : "时间未知";
    return {
      summary: `评分：${target} · ${record.stars ?? "—"} 星 · 用户：${user} · ${time}`,
      impact: "删除后无法恢复，相关聚合评分会立即重新计算。",
    };
  }
  if (resource === "sessions") {
    const admin = record.admin?.display_name || record.admin_id || "未知管理员";
    const lastSeen = record.last_seen_at
      ? new Date(record.last_seen_at).toLocaleString("zh-CN")
      : "无活动记录";
    return {
      summary: `管理会话：${admin} · 最近活动 ${lastSeen}`,
      impact: "该会话会立即失效，管理员需要重新登录。",
    };
  }
  if (resource === "admins" && action.action === "disableAdmin") {
    const admin =
      record.display_name || record.username || record.id || "未知管理员";
    return {
      summary: `管理员账号：${admin}`,
      impact: "账号将无法继续登录，已有会话也应尽快撤销。",
    };
  }
  const identity =
    record.title ||
    record.name ||
    record.nickname ||
    record.display_name ||
    record.id ||
    "当前记录";
  return {
    summary: `操作对象：${identity}`,
    impact: "此操作会立即影响当前记录。",
  };
}

export function valueAt(record: Record<string, any>, path: string): any {
  return path.split(".").reduce((v, k) => v?.[k], record);
}
export function valueLabel(value: unknown): string {
  if (value == null || value === "") return "—";
  if (typeof value === "boolean") return value ? "是" : "否";
  const labels: Record<string, string> = {
    published: "已发布",
    pending: "待处理",
    pending_review: "发布异常",
    hidden: "已隐藏",
    deleted: "已删除",
    open: "未查看",
    reviewed: "已查看待处理",
    closed: "已完成",
    resolved: "已处理",
    rejected: "已驳回",
    draft: "草稿",
    archived: "已下线",
    approved: "已通过",
    ready: "待发布",
    publishing: "发布中",
    failed: "失败",
    succeeded: "成功",
    running: "运行中",
    revoked: "已撤回",
    viewer: "只读管理员",
    operator: "运营管理员",
    super_admin: "超级管理员",
    publish_failed: "自动发布失败",
    publish_exception: "发布异常",
    upload_incomplete: "上传不完整",
  };
  return labels[String(value)] ?? String(value);
}
export function initialValue(record: Record<string, any>, source: string) {
  return (
    record[source] ??
    record[source.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()] ??
    ""
  );
}
