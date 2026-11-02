import { useEffect, useRef, useState } from "react";
import { useLocation } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Descriptions,
  Empty,
  Input,
  Pagination,
  Select,
  Space,
  Statistic,
  Table,
  Tag,
  Typography,
} from "antd";
import dayjs from "dayjs";
import { RefreshCw } from "lucide-react";
import { useAdmin } from "../providers/context";
import { dataProvider } from "../providers/dataProvider";
import { PageHeader, ErrorState, Dialog } from "../components/ui";

type Row = Record<string, any>;
type Range = { hours: number; start?: string; end?: string };
const titles: Record<string, string> = {
  overview: "监控总览",
  traffic: "流量与接口",
  server: "主机与服务",
  requests: "访问日志",
  logs: "应用与系统日志",
  alerts: "告警",
  reports: "日报与发送记录",
};
const metrics: Record<string, string> = {
  requests: "每秒请求数",
  bytes: "响应字节 / 秒",
  errors: "5xx 比例",
  p50: "P50 响应秒数",
  p95: "P95 响应秒数",
  p99: "P99 响应秒数",
  cpu: "CPU 使用率 %",
  memory: "内存使用率 %",
  disk: "磁盘使用率 %",
  diskRead: "磁盘读取字节 / 秒",
  diskWrite: "磁盘写入字节 / 秒",
  networkIn: "网卡接收字节 / 秒",
  networkOut: "网卡发送字节 / 秒",
  nodeMemory: "Node 常驻内存字节",
  nodeCPU: "Node CPU 核数",
  eventLoop: "事件循环 P99 秒数",
  websocket: "WebSocket 连接数",
};
const number = (value: unknown, digits = 0) =>
  typeof value === "number" && Number.isFinite(value)
    ? value.toLocaleString("zh-CN", { maximumFractionDigits: digits })
    : "未采集";
const time = (value: unknown) =>
  typeof value === "number" || typeof value === "string"
    ? new Date(value).toLocaleString("zh-CN", {
        timeZone: "Asia/Shanghai",
        hour12: false,
      })
    : "未采集";
