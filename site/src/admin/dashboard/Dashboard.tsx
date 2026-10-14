import type { AdminOverview } from "../contracts";
import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { useAction } from "../providers/context";
import {
  PageHeader,
  Button,
  Help,
  ErrorState,
  Loading,
} from "../components/ui";
import { dateLabel } from "../resources/ResourcePages";
export const listLink = (
  resource: string,
  filters: Record<string, unknown> = {},
) =>
  `/${resource}?filter=${encodeURIComponent(JSON.stringify({ status: "all", ...filters }))}`;
export function AdminDashboard() {
  const [days, setDays] = useState(30),
    query = useAction<AdminOverview>("overview", {
      days,
      timezone: "Asia/Shanghai",
    });
  const data = query.data,
    summary = data?.summary,
    meta = data?.analyticsMeta;
  if (query.isPending) return <Loading />;
  if (query.error)
    return (
      <ErrorState error={query.error} retry={() => void query.refetch()} />
    );
  if (
    !summary?.operations ||
    !summary.feedback ||
    !summary.moderation ||
    !summary.teachers ||
    !meta ||
    !Array.isArray(summary?.operations.daily) ||
    !Array.isArray(summary?.feedback.aging) ||
    ![
      summary.operations.totalProfiles,
      summary.operations.completeProfiles,
      summary.feedback.pending,
      data?.cards?.posts?.hidden,
    ].every((n) => typeof n === "number" && Number.isFinite(n))
  )
    return <ErrorState error="统计响应不完整，请保留请求信息并重试。" />;
  const ops = summary.operations,
    feedback = summary.feedback,
    moderation = summary.moderation;
  const daily = ops.daily,
    range = { start: meta.startDate, before: meta.endAt };
  return (
    <>
      <PageHeader title="运营总览" description="用户增长、内容与待办">
        <div className="studio-actions">
          <select
            aria-label="统计时间范围"
            value={days}
            onChange={(e) => setDays(Number(e.target.value))}
          >
            {[7, 30, 90].map((n) => (
              <option key={n} value={n}>
                最近 {n} 天
              </option>
            ))}
          </select>
          <Button onClick={() => void query.refetch()}>刷新</Button>
        </div>
      </PageHeader>
      <div className="studio-grid">
        <Metric
          title="用户总数"
          value={ops.totalProfiles}
          detail={`今日新增 ${ops.newProfilesToday}`}
          href={listLink("profiles")}
          help="当前非演示 profile 数，不代表安装量或活跃度。"
        />
        <Metric
          title="资料完善"
          value={ops.completeProfiles}
          detail="已设置有效昵称"
          href={listLink("profiles", { complete: true })}
        />
        <Metric
          title="待处理举报"
          value={moderation.openReports}
          detail={`超过 24 小时 ${moderation.overdueReports}`}
          href={listLink("reports", { pending: true })}
        />
        <Metric
          title="待处理反馈"
          value={feedback.pending}
          detail={`未查看 ${feedback.open} · 已查看 ${feedback.reviewed} · 逾期 ${feedback.overdue}`}
          href={listLink("feedback", { pending: true })}
        />
      </div>
      <div className="studio-charts">
        <Chart
          title={`${days} 天新增与内容趋势`}
          label={`内容趋势，日期：${daily.map((r: any) => formatBucketDate(r.bucket_date)).join("、")}`}
          option={{
            tooltip: { trigger: "axis" },
            legend: { data: ["帖子", "评论", "新增用户"] },
            xAxis: {
              type: "category",
              data: daily.map((r: any) => formatBucketDate(r.bucket_date)),
            },
            yAxis: { type: "value", minInterval: 1 },
            series: ["posts", "comments", "profiles"].map((key, i) => ({
              name: ["帖子", "评论", "新增用户"][i],
              type: "line",
              data: daily.map((r: any) => r[key]),
              showSymbol: daily.length === 1,
            })),
          }}
        />
        <Chart
          title="反馈等待时长"
          label="反馈等待时长分布"
          option={{
            tooltip: { trigger: "axis" },
            xAxis: {
              type: "category",
              data: feedback.aging.map((r: any) => r.label),
            },
            yAxis: { type: "value", minInterval: 1 },
            series: [
              {
                type: "bar",
                data: feedback.aging.map((r: any) => r.count),
                itemStyle: { color: "#30a46c", borderRadius: [3, 3, 0, 0] },
              },
            ],
          }}
        />
      </div>
      <div className="studio-grid">
        <Metric
          title={`${days} 天新增帖子`}
          value={ops.postsInRange}
          detail={`今日 ${ops.postsToday}`}
          href={listLink("posts", range)}
        />
        <Metric
          title={`${days} 天新增评论`}
          value={ops.commentsInRange}
          detail={`今日 ${ops.commentsToday}`}
          href={listLink("comments", range)}
        />
        <Metric
          title="当前隐藏帖子"
          value={data.cards.posts.hidden}
          detail={`本期采集到下架 ${moderation.hiddenPostsInRange} 次`}
          href={listLink("posts", { status: "hidden" })}
        />
        <Metric
          title="教师平均评分"
          value={summary.teachers.average}
          detail={`${summary.teachers.totalRatings} 条原始评分`}
          href={listLink("ratings", { target: "teacher" })}
        />
      </div>
      <small className="block mt-4">
        Asia/Shanghai · {meta.startDate} 至 {dateLabel(meta.endAt)} ·
        下架次数记录始于 {dateLabel(meta.moderationStartedAt)} · 生成于{" "}
        {dateLabel(meta.generatedAt)}
      </small>
    </>
  );
}
export function Metric({
  title,
  value,
  detail,
  href,
  help,
}: {
  title: string;
  value: unknown;
  detail: string;
  href: string;
  help?: string;
}) {
  return (
    <div className="studio-card">
      <div className="studio-metric-title" style={{ padding: "16px 20px 0" }}>
        {title}
        {help && <Help>{help}</Help>}
      </div>
      <Link className="studio-metric" to={href}>
        <strong>
          {typeof value === "number" && Number.isFinite(value)
            ? value.toLocaleString("zh-CN")
            : "未采集"}
        </strong>
        <small>{detail}</small>
      </Link>
    </div>
  );
}
function Chart({
  title,
  label,
  option,
}: {
  title: string;
  label: string;
  option: Record<string, any>;
}) {
  const element = useRef<HTMLDivElement>(null),
    [error, setError] = useState<unknown>(null);
  const key = JSON.stringify(option);
  const stable = useMemo(() => option, [key]);
  useEffect(() => {
    let active = true,
      chart: any;
    const root = element.current;
    if (!root) return;
    import("./echarts-runtime")
      .then(({ echarts }) => {
        if (!active) return;
        chart = echarts.init(root);
        render();
      })
      .catch((err) => active && setError(err));
    const observer = new ResizeObserver(() => chart?.resize());
    observer.observe(root);
    function render() {
      if (!chart || !root) return;
      const styles = getComputedStyle(root),
        muted = styles.getPropertyValue("--s-muted").trim(),
        border = styles.getPropertyValue("--s-border").trim(),
        background = styles.getPropertyValue("--s-panel").trim();
      chart.setOption({
        ...stable,
        animation: false,
        color: ["#30a46c", "#8b9de3", "#e4ae65"],
        textStyle: { color: muted },
        legend: { ...stable.legend, textStyle: { color: muted } },
        tooltip: {
          ...stable.tooltip,
          backgroundColor: background,
          borderColor: border,
          textStyle: { color: muted },
        },
        xAxis: {
          ...stable.xAxis,
          axisLabel: { color: muted },
          axisLine: { lineStyle: { color: border } },
        },
        yAxis: {
          ...stable.yAxis,
          axisLabel: { color: muted },
          splitLine: { lineStyle: { color: border } },
        },
      });
    }
    const themeObserver = new MutationObserver(render);
    themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "data-theme"],
    });
    themeObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ["class", "data-admin-theme"],
    });
    return () => {
      active = false;
      observer.disconnect();
      themeObserver.disconnect();
      chart?.dispose();
    };
  }, [stable]);
  return (
    <section className="studio-card">
      <div className="studio-card-header">
        <h2>{title}</h2>
      </div>
      {error ? (
        <ErrorState error={error} />
      ) : (
        <div
          className="studio-chart"
          role="img"
          aria-label={label}
          ref={element}
        />
      )}
    </section>
  );
}
export function formatBucketDate(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  return match ? `${match[2]}-${match[3]}` : "—";
}
