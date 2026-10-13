import { useState, useEffect } from "react";
import { useAction, useAdmin, queryClient } from "../providers/context";
import { dataProvider } from "../providers/dataProvider";
import {
  PageHeader,
  Button,
  Dialog,
  Badge,
  ErrorState,
  Loading,
  Empty,
} from "../components/ui";
import { dateLabel } from "./ResourcePages";
import { valueLabel } from "./helpers";
export function AndroidReleasesPage() {
  const { can } = useAdmin(),
    query = useAction("listAndroidReleases", { page: 0, pageSize: 100 }),
    [record, setRecord] = useState<any>(null),
    [mode, setMode] = useState("details"),
    [accepted, setAccepted] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<unknown>(null);
  const releases = query.data?.items ?? [];
  const active = releases.some((r: any) => r.status === "publishing");
  useEffect(() => {
    if (!active) return;
    const timer = window.setInterval(() => void query.refetch(), 10000);
    return () => window.clearInterval(timer);
  }, [active, query.refetch]);
  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      await dataProvider.execute(
        mode === "revoke"
          ? "revokeAndroidRelease"
          : "requestAndroidPublication",
        { id: record.id, ...(mode === "publish" ? { accepted } : {}) },
      );
      setRecord(null);
      await queryClient.invalidateQueries({ queryKey: ["admin"] });
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  return (
    <>
      <PageHeader
        title="Android 版本"
        description="下载候选包验收后，由超级管理员确认正式发布"
      >
        <Button onClick={() => void query.refetch()}>刷新状态</Button>
      </PageHeader>
      {query.error ? (
        <ErrorState error={query.error} />
      ) : query.isPending ? (
        <Loading />
      ) : releases.length ? (
        <div className="studio-card studio-table-wrap">
          <table className="studio-table">
            <thead>
              <tr>
                <th>版本</th>
                <th>状态</th>
                <th>安装包</th>
                <th>检查</th>
                <th>发布时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {releases.map((r: any) => (
                <tr key={r.id}>
                  <td>
                    {r.versionName} / {r.versionCode}
                  </td>
                  <td>
                    <Badge
                      tone={
                        r.status === "published"
                          ? "success"
                          : r.status === "failed"
                            ? "danger"
                            : "neutral"
                      }
                    >
                      {r.status === "failed" ? "发布失败" : valueLabel(r.status)}
                    </Badge>
                  </td>
                  <td>{(r.sizeBytes / 1048576).toFixed(1)} MB</td>
                  <td>{r.ciVerified ? "已通过" : "历史发行"}</td>
                  <td>{dateLabel(r.published_at)}</td>
                  <td>
                    <div className="studio-actions">
                      <Button
                        onClick={() => {
                          setRecord(r);
                          setMode("details");
                        }}
                      >
                        详情
                      </Button>
                      {["ready", "failed"].includes(r.status) && (
                        <a
                          className="studio-button"
                          href={`/api/admin/android-candidate?id=${encodeURIComponent(r.id)}`}
                        >
                          下载验收
                        </a>
                      )}
                      {can("android-releases", "edit") &&
                        ["ready", "failed", "published"].includes(r.status) && (
                          <Button
                            variant={
                              r.status === "published" ? "danger" : "primary"
                            }
                            onClick={() => {
                              setRecord(r);
                              setMode(
                                r.status === "published" ? "revoke" : "publish",
                              );
                              setAccepted(false);
                              setError(null);
                            }}
                          >
                            {r.status === "published"
                              ? "撤回"
                              : r.status === "failed"
                                ? "重试发布"
                                : "发布"}
                          </Button>
                        )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <Empty>主线版本更新并通过检查后，候选包会显示在这里。</Empty>
      )}
      <Dialog
        open={!!record}
        busy={busy}
        onClose={() => setRecord(null)}
        title={`${mode === "details" ? "版本详情" : mode === "revoke" ? "撤回版本" : "发布 Android 版本"} ${record?.versionName ?? ""}`}
      >
        <div className="studio-form">
          <p>{record?.releaseNotes}</p>
          {mode === "details" ? (
            <>
              <dl>
                {[
                  "status",
                  "versionCode",
                  "commit",
                  "sha256",
                  "certificateSha256",
                  "approvedBy",
                  "approvedAt",
                  "errorCode",
                ].map((key) => (
                  <div key={key} className="break-all">
                    <dt>{key}</dt>
                    <dd>{String(record?.[key] ?? "—")}</dd>
                  </div>
                ))}
              </dl>
              {["preparationRunUrl", "runUrl", "githubReleaseUrl"].map(
                (key) =>
                  record?.[key] && (
                    <a
                      key={key}
                      href={record[key]}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {key === "runUrl"
                        ? "查看发布任务"
                        : key === "preparationRunUrl"
                          ? "查看检查与构建"
                          : "GitHub 镜像"}
                    </a>
                  ),
              )}
            </>
          ) : mode === "publish" ? (
            <>
              <p>
                使用同一份已下载验收的 APK。发布后官网提供下载，App 提示更新。
              </p>
              <label className="flex gap-2">
                <input
                  type="checkbox"
                  checked={accepted}
                  onChange={(e) => setAccepted(e.target.checked)}
                />
                我已完成候选包验收，确认发布此版本
              </label>
            </>
          ) : (
            <p>撤回后不再推荐此版本，已安装的版本需要后续更新修复。</p>
          )}
          {error != null && <ErrorState error={error} />}
          <footer>
            <Button disabled={busy} onClick={() => setRecord(null)}>
              {mode === "details" ? "关闭" : "取消"}
            </Button>
            {mode !== "details" && (
              <Button
                variant={mode === "revoke" ? "danger" : "primary"}
                disabled={busy || (mode === "publish" && !accepted)}
                onClick={() => void submit()}
              >
                {busy
                  ? "正在提交…"
                  : mode === "revoke"
                    ? "确认撤回"
                    : "确认发布"}
              </Button>
            )}
          </footer>
        </div>
      </Dialog>
    </>
  );
}
