import { useEffect, useState, type ReactNode } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  Leaf,
  Search,
  LayoutDashboard,
  Users,
  MessagesSquare,
  BookOpen,
  Settings,
  Shield,
  PanelLeft,
  LogOut,
  Sun,
  Moon,
  Monitor,
  CheckSquare,
  Activity,
  Database,
} from "lucide-react";
import { useAdmin, useAction, reportError } from "../providers/context";
import { dataProvider } from "../providers/dataProvider";
import type { GlobalSearchResult } from "../contracts";
import { Button, Dialog, Badge } from "./ui";
const groups = [
  {
    label: "工作台",
    icon: LayoutDashboard,
    items: [
      ["", "总览"],
      ["work-queue", "待办"],
      ["manual", "手册"],
    ],
  },
  {
    label: "社区运营",
    icon: MessagesSquare,
    items: [
      ["posts", "帖子"],
      ["polls", "投票"],
      ["comments", "评论"],
      ["reports", "举报"],
      ["profiles", "用户"],
      ["feedback", "反馈"],
      ["announcements", "公告"],
      ["community-banners", "Banner"],
    ],
  },
  {
    label: "资料名录",
    icon: BookOpen,
    items: [
      ["postgraduate", "考研信息"],
      ["postgraduate-suggestions", "考研线索"],
      ["suggestions", "名录建议"],
      ["teachers", "教师"],
      ["courses", "课程"],
      ["dishes", "菜品"],
      ["ratings", "评分"],
    ],
  },
  {
    label: "运行配置",
    icon: Settings,
    items: [
      ["campuses", "学校"],
      ["campus-requests", "学校申请"],
      ["android-releases", "Android 版本"],
      ["semester-configs", "学期配置"],
      ["national-calendar", "国家日历"],
    ],
  },
  {
    label: "系统管理",
    icon: Shield,
    items: [
      ["operations", "运行诊断"],
      ["data-quality", "数据质量"],
      ["admins", "管理员"],
      ["sessions", "会话"],
      ["audit-logs", "审计日志"],
    ],
  },
];
const resourceIcons: Record<string, typeof Leaf> = {
  profiles: Users,
  "work-queue": CheckSquare,
  operations: Activity,
  "data-quality": Database,
};
export function AdminLayout({ children }: { children: ReactNode }) {
  const { campus, setCampus, identity, can, logout } = useAdmin(),
    location = useLocation(),
    navigate = useNavigate();
  const schools = useAction<{ items: { id: string; display_name: string }[] }>(
    "listCampuses",
    { status: "all", page: 0, pageSize: 100 },
  );
  const [collapsed, setCollapsed] = useState(false),
    [searchOpen, setSearchOpen] = useState(false),
    [query, setQuery] = useState(""),
    [results, setResults] = useState<GlobalSearchResult[]>([]),
    [searchError, setSearchError] = useState<unknown>(null),
    [searching, setSearching] = useState(false),
    [theme, setTheme] = useState(
      () => localStorage.getItem("leafy-admin-theme") ?? "system",
    );
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => {
      document.body.dataset.adminTheme =
        theme === "system" ? (media.matches ? "dark" : "light") : theme;
    };
    update();
    media.addEventListener("change", update);
    localStorage.setItem("leafy-admin-theme", theme);
    return () => media.removeEventListener("change", update);
  }, [theme]);
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
    let active = true;
    if (query.trim().length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    const timer = setTimeout(() => {
      setSearching(true);
      setSearchError(null);
      dataProvider
        .globalSearch(query.trim())
        .then((value) => active && setResults(value))
        .catch((err) => active && setSearchError(err))
        .finally(() => active && setSearching(false));
    }, 250);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [query, campus]);
  useEffect(() => {
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
  const current = location.pathname.split("/")[1] ?? "",
    group = groups.find((g) => g.items.some(([path]) => path === current)),
    label = group?.items.find(([path]) => path === current)?.[1] ?? "总览";
  return (
    <div className={`studio ${collapsed ? "nav-collapsed" : ""}`}>
      <aside className="studio-rail">
        <Link to="/" className="studio-logo" aria-label="MyLeafy 总览">
          <Leaf size={25} />
        </Link>
        {groups.map((g) => {
          const entry = g.items.find(([path]) => can(path || "dashboard"));
          return entry ? (
            <Link
              key={g.label}
              to={`/${entry[0]}`}
              aria-label={g.label}
              title={g.label}
              className={group === g ? "selected" : ""}
            >
              <g.icon size={19} />
            </Link>
          ) : null;
        })}
        <div className="studio-rail-bottom">
          <Button
            variant="ghost"
            aria-label="切换导航"
            onClick={() => setCollapsed((v) => !v)}
          >
            <PanelLeft size={18} />
          </Button>
        </div>
      </aside>
      <aside className="studio-sidebar">
        <div className="studio-workspace">
          <strong>MyLeafy</strong>
          <Badge>运营工作台</Badge>
        </div>
        <label className="studio-campus">
          学校范围
          <select
            aria-label="学校范围"
            value={campus}
            onChange={(e) => {
              setCampus(e.target.value);
              const params = new URLSearchParams(location.search);
              params.set("campus", e.target.value);
              navigate(
                { pathname: location.pathname, search: params.toString() },
                { replace: true },
              );
            }}
          >
            <option value="all">全部学校</option>
            {schools.data?.items.map((s) => (
              <option key={s.id} value={s.id}>
                {s.display_name}
              </option>
            ))}
          </select>
        </label>
        {schools.error && (
          <small role="alert">
            学校加载失败{" "}
            <button onClick={() => void schools.refetch()}>重试</button>
          </small>
        )}
        <nav>
          {groups.map((g) => (
            <section key={g.label}>
              <h2>{g.label}</h2>
              {g.items
                .filter(([path]) => can(path || "dashboard"))
                .map(([path, text]) => {
                  const Icon = resourceIcons[path] ?? g.icon;
                  return (
                    <Link
                      key={path}
                      to={`/${path}`}
                      className={current === path ? "active" : ""}
                    >
                      <Icon size={15} />
                      {text}
                    </Link>
                  );
                })}
            </section>
          ))}
        </nav>
        <div className="studio-account">
          <span>
            {identity?.admin.display_name}
            <small>
              {identity?.admin.role === "super_admin"
                ? "超级管理员"
                : identity?.admin.role === "operator"
                  ? "运营管理员"
                  : "只读管理员"}
            </small>
          </span>
          <Button
            aria-label="退出登录"
            variant="ghost"
            onClick={() => void logout().catch(reportError)}
          >
            <LogOut size={16} />
          </Button>
        </div>
      </aside>
      <div className="studio-main">
        <header className="studio-topbar">
          <div className="studio-breadcrumb">
            <Button
              className="mobile-nav"
              aria-label="展开导航"
              variant="ghost"
              onClick={() => setCollapsed((v) => !v)}
            >
              <PanelLeft size={18} />
            </Button>
            <span>MyLeafy</span>
            <span>/</span>
            <span>{group?.label}</span>
            <span>/</span>
            <strong>{label}</strong>
          </div>
          <div className="studio-top-actions">
            <Button onClick={() => setSearchOpen(true)} aria-label="全局搜索">
              <Search size={14} />
              <span>搜索</span>
              <kbd>⌘ K</kbd>
            </Button>
            <select
              aria-label="主题"
              value={theme}
              onChange={(e) => setTheme(e.target.value)}
            >
              <option value="system">跟随系统</option>
              <option value="light">浅色</option>
              <option value="dark">深色</option>
            </select>
            {theme === "light" ? (
              <Sun size={15} />
            ) : theme === "dark" ? (
              <Moon size={15} />
            ) : (
              <Monitor size={15} />
            )}
          </div>
        </header>
        <main className="studio-content">{children}</main>
        <footer className="studio-footer">
          Cloudflare · 数据以服务端返回为准
        </footer>
      </div>
      <Dialog
        open={searchOpen}
        onClose={() => setSearchOpen(false)}
        title="搜索运营对象"
      >
        <div className="studio-form">
          <input
            autoFocus
            aria-label="搜索内容"
            placeholder="帖子、用户、反馈、名录…（至少 2 个字符）"
            maxLength={100}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          {searchError != null ? (
            <p role="alert">{String(searchError)}</p>
          ) : searching ? (
            <p>正在搜索…</p>
          ) : query.length >= 2 && results.length === 0 ? (
            <p>未找到匹配结果</p>
          ) : null}
          {[...new Set(results.map((r) => r.resource))].map((resource) => (
            <section key={resource}>
              <h3>
                {groups
                  .flatMap((g) => g.items)
                  .find(([path]) => path === resource)?.[1] ?? resource}
              </h3>
              {results
                .filter((r) => r.resource === resource)
                .map((r) => (
                  <button
                    className="studio-search-result"
                    key={`${r.resource}:${r.id}`}
                    onClick={() => {
                      navigate(r.path.replace(/^\/admin/, "") || "/");
                      setSearchOpen(false);
                      setQuery("");
                    }}
                  >
                    <strong>{r.title}</strong>
                    <small>{r.subtitle}</small>
                  </button>
                ))}
            </section>
          ))}
        </div>
      </Dialog>
    </div>
  );
}
