import { useState } from "react";
import { Link } from "react-router-dom";
import { useAction } from "../providers/context";
import {
  PageHeader,
  Button,
  Badge,
  ErrorState,
  Loading,
  Dialog,
  Empty,
} from "../components/ui";
import { listLink } from "../dashboard/Dashboard";
import { dateLabel } from "./ResourcePages";
import { valueLabel } from "./helpers";
export function WorkQueuePage() {
  const query = useAction("workQueue");
  return (
    <>
      <PageHeader
        title="待办工作台"
        description="跨资源统一处理入口，先处理等待时间最长的记录"
      >
        <Button onClick={() => void query.refetch()}>刷新</Button>
      </PageHeader>
      {query.error ? (
        <ErrorState error={query.error} />
      ) : query.isPending ? (
        <Loading />
      ) : (
        <div className="studio-diagnostic">
          {query.data?.groups.map((group: any) => (
            <section className="studio-card" key={group.resource}>
              <div className="studio-card-header">
                <h2>
                  {group.label} <Badge>{group.total}</Badge>
                </h2>
                <Link
                  className="studio-button"
                  to={listLink(group.resource, group.filters)}
                >
                  查看全部
                </Link>
              </div>
              <div className="studio-queue-items">
                {group.items.length ? (
                  group.items.map((r: any) => (
                    <Link key={r.id} to={`/${group.resource}/${r.id}`}>
                      <span>
                        {r.title ??
                          r.question ??
                          r.name ??
                          r.school_name ??
                          r.reason ??
                          r.body ??
                          r.id}
                      </span>
                      <small>{dateLabel(r.created_at)}</small>
                    </Link>
                  ))
                ) : (
                  <Empty>已处理完当前队列</Empty>
                )}
              </div>
            </section>
          ))}
        </div>
      )}
    </>
  );
}
export function OperationsPage() {
  const health = useAction("operationalHealth"),
    [kind, setKind] = useState("tasks"),
    [status, setStatus] = useState("all"),
    [failed, setFailed] = useState(false),
    [page, setPage] = useState(0),
    [job, setJob] = useState(""),
    [start, setStart] = useState(""),
    [end, setEnd] = useState(""),
    [selected, setSelected] = useState<any>(null);
  const list = useAction("diagnosticList", {
    kind,
    status,
    failed,
    page,
    pageSize: 20,
    job,
    start,
    end,
    timezone: "Asia/Shanghai",
  });
  return (
    <>
      <PageHeader title="运行诊断" description="只读查看任务执行与队列状态">
        <Button
          onClick={() => {
            void health.refetch();
            void list.refetch();
          }}
        >
          刷新
        </Button>
      </PageHeader>
      {health.error ? (
        <ErrorState error={health.error} />
      ) : health.isPending ? (
        <Loading />
      ) : (
        <div className="studio-grid">
          {[
            ["运行环境", health.data?.environment],
            ["服务模式", health.data?.mode],
            ["通知积压", health.data?.signals.pending],
            ["媒体删除", health.data?.media.pending],
          ].map(([label, value]) => (
            <div className="studio-card studio-metric" key={label}>
              <small>{label}</small>
              <strong>{String(value ?? "未采集")}</strong>
            </div>
          ))}
        </div>
      )}
      <p className="mb-4 text-xs">
        部署提交：{health.data?.commit ?? "未采集"} · 请求日志 /
        性能测量：未采集 · 生成于 {dateLabel(health.data?.generatedAt)}
      </p>
      <div className="studio-tabs">
        {[
          ["tasks", "定时任务"],
          ["signals", "通知积压"],
          ["media", "媒体清理"],
        ].map(([id, label]) => (
          <button
            className={kind === id ? "active" : ""}
            key={id}
            onClick={() => {
              setKind(id);
              setPage(0);
              setSelected(null);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="studio-card">
        <div className="studio-toolbar">
          <div className="studio-filters">
            {kind === "tasks" && (
              <>
                <label>
                  运行状态
                  <select
                    value={status}
                    onChange={(e) => {
                      setStatus(e.target.value);
                      setPage(0);
                    }}
                  >
                    {["all", "running", "succeeded", "failed"].map((s) => (
                      <option key={s} value={s}>
                        {s === "all" ? "全部" : valueLabel(s)}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  任务
                  <input
                    value={job}
                    onChange={(e) => {
                      setJob(e.target.value);
                      setPage(0);
                    }}
                  />
                </label>
              </>
            )}
            {kind === "media" && (
              <label>
                <input
                  type="checkbox"
                  checked={failed}
                  onChange={(e) => {
                    setFailed(e.target.checked);
                    setPage(0);
                  }}
                />
                只看失败重试
              </label>
            )}
            <label>
              开始日期
              <input
                type="date"
                value={start}
                onChange={(e) => {
                  setStart(e.target.value);
                  setPage(0);
                }}
              />
            </label>
            <label>
              结束日期
              <input
                type="date"
                value={end}
                onChange={(e) => {
                  setEnd(e.target.value);
                  setPage(0);
                }}
              />
            </label>
          </div>
        </div>
        {list.error ? (
          <ErrorState error={list.error} />
        ) : list.isPending ? (
          <Loading />
        ) : list.data?.items.length ? (
          <div className="studio-table-wrap">
            <table className="studio-table">
              <thead>
                <tr>
                  <th>任务 / 对象</th>
                  <th>状态</th>
                  <th>时间</th>
                  <th>错误 / 次数</th>
                </tr>
              </thead>
              <tbody>
                {list.data.items.map((r: any) => (
                  <tr key={r.id}>
                    <td>
                      <button onClick={() => setSelected(r)}>
                        {r.job ?? r.room ?? r.path}
                      </button>
                    </td>
                    <td>
                      {valueLabel(
                        r.status ?? (kind === "media" ? "待清理" : "待投递"),
                      )}
                    </td>
                    <td>{dateLabel(r.started_at ?? r.created_at)}</td>
                    <td>
                      {r.error_code ?? r.last_error_code ?? r.attempts ?? "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <Empty />
        )}
        <div className="studio-pagination">
          <span>共 {list.data?.total ?? "—"} 条</span>
          <Button disabled={page === 0} onClick={() => setPage((v) => v - 1)}>
            上一页
          </Button>
          <span>{page + 1}</span>
          <Button
            disabled={!list.data || (page + 1) * 20 >= list.data.total}
            onClick={() => setPage((v) => v + 1)}
          >
            下一页
          </Button>
        </div>
      </div>
      <Dialog
        open={selected != null}
        onClose={() => setSelected(null)}
        title="运行记录详情"
        side
      >
        <div className="studio-detail">
          <dl>
            {Object.entries(selected ?? {}).map(([key, v]) => (
              <div className="contents" key={key}>
                <dt>{key}</dt>
                <dd>{String(v ?? "—")}</dd>
              </div>
            ))}
          </dl>
        </div>
      </Dialog>
    </>
  );
}
export function QualityPage() {
  const query = useAction("dataQuality"),
    [check, setCheck] = useState<any>(null);
  return (
    <>
      <PageHeader
        title="数据质量"
        description="比对原始记录和业务聚合；异常不会被自动修改"
      >
        <Button onClick={() => void query.refetch()}>重新检查</Button>
      </PageHeader>
      {query.error ? (
        <ErrorState error={query.error} />
      ) : query.isPending ? (
        <Loading />
      ) : (
        <div className="studio-card">
          <table className="studio-table">
            <thead>
              <tr>
                <th>检查项</th>
                <th>异常数</th>
                <th>检查结果</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {query.data?.checks.map((c: any) => (
                <tr key={c.key}>
                  <td>{c.label}</td>
                  <td>
                    {c.count}
                    {c.unknownCount > 0 && (
                      <small> · 未声明数量 {c.unknownCount}</small>
                    )}
                  </td>
                  <td>
                    <Badge tone={c.count ? "danger" : "success"}>
                      {c.count
                        ? "存在异常"
                        : c.unknownCount
                          ? "部分不可核验"
                          : "一致"}
                    </Badge>
                  </td>
                  <td>
                    <Button disabled={!c.count} onClick={() => setCheck(c)}>
                      查看样本
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="mt-4 text-xs">
        检查时间：{dateLabel(query.data?.generatedAt)}。每项最多展示 20 个对象
        ID；历史异常需单独调查和处理。
      </p>
      <Dialog
        open={check != null}
        onClose={() => setCheck(null)}
        title={check?.label ?? "异常样本"}
        side
      >
        <div className="studio-detail">
          {check?.samples.map((sample: any) => (
            <p key={sample.id}>
              {["teachers", "course_catalog", "dish_catalog"].includes(
                check.key,
              ) ? (
                <Link
                  to={`/${check.key === "course_catalog" ? "courses" : check.key === "dish_catalog" ? "dishes" : "teachers"}/${sample.id}`}
                >
                  {sample.id}
                </Link>
              ) : check.key.startsWith("post") ? (
                <Link to={`/posts/${sample.id}`}>{sample.id}</Link>
              ) : (
                String(sample.id)
              )}
            </p>
          ))}
        </div>
      </Dialog>
    </>
  );
}