function useMonitor(
  action: string,
  range: Range,
  params: Row = {},
  enabled = true,
) {
  const { identity } = useAdmin();
  return useQuery<Row>({
    queryKey: [
      "admin",
      identity?.admin.id,
      "monitoring",
      action,
      range,
      params,
    ],
    queryFn: ({ signal }) => {
      const end = range.end ?? new Date().toISOString(),
        start =
          range.start ??
          new Date(Date.parse(end) - range.hours * 3_600_000).toISOString();
      return dataProvider.execute(action, { ...params, start, end }, signal);
    },
    enabled: !!identity && enabled,
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
  });
}
export function MonitoringPage() {
  const location = useLocation(),
    view = location.pathname.split("/")[2] || "overview";
  const [range, setRange] = useState<Range>({ hours: 24 });
  const overview = useMonitor("monitoringOverview", range);
  return (
    <>
      <PageHeader
        title={titles[view] ?? "监控总览"}
        description="服务器运行与请求数据 · 时间以北京时间显示"
      >
        <Space>
          <Button
            icon={<RefreshCw size={14} />}
            loading={overview.isFetching}
            onClick={() => void overview.refetch()}
          >
            刷新
          </Button>
        </Space>
      </PageHeader>
      <div className="monitor-range">
        <Select
          aria-label="监控时间范围"
          value={range.start ? "custom" : String(range.hours)}
          style={{ width: 160 }}
          onChange={(value) => setRange({ hours: Number(value) })}
          options={[
            { value: "1", label: "最近 1 小时" },
            { value: "6", label: "最近 6 小时" },
            { value: "24", label: "最近 24 小时" },
            { value: "72", label: "最近 3 天" },
            { value: "168", label: "最近 7 天" },
            { value: "336", label: "最近 14 天" },
            ...(range.start ? [{ value: "custom", label: "自定义范围" }] : []),
          ]}
        />
        <DatePicker.RangePicker
          aria-label="自定义监控日期"
          placeholder={["开始时间", "结束时间"]}
          showTime
          format="YYYY-MM-DD HH:mm"
          value={range.start ? [dayjs(range.start), dayjs(range.end)] : null}
          onChange={(value) => {
            if (value?.[0] && value?.[1])
              setRange({
                hours: 24,
                start: value[0].toISOString(),
                end: value[1].toISOString(),
              });
            else setRange({ hours: 24 });
          }}
        />
        <Typography.Text type="secondary">每 30 秒刷新</Typography.Text>
      </div>
      {overview.error && (
        <div className="monitor-section">
          <ErrorState
            error={overview.error}
            retry={() => void overview.refetch()}
          />
        </div>
      )}
      {overview.data && (
        <>
          <Coverage value={overview.data.coverage} />
          {view === "overview" ? (
            <Overview value={overview.data} range={range} />
          ) : view === "traffic" ? (
            <Traffic value={overview.data} range={range} />
          ) : view === "server" ? (
            <Server value={overview.data} range={range} />
          ) : ["requests", "logs", "alerts", "reports"].includes(view) ? (
            <Records key={view} kind={view} range={range} />
          ) : (
            <Empty description="页面不存在" />
          )}
        </>
      )}
    </>
  );
}
function Coverage({ value }: { value: Row }) {
  return (
    <div className="monitor-section">
      {(value?.stale || value?.collectionError) && (
        <Alert
          type="warning"
          showIcon
          message="监控数据不完整"
          description={`采集状态：${value.collectionError ?? "数据已过期"}。缺失数据不会计为正常。`}
        />
      )}
      {value?.capacityLimited && (
        <Alert
          type="warning"
          showIcon
          message="日志曾达到容量上限，已清理最旧记录"
        />
      )}
      {value?.sourceBacklog && (
        <Alert
          type="warning"
          showIcon
          message="日志采集存在积压，正在按顺序补齐。"
        />
      )}
      {value?.partial && (
        <Alert
          type="info"
          showIcon
          message="所选时间范围早于采集开始，当前结果只覆盖已采集部分。"
        />
      )}
      <p className="monitor-summary">
        采集开始：{time(value?.startedAt)} · 最近采集：
        {time(value?.lastCollection)} · 日志可查询起点：{time(value?.oldestLog)}{" "}
        · 指标保留 14 天，日志保留 7 天；以实际覆盖范围为准。
      </p>
    </div>
  );
}
function Overview({ value, range }: { value: Row; range: Range }) {
  const summary = value.summary ?? {},
    sample = value.coverage?.stale ? {} : (value.sample ?? {});
  return (
    <>
      <div className="monitor-grid">
        {[
          ["请求数", summary.requests],
          [
            "响应流量（MiB）",
            summary.bytes === undefined ? null : summary.bytes / 1048576,
          ],
          [
            "5xx 比例（%）",
            summary.errorRate == null ? null : summary.errorRate * 100,
          ],
          ["P95 响应（秒）", summary.p95],
          ["CPU（%）", sample.cpu],
          ["内存（%）", sample.memory],
        ].map(([title, value]) => (
          <Card key={String(title)}>
            <Statistic title={String(title)} value={number(value, 2)} />
          </Card>
        ))}
      </div>
      <div className="monitor-status">
        {Object.entries(sample.services ?? {}).map(
          ([name, state]: [string, any]) => (
            <Tag
              key={name}
              color={
                state.healthy === true
                  ? "success"
                  : state.healthy === false
                    ? "error"
                    : "default"
              }
            >
              {name} ·{" "}
              {state.healthy === true
                ? "正常"
                : state.healthy === false
                  ? "异常"
                  : "未知"}
            </Tag>
          ),
        )}
      </div>
      {!!value.alerts?.length && (
        <Alert
          type="warning"
          showIcon
          message={`当前有 ${value.alerts.length} 项待确认或未恢复异常`}
          description={value.alerts
            .slice(0, 3)
            .map((a: Row) => a.title)
            .join("；")}
        />
      )}
      <MetricChart
        range={range}
        initial="requests"
        options={["requests", "bytes", "errors", "p95"]}
      />
      <Card className="monitor-section" title="采集与通知">
        <Descriptions
          column={{ xs: 1, sm: 2 }}
          items={[
            { key: "environment", label: "环境", children: value.environment },
            {
              key: "timestamp",
              label: "生成时间",
              children: time(value.generatedAt),
            },
            {
              key: "mail",
              label: "邮件",
              children: value.mail?.enabled
                ? "已启用"
                : "未启用（测试环境默认关闭）",
            },
            {
              key: "mailError",
              label: "发信状态",
              children: value.mail?.error ?? "无已记录错误",
            },
            {
              key: "pending",
              label: "等待发送",
              children: number(value.mail?.pending),
            },
            {
              key: "commit",
              label: "运行提交",
              children: value.tasks?.commit ?? "未采集",
            },
          ]}
        />
      </Card>
    </>
  );
}
function MetricChart({
  range,
  initial,
  options,
}: {
  range: Range;
  initial: string;
  options: string[];
}) {
  const [metric, setMetric] = useState(initial),
    query = useMonitor("monitoringSeries", range, { metric }),
    element = useRef<HTMLDivElement>(null);
  const { themeMode } = useAdmin();
  useEffect(() => {
    if (!element.current || !query.data?.series?.length) return;
    let active = true,
      chart: import("echarts/core").ECharts | undefined;
    const resize = new ResizeObserver(() => chart?.resize());
    resize.observe(element.current);
    void import("../dashboard/echarts-runtime")
      .then(({ echarts }) => {
        if (!active || !element.current) return;
        chart = echarts.init(
          element.current,
          document.body.dataset.adminTheme === "dark" ? "dark" : undefined,
        );
        chart.setOption({
          backgroundColor: "transparent",
          animation: false,
          grid: { left: 62, right: 24, top: 24, bottom: 45 },
          tooltip: { trigger: "axis" },
          xAxis: { type: "time" },
          yAxis: { type: "value", splitLine: { lineStyle: { opacity: 0.12 } } },
          series: query.data.series.map((row: Row) => ({
            type: "line",
            name: metrics[metric],
            showSymbol: false,
            connectNulls: false,
            data: row.points,
            lineStyle: { width: 2 },
            areaStyle: { opacity: 0.06 },
          })),
        });
      })
      .catch(() => {
        if (element.current)
          element.current.textContent = "图表暂时无法加载，请刷新重试。";
      });
    return () => {
      active = false;
      resize.disconnect();
      chart?.dispose();
    };
  }, [query.data, metric, themeMode]);
  const points = query.data?.series?.flatMap((s: Row) => s.points) ?? [],
    latest = points.length ? points[points.length - 1]?.[1] : null;
  return (
    <Card
      className="monitor-section"
      title={
        <Select
          aria-label="图表指标"
          value={metric}
          onChange={setMetric}
          style={{ minWidth: 210 }}
          options={options.map((value) => ({ value, label: metrics[value] }))}
        />
      }
      extra={
        <Typography.Text type="secondary">
          最新值：{number(latest, 3)}
        </Typography.Text>
      }
    >
      {query.error ? (
        <ErrorState error={query.error} retry={() => void query.refetch()} />
      ) : !points.length ? (
        <Empty
          description={
            query.isPending ? "正在读取指标…" : "该时间范围尚无指标数据"
          }
        />
      ) : (
        <div
          ref={element}
          role="img"
          aria-label={`${metrics[metric]}趋势图，最新值 ${number(latest, 3)}`}
          className="monitor-chart"
        />
      )}
    </Card>
  );
}
function Traffic({ value, range }: { value: Row; range: Range }) {
  return (
    <>
      <Alert
        type="info"
        showIcon
        message="统计到达服务器并完成的请求，包含网站、API 与下载；请求量不代表活跃用户。长连接流量在连接结束后计入。"
      />
      <MetricChart
        range={range}
        initial="requests"
        options={["requests", "bytes", "errors", "p50", "p95", "p99"]}
      />
      <Card className="monitor-section" title="热门接口">
        <Table<Row>
          rowKey={(r) => `${r.host}:${r.method}:${r.route}`}
          dataSource={value.summary?.topRoutes ?? []}
          pagination={false}
          scroll={{ x: 800 }}
          columns={[
            { title: "域名", dataIndex: "host" },
            { title: "方法", dataIndex: "method" },
            { title: "接口", dataIndex: "route" },
            { title: "请求", dataIndex: "requests", render: (v) => number(v) },
            { title: "响应字节", dataIndex: "bytes", render: (v) => number(v) },
            { title: "5xx", dataIndex: "errors", render: (v) => number(v) },
          ]}
        />
      </Card>
      <Card className="monitor-section" title="错误摘要">
        <Table<Row>
          rowKey={(r) => `${r.source}:${r.event}:${r.code}`}
          dataSource={value.summary?.topErrors ?? []}
          pagination={false}
          columns={[
            { title: "来源", dataIndex: "source" },
            { title: "事件", dataIndex: "event" },
            { title: "错误码", dataIndex: "code" },
            { title: "次数", dataIndex: "count" },
          ]}
        />
      </Card>
    </>
  );
}
function Server({ value, range }: { value: Row; range: Range }) {
  const sample = value.coverage?.stale ? {} : (value.sample ?? {});
  return (
    <>
      <div className="monitor-grid">
        {[
          ["CPU（%）", sample.cpu],
          ["内存（%）", sample.memory],
          ["磁盘（%）", sample.disk],
        ].map(([title, value]) => (
          <Card key={String(title)}>
            <Statistic title={String(title)} value={number(value, 2)} />
          </Card>
        ))}
      </div>
      <MetricChart
        range={range}
        initial="cpu"
        options={[
          "cpu",
          "memory",
          "disk",
          "diskRead",
          "diskWrite",
          "networkIn",
          "networkOut",
          "nodeMemory",
          "nodeCPU",
          "eventLoop",
          "websocket",
        ]}
      />
      <Card className="monitor-section" title="服务与备份">
        <Table
          rowKey="name"
          dataSource={Object.entries(sample.services ?? {}).map(
            ([name, state]) => ({ name, ...(state as Row) }),
          )}
          pagination={false}
          columns={[
            { title: "服务", dataIndex: "name" },
            {
              title: "状态",
              dataIndex: "healthy",
              render: (v) => (
                <Tag
                  color={
                    v === true ? "success" : v === false ? "error" : "default"
                  }
                >
                  {v === true ? "正常" : v === false ? "异常" : "未知"}
                </Tag>
              ),
            },
            { title: "连续失败", dataIndex: "failures" },
            {
              title: "自动重启次数",
              dataIndex: "restarts",
              render: (v) => number(v),
            },
          ]}
        />
        <Descriptions
          className="monitor-section"
          items={[
            {
              key: "backup",
              label: "最近成功备份",
              children: time(sample.backup?.successAt),
            },
            {
              key: "result",
              label: "备份结果",
              children:
                sample.backup?.failed === null ||
                sample.backup?.failed === undefined
                  ? "未采集"
                  : sample.backup.failed
                    ? "失败"
                    : "成功",
            },
            {
              key: "maintenance",
              label: "维护窗口截止",
              children: sample.maintenanceUntil
                ? time(sample.maintenanceUntil)
                : "无",
            },
          ]}
        />
      </Card>
      <Card className="monitor-section" title="定时任务">
        <Table
          rowKey="job"
          pagination={false}
          dataSource={value.tasks?.tasks ?? []}
          columns={[
            { title: "任务（UTC）", dataIndex: "job" },
            { title: "状态", dataIndex: "status" },
            { title: "最近完成", dataIndex: "finished_at", render: time },
            { title: "错误码", dataIndex: "error_code" },
          ]}
        />
      </Card>
    </>
  );
}
function Records({ kind, range }: { kind: string; range: Range }) {
  const [page, setPage] = useState(0),
    [filters, setFilters] = useState<Row>({}),
    [selected, setSelected] = useState<Row | null>(null);
  const actions: Record<string, string> = {
    requests: "requestLogList",
    logs: "serviceLogList",
    alerts: "monitoringAlerts",
    reports: "monitoringReports",
  };
  const query = useMonitor(actions[kind], range, {
    ...filters,
    page,
    pageSize: 20,
  });
  useEffect(() => setPage(0), [range]);
  const filter = (key: string, value: unknown) => {
    setPage(0);
    setFilters((previous) => ({ ...previous, [key]: value }));
  };
  const columns: any[] =
    kind === "requests"
      ? [
          { title: "时间", dataIndex: "timestamp", render: time },
          { title: "域名", dataIndex: "host" },
          { title: "方法", dataIndex: "method" },
          { title: "接口", dataIndex: "route" },
          { title: "状态码", dataIndex: "status" },
          {
            title: "耗时（秒）",
            dataIndex: "duration",
            render: (v: unknown) => number(v, 3),
          },
          { title: "响应字节", dataIndex: "bytes" },
          { title: "来源 IP（脱敏）", dataIndex: "ip" },
        ]
      : kind === "logs"
        ? [
            { title: "时间", dataIndex: "timestamp", render: time },
            { title: "来源", dataIndex: "source" },
            { title: "级别", dataIndex: "level" },
            { title: "事件", dataIndex: "event" },
            { title: "错误码", dataIndex: "code" },
          ]
        : kind === "alerts"
          ? [
              { title: "异常", dataIndex: "title" },
              { title: "首次发现", dataIndex: "firstSeen", render: time },
              {
                title: "状态",
                render: (_: unknown, row: Row) => (
                  <Tag
                    color={
                      row.resolvedAt
                        ? "success"
                        : row.lastNotified
                          ? "error"
                          : "warning"
                    }
                  >
                    {row.resolvedAt
                      ? "已恢复"
                      : row.lastNotified
                        ? "异常"
                        : "待确认"}
                  </Tag>
                ),
              },
              { title: "恢复时间", dataIndex: "resolvedAt", render: time },
              {
                title: "通知状态",
                render: (_: unknown, row: Row) =>
                  row.notification?.status ?? "尚未通知",
              },
            ]
          : [
              { title: "统计起点", dataIndex: "start", render: time },
              { title: "统计终点", dataIndex: "end", render: time },
              {
                title: "覆盖范围",
                render: (_: unknown, row: Row) =>
                  row.summary?.complete ? "完整" : "不完整",
              },
              {
                title: "发送状态",
                render: (_: unknown, row: Row) =>
                  row.delivery?.status ?? "未知",
              },
              {
                title: "发送次数",
                render: (_: unknown, row: Row) => row.delivery?.attempts ?? 0,
              },
              {
                title: "错误码",
                render: (_: unknown, row: Row) => row.delivery?.error ?? "—",
              },
            ];
  columns.push({
    title: "详情",
    key: "detail",
    render: (_: unknown, row: Row) => (
      <Button type="link" onClick={() => setSelected(row)}>
        详情
      </Button>
    ),
  });
  return (
    <Card className="monitor-section">
      {["requests", "logs"].includes(kind) && (
        <div className="monitor-filters">
          {(kind === "requests"
            ? [
                ["host", "域名"],
                ["route", "接口"],
                ["status", "状态码"],
                ["minDuration", "最小耗时（秒）"],
                ["requestId", "请求 ID"],
              ]
            : [
                ["source", "来源"],
                ["level", "级别"],
                ["event", "事件"],
                ["code", "错误码"],
                ["requestId", "请求 ID"],
              ]
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <Input
                aria-label={label}
                value={filters[key] ?? ""}
                onChange={(e) => filter(key, e.target.value)}
              />
            </label>
          ))}
          <Button
            onClick={() => {
              setFilters({});
              setPage(0);
            }}
          >
            清除筛选
          </Button>
        </div>
      )}
      {kind === "reports" && (
        <Alert
          type="info"
          message="日报每天北京时间 21:00 发往指定 QQ 邮箱。发送状态与服务商回执可在详情查看；回执不等同于收件人实际收到。"
        />
      )}
      {query.error ? (
        <ErrorState error={query.error} retry={() => void query.refetch()} />
      ) : (
        <Table
          className="monitor-table"
          rowKey="id"
          loading={query.isPending}
          dataSource={query.data?.items ?? []}
          columns={columns}
          pagination={false}
          scroll={{ x: "max-content" }}
        />
      )}
      <div className="monitor-footer">
        <Pagination
          current={page + 1}
          pageSize={20}
          total={query.data?.total ?? 0}
          showSizeChanger={false}
          showTotal={(total) => `共 ${total} 条`}
          onChange={(value) => setPage(value - 1)}
        />
      </div>
      <Dialog
        open={selected !== null}
        onClose={() => setSelected(null)}
        title="监控记录详情"
      >
        <pre className="monitor-json">{JSON.stringify(selected, null, 2)}</pre>
      </Dialog>
    </Card>
  );
}
