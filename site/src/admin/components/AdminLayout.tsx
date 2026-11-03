import { useEffect, useState, type ReactNode } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  Layout,
  Menu,
  Breadcrumb,
  Select,
  Button,
  Input,
  Space,
  Typography,
  Alert,
  Grid,
  Tag,
  Drawer,
} from "antd";
import {
  Leaf,
  Search,
  Menu as MenuIcon,
  LogOut,
  Activity,
  Users,
  ScrollText,
  Settings,
  LayoutDashboard,
} from "lucide-react";
import { useAdmin, useAction, reportError } from "../providers/context";
import { dataProvider } from "../providers/dataProvider";
import { resourceConfigs } from "../resources/config";
import type { GlobalSearchResult } from "../contracts";
import { Dialog, ErrorState, Empty } from "./ui";
const monitoring = [
  ["monitoring", "监控总览"],
  ["monitoring/traffic", "流量与接口"],
  ["monitoring/server", "主机与服务"],
  ["operations", "运行诊断"],
  ["monitoring/alerts", "告警"],
  ["monitoring/reports", "日报与发送记录"],
];
const logs = [
  ["monitoring/requests", "访问日志"],
  ["monitoring/logs", "应用与系统日志"],
];
const system = [
  ["data-quality", "数据质量"],
  ["admins", "管理员"],
  ["sessions", "会话"],
  ["audit-logs", "审计日志"],
  ["manual", "手册"],
];
const names = Object.fromEntries([
  ["", "总览"],
  ["work-queue", "待办"],
  ...Object.entries(resourceConfigs).map(([path, c]) => [path, c.label]),
  ...monitoring,
  ...logs,
  ...system,
]);
Object.assign(names, {
  campuses: "学校",
  "campus-requests": "学校申请",
  posts: "帖子",
  polls: "投票",
  comments: "评论",
  reports: "举报",
  profiles: "用户",
  feedback: "反馈",
  announcements: "公告",
  "community-banners": "Banner",
  postgraduate: "考研信息",
  "postgraduate-suggestions": "考研线索",
  suggestions: "名录建议",
  teachers: "教师",
  courses: "课程",
  dishes: "菜品",
  ratings: "评分",
  "semester-configs": "学期配置",
  "national-calendar": "国家日历",
  "android-releases": "Android 版本",
});
export function AdminLayout({ children }: { children: ReactNode }) {
  const {
      campus,
      setCampus,
      identity,
      can,
      logout,
      themeMode,
      setThemeMode,
      dark,
    } = useAdmin(),
    location = useLocation(),
    navigate = useNavigate(),
    screens = Grid.useBreakpoint();
  const schools = useAction<{ items: { id: string; display_name: string }[] }>(
    "listCampuses",
    { status: "all", page: 0, pageSize: 100 },
  );
  const desktop = screens.lg ?? window.matchMedia("(min-width: 992px)").matches;
  const [collapsed, setCollapsed] = useState(
      () => !window.matchMedia("(min-width: 992px)").matches,
    ),
    [searchOpen, setSearchOpen] = useState(false),
    [query, setQuery] = useState(""),
    [results, setResults] = useState<GlobalSearchResult[]>([]),
    [error, setError] = useState<unknown>(null),
    [searching, setSearching] = useState(false);
  useEffect(() => {
    setCollapsed(!desktop);
  }, [desktop]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setSearchOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  useEffect(() => {
    // Server monitoring is global to the environment, not a campus-scoped resource.
    if (
      location.pathname === "/monitoring" ||
      location.pathname.startsWith("/monitoring/")
    )
      return;
    const params = new URLSearchParams(location.search),
      selected = params.get("campus");
    if (selected === null) {
      params.set("campus", campus);
      navigate(
        { pathname: location.pathname, search: params.toString() },
        { replace: true },
      );
    } else if (selected !== campus) setCampus(selected);
  }, [location.pathname, location.search]);
  useEffect(() => {
    let active = true;
    if (query.trim().length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    const timer = setTimeout(() => {
      setSearching(true);
      setError(null);
      dataProvider
        .globalSearch(query.trim())
        .then((value) => active && setResults(value))
        .catch((error) => active && setError(error))
        .finally(() => active && setSearching(false));
    }, 250);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [query, campus]);
  const path = location.pathname.replace(/^\//, ""),
    current = path.startsWith("monitoring") ? path : path.split("/")[0];
  const item = ([key, label]: string[]) => ({
    key,
    label: (
      <Link
        to={`/${key}`}
        onClick={() => {
          if (!desktop) setCollapsed(true);
        }}
      >
        {label}
      </Link>
    ),
  });
  const allowed = (items: string[][]) =>
    items.filter(([key]) =>
      can(key.startsWith("monitoring") ? "monitoring" : key),
    );
  const business = [
    ["work-queue", "待办"],
    ...Object.entries(resourceConfigs)
      .filter(([key]) => !system.some(([name]) => name === key))
      .map(([key, c]) => [key, names[key] ?? c.label]),
  ];
  const items = [
    {
      key: "",
      icon: <LayoutDashboard size={17} />,
      label: <Link to="/">总览</Link>,
    },
    {
      key: "business",
      icon: <Users size={17} />,
      label: "业务管理",
      children: allowed(business).map(item),
    },
    ...(can("monitoring")
      ? [
          {
            key: "monitor",
            icon: <Activity size={17} />,
            label: "运行监控",
            children: allowed(monitoring).map(item),
          },
          {
            key: "logs",
            icon: <ScrollText size={17} />,
            label: "日志中心",
            children: allowed(logs).map(item),
          },
        ]
      : []),
    {
      key: "system",
      icon: <Settings size={17} />,
      label: "系统管理",
      children: allowed(system).map(item),
    },
  ];
  const navigation = (
    <nav
      id="admin-navigation"
      aria-label="管理导航"
      className="admin-navigation"
    >
      <Link
        to="/"
        className="admin-brand"
        onClick={() => {
          if (!desktop) setCollapsed(true);
        }}
      >
        <Leaf size={25} />
        <span>
          MyLeafy<small>管理控制台</small>
        </span>
      </Link>
      <Menu
        mode="inline"
        items={items}
        selectedKeys={[current]}
        defaultOpenKeys={["business", "monitor", "logs", "system"]}
      />
      <div className="admin-account">
        <Typography.Text strong>{identity?.admin.display_name}</Typography.Text>
        <Tag>
          {identity?.admin.role === "super_admin"
            ? "超级管理员"
            : identity?.admin.role === "operator"
              ? "运营管理员"
              : "只读管理员"}
        </Tag>
        <Button
          aria-label="退出登录"
          onClick={() => void logout().catch(reportError)}
          icon={<LogOut size={16} />}
        />
      </div>
    </nav>
  );
  return (
    <Layout className="admin-shell">
      <a className="admin-skip" href="#admin-content">
        跳到主要内容
      </a>
      {desktop ? (
        <Layout.Sider
          className="admin-sidebar"
          width={248}
          collapsedWidth={0}
          collapsed={collapsed}
          theme={dark ? "dark" : "light"}
        >
          {!collapsed && navigation}
        </Layout.Sider>
      ) : (
        <Drawer
          rootClassName="admin-nav-drawer"
          title="导航"
          placement="left"
          width={280}
          open={!collapsed}
          onClose={() => setCollapsed(true)}
        >
          {navigation}
        </Drawer>
      )}
      <Layout className="admin-workspace">
        <Layout.Header className="admin-topbar">
          <Space>
            <Button
              type="text"
              aria-label="切换导航"
              aria-expanded={!collapsed}
              aria-controls="admin-navigation"
              icon={<MenuIcon size={18} />}
              onClick={() => setCollapsed((v) => !v)}
            />
            <Breadcrumb
              items={[
                { title: "MyLeafy" },
                { title: names[current] ?? "管理控制台" },
              ]}
            />
          </Space>
          <Space wrap className="admin-tools">
            {!current.startsWith("monitoring") && (
              <Select
                aria-label="学校范围"
                value={campus}
                style={{ minWidth: 150 }}
                options={[
                  { value: "all", label: "全部学校" },
                  ...(schools.data?.items ?? []).map((s) => ({
                    value: s.id,
                    label: s.display_name,
                  })),
                ]}
                onChange={(value) => {
                  setCampus(value);
                  const params = new URLSearchParams(location.search);
                  params.set("campus", value);
                  navigate(
                    { pathname: location.pathname, search: params.toString() },
                    { replace: true },
                  );
                }}
              />
            )}
            <Button
              aria-label="全局搜索"
              icon={<Search size={15} />}
              onClick={() => setSearchOpen(true)}
            >
              搜索 <kbd>⌘K</kbd>
            </Button>
            <Select
              aria-label="主题"
              value={themeMode}
              onChange={setThemeMode}
              options={[
                { value: "system", label: "跟随系统" },
                { value: "light", label: "浅色" },
                { value: "dark", label: "深色" },
              ]}
            />
          </Space>
        </Layout.Header>
        <Layout.Content className="studio-content">
          <div id="admin-content" className="admin-content-inner">
            {schools.error && (
              <Alert
                type="warning"
                message="学校加载失败"
                action={
                  <Button onClick={() => void schools.refetch()}>重试</Button>
                }
              />
            )}{" "}
            {children}
          </div>
        </Layout.Content>
        <Layout.Footer className="admin-footer">
          MyLeafy · 数据以服务端返回为准
        </Layout.Footer>
      </Layout>
      <Dialog
        open={searchOpen}
        onClose={() => setSearchOpen(false)}
        title="搜索运营对象"
      >
        <Input
          autoFocus
          aria-label="搜索内容"
          placeholder="帖子、用户、反馈、名录…（至少 2 个字符）"
          maxLength={100}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        {error ? (
          <ErrorState error={error} />
        ) : searching ? (
          <p role="status">正在搜索…</p>
        ) : query.length >= 2 && results.length === 0 ? (
          <Empty>未找到匹配结果</Empty>
        ) : null}
        {[...new Set(results.map((r) => r.resource))].map((resource) => (
          <section key={resource}>
            <h3>{names[resource] ?? resource}</h3>
            {results
              .filter((r) => r.resource === resource)
              .map((r) => (
                <Button
                  block
                  className="admin-search-result"
                  key={`${r.resource}:${r.id}`}
                  onClick={() => {
                    navigate(r.path.replace(/^\/admin/, "") || "/");
                    setSearchOpen(false);
                    setQuery("");
                  }}
                >
                  <strong>{r.title}</strong>
                  <small>{r.subtitle}</small>
                </Button>
              ))}
          </section>
        ))}
      </Dialog>
    </Layout>
  );
}
