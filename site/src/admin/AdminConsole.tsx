import React, { FormEvent, createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  Building2,
  BookOpen,
  Database,
  Utensils,
  FileText,
  Flag,
  GraduationCap,
  Home,
  Inbox,
  LayoutDashboard,
  Lightbulb,
  LoaderCircle,
  LogIn,
  LogOut,
  Megaphone,
  MessageSquare,
  Pin,
  RefreshCw,
  ScrollText,
  Settings,
  ShieldCheck,
  Star,
  Users,
  Vote,
  X
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import {
  AdminAccount,
  AdminSession,
  adminAction,
  fetchCurrentAdmin,
  login,
  logout
} from "./api";
import "./styles.css";

type ViewKey =
  | "overview"
  | "manual"
  | "campuses"
  | "posts"
  | "polls"
  | "comments"
  | "reports"
  | "profiles"
  | "feedback"
  | "announcements"
  | "postgraduate"
  | "suggestions"
  | "teachers"
  | "courses"
  | "dishes"
  | "ratings"
  | "admins"
  | "logs";

type Row = Record<string, any>;

type ListResult<T = Row> = {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
};

type MessageTone = "success" | "error";
type Message = { tone: MessageTone; text: string } | null;
type PinScope = "global" | "category";
type PinDialogState = { post: Row; scope: PinScope } | null;
type NavGroupKey = "general" | "community" | "catalog" | "administration";

const storageKey = "leafy-admin-session";
const CampusScopeContext = createContext("all");

const views: Array<{ key: ViewKey; label: string; description: string; icon: LucideIcon; group: NavGroupKey; superOnly?: boolean }> = [
  { key: "overview", label: "总览", description: "增长、审核、反馈和内容健康的实时视图", icon: LayoutDashboard, group: "general" },
  { key: "manual", label: "手册", description: "日常运营顺序、置顶规则和权限边界", icon: ScrollText, group: "general" },
  { key: "campuses", label: "学校", description: "审核学校申请并查看学校社区空间", icon: Building2, group: "community" },
  { key: "posts", label: "帖子", description: "管理帖子状态、内容可见性与批量操作", icon: FileText, group: "community" },
  { key: "polls", label: "投票", description: "审核用户发起的投票并查看聚合统计", icon: Vote, group: "community" },
  { key: "comments", label: "评论", description: "查看评论上下文并处理隐藏与恢复", icon: MessageSquare, group: "community" },
  { key: "reports", label: "举报", description: "处理用户举报、SLA 压力和处置动作", icon: Flag, group: "community" },
  { key: "profiles", label: "用户", description: "检索用户资料、禁言状态和社区活动", icon: Users, group: "community" },
  { key: "feedback", label: "反馈", description: "跟进用户反馈、分类和关闭进度", icon: Inbox, group: "community" },
  { key: "announcements", label: "公告", description: "维护站内公告和发布节奏", icon: Megaphone, group: "community" },
  { key: "postgraduate", label: "考研信息", description: "维护考研公共来源并审核用户提交的信息线索", icon: GraduationCap, group: "catalog" },
  { key: "suggestions", label: "名录建议", description: "审核教师、课程和菜品名录补充建议", icon: Lightbulb, group: "catalog" },
  { key: "teachers", label: "教师", description: "维护教师档案、院系和公开状态", icon: GraduationCap, group: "catalog" },
  { key: "courses", label: "课程", description: "管理课程目录、教师关联和元数据", icon: BookOpen, group: "catalog" },
  { key: "dishes", label: "菜品", description: "维护食堂菜品、地点和公开状态", icon: Utensils, group: "catalog" },
  { key: "ratings", label: "评分", description: "查看教师和菜品评分明细", icon: Star, group: "catalog" },
  { key: "admins", label: "管理员", description: "管理后台账号、角色和可用状态", icon: ShieldCheck, group: "administration", superOnly: true },
  { key: "logs", label: "日志", description: "审计后台操作记录和执行来源", icon: ScrollText, group: "administration", superOnly: true }
];

const navGroups: Array<{ key: NavGroupKey; label: string; icon: LucideIcon }> = [
  { key: "general", label: "概览", icon: Home },
  { key: "community", label: "社区运营", icon: MessageSquare },
  { key: "catalog", label: "资料名录", icon: Database },
  { key: "administration", label: "后台管理", icon: Settings }
];

const diningLocations = [
  { value: "东区食堂 · 一层 · 学一食堂", label: "东区食堂 · 一层 · 学一食堂" },
  { value: "东区食堂 · 一层 · 学三食堂", label: "东区食堂 · 一层 · 学三食堂" },
  { value: "东区食堂 · 一层 · 烘焙坊", label: "东区食堂 · 一层 · 烘焙坊" },
  { value: "东区食堂 · 二层 · 教工餐厅", label: "东区食堂 · 二层 · 教工餐厅" },
  { value: "东区食堂 · 二层 · 学四食堂", label: "东区食堂 · 二层 · 学四食堂" },
  { value: "东区食堂 · 三层 · 楸木园餐厅", label: "东区食堂 · 三层 · 楸木园餐厅" },
  { value: "东区食堂 · 三层 · 林园餐厅", label: "东区食堂 · 三层 · 林园餐厅" },
  { value: "西区食堂 · B1层 · 小食光餐厅", label: "西区食堂 · B1层 · 小食光餐厅" },
  { value: "西区食堂 · 一层 · 学二食堂", label: "西区食堂 · 一层 · 学二食堂" },
  { value: "西区食堂 · 二层 · 齐芳阁餐厅", label: "西区食堂 · 二层 · 齐芳阁餐厅" },
  { value: "西区食堂 · 三层 · 林汇园餐厅", label: "西区食堂 · 三层 · 林汇园餐厅" }
];

const postgraduateSourceKinds = [
  { value: "admission_notice", label: "招生简章" },
  { value: "major_catalog", label: "专业目录" },
  { value: "score_line", label: "复试线" },
  { value: "enrollment_plan", label: "招生计划" },
  { value: "bibliography", label: "参考书目" },
  { value: "retest", label: "复试" },
  { value: "registration", label: "报名" },
  { value: "other", label: "其他" }
];

const postgraduateTrustLevels = [
  { value: "official", label: "官方原文" },
  { value: "curated", label: "运营整理" },
  { value: "verified_user", label: "用户线索已核验" }
];

function AdminApp() {
  const [session, setSession] = useState<AdminSession | null>(() => readStoredSession());
  const [admin, setAdmin] = useState<AdminAccount | null>(() => readStoredSession()?.admin ?? null);
  const [activeView, setActiveView] = useState<ViewKey>("overview");
  const [isBooting, setIsBooting] = useState(true);
  const [message, setMessage] = useState<Message>(null);
  const [selectedCampusID, setSelectedCampusID] = useState("all");

  useEffect(() => {
    if (!session?.token) {
      setIsBooting(false);
      return;
    }

    fetchCurrentAdmin(session.token)
      .then((currentAdmin) => {
        setAdmin(currentAdmin);
        const nextSession = { ...session, admin: currentAdmin };
        setSession(nextSession);
        localStorage.setItem(storageKey, JSON.stringify(nextSession));
      })
      .catch(() => {
        clearSession();
      })
      .finally(() => setIsBooting(false));
  }, [session?.token]);

  const token = session?.token ?? "";

  const notify = useCallback((text: string, tone: MessageTone = "success") => {
    setMessage({ text, tone });
  }, []);

  const clearSession = useCallback(() => {
    localStorage.removeItem(storageKey);
    setSession(null);
    setAdmin(null);
  }, []);

  async function handleLogout() {
    if (session?.token) {
      await logout(session.token).catch(() => undefined);
    }
    clearSession();
  }

  if (isBooting) {
    return <main className="boot" role="status" aria-live="polite">加载后台...</main>;
  }

  if (!session || !admin) {
    return (
      <LoginScreen
        onLogin={(nextSession) => {
          localStorage.setItem(storageKey, JSON.stringify(nextSession));
          setSession(nextSession);
          setAdmin(nextSession.admin);
        }}
      />
    );
  }

  const availableViews = views.filter((view) => !view.superOnly || admin.role === "super_admin");
  const activeDefinition = availableViews.find((view) => view.key === activeView) ?? availableViews[0];
  const visibleGroups = navGroups
    .map((group) => ({ ...group, views: availableViews.filter((view) => view.group === group.key) }))
    .filter((group) => group.views.length > 0);

  return (
    <CampusScopeContext.Provider value={selectedCampusID}>
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark">L</span>
          <div>
            <strong>MyLeafy Admin</strong>
            <span>社区运营后台</span>
          </div>
        </div>
        <div className="admin-context" aria-label="当前后台">
          <span>生产后台</span>
          <strong>/admin</strong>
        </div>
        <div className="topbar-spacer" />
        <div className="account-box">
          <CampusSelector token={token} value={selectedCampusID} onChange={setSelectedCampusID} />
          <div>
            <strong>{admin.display_name}</strong>
            <span>{roleLabel(admin.role)}</span>
          </div>
          <button className="button secondary compact" onClick={() => void handleLogout()}>
            <LogOut aria-hidden="true" size={15} />
            退出
          </button>
        </div>
      </header>

      <aside className="icon-rail" aria-label="产品导航">
        <span className="rail-mark">L</span>
        <nav>
          {visibleGroups.map((group) => {
            const Icon = group.icon;
            const isActive = group.key === activeDefinition.group;
            return (
              <button
                key={group.key}
                className={isActive ? "active" : ""}
                type="button"
                aria-label={group.label}
                onClick={() => {
                  setActiveView(group.views[0].key);
                  setMessage(null);
                }}
              >
                <Icon aria-hidden="true" size={18} />
              </button>
            );
          })}
        </nav>
      </aside>

      <aside className="sidebar">
        <div className="sidebar-title">
          <strong>{navGroups.find((group) => group.key === activeDefinition.group)?.label}</strong>
          <span>MyLeafy Admin</span>
        </div>
        <nav className="nav-list">
          {visibleGroups.map((group) => (
            <div className="nav-section" key={group.key}>
              <p>{group.label}</p>
              {group.views.map((view) => {
                const Icon = view.icon;
                return (
                  <button
                    key={view.key}
                    className={view.key === activeDefinition.key ? "active" : ""}
                    onClick={() => {
                      setActiveView(view.key);
                      setMessage(null);
                    }}
                  >
                    <Icon aria-hidden="true" size={15} />
                    <span>{view.label}</span>
                  </button>
                );
              })}
            </div>
          ))}
        </nav>
      </aside>

      <main className="workspace">
        <section className="workspace-head">
          <div>
            <h1>{activeDefinition.label}</h1>
            <p>{activeDefinition.description}</p>
          </div>
        </section>

        {message && <div className={`notice ${message.tone}`} role={message.tone === "error" ? "alert" : "status"}>{message.text}</div>}

        <ViewRenderer
          view={activeDefinition.key}
          token={token}
          admin={admin}
          campusID={selectedCampusID}
          notify={notify}
          onSessionExpired={clearSession}
        />
      </main>
    </div>
    </CampusScopeContext.Provider>
  );
}

function LoginScreen({ onLogin }: { onLogin: (session: AdminSession) => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      onLogin(await login(username, password));
    } catch (loginError) {
      setError(loginError instanceof Error ? loginError.message : "登录失败。");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <main className="login-shell">
      <form className="login-panel" onSubmit={submit}>
        <p className="eyebrow">MyLeafy Admin</p>
        <h1>社区管理后台</h1>
        <label>
          账号
          <input value={username} onChange={(event) => setUsername(event.target.value)} autoComplete="username" required />
        </label>
        <label>
          密码
          <input
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            autoComplete="current-password"
            required
          />
        </label>
        <button className="button primary" disabled={isSubmitting} aria-busy={isSubmitting}>
          {isSubmitting ? <LoaderCircle aria-hidden="true" className="icon-spin" size={16} /> : <LogIn aria-hidden="true" size={16} />}
          {isSubmitting ? "登录中..." : "登录"}
        </button>
        {error && <div className="notice error" role="alert">{error}</div>}
      </form>
    </main>
  );
}

function ViewRenderer(props: {
  view: ViewKey;
  token: string;
  admin: AdminAccount;
  campusID: string;
  notify: (text: string, tone?: MessageTone) => void;
  onSessionExpired: () => void;
}) {
  switch (props.view) {
    case "overview":
      return <OverviewView {...props} />;
    case "manual":
      return <ManualView admin={props.admin} />;
    case "campuses":
      return <CampusesView {...props} />;
    case "posts":
      return <PostsView {...props} />;
    case "polls":
      return <PollsView {...props} />;
    case "comments":
      return <CommentsView {...props} />;
    case "reports":
      return <ReportsView {...props} />;
    case "profiles":
      return <ProfilesView {...props} />;
    case "feedback":
      return <FeedbackView {...props} />;
    case "announcements":
      return <AnnouncementsView {...props} />;
    case "postgraduate":
      return <PostgraduateInfoAdminView {...props} />;
    case "suggestions":
      return <CatalogSuggestionsView {...props} />;
    case "teachers":
      return <TeachersView {...props} />;
    case "courses":
      return <CoursesView {...props} />;
    case "dishes":
      return <DishesView {...props} />;
    case "ratings":
      return <RatingsView {...props} />;
    case "admins":
      return <AdminsView {...props} />;
    case "logs":
      return <LogsView {...props} />;
  }
}

function OverviewView({ token, admin }: ViewProps) {
  const [days, setDays] = useState(30);
  const timezone = useMemo(() => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC", []);
  const query = useMemo(() => ({ days, timezone }), [days, timezone]);
  const { data, isLoading, error, reload } = useAdminQuery<Row>(token, "overview", query);
  const summary = useMemo(() => overviewSummary(data), [data]);
  const operations = summary.operations ?? {};
  const moderation = summary.moderation ?? {};
  const feedback = summary.feedback ?? {};
  const content = summary.content ?? {};
  const teachers = summary.teachers ?? {};

  return (
    <section className="stack">
      <div className="panel-head">
        <div>
          <h2>运营总览</h2>
          <p>只展示需要运营动作的指标，趋势按 {timezone} 统计。</p>
        </div>
        <div className="segmented-actions" aria-label="趋势范围">
          {[7, 30, 90].map((value) => (
            <button
              key={value}
              className={days === value ? "active" : ""}
              onClick={() => setDays(value)}
              type="button"
            >
              {value} 天
            </button>
          ))}
          <button className="button secondary compact" onClick={reload} type="button">
            <RefreshCw aria-hidden="true" size={16} />
            刷新
          </button>
        </div>
      </div>
      {error && <div className="notice error" role="alert">{error}</div>}
      {isLoading ? (
        <div className="empty" role="status" aria-live="polite">加载数据中...</div>
      ) : (
        <>
          <section className="project-overview">
            <div className="project-summary">
              <div>
                <h2>今日运营重点</h2>
                <p>MyLeafy 社区运营后台 · {timezone} · {days} 天趋势窗口</p>
              </div>
              <span className="status-chip healthy">数据已加载</span>
            </div>
            <div className="project-health-grid">
              <ProjectHealthCard
                icon={LayoutDashboard}
                label="待处理"
                value={(Number(moderation.openReports ?? 0) + Number(feedback.open ?? 0)).toLocaleString("zh-CN")}
                meta={`${moderation.overdueReports ?? 0} 举报超时 · ${feedback.overdue ?? 0} 反馈超时`}
                accent="success"
              />
              <ProjectHealthCard
                icon={MessageSquare}
                label="今日内容"
                value={`${operations.postsToday ?? 0} 帖 / ${operations.commentsToday ?? 0} 评`}
                meta={`${days} 天 ${operations.postsInRange ?? 0} 帖`}
              />
              <ProjectHealthCard
                icon={Users}
                label="社区用户"
                value={Number(operations.totalProfiles ?? 0).toLocaleString("zh-CN")}
                meta={`完整资料 ${operations.activeProfiles ?? 0} · 今日新增 ${operations.newProfilesToday ?? 0}`}
              />
              <ProjectHealthCard
                icon={Star}
                label="评分反馈"
                value={`${teachers.average ?? 0} 分`}
                meta={`${teachers.totalRatings ?? 0} 次评分 · 低分关注 ${teachers.lowScoreTeachers?.length ?? 0}`}
              />
            </div>
          </section>
          <div className="stat-grid">
            <StatCard title="运营健康" value={operations.activeProfiles} detail={`今日 ${operations.postsToday ?? 0} 帖 / ${operations.commentsToday ?? 0} 评 · ${days} 天 ${operations.postsInRange ?? 0} 帖`} />
            <StatCard title="审核压力" value={moderation.openReports} detail={`超 24h ${moderation.overdueReports ?? 0} · 待审帖 ${moderation.pendingPosts ?? 0}`} />
            <StatCard title="反馈 SLA" value={feedback.open} detail={`超 3 天 ${feedback.overdue ?? 0} · ${days} 天关闭 ${feedback.closedInRange ?? 0}`} />
            <StatCard title="高互动内容" value={content.topPostCount} detail={`最高热度 ${content.leadingScore ?? 0} · 总帖子 ${content.postsTotal ?? 0}`} />
            <StatCard title="教师评分" value={teachers.average} detail={`${teachers.totalRatings ?? 0} 次评分 · 低分关注 ${teachers.lowScoreTeachers?.length ?? 0}`} />
          </div>
          <div className="analytics-grid">
            <section className="panel analytics-panel wide">
              <div className="panel-title-row">
                <div>
                  <h2>运营趋势</h2>
                  <p>{days} 天内有效用户、帖子、评论、反馈和评分新增走势。</p>
                </div>
              </div>
              <TrendChart data={operations.daily ?? []} />
            </section>
            <section className="panel analytics-panel">
              <h2>审核压力</h2>
              <p>待处理、超时和近期处置量集中在这里。</p>
              <ModerationSummary data={moderation} showRecent={admin.role === "super_admin"} />
            </section>
          </div>
          <section className="panel service-health-panel">
            <div className="panel-title-row">
              <div>
                <h2>处理优先级</h2>
                <p>把待处理、超时和高互动内容放在同一视线内，方便决定下一步动作。</p>
              </div>
            </div>
            <div className="service-health-list">
              <ServiceHealthRow name="举报队列" value={`${moderation.openReports ?? 0} 待处理`} detail={`${moderation.overdueReports ?? 0} 超 24h · 待审帖子 ${moderation.pendingPosts ?? 0}`} />
              <ServiceHealthRow name="反馈处理" value={`${feedback.open ?? 0} 待处理`} detail={`${feedback.overdue ?? 0} 超 3 天 · ${days} 天关闭 ${feedback.closedInRange ?? 0}`} />
              <ServiceHealthRow name="内容巡检" value={`${content.topPostCount ?? 0} 高互动`} detail={`最高热度 ${content.leadingScore ?? 0} · 总帖子 ${content.postsTotal ?? 0}`} />
              <ServiceHealthRow name="账号状态" value={`${moderation.mutedProfiles ?? 0} 禁言中`} detail={`社区用户 ${operations.totalProfiles ?? 0} · 今日新增 ${operations.newProfilesToday ?? 0}`} />
            </div>
          </section>
          <div className="analytics-grid four">
            <section className="panel analytics-panel">
              <h2>反馈老化</h2>
              <FeedbackAging data={feedback.aging ?? []} />
            </section>
            <section className="panel analytics-panel">
              <h2>教师评分</h2>
              <TeacherRatingBars data={teachers} />
            </section>
            <section className="panel analytics-panel wide-card">
              <h2>低分关注</h2>
              <TeacherWatchList data={teachers.lowScoreTeachers ?? []} />
            </section>
          </div>
          <div className="two-column">
            <section className="panel">
              <h2>高互动帖子</h2>
              <SimpleList
                items={content.topPosts ?? []}
                primary={(item) => item.title}
                secondary={(item) => `${item.score ?? 0} 热度 · ${item.comment_count ?? 0} 评 · ${item.like_count ?? 0} 赞`}
              />
            </section>
            <section className="panel">
              <h2>最新反馈</h2>
              <SimpleList
                items={data?.recentFeedback ?? []}
                primary={(item) => item.issue_type}
                secondary={(item) => `${statusLabel(item.status)} · ${brief(item.body, 72)}`}
              />
            </section>
          </div>
          {admin.role === "super_admin" && (
            <section className="panel">
              <h2>高风险操作</h2>
              <SimpleList
                items={moderation.recentRiskActions ?? []}
                primary={(item) => riskActionLabel(item.action)}
                secondary={(item) => `${item.admin?.display_name ?? "管理员"} · ${[item.target_type, item.target_id].filter(Boolean).join(" / ") || "无目标"} · ${formatDate(item.created_at)}`}
              />
            </section>
          )}
        </>
      )}
    </section>
  );
}

function ManualView({ admin }: { admin: AdminAccount }) {
  const dailyFlow = [
    "先看总览，确认待处理举报、待审帖子、未关闭反馈和今日新增内容。",
    "进入举报队列，优先处理超过 24 小时的举报；必要时同时下架目标内容并禁言用户。",
    "进入帖子和评论页，按状态、日期和关键词补查内容；批量操作前先确认选择数量。",
    "反馈处理后写入备注，再标记已看或关闭；公告发布前确认级别、发布时间和过期时间。",
    "超级管理员定期查看日志，核对置顶、下架、禁言、管理员变更等高风险动作。"
  ];
  const pinRules = [
    "只有已发布帖子可以置顶，待审核、已下架或用户删除的帖子不能置顶。",
    "全局置顶会进入全社区 Feed 顶部；分类置顶只在对应分类 Feed 顶部生效。",
    "优先级越大越靠前；优先级相同时，开始时间更新的置顶更靠前。",
    "开始时间留空时服务端按当前时间生效；结束时间留空表示长期有效。",
    "完成置顶或取消置顶后，用帖子页底部的客户端 Feed 预览检查 App 实际排序。"
  ];
  const permissions = [
    ["只读", "可以查看总览和列表，不能执行写操作。"],
    ["运营", "可以审核帖子/评论、置顶、处理举报、禁言、处理反馈和维护公告。"],
    ["超级管理员", "额外可以管理后台账号，并查看完整审计日志。"]
  ];

  return (
    <section className="stack">
      <section className="manual-hero">
        <div>
          <p className="eyebrow">Operator Manual</p>
          <h2>后台操作说明书</h2>
          <p>当前账号是 {roleLabel(admin.role)}。所有写操作都通过 Edge Function 执行，并记录到审计日志。</p>
        </div>
        <div className="manual-callout">
          <strong>置顶验证路径</strong>
          <span>帖子页置顶到客户端 Feed 预览，再到 iOS 社区列表置顶标识</span>
        </div>
      </section>

      <div className="manual-grid">
        <section className="panel guide-card">
          <h2>日常处理顺序</h2>
          <ol className="guide-list ordered">
            {dailyFlow.map((item) => <li key={item}>{item}</li>)}
          </ol>
        </section>

        <section className="panel guide-card">
          <h2>置顶操作</h2>
          <ul className="guide-list">
            {pinRules.map((item) => <li key={item}>{item}</li>)}
          </ul>
        </section>

        <section className="panel guide-card">
          <h2>权限边界</h2>
          <div className="permission-list">
            {permissions.map(([role, detail]) => (
              <article key={role}>
                <strong>{role}</strong>
                <span>{detail}</span>
              </article>
            ))}
          </div>
        </section>

        <section className="panel guide-card">
          <h2>常用动作速查</h2>
          <div className="quick-actions">
            <div><strong>下架内容</strong><span>帖子 / 评论页输入原因后执行，原因进入审核字段和日志参数。</span></div>
            <div><strong>禁言用户</strong><span>用户页或举报处理时设置截止时间；留存原因，避免只写模糊描述。</span></div>
            <div><strong>公告发布</strong><span>普通、重要、紧急三级；可先存草稿，确认后发布或下线。</span></div>
            <div><strong>账号管理</strong><span>只给必要人员开通运营或只读账号，超级管理员数量保持最少。</span></div>
          </div>
        </section>
      </div>
    </section>
  );
}

function CampusSelector({ token, value, onChange }: { token: string; value: string; onChange: (value: string) => void }) {
  const { data } = useAdminQuery<ListResult>(token, "listCampuses", { status: "all" });
  const campuses = data?.items ?? [];

  return (
    <label className="campus-selector">
      学校空间
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="all">全部学校</option>
        {campuses
          .filter((campus) => campus.id !== "general")
          .map((campus) => (
            <option key={campus.id} value={campus.id}>
              {campus.display_name}
            </option>
          ))}
      </select>
    </label>
  );
}

function CampusesView(props: ViewProps) {
  const [status, setStatus] = useState("pending");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const [pageSize, setPageSize] = useState(20);
  const query = useMemo(() => ({ status, search, page, pageSize }), [status, search, page, pageSize]);
  const requests = useAdminQuery<ListResult>(props.token, "listCampusRequests", query);
  const campuses = useAdminQuery<ListResult>(props.token, "listCampuses", { status: "all" });

  const reload = () => {
    requests.reload();
    campuses.reload();
  };

  async function approveAsNew(item: Row) {
    const displayName = window.prompt("学校显示名称", item.school_name);
    if (displayName === null) return;
    await runMutation(props, "approveCampusRequest", { id: item.id, displayName }, "学校申请已通过。", reload);
  }

  async function approveWithExisting(item: Row) {
    const campusID = window.prompt("输入已有学校 campus id", "");
    if (!campusID) return;
    await runMutation(props, "approveCampusRequest", { id: item.id, campusID }, "学校申请已关联到已有学校。", reload);
  }

  async function approveSchoolChange(item: Row) {
    await runMutation(
      props,
      "approveCampusRequest",
      { id: item.id, campusID: item.requested_campus_id },
      "学校更换申请已通过。",
      reload
    );
  }

  async function reject(item: Row) {
    const note = window.prompt("拒绝原因", "学校信息暂无法核验。");
    if (note === null) return;
    await runMutation(props, "rejectCampusRequest", { id: item.id, note }, "学校申请已拒绝。", reload);
  }

  return (
    <section className="stack">
      <section className="panel">
        <ResourceHeader title="学校归属申请" total={requests.data?.total} onReload={requests.reload}>
          <select value={status} onChange={(event) => { setStatus(event.target.value); setPage(0); }}>
            <option value="pending">待审核</option>
            <option value="approved">已通过</option>
            <option value="rejected">已拒绝</option>
            <option value="all">全部</option>
          </select>
          <input value={search} onChange={(event) => { setSearch(event.target.value); setPage(0); }} placeholder="搜索学校或备注" />
        </ResourceHeader>
        <DataState isLoading={requests.isLoading} error={requests.error} empty={!requests.data?.items?.length} />
        {requests.data?.items?.length ? (
          <table>
            <thead><tr><th>类型</th><th>学校</th><th>用户</th><th>状态</th><th>审核备注</th><th>时间</th><th>操作</th></tr></thead>
            <tbody>
              {requests.data.items.map((item) => {
                const isBJFURequest = isBJFUSchoolName(item.school_name);
                const isSchoolChange = item.request_type === "school_change";
                return (
                  <tr key={item.id}>
                    <td>{isSchoolChange ? "更换学校" : "新增学校"}</td>
                    <td>
                      <strong>{isSchoolChange ? `${item.from_campus_id ?? "当前学校"} → ${item.school_name}` : item.school_name}</strong>
                      <span>{isSchoolChange ? `目标 campus: ${item.requested_campus_id ?? "未记录"}` : item.normalized_school_name}</span>
                      {isBJFURequest && <small>北林用户请使用北京林业大学专属入口</small>}
                    </td>
                    <td>{item.requester ? profileName(item.requester) : item.requester_profile_id}</td>
                    <td><span className={`pill ${item.status}`}>{statusLabel(item.status)}</span></td>
                    <td>{item.admin_note ?? "无"}</td>
                    <td>{formatDate(item.created_at)}</td>
                    <td>
                      {item.status === "pending" ? (
                        <div className="actions">
                          {isSchoolChange ? (
                            <button type="button" onClick={() => void approveSchoolChange(item)}>批准更换</button>
                          ) : (
                            <>
                              {!isBJFURequest && <button type="button" onClick={() => void approveAsNew(item)}>批准为新学校</button>}
                              {!isBJFURequest && <button type="button" onClick={() => void approveWithExisting(item)}>关联已有</button>}
                            </>
                          )}
                          <button type="button" className="danger" onClick={() => void reject(item)}>拒绝</button>
                        </div>
                      ) : (
                        <span className="muted-note">{item.approved_campus_id ?? "通用模式"}</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        ) : null}
        <Pagination
          page={page}
          pageSize={pageSize}
          total={requests.data?.total ?? 0}
          onPage={setPage}
          onPageSize={(nextPageSize) => { setPageSize(nextPageSize); setPage(0); }}
        />
      </section>

      <section className="panel">
        <ResourceHeader title="学校空间" total={campuses.data?.total} onReload={campuses.reload} />
        <DataState isLoading={campuses.isLoading} error={campuses.error} empty={!campuses.data?.items?.length} />
        {campuses.data?.items?.length ? (
          <table>
            <thead><tr><th>ID</th><th>学校</th><th>连接器</th><th>社区</th><th>状态</th></tr></thead>
            <tbody>
              {campuses.data.items.map((campus) => (
                <tr key={campus.id}>
                  <td><code>{campus.id}</code></td>
                  <td><strong>{campus.display_name}</strong><span>{campus.short_name}</span></td>
                  <td>{campus.connector_kind}</td>
                  <td>{campus.is_community_enabled ? "已开放" : "未开放"}</td>
                  <td><span className={`pill ${campus.status}`}>{statusLabel(campus.status)}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
      </section>
    </section>
  );
}

function PostsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "published", start: "", end: "", page: 0, pageSize: 20 });
  const [feedPreviewFilters, setFeedPreviewFilters] = useState({ search: "", category: "", limit: 20 });
  const [selected, setSelected] = useState<Row | null>(null);
  const [selectedIDs, setSelectedIDs] = useState<string[]>([]);
  const [pinDialog, setPinDialog] = useState<PinDialogState>(null);
  const query = useMemo(() => ({ ...filters, status: filters.status || "all" }), [filters]);
  const feedPreviewQuery = useMemo(() => ({
    search: feedPreviewFilters.search,
    category: feedPreviewFilters.category,
    limit: feedPreviewFilters.limit
  }), [feedPreviewFilters]);
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listPosts", query);
  const {
    data: feedPreview,
    isLoading: isFeedPreviewLoading,
    error: feedPreviewError,
    reload: reloadFeedPreview
  } = useAdminQuery<Row>(props.token, "previewCommunityFeed", feedPreviewQuery);
  const visibleIDs = useMemo(() => (data?.items ?? []).map((item) => String(item.id)), [data?.items]);

  useEffect(() => {
    setSelectedIDs((ids) => ids.filter((id) => visibleIDs.includes(id)));
  }, [visibleIDs.join("|")]);

  async function moderate(id: string, status: "hidden" | "published") {
    const reason = status === "hidden" ? window.prompt("下架原因", "违反社区规范") : null;
    if (status === "hidden" && reason === null) return;
    await runMutation(props, "moderatePost", { id, status, reason }, status === "hidden" ? "帖子已下架。" : "帖子已恢复。", reload);
  }

  async function bulkModerate(status: "hidden" | "published") {
    if (!selectedIDs.length) {
      props.notify("请先选择帖子。", "error");
      return;
    }
    const reason = status === "hidden" ? window.prompt("批量下架原因", "违反社区规范") : null;
    if (status === "hidden" && reason === null) return;
    await runMutation(
      props,
      "bulkModeratePosts",
      { ids: selectedIDs, status, reason },
      status === "hidden" ? "已批量下架帖子。" : "已批量恢复帖子。",
      () => {
        setSelectedIDs([]);
        reload();
      }
    );
  }

  function openPinDialog(post: Row, scope: PinScope) {
    setPinDialog({ post, scope });
  }

  async function submitPin(payload: Record<string, unknown>, scope: PinScope) {
    return runMutation(
      props,
      "pinPost",
      payload,
      scope === "global" ? "帖子已全局置顶。" : "帖子已分类置顶。",
      () => {
        setPinDialog(null);
        reload();
        reloadFeedPreview();
      }
    );
  }

  async function unpin(post: Row) {
    const pin = post.pin;
    if (!pin) {
      props.notify("该帖子当前没有置顶。", "error");
      return;
    }
    if (!window.confirm(`取消${pinScopeLabel(pin.scope)}？`)) return;
    await runMutation(props, "unpinPost", { id: pin.id, postID: post.id }, "已取消置顶。", () => {
      reload();
      reloadFeedPreview();
    });
  }

  async function openDetail(row: Row) {
    try {
      setSelected(await adminAction<Row>(props.token, "getPost", { id: row.id }));
    } catch (detailError) {
      props.notify(errorText(detailError), "error");
    }
  }

  return (
    <section className="panel">
      <ResourceHeader title="帖子管理" total={data?.total} onReload={reload}>
        <input placeholder="标题、正文、分类" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="published">已发布</option>
          <option value="pending_review">待审核</option>
          <option value="hidden">已下架</option>
          <option value="deleted">用户删除</option>
          <option value="all">全部</option>
        </select>
      </ResourceHeader>
      <BulkBar count={selectedIDs.length} onClear={() => setSelectedIDs([])}>
        <button className="danger" type="button" onClick={() => void bulkModerate("hidden")}>批量下架</button>
        <button type="button" onClick={() => void bulkModerate("published")}>批量恢复</button>
      </BulkBar>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th className="select-col">
                <input
                  aria-label="选择当前页帖子"
                  type="checkbox"
                  checked={visibleIDs.length > 0 && visibleIDs.every((id) => selectedIDs.includes(id))}
                  onChange={(event) => setSelectedIDs(event.target.checked ? visibleIDs : [])}
                />
              </th>
              <th>标题</th>
              <th>作者</th>
              <th>状态</th>
              <th>互动</th>
              <th>时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((post) => (
              <tr key={post.id}>
                <td className="select-col">
                  <input
                    aria-label={`选择帖子 ${post.title}`}
                    type="checkbox"
                    checked={selectedIDs.includes(String(post.id))}
                    onChange={(event) => {
                      const id = String(post.id);
                      setSelectedIDs((ids) => event.target.checked ? uniqueStrings([...ids, id]) : ids.filter((item) => item !== id));
                    }}
                  />
                </td>
                <td>
                  <strong>{post.title}</strong>
                  <span>{brief(post.body, 88)}</span>
                </td>
                <td>{post.is_anonymous ? "匿名同学" : profileName(post.author)}</td>
                <td>
                  <StatusPill status={post.status} />
                  {post.pin && <span className="pin-note">{pinScopeLabel(post.pin.scope)} · P{post.pin.priority ?? 0}</span>}
                </td>
                <td>{post.comment_count ?? 0} 评 · {post.like_count ?? 0} 赞</td>
                <td>{formatDate(post.created_at)}</td>
                <td className="actions">
                  <button onClick={() => void openDetail(post)}>详情</button>
                  {post.status === "published" && (
                    <>
                      <button onClick={() => openPinDialog(post, "global")}>全局置顶</button>
                      <button onClick={() => openPinDialog(post, "category")}>分类置顶</button>
                      {post.pin && <button onClick={() => void unpin(post)}>取消置顶</button>}
                    </>
                  )}
                  {post.status === "published" ? (
                    <button className="danger" onClick={() => void moderate(post.id, "hidden")}>下架</button>
                  ) : post.status === "pending_review" ? (
                    <>
                      <button onClick={() => void moderate(post.id, "published")}>通过</button>
                      <button className="danger" onClick={() => void moderate(post.id, "hidden")}>下架</button>
                    </>
                  ) : post.status === "hidden" ? (
                    <button onClick={() => void moderate(post.id, "published")}>恢复</button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
      {selected && (
        <PostDrawer
          data={selected}
          onClose={() => setSelected(null)}
          onPinGlobal={(post) => openPinDialog(post, "global")}
          onPinCategory={(post) => openPinDialog(post, "category")}
          onUnpin={(post) => void unpin(post)}
        />
      )}
      {pinDialog && (
        <PinPostDialog
          state={pinDialog}
          onClose={() => setPinDialog(null)}
          onSubmit={submitPin}
        />
      )}
      <section className="feed-preview-panel">
        <div className="panel-title-row">
          <div>
            <h2>客户端 Feed 预览</h2>
            <p>使用社区客户端同一套 RPC 输出，检查置顶、分类和搜索最终排序。</p>
          </div>
          <div className="filters">
            <input
              placeholder="搜索标题、正文、分类"
              value={feedPreviewFilters.search}
              onChange={(event) => setFeedPreviewFilters({ ...feedPreviewFilters, search: event.target.value })}
            />
            <input
              placeholder="分类"
              value={feedPreviewFilters.category}
              onChange={(event) => setFeedPreviewFilters({ ...feedPreviewFilters, category: event.target.value })}
            />
            <select
              aria-label="Feed 数量"
              value={feedPreviewFilters.limit}
              onChange={(event) => setFeedPreviewFilters({ ...feedPreviewFilters, limit: Number(event.target.value) })}
            >
              {[10, 20, 30, 50].map((value) => <option key={value} value={value}>{value}</option>)}
            </select>
            <button className="button secondary" type="button" onClick={reloadFeedPreview}>
              <RefreshCw aria-hidden="true" size={16} />
              预览
            </button>
          </div>
        </div>
        <DataState isLoading={isFeedPreviewLoading} error={feedPreviewError} empty={!feedPreview?.posts?.length} />
        {feedPreview?.posts?.length ? (
          <div className="feed-preview-list">
            {feedPreview.posts.map((post: Row, index: number) => (
              <article key={post.id ?? index} className="feed-preview-item">
                <div>
                  <span className="feed-rank">#{index + 1}</span>
                  {post.pin && <span className="pin-note">{pinScopeLabel(post.pin.scope)} · P{post.pin.priority ?? 0}</span>}
                </div>
                <strong>{post.title}</strong>
                <p>{brief(post.body, 120)}</p>
                <small>
                  {[post.category || "社区", profileName(post.author), `${post.comment_count ?? 0} 评`, `${post.like_count ?? 0} 赞`, formatDate(post.created_at)]
                    .filter(Boolean)
                    .join(" · ")}
                </small>
              </article>
            ))}
          </div>
        ) : null}
      </section>
    </section>
  );
}

function PollsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "pending", start: "", end: "", page: 0, pageSize: 20 });
  const [selected, setSelected] = useState<Row | null>(null);
  const query = useMemo(() => ({ ...filters, status: filters.status || "all" }), [filters]);
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listPolls", query);

  async function moderate(id: string, status: "hidden" | "published") {
    const reason = status === "hidden" ? window.prompt("驳回或下架原因", "不符合社区投票规范") : null;
    if (status === "hidden" && reason === null) return;
    await runMutation(props, "moderatePoll", { id, status, reason }, status === "hidden" ? "投票已隐藏。" : "投票已通过。", reload);
  }

  async function reviewDeletion(id: string, decision: "approved" | "rejected") {
    const reason = window.prompt(decision === "approved" ? "批准删除原因" : "拒绝删除原因", decision === "approved" ? "用户申请删除" : "删除申请不成立");
    if (reason === null) return;
    await runMutation(
      props,
      "reviewPollDeletion",
      { id, decision, reason },
      decision === "approved" ? "删除申请已批准。" : "删除申请已拒绝。",
      reload
    );
  }

  async function openDetail(row: Row) {
    try {
      setSelected(await adminAction<Row>(props.token, "getPoll", { id: row.id }));
    } catch (detailError) {
      props.notify(errorText(detailError), "error");
    }
  }

  return (
    <section className="panel">
      <ResourceHeader title="投票审核" total={data?.total} onReload={reload}>
        <input placeholder="问题、说明" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="pending">待处理</option>
          <option value="pending_review">待发布审核</option>
          <option value="published">已发布</option>
          <option value="hidden">已隐藏</option>
          <option value="deleted">已删除</option>
          <option value="all">全部</option>
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th>问题</th>
              <th>作者</th>
              <th>状态</th>
              <th>票数</th>
              <th>选项统计</th>
              <th>时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((poll) => (
              <tr key={poll.id}>
                <td>
                  <strong>{poll.question}</strong>
                  {poll.detail && <span>{brief(poll.detail, 88)}</span>}
                </td>
                <td>{profileName(poll.author)}</td>
                <td>
                  <StatusPill status={poll.status} />
                  {poll.deletion_status && poll.deletion_status !== "none" && <StatusPill status={`deletion_${poll.deletion_status}`} />}
                  {poll.moderator && <span>{profileName(poll.moderator)}</span>}
                </td>
                <td>{poll.total_vote_count ?? 0} 票</td>
                <td>{pollOptionSummary(poll)}</td>
                <td>{formatDate(poll.created_at)}</td>
                <td className="actions">
                  <button onClick={() => void openDetail(poll)}>详情</button>
                  {poll.status === "pending_review" ? (
                    <>
                      <button onClick={() => void moderate(poll.id, "published")}>通过</button>
                      <button className="danger" onClick={() => void moderate(poll.id, "hidden")}>驳回</button>
                    </>
                  ) : poll.status === "published" ? (
                    <button className="danger" onClick={() => void moderate(poll.id, "hidden")}>隐藏</button>
                  ) : poll.status === "hidden" ? (
                    <button onClick={() => void moderate(poll.id, "published")}>恢复</button>
                  ) : null}
                  {poll.deletion_status === "pending" ? (
                    <>
                      <button className="danger" onClick={() => void reviewDeletion(poll.id, "approved")}>批准删除</button>
                      <button onClick={() => void reviewDeletion(poll.id, "rejected")}>拒绝删除</button>
                    </>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
      {selected && <PollDrawer data={selected} onClose={() => setSelected(null)} />}
    </section>
  );
}

function CommentsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "published", start: "", end: "", page: 0, pageSize: 20 });
  const [selectedIDs, setSelectedIDs] = useState<string[]>([]);
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listComments", filters);
  const visibleIDs = useMemo(() => (data?.items ?? []).map((item) => String(item.id)), [data?.items]);

  useEffect(() => {
    setSelectedIDs((ids) => ids.filter((id) => visibleIDs.includes(id)));
  }, [visibleIDs.join("|")]);

  async function moderate(id: string, status: "hidden" | "published") {
    const reason = status === "hidden" ? window.prompt("下架原因", "违反社区规范") : null;
    if (status === "hidden" && reason === null) return;
    await runMutation(props, "moderateComment", { id, status, reason }, status === "hidden" ? "评论已下架。" : "评论已恢复。", reload);
  }

  async function bulkModerate(status: "hidden" | "published") {
    if (!selectedIDs.length) {
      props.notify("请先选择评论。", "error");
      return;
    }
    const reason = status === "hidden" ? window.prompt("批量下架原因", "违反社区规范") : null;
    if (status === "hidden" && reason === null) return;
    await runMutation(
      props,
      "bulkModerateComments",
      { ids: selectedIDs, status, reason },
      status === "hidden" ? "已批量下架评论。" : "已批量恢复评论。",
      () => {
        setSelectedIDs([]);
        reload();
      }
    );
  }

  return (
    <section className="panel">
      <ResourceHeader title="评论管理" total={data?.total} onReload={reload}>
        <input placeholder="评论内容" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="published">已发布</option>
          <option value="pending_review">待审核</option>
          <option value="hidden">已下架</option>
          <option value="deleted">用户删除</option>
          <option value="all">全部</option>
        </select>
      </ResourceHeader>
      <BulkBar count={selectedIDs.length} onClear={() => setSelectedIDs([])}>
        <button className="danger" type="button" onClick={() => void bulkModerate("hidden")}>批量下架</button>
        <button type="button" onClick={() => void bulkModerate("published")}>批量恢复</button>
      </BulkBar>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th className="select-col">
                <input
                  aria-label="选择当前页评论"
                  type="checkbox"
                  checked={visibleIDs.length > 0 && visibleIDs.every((id) => selectedIDs.includes(id))}
                  onChange={(event) => setSelectedIDs(event.target.checked ? visibleIDs : [])}
                />
              </th>
              <th>内容</th>
              <th>作者</th>
              <th>帖子</th>
              <th>状态</th>
              <th>时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((comment) => (
              <tr key={comment.id}>
                <td className="select-col">
                  <input
                    aria-label={`选择评论 ${brief(comment.body, 20)}`}
                    type="checkbox"
                    checked={selectedIDs.includes(String(comment.id))}
                    onChange={(event) => {
                      const id = String(comment.id);
                      setSelectedIDs((ids) => event.target.checked ? uniqueStrings([...ids, id]) : ids.filter((item) => item !== id));
                    }}
                  />
                </td>
                <td>{brief(comment.body, 110)}</td>
                <td>{comment.is_anonymous ? "匿名同学" : profileName(comment.author)}</td>
                <td>{comment.post?.title ?? "帖子不可见"}</td>
                <td><StatusPill status={comment.status} /></td>
                <td>{formatDate(comment.created_at)}</td>
                <td className="actions">
                  {comment.status === "published" ? (
                    <button className="danger" onClick={() => void moderate(comment.id, "hidden")}>下架</button>
                  ) : comment.status === "pending_review" ? (
                    <>
                      <button onClick={() => void moderate(comment.id, "published")}>通过</button>
                      <button className="danger" onClick={() => void moderate(comment.id, "hidden")}>下架</button>
                    </>
                  ) : comment.status === "hidden" ? (
                    <button onClick={() => void moderate(comment.id, "published")}>恢复</button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

function ReportsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "open", targetType: "all", start: "", end: "", page: 0, pageSize: 20 });
  const query = useMemo(() => ({ ...filters }), [filters]);
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listModerationReports", query);

  async function resolve(item: Row, status: "reviewed" | "resolved" | "rejected", options: Record<string, unknown> = {}) {
    const defaultNote = status === "resolved" ? "举报成立，已处理违规内容。" : status === "rejected" ? "举报不成立。" : "已查看举报。";
    const resolutionNote = window.prompt("处理备注", defaultNote);
    if (resolutionNote === null) return;

    await runMutation(
      props,
      "resolveModerationReport",
      { id: item.id, status, resolutionNote, ...options },
      "举报状态已更新。",
      reload
    );
  }

  async function resolveAndMute(item: Row) {
    const mutedUntil = window.prompt("禁言截止时间，留空默认 365 天", "");
    await resolve(item, "resolved", {
      hideContent: true,
      muteUser: true,
      ...(mutedUntil ? { mutedUntil } : {})
    });
  }

  return (
    <section className="panel">
      <ResourceHeader title="举报处理" total={data?.total} onReload={reload}>
        <input placeholder="原因、详情、处理备注" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="open">待处理</option>
          <option value="reviewed">已查看</option>
          <option value="resolved">已处理</option>
          <option value="rejected">已驳回</option>
          <option value="all">全部</option>
        </select>
        <select value={filters.targetType} onChange={(event) => setFilters({ ...filters, targetType: event.target.value, page: 0 })}>
          <option value="all">全部类型</option>
          <option value="post">帖子</option>
          <option value="comment">评论</option>
          <option value="user">用户</option>
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th>举报对象</th>
              <th>原因</th>
              <th>举报人</th>
              <th>被举报用户</th>
              <th>SLA</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((item) => (
              <tr key={item.id}>
                <td>
                  <strong>{reportTargetLabel(item)}</strong>
                  <span>{reportTargetBody(item)}</span>
                </td>
                <td>
                  <strong>{item.reason}</strong>
                  <span>{item.detail || "无补充说明"}</span>
                </td>
                <td>{profileName(item.reporter)}</td>
                <td>{item.reported_user ? profileName(item.reported_user) : "未知"}</td>
                <td>{reportSlaText(item.created_at)}</td>
                <td><StatusPill status={item.status} /></td>
                <td className="actions">
                  <button onClick={() => void resolve(item, "reviewed", { hideContent: false })}>已看</button>
                  <button className="danger" onClick={() => void resolve(item, "resolved", { hideContent: true })}>下架并关闭</button>
                  <button className="danger" onClick={() => void resolveAndMute(item)}>下架并禁言</button>
                  <button onClick={() => void resolve(item, "rejected", { hideContent: false })}>驳回</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

function ProfilesView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", muted: "", start: "", end: "", page: 0, pageSize: 20 });
  const [selected, setSelected] = useState<Row | null>(null);
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listProfiles", filters);

  async function mute(profile: Row) {
    const mutedUntil = window.prompt("禁言截止时间，例如 2026-05-01 18:00", "");
    if (!mutedUntil) return;
    const reason = window.prompt("禁言原因", "社区发言违规");
    if (reason === null) return;
    await runMutation(props, "muteProfile", { id: profile.id, mutedUntil, reason }, "用户已禁言。", reload);
  }

  async function unmute(profile: Row) {
    if (!window.confirm(`解除 ${profileName(profile)} 的禁言？`)) return;
    await runMutation(props, "unmuteProfile", { id: profile.id }, "禁言已解除。", reload);
  }

  async function openProfile(profile: Row) {
    try {
      setSelected(await adminAction<Row>(props.token, "getProfile", { id: profile.id }));
    } catch (detailError) {
      props.notify(errorText(detailError), "error");
    }
  }

  return (
    <section className="panel">
      <ResourceHeader title="用户资料" total={data?.total} onReload={reload}>
        <input placeholder="学号、昵称、实名、邮箱" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.muted} onChange={(event) => setFilters({ ...filters, muted: event.target.value, page: 0 })}>
          <option value="">全部用户</option>
          <option value="active">禁言中</option>
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th>用户</th>
              <th>学号</th>
              <th>资料</th>
              <th>内容</th>
              <th>禁言</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((profile) => (
              <tr key={profile.id}>
                <td>
                  <strong>{profileName(profile)}</strong>
                  <span>{profile.bound_email || profile.pending_bound_email || "未绑定邮箱"}</span>
                </td>
                <td>{profile.edu_id}</td>
                <td>{profile.is_profile_complete ? "已完善" : "未完善"}</td>
                <td>{profile.post_count ?? 0} 帖 · {profile.comment_count ?? 0} 评</td>
                <td>{profile.is_muted ? `至 ${formatDate(profile.muted_until)}` : "正常"}</td>
                <td className="actions">
                  <button onClick={() => void openProfile(profile)}>详情</button>
                  {profile.is_muted ? (
                    <button onClick={() => void unmute(profile)}>解禁</button>
                  ) : (
                    <button className="danger" onClick={() => void mute(profile)}>禁言</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
      {selected && <ProfileDrawer data={selected} onClose={() => setSelected(null)} />}
    </section>
  );
}

function FeedbackView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "open", start: "", end: "", page: 0, pageSize: 20 });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listFeedback", filters);

  async function update(item: Row, status: string) {
    const adminNote = window.prompt("处理备注", item.admin_note ?? "");
    if (adminNote === null) return;
    await runMutation(props, "updateFeedback", { id: item.id, status, adminNote }, "反馈状态已更新。", reload);
  }

  return (
    <section className="panel">
      <ResourceHeader title="反馈处理" total={data?.total} onReload={reload}>
        <input placeholder="反馈内容、联系方式" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="open">待处理</option>
          <option value="reviewed">已查看</option>
          <option value="closed">已关闭</option>
          <option value="all">全部</option>
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead>
            <tr>
              <th>类型</th>
              <th>内容</th>
              <th>用户</th>
              <th>状态</th>
              <th>提交时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {data.items.map((item) => (
              <tr key={item.id}>
                <td>{item.issue_type}</td>
                <td>
                  <strong>{brief(item.body, 120)}</strong>
                  <span>{item.contact || "未留联系方式"}</span>
                </td>
                <td>{item.user ? profileName(item.user) : "匿名会话"}</td>
                <td><StatusPill status={item.status} /></td>
                <td>{formatDate(item.created_at)}</td>
                <td className="actions">
                  <button onClick={() => void update(item, "reviewed")}>已看</button>
                  <button onClick={() => void update(item, "closed")}>关闭</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

function AnnouncementsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "all" });
  const [form, setForm] = useState({
    title: "",
    body: "",
    level: "info",
    status: "published",
    publishedAt: "",
    expiresAt: ""
  });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listAnnouncements", filters);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(
      props,
      "createAnnouncement",
      {
        title: form.title,
        body: form.body,
        level: form.level,
        status: form.status,
        publishedAt: form.publishedAt,
        expiresAt: form.expiresAt
      },
      form.status === "draft" ? "公告草稿已保存。" : "公告已发布。",
      () => {
        setForm({ title: "", body: "", level: "info", status: "published", publishedAt: "", expiresAt: "" });
        reload();
      }
    );
  }

  async function updateStatus(item: Row, status: string) {
    await runMutation(props, "updateAnnouncement", { id: item.id, status }, "公告状态已更新。", reload);
  }

  return (
    <div className="split-layout">
      <form className="panel composer" onSubmit={submit}>
        <h2>发布公告</h2>
        <label>标题<input value={form.title} maxLength={120} onChange={(event) => setForm({ ...form, title: event.target.value })} required /></label>
        <label>正文<textarea value={form.body} rows={8} maxLength={4000} onChange={(event) => setForm({ ...form, body: event.target.value })} required /></label>
        <div className="form-grid">
          <label>级别<select value={form.level} onChange={(event) => setForm({ ...form, level: event.target.value })}><option value="info">普通</option><option value="warning">重要</option><option value="urgent">紧急</option></select></label>
          <label>状态<select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="published">立即发布</option><option value="draft">保存草稿</option></select></label>
        </div>
        <div className="form-grid">
          <label>发布时间<input type="datetime-local" value={form.publishedAt} onChange={(event) => setForm({ ...form, publishedAt: event.target.value })} /></label>
          <label>过期时间<input type="datetime-local" value={form.expiresAt} onChange={(event) => setForm({ ...form, expiresAt: event.target.value })} /></label>
        </div>
        <button className="button primary">提交公告</button>
      </form>
      <section className="panel">
        <ResourceHeader title="公告列表" total={data?.total} onReload={reload}>
          <input placeholder="标题或正文" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value })} />
          <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value })}>
            <option value="all">全部</option>
            <option value="published">已发布</option>
            <option value="draft">草稿</option>
            <option value="archived">已下线</option>
          </select>
        </ResourceHeader>
        <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
        <div className="item-list">
          {data?.items.map((item) => (
            <article key={item.id} className="list-item">
              <div>
                <strong>{item.title}</strong>
                <span>{brief(item.body, 120)}</span>
                <small>{formatDate(item.published_at ?? item.created_at)} · {levelLabel(item.level)}</small>
              </div>
              <div className="actions">
                <StatusPill status={item.status} />
                {item.status !== "published" && <button onClick={() => void updateStatus(item, "published")}>发布</button>}
                {item.status === "published" && <button className="danger" onClick={() => void updateStatus(item, "archived")}>下线</button>}
              </div>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function PostgraduateInfoAdminView(props: ViewProps) {
  const [sourceFilters, setSourceFilters] = useState({ search: "", status: "published", kind: "all", trustLevel: "all", page: 0, pageSize: 20 });
  const [suggestionFilters, setSuggestionFilters] = useState({ search: "", status: "open", kind: "all", start: "", end: "", page: 0, pageSize: 20 });
  const [form, setForm] = useState({
    id: "",
    title: "",
    summary: "",
    sourceUrl: "",
    sourceKind: "major_catalog",
    trustLevel: "official",
    school: "",
    unit: "",
    major: "",
    examYear: "",
    status: "published"
  });
  const sources = useAdminQuery<ListResult>(props.token, "listPostgraduateSources", sourceFilters);
  const suggestions = useAdminQuery<ListResult>(props.token, "listPostgraduateSuggestions", suggestionFilters);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(props, "upsertPostgraduateSource", form, form.id ? "考研来源已更新。" : "考研来源已新增。", () => {
      setForm({ id: "", title: "", summary: "", sourceUrl: "", sourceKind: "major_catalog", trustLevel: "official", school: "", unit: "", major: "", examYear: "", status: "published" });
      sources.reload();
    });
  }

  async function setSourceStatus(item: Row, status: "published" | "hidden" | "archived") {
    await runMutation(props, "setPostgraduateSourceStatus", { id: item.id, status }, "考研来源状态已更新。", sources.reload);
  }

  async function approve(item: Row) {
    const summary = window.prompt("入库摘要", item.note ?? "");
    if (summary === null) return;
    const adminNote = window.prompt("审核备注", item.admin_note ?? "");
    if (adminNote === null) return;
    await runMutation(props, "approvePostgraduateSuggestion", { id: item.id, summary, adminNote }, "线索已通过并发布。", () => {
      suggestions.reload();
      sources.reload();
    });
  }

  async function reject(item: Row) {
    const adminNote = window.prompt("驳回原因", item.admin_note ?? "");
    if (adminNote === null) return;
    await runMutation(props, "rejectPostgraduateSuggestion", { id: item.id, adminNote }, "线索已驳回。", suggestions.reload);
  }

  return (
    <div className="stack">
      <div className="split-layout">
        <form className="panel composer" onSubmit={submit}>
          <h2>{form.id ? "编辑考研来源" : "新增考研来源"}</h2>
          <label>标题<input value={form.title} maxLength={180} onChange={(event) => setForm({ ...form, title: event.target.value })} required /></label>
          <label>来源链接<input type="url" value={form.sourceUrl} onChange={(event) => setForm({ ...form, sourceUrl: event.target.value })} required /></label>
          <label>摘要<textarea value={form.summary} rows={5} maxLength={1200} onChange={(event) => setForm({ ...form, summary: event.target.value })} /></label>
          <div className="form-grid">
            <label>类型<select value={form.sourceKind} onChange={(event) => setForm({ ...form, sourceKind: event.target.value })}>{postgraduateSourceKinds.map((kind) => <option key={kind.value} value={kind.value}>{kind.label}</option>)}</select></label>
            <label>可信度<select value={form.trustLevel} onChange={(event) => setForm({ ...form, trustLevel: event.target.value })}>{postgraduateTrustLevels.map((level) => <option key={level.value} value={level.value}>{level.label}</option>)}</select></label>
          </div>
          <div className="form-grid">
            <label>学校<input value={form.school} onChange={(event) => setForm({ ...form, school: event.target.value })} /></label>
            <label>学院/单位<input value={form.unit} onChange={(event) => setForm({ ...form, unit: event.target.value })} /></label>
          </div>
          <div className="form-grid">
            <label>专业<input value={form.major} onChange={(event) => setForm({ ...form, major: event.target.value })} /></label>
            <label>考试年份<input type="number" min="2000" max="2100" value={form.examYear} onChange={(event) => setForm({ ...form, examYear: event.target.value })} /></label>
          </div>
          <label>状态<select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="published">发布</option><option value="hidden">隐藏</option><option value="archived">归档</option></select></label>
          <button className="button primary">{form.id ? "保存来源" : "新增来源"}</button>
          {form.id && <button type="button" className="button secondary" onClick={() => setForm({ id: "", title: "", summary: "", sourceUrl: "", sourceKind: "major_catalog", trustLevel: "official", school: "", unit: "", major: "", examYear: "", status: "published" })}>取消编辑</button>}
        </form>

        <section className="panel">
          <ResourceHeader title="公共来源" total={sources.data?.total} onReload={sources.reload}>
            <input placeholder="标题、摘要、学校、专业" value={sourceFilters.search} onChange={(event) => setSourceFilters({ ...sourceFilters, search: event.target.value, page: 0 })} />
            <select value={sourceFilters.kind} onChange={(event) => setSourceFilters({ ...sourceFilters, kind: event.target.value, page: 0 })}>
              <option value="all">全部类型</option>
              {postgraduateSourceKinds.map((kind) => <option key={kind.value} value={kind.value}>{kind.label}</option>)}
            </select>
            <select value={sourceFilters.trustLevel} onChange={(event) => setSourceFilters({ ...sourceFilters, trustLevel: event.target.value, page: 0 })}>
              <option value="all">全部可信度</option>
              {postgraduateTrustLevels.map((level) => <option key={level.value} value={level.value}>{level.label}</option>)}
            </select>
            <select value={sourceFilters.status} onChange={(event) => setSourceFilters({ ...sourceFilters, status: event.target.value, page: 0 })}>
              <option value="published">已发布</option>
              <option value="hidden">已隐藏</option>
              <option value="archived">已归档</option>
              <option value="all">全部状态</option>
            </select>
          </ResourceHeader>
          <DataState isLoading={sources.isLoading} error={sources.error} empty={!sources.data?.items.length} />
          {sources.data?.items.length ? (
            <table>
              <thead><tr><th>来源</th><th>范围</th><th>可信度</th><th>状态</th><th>更新</th><th>操作</th></tr></thead>
              <tbody>
                {sources.data.items.map((source) => (
                  <tr key={source.id}>
                    <td><strong>{source.title}</strong><span>{brief(source.summary, 90)}</span><a href={source.source_url} target="_blank" rel="noreferrer">{brief(source.source_url, 80)}</a></td>
                    <td>{postgraduateScopeText(source)}</td>
                    <td>{postgraduateTrustLabel(source.trust_level)} · {postgraduateKindLabel(source.source_kind)}</td>
                    <td><StatusPill status={source.status} /></td>
                    <td>{formatDate(source.verified_at ?? source.updated_at)}</td>
                    <td className="actions">
                      <button onClick={() => setForm({
                        id: source.id,
                        title: source.title ?? "",
                        summary: source.summary ?? "",
                        sourceUrl: source.source_url ?? "",
                        sourceKind: source.source_kind ?? "other",
                        trustLevel: source.trust_level ?? "curated",
                        school: source.school ?? "",
                        unit: source.unit ?? "",
                        major: source.major ?? "",
                        examYear: source.exam_year ? String(source.exam_year) : "",
                        status: source.status ?? "published"
                      })}>编辑</button>
                      {source.status === "published" ? (
                        <button className="danger" onClick={() => void setSourceStatus(source, "hidden")}>隐藏</button>
                      ) : (
                        <button onClick={() => void setSourceStatus(source, "published")}>发布</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : null}
          <Pagination
            page={sourceFilters.page}
            pageSize={sourceFilters.pageSize}
            total={sources.data?.total ?? 0}
            onPage={(page) => setSourceFilters({ ...sourceFilters, page })}
            onPageSize={(pageSize) => setSourceFilters({ ...sourceFilters, pageSize, page: 0 })}
          />
        </section>
      </div>

      <section className="panel">
        <ResourceHeader title="用户线索" total={suggestions.data?.total} onReload={suggestions.reload}>
          <input placeholder="标题、链接、学校、专业、说明" value={suggestionFilters.search} onChange={(event) => setSuggestionFilters({ ...suggestionFilters, search: event.target.value, page: 0 })} />
          <input aria-label="开始日期" type="date" value={suggestionFilters.start} onChange={(event) => setSuggestionFilters({ ...suggestionFilters, start: event.target.value, page: 0 })} />
          <input aria-label="结束日期" type="date" value={suggestionFilters.end} onChange={(event) => setSuggestionFilters({ ...suggestionFilters, end: event.target.value, page: 0 })} />
          <select value={suggestionFilters.kind} onChange={(event) => setSuggestionFilters({ ...suggestionFilters, kind: event.target.value, page: 0 })}>
            <option value="all">全部类型</option>
            {postgraduateSourceKinds.map((kind) => <option key={kind.value} value={kind.value}>{kind.label}</option>)}
          </select>
          <select value={suggestionFilters.status} onChange={(event) => setSuggestionFilters({ ...suggestionFilters, status: event.target.value, page: 0 })}>
            <option value="open">待审核</option>
            <option value="approved">已通过</option>
            <option value="rejected">已驳回</option>
            <option value="all">全部状态</option>
          </select>
        </ResourceHeader>
        <DataState isLoading={suggestions.isLoading} error={suggestions.error} empty={!suggestions.data?.items.length} />
        {suggestions.data?.items.length ? (
          <table>
            <thead><tr><th>线索</th><th>范围</th><th>用户</th><th>状态</th><th>提交时间</th><th>操作</th></tr></thead>
            <tbody>
              {suggestions.data.items.map((item) => (
                <tr key={item.id}>
                  <td><strong>{item.title}</strong><span>{postgraduateKindLabel(item.source_kind)} · {brief(item.note, 90)}</span><a href={item.source_url} target="_blank" rel="noreferrer">{brief(item.source_url, 80)}</a>{item.admin_note && <span>备注：{brief(item.admin_note, 80)}</span>}</td>
                  <td>{postgraduateScopeText(item)}</td>
                  <td>{item.user ? profileName(item.user) : "匿名会话"}</td>
                  <td><StatusPill status={item.status} /></td>
                  <td>{formatDate(item.created_at)}</td>
                  <td className="actions">
                    {item.status === "open" ? (
                      <>
                        <button onClick={() => void approve(item)}>通过</button>
                        <button className="danger" onClick={() => void reject(item)}>驳回</button>
                      </>
                    ) : (
                      <span>{item.reviewer?.display_name ?? "已处理"}</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
        <Pagination
          page={suggestionFilters.page}
          pageSize={suggestionFilters.pageSize}
          total={suggestions.data?.total ?? 0}
          onPage={(page) => setSuggestionFilters({ ...suggestionFilters, page })}
          onPageSize={(pageSize) => setSuggestionFilters({ ...suggestionFilters, pageSize, page: 0 })}
        />
      </section>
    </div>
  );
}

function CatalogSuggestionsView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "open", type: "all", start: "", end: "", page: 0, pageSize: 20 });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listCatalogSuggestions", filters);

  async function approve(item: Row) {
    const adminNote = window.prompt("审核备注", item.admin_note ?? "");
    if (adminNote === null) return;
    await runMutation(props, "approveCatalogSuggestion", { id: item.id, adminNote }, "建议已通过并写入名录。", reload);
  }

  async function reject(item: Row) {
    const adminNote = window.prompt("驳回原因", item.admin_note ?? "");
    if (adminNote === null) return;
    await runMutation(props, "rejectCatalogSuggestion", { id: item.id, adminNote }, "建议已驳回。", reload);
  }

  return (
    <section className="panel">
      <ResourceHeader title="名录建议" total={data?.total} onReload={reload}>
        <input placeholder="名称、单位、老师、说明" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.type} onChange={(event) => setFilters({ ...filters, type: event.target.value, page: 0 })}>
          <option value="all">全部类型</option>
          <option value="teacher">老师</option>
          <option value="course">课程</option>
          <option value="dish">菜品</option>
        </select>
        <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
          <option value="open">待审核</option>
          <option value="approved">已通过</option>
          <option value="rejected">已驳回</option>
          <option value="all">全部状态</option>
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead><tr><th>类型</th><th>建议内容</th><th>用户</th><th>状态</th><th>提交时间</th><th>操作</th></tr></thead>
          <tbody>
            {data.items.map((item) => (
              <tr key={item.id}>
                <td>{suggestionTypeLabel(item.suggestion_type)}</td>
                <td>
                  <strong>{item.name}</strong>
                  <span>{catalogSuggestionDetail(item)}</span>
                  {item.initial_stars && <span>顺手评分：{item.initial_stars} 星</span>}
                  {item.note && <span>{brief(item.note, 80)}</span>}
                  {item.admin_note && <span>备注：{brief(item.admin_note, 80)}</span>}
                </td>
                <td>{item.user ? profileName(item.user) : "匿名会话"}</td>
                <td><StatusPill status={item.status} /></td>
                <td>{formatDate(item.created_at)}</td>
                <td className="actions">
                  {item.status === "open" ? (
                    <>
                      <button onClick={() => void approve(item)}>通过</button>
                      <button className="danger" onClick={() => void reject(item)}>驳回</button>
                    </>
                  ) : (
                    <span>{item.reviewer?.display_name ?? "已处理"}</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

function TeachersView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "published" });
  const [form, setForm] = useState({ id: "", name: "", unit: "", status: "published" });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listTeachers", filters);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(props, "upsertTeacher", form, form.id ? "教师信息已更新。" : "教师已新增。", () => {
      setForm({ id: "", name: "", unit: "", status: "published" });
      reload();
    });
  }

  async function setStatus(item: Row, status: "published" | "hidden") {
    await runMutation(props, "setTeacherStatus", { id: item.id, status }, status === "hidden" ? "教师已隐藏。" : "教师已恢复。", reload);
  }

  return (
    <div className="split-layout">
      <form className="panel composer" onSubmit={submit}>
        <h2>{form.id ? "编辑教师" : "新增教师"}</h2>
        <label>姓名<input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required /></label>
        <label>学院/单位<input value={form.unit} onChange={(event) => setForm({ ...form, unit: event.target.value })} required /></label>
        <label>状态<select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="published">展示</option><option value="hidden">隐藏</option></select></label>
        <button className="button primary">{form.id ? "保存教师" : "新增教师"}</button>
        {form.id && <button type="button" className="button secondary" onClick={() => setForm({ id: "", name: "", unit: "", status: "published" })}>取消编辑</button>}
      </form>
      <section className="panel">
        <ResourceHeader title="教师名录" total={data?.total} onReload={reload}>
          <input placeholder="姓名、学院" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value })} />
          <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value })}>
            <option value="published">展示中</option>
            <option value="hidden">已隐藏</option>
            <option value="all">全部</option>
          </select>
        </ResourceHeader>
        <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
        {data?.items.length ? (
          <table>
            <thead><tr><th>教师</th><th>评分</th><th>状态</th><th>更新</th><th>操作</th></tr></thead>
            <tbody>
              {data.items.map((teacher) => (
                <tr key={teacher.id}>
                  <td><strong>{teacher.name}</strong><span>{teacher.unit}</span></td>
                  <td>{teacher.rating_average} · {teacher.rating_count} 人</td>
                  <td><StatusPill status={teacher.status} /></td>
                  <td>{formatDate(teacher.updated_at)}</td>
                  <td className="actions">
                    <button onClick={() => setForm({ id: String(teacher.id), name: teacher.name, unit: teacher.unit, status: teacher.status })}>编辑</button>
                    {teacher.status === "published" ? (
                      <button className="danger" onClick={() => void setStatus(teacher, "hidden")}>隐藏</button>
                    ) : (
                      <button onClick={() => void setStatus(teacher, "published")}>恢复</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
      </section>
    </div>
  );
}

function CoursesView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "published", category: "", page: 0, pageSize: 20 });
  const [form, setForm] = useState({ id: "", name: "", unit: "", category: "公选课", credit: "", status: "published" });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listCourses", filters);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(props, "upsertCourse", form, form.id ? "课程信息已更新。" : "课程已新增。", () => {
      setForm({ id: "", name: "", unit: "", category: "公选课", credit: "", status: "published" });
      reload();
    });
  }

  async function setStatus(item: Row, status: "published" | "hidden") {
    await runMutation(props, "setCourseStatus", { id: item.id, status }, status === "hidden" ? "课程已隐藏。" : "课程已恢复。", reload);
  }

  return (
    <div className="split-layout">
      <form className="panel composer" onSubmit={submit}>
        <h2>{form.id ? "编辑课程" : "新增课程"}</h2>
        <label>课程名<input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required /></label>
        <label>开课单位<input value={form.unit} onChange={(event) => setForm({ ...form, unit: event.target.value })} required /></label>
        <label>分类<input value={form.category} onChange={(event) => setForm({ ...form, category: event.target.value })} required /></label>
        <label>学分<input type="number" min="0" step="0.5" value={form.credit} onChange={(event) => setForm({ ...form, credit: event.target.value })} placeholder="默认 0" /></label>
        <label>状态<select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="published">展示</option><option value="hidden">隐藏</option></select></label>
        <button className="button primary">{form.id ? "保存课程" : "新增课程"}</button>
        {form.id && <button type="button" className="button secondary" onClick={() => setForm({ id: "", name: "", unit: "", category: "公选课", credit: "", status: "published" })}>取消编辑</button>}
      </form>
      <section className="panel">
        <ResourceHeader title="课程库" total={data?.total} onReload={reload}>
          <input placeholder="课程名、单位、分类" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
          <input placeholder="分类" value={filters.category} onChange={(event) => setFilters({ ...filters, category: event.target.value, page: 0 })} />
          <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
            <option value="published">展示中</option>
            <option value="hidden">已隐藏</option>
            <option value="all">全部</option>
          </select>
        </ResourceHeader>
        <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
        {data?.items.length ? (
          <table>
            <thead><tr><th>课程</th><th>评分</th><th>状态</th><th>更新</th><th>操作</th></tr></thead>
            <tbody>
              {data.items.map((course) => (
                <tr key={course.id}>
                  <td><strong>{course.name}</strong><span>{course.unit} · {course.category} · {formatCredit(course.credit)}</span></td>
                  <td>{course.rating_average} · {course.rating_count} 人</td>
                  <td><StatusPill status={course.status} /></td>
                  <td>{formatDate(course.updated_at)}</td>
                  <td className="actions">
                    <button onClick={() => setForm({ id: String(course.id), name: course.name, unit: course.unit, category: course.category, credit: String(course.credit ?? ""), status: course.status })}>编辑</button>
                    {course.status === "published" ? (
                      <button className="danger" onClick={() => void setStatus(course, "hidden")}>隐藏</button>
                    ) : (
                      <button onClick={() => void setStatus(course, "published")}>恢复</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
        <Pagination
          page={filters.page}
          pageSize={filters.pageSize}
          total={data?.total ?? 0}
          onPage={(page) => setFilters({ ...filters, page })}
          onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
        />
      </section>
    </div>
  );
}

function DishesView(props: ViewProps) {
  const [filters, setFilters] = useState({ search: "", status: "published", location: "", page: 0, pageSize: 20 });
  const [form, setForm] = useState({ id: "", name: "", location: "", status: "published" });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listDishes", filters);

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(props, "upsertDish", form, form.id ? "菜品信息已更新。" : "菜品已新增。", () => {
      setForm({ id: "", name: "", location: "", status: "published" });
      reload();
    });
  }

  async function setStatus(item: Row, status: "published" | "hidden") {
    await runMutation(props, "setDishStatus", { id: item.id, status }, status === "hidden" ? "菜品已隐藏。" : "菜品已恢复。", reload);
  }

  return (
    <div className="split-layout">
      <form className="panel composer" onSubmit={submit}>
        <h2>{form.id ? "编辑菜品" : "新增菜品"}</h2>
        <label>菜名<input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required /></label>
        <label>地点
          <select value={form.location} onChange={(event) => setForm({ ...form, location: event.target.value })} required>
            <option value="">选择地点</option>
            {diningLocations.map((location) => <option key={location.value} value={location.value}>{location.label}</option>)}
          </select>
        </label>
        <label>状态<select value={form.status} onChange={(event) => setForm({ ...form, status: event.target.value })}><option value="published">展示</option><option value="hidden">隐藏</option></select></label>
        <button className="button primary">{form.id ? "保存菜品" : "新增菜品"}</button>
        {form.id && <button type="button" className="button secondary" onClick={() => setForm({ id: "", name: "", location: "", status: "published" })}>取消编辑</button>}
      </form>
      <section className="panel">
        <ResourceHeader title="菜品库" total={data?.total} onReload={reload}>
          <input placeholder="菜名、地点" value={filters.search} onChange={(event) => setFilters({ ...filters, search: event.target.value, page: 0 })} />
          <select value={filters.location} onChange={(event) => setFilters({ ...filters, location: event.target.value, page: 0 })}>
            <option value="">全部地点</option>
            {diningLocations.map((location) => <option key={location.value} value={location.value}>{location.label}</option>)}
          </select>
          <select value={filters.status} onChange={(event) => setFilters({ ...filters, status: event.target.value, page: 0 })}>
            <option value="published">展示中</option>
            <option value="hidden">已隐藏</option>
            <option value="all">全部</option>
          </select>
        </ResourceHeader>
        <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
        {data?.items.length ? (
          <table>
            <thead><tr><th>菜品</th><th>评分</th><th>状态</th><th>更新</th><th>操作</th></tr></thead>
            <tbody>
              {data.items.map((dish) => (
                <tr key={dish.id}>
                  <td><strong>{dish.name}</strong><span>{dish.location}</span></td>
                  <td>{dish.rating_average} · {dish.rating_count} 人</td>
                  <td><StatusPill status={dish.status} /></td>
                  <td>{formatDate(dish.updated_at)}</td>
                  <td className="actions">
                    <button onClick={() => setForm({ id: String(dish.id), name: dish.name, location: dish.location, status: dish.status })}>编辑</button>
                    {dish.status === "published" ? (
                      <button className="danger" onClick={() => void setStatus(dish, "hidden")}>隐藏</button>
                    ) : (
                      <button onClick={() => void setStatus(dish, "published")}>恢复</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
        <Pagination
          page={filters.page}
          pageSize={filters.pageSize}
          total={data?.total ?? 0}
          onPage={(page) => setFilters({ ...filters, page })}
          onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
        />
      </section>
    </div>
  );
}

function RatingsView(props: ViewProps) {
  const [target, setTarget] = useState<"teacher" | "dish">("teacher");
  const [filters, setFilters] = useState({ target: "teacher", teacherID: "", dishID: "", userID: "", stars: "", start: "", end: "", page: 0, pageSize: 20 });
  const queryAction = target === "dish" ? "listDishRatings" : "listTeacherRatings";
  const queryFilters = target === "dish"
    ? { dishID: filters.dishID, userID: filters.userID, stars: filters.stars, start: filters.start, end: filters.end, page: filters.page, pageSize: filters.pageSize }
    : { teacherID: filters.teacherID, userID: filters.userID, stars: filters.stars, start: filters.start, end: filters.end, page: filters.page, pageSize: filters.pageSize };
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, queryAction, queryFilters);

  function updateTarget(nextTarget: "teacher" | "dish") {
    setTarget(nextTarget);
    setFilters({ ...filters, target: nextTarget, page: 0 });
  }

  async function remove(item: Row) {
    if (!window.confirm("删除这条评分？评分汇总会自动重算。")) return;
    if (target === "dish") {
      await runMutation(props, "deleteDishRating", { dishID: item.dish_id, userID: item.user_id }, "评分已删除。", reload);
      return;
    }
    await runMutation(props, "deleteTeacherRating", { teacherID: item.teacher_id, userID: item.user_id }, "评分已删除。", reload);
  }

  return (
    <section className="panel">
      <ResourceHeader title="评分明细" total={data?.total} onReload={reload}>
        <select value={target} onChange={(event) => updateTarget(event.target.value as "teacher" | "dish")}>
          <option value="teacher">教师评分</option>
          <option value="dish">菜品评分</option>
        </select>
        {target === "dish" ? (
          <input placeholder="菜品 ID" value={filters.dishID} onChange={(event) => setFilters({ ...filters, dishID: event.target.value, page: 0 })} />
        ) : (
          <input placeholder="教师 ID" value={filters.teacherID} onChange={(event) => setFilters({ ...filters, teacherID: event.target.value, page: 0 })} />
        )}
        <input placeholder="用户 UUID" value={filters.userID} onChange={(event) => setFilters({ ...filters, userID: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
        <select value={filters.stars} onChange={(event) => setFilters({ ...filters, stars: event.target.value, page: 0 })}>
          <option value="">全部星级</option>
          {[1, 2, 3, 4, 5].map((stars) => <option key={stars} value={stars}>{stars} 星</option>)}
        </select>
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead><tr><th>{target === "dish" ? "菜品" : "教师"}</th><th>用户</th><th>星级</th><th>时间</th><th>操作</th></tr></thead>
          <tbody>
            {data.items.map((rating) => (
              <tr key={`${target}-${rating.teacher_id ?? rating.dish_id}-${rating.user_id}`}>
                <td>
                  {target === "dish" ? (
                    <><strong>{rating.dish?.name ?? rating.dish_id}</strong><span>{rating.dish?.location}</span></>
                  ) : (
                    <><strong>{rating.teacher?.name ?? rating.teacher_id}</strong><span>{rating.teacher?.unit}</span></>
                  )}
                </td>
                <td>{rating.user ? profileName(rating.user) : rating.user_id}</td>
                <td>{rating.stars} 星</td>
                <td>{formatDate(rating.updated_at ?? rating.created_at)}</td>
                <td className="actions"><button className="danger" onClick={() => void remove(rating)}>删除</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

function AdminsView(props: ViewProps) {
  const [form, setForm] = useState({ username: "", password: "", displayName: "", role: "operator" });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listAdmins", {});

  async function submit(event: FormEvent) {
    event.preventDefault();
    await runMutation(props, "createAdmin", form, "管理员已创建。", () => {
      setForm({ username: "", password: "", displayName: "", role: "operator" });
      reload();
    });
  }

  async function update(item: Row) {
    const displayName = window.prompt("显示名", item.display_name);
    if (displayName === null) return;
    const role = window.prompt("角色：super_admin / operator / viewer", item.role);
    if (role === null) return;
    await runMutation(props, "updateAdmin", { id: item.id, displayName, role }, "管理员已更新。", reload);
  }

  async function disable(item: Row) {
    if (!window.confirm(`停用 ${item.username}？`)) return;
    await runMutation(props, "disableAdmin", { id: item.id }, "管理员已停用。", reload);
  }

  return (
    <div className="split-layout">
      <form className="panel composer" onSubmit={submit}>
        <h2>新增管理员</h2>
        <label>账号<input value={form.username} onChange={(event) => setForm({ ...form, username: event.target.value })} required /></label>
        <label>显示名<input value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} /></label>
        <label>初始密码<input type="password" value={form.password} onChange={(event) => setForm({ ...form, password: event.target.value })} required /></label>
        <label>角色<select value={form.role} onChange={(event) => setForm({ ...form, role: event.target.value })}><option value="operator">运营</option><option value="viewer">只读</option><option value="super_admin">超级管理员</option></select></label>
        <button className="button primary">创建管理员</button>
      </form>
      <section className="panel">
        <ResourceHeader title="管理员列表" total={data?.total} onReload={reload} />
        <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
        {data?.items.length ? (
          <table>
            <thead><tr><th>账号</th><th>角色</th><th>状态</th><th>最近登录</th><th>操作</th></tr></thead>
            <tbody>
              {data.items.map((item) => (
                <tr key={item.id}>
                  <td><strong>{item.display_name}</strong><span>{item.username}</span></td>
                  <td>{roleLabel(item.role)}</td>
                  <td><StatusPill status={item.active ? "active" : "disabled"} /></td>
                  <td>{formatDate(item.last_login_at)}</td>
                  <td className="actions">
                    <button onClick={() => void update(item)}>编辑</button>
                    {item.active && item.id !== props.admin.id && <button className="danger" onClick={() => void disable(item)}>停用</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
      </section>
    </div>
  );
}

function LogsView(props: ViewProps) {
  const [filters, setFilters] = useState({ action: "", start: "", end: "", page: 0, pageSize: 20 });
  const { data, isLoading, error, reload } = useAdminQuery<ListResult>(props.token, "listAuditLogs", filters);

  return (
    <section className="panel">
      <ResourceHeader title="操作日志" total={data?.total} onReload={reload}>
        <input placeholder="动作" value={filters.action} onChange={(event) => setFilters({ ...filters, action: event.target.value, page: 0 })} />
        <input aria-label="开始日期" type="date" value={filters.start} onChange={(event) => setFilters({ ...filters, start: event.target.value, page: 0 })} />
        <input aria-label="结束日期" type="date" value={filters.end} onChange={(event) => setFilters({ ...filters, end: event.target.value, page: 0 })} />
      </ResourceHeader>
      <DataState isLoading={isLoading} error={error} empty={!data?.items.length} />
      {data?.items.length ? (
        <table>
          <thead><tr><th>管理员</th><th>动作</th><th>目标</th><th>参数</th><th>时间</th></tr></thead>
          <tbody>
            {data.items.map((item) => (
              <tr key={item.id}>
                <td>{item.admin?.display_name ?? "已删除管理员"}</td>
                <td>{item.action}</td>
                <td>{[item.target_type, item.target_id].filter(Boolean).join(" / ") || "无"}</td>
                <td><code>{brief(JSON.stringify(item.params ?? {}), 120)}</code></td>
                <td>{formatDate(item.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      <Pagination
        page={filters.page}
        pageSize={filters.pageSize}
        total={data?.total ?? 0}
        onPage={(page) => setFilters({ ...filters, page })}
        onPageSize={(pageSize) => setFilters({ ...filters, pageSize, page: 0 })}
      />
    </section>
  );
}

type ViewProps = {
  token: string;
  admin: AdminAccount;
  campusID: string;
  notify: (text: string, tone?: MessageTone) => void;
  onSessionExpired: () => void;
};

function useAdminQuery<T>(token: string, action: string, params: Record<string, unknown>) {
  const campusID = useContext(CampusScopeContext);
  const scopedParams = withCampusScope(campusID, action, params);
  const [data, setData] = useState<T | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const requestKey = JSON.stringify(scopedParams);

  const reload = useCallback(() => setReloadKey((value) => value + 1), []);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setError(null);
    adminAction<T>(token, action, scopedParams)
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((queryError) => {
        if (!cancelled) setError(errorText(queryError));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [token, action, requestKey, reloadKey]);

  return { data, isLoading, error, reload };
}

function withCampusScope(campusID: string, action: string, params: Record<string, unknown>) {
  if (campusID === "all" || campusScopeExcludedActions.has(action)) {
    return params;
  }
  return { ...params, campusID };
}

const campusScopeExcludedActions = new Set([
  "listCampuses",
  "listCampusRequests",
  "approveCampusRequest",
  "rejectCampusRequest",
  "listAdmins",
  "createAdmin",
  "updateAdmin",
  "disableAdmin",
  "listAuditLogs",
]);

function overviewSummary(data?: Row | null) {
  if (data?.summary?.operations) {
    return data.summary;
  }

  const cards = data?.cards ?? {};
  const analytics = data?.analytics ?? {};
  const daily = analytics.daily ?? [];
  const moderation = analytics.moderation ?? {};
  const feedbackAging = analytics.feedbackAging ?? [];
  const topPosts = analytics.topPosts ?? [];
  const teacherRatings = analytics.teacherRatings ?? {};

  return {
    operations: {
      totalProfiles: cards.profiles?.total ?? 0,
      activeProfiles: cards.profiles?.complete ?? 0,
      newProfilesToday: cards.profiles?.today ?? 0,
      mutedProfiles: cards.profiles?.muted ?? 0,
      postsToday: cards.posts?.today ?? 0,
      commentsToday: cards.comments?.today ?? 0,
      postsInRange: sumRows(daily, "posts"),
      commentsInRange: sumRows(daily, "comments"),
      profilesInRange: sumRows(daily, "profiles"),
      daily
    },
    moderation: {
      openReports: cards.reports?.open ?? 0,
      overdueReports: cards.reports?.overdue ?? 0,
      hiddenPosts: moderation.hiddenPosts ?? cards.posts?.hidden ?? 0,
      hiddenComments: moderation.hiddenComments ?? cards.comments?.hidden ?? 0,
      mutedProfiles: moderation.mutedProfiles ?? cards.profiles?.muted ?? 0,
      pendingPosts: cards.posts?.pendingReview ?? 0,
      publishedPosts: cards.posts?.published ?? 0,
      publishedComments: cards.comments?.published ?? 0,
      recentRiskActions: moderation.recentRiskActions ?? []
    },
    feedback: {
      open: cards.feedback?.open ?? 0,
      reviewed: cards.feedback?.reviewed ?? 0,
      closed: cards.feedback?.closed ?? 0,
      closedInRange: moderation.closedFeedback ?? 0,
      overdue: overdueFeedbackRows(feedbackAging),
      aging: feedbackAging
    },
    content: {
      topPosts,
      topPostCount: topPosts.length,
      leadingScore: Number(topPosts[0]?.score) || 0,
      postsTotal: cards.posts?.total ?? 0,
      commentsTotal: cards.comments?.total ?? 0
    },
    teachers: {
      total: cards.teachers?.total ?? 0,
      hidden: cards.teachers?.hidden ?? 0,
      ratedTeachers: teacherRatings.teacherCount ?? 0,
      totalRatings: teacherRatings.totalRatings ?? 0,
      average: teacherRatings.average ?? 0,
      stars: teacherRatings.stars ?? [],
      lowScoreTeachers: teacherRatings.lowScoreTeachers ?? []
    }
  };
}

function sumRows(rows: Row[], key: string) {
  return rows.reduce((sum, row) => sum + (Number(row?.[key]) || 0), 0);
}

function overdueFeedbackRows(rows: Row[]) {
  return rows.reduce((sum, row) => {
    const key = String(row?.key ?? "");
    return key === "3-7d" || key === "7d+" ? sum + (Number(row?.count) || 0) : sum;
  }, 0);
}

async function runMutation(
  props: ViewProps,
  action: string,
  params: Record<string, unknown>,
  successMessage: string,
  afterSuccess: () => void
) {
  try {
    await adminAction(props.token, action, withCampusScope(props.campusID, action, params));
    props.notify(successMessage);
    afterSuccess();
    return true;
  } catch (mutationError) {
    props.notify(errorText(mutationError), "error");
    return false;
  }
}

function ResourceHeader({
  title,
  total,
  children,
  onReload
}: {
  title: string;
  total?: number;
  children?: React.ReactNode;
  onReload: () => void;
}) {
  return (
    <div className="resource-head">
      <div>
        <h2>{title}</h2>
        <p>{typeof total === "number" ? `${total} 条记录` : " "}</p>
      </div>
      <div className="filters">
        {children}
        <button className="button secondary" onClick={onReload}>
          <RefreshCw aria-hidden="true" size={16} />
          刷新
        </button>
      </div>
    </div>
  );
}

function DataState({ isLoading, error, empty }: { isLoading: boolean; error: string | null; empty: boolean }) {
  if (isLoading) return <div className="empty" role="status" aria-live="polite">加载中...</div>;
  if (error) return <div className="notice error" role="alert">{error}</div>;
  if (empty) return <div className="empty" role="status">没有匹配记录。</div>;
  return null;
}

function BulkBar({ count, children, onClear }: { count: number; children: React.ReactNode; onClear: () => void }) {
  if (count === 0) return null;
  return (
    <div className="bulk-bar" role="status">
      <span>已选择 {count} 条</span>
      <div className="actions">
        {children}
        <button type="button" onClick={onClear}>清除</button>
      </div>
    </div>
  );
}

function Pagination({
  page,
  pageSize,
  total,
  onPage,
  onPageSize
}: {
  page: number;
  pageSize: number;
  total: number;
  onPage: (page: number) => void;
  onPageSize: (pageSize: number) => void;
}) {
  const pageCount = Math.max(1, Math.ceil(total / pageSize));
  const currentPage = Math.min(page, pageCount - 1);
  if (total === 0) return null;

  return (
    <div className="pagination">
      <span>第 {currentPage + 1} / {pageCount} 页</span>
      <label>
        页大小
        <select value={pageSize} onChange={(event) => onPageSize(Number(event.target.value))}>
          {[10, 20, 50, 100].map((value) => <option key={value} value={value}>{value}</option>)}
        </select>
      </label>
      <div className="actions">
        <button type="button" disabled={currentPage <= 0} onClick={() => onPage(Math.max(0, currentPage - 1))}>上一页</button>
        <button type="button" disabled={currentPage >= pageCount - 1} onClick={() => onPage(Math.min(pageCount - 1, currentPage + 1))}>下一页</button>
      </div>
    </div>
  );
}

function StatCard({ title, value, detail }: { title: string; value?: number; detail: string }) {
  return (
    <article className="stat-card">
      <span>{title}</span>
      <strong>{value ?? 0}</strong>
      <small>{detail}</small>
    </article>
  );
}

function ProjectHealthCard({
  icon: Icon,
  label,
  value,
  meta,
  accent
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  meta?: string;
  accent?: "success";
}) {
  return (
    <article className={`project-health-card ${accent ?? ""}`}>
      <span className="project-health-icon"><Icon aria-hidden="true" size={18} /></span>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
        {meta && <small>{meta}</small>}
      </div>
    </article>
  );
}

function ServiceHealthRow({ name, value, detail }: { name: string; value: string; detail: string }) {
  return (
    <article className="service-health-row">
      <div>
        <strong>{name}</strong>
        <span>{detail}</span>
      </div>
      <p>{value}</p>
    </article>
  );
}

function TrendChart({ data }: { data: Row[] }) {
  const series = [
    { key: "profiles", label: "用户", color: "var(--color-primary)" },
    { key: "posts", label: "帖子", color: "var(--color-success)" },
    { key: "comments", label: "评论", color: "var(--color-warning)" },
    { key: "feedback", label: "反馈", color: "var(--color-danger)" },
    { key: "ratings", label: "评分", color: "var(--color-info)" }
  ];
  if (!data.length) return <div className="empty" role="status">暂无趋势数据。</div>;

  const width = 720;
  const height = 240;
  const pad = 28;
  const max = Math.max(1, ...data.flatMap((item) => series.map((serie) => Number(item[serie.key]) || 0)));
  const xStep = data.length > 1 ? (width - pad * 2) / (data.length - 1) : 0;
  const y = (value: number) => height - pad - (value / max) * (height - pad * 2);
  const x = (index: number) => pad + index * xStep;

  return (
    <div className="chart-wrap">
      <svg className="trend-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="运营增长趋势折线图">
        <defs>
          <linearGradient id="trend-fill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="var(--color-primary)" stopOpacity="0.22" />
            <stop offset="100%" stopColor="var(--color-primary)" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[0, 0.5, 1].map((ratio) => (
          <line
            key={ratio}
            x1={pad}
            x2={width - pad}
            y1={pad + ratio * (height - pad * 2)}
            y2={pad + ratio * (height - pad * 2)}
            className="chart-gridline"
          />
        ))}
        {series.map((serie) => {
          const points = data.map((item, index) => `${x(index)},${y(Number(item[serie.key]) || 0)}`).join(" ");
          return <polyline key={serie.key} points={points} fill="none" stroke={serie.color} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />;
        })}
        {data.map((item, index) => (
          <text key={item.bucket_date ?? index} x={x(index)} y={height - 6} textAnchor="middle" className="chart-label">
            {formatShortDate(item.bucket_date)}
          </text>
        ))}
      </svg>
      <div className="legend">
        {series.map((serie) => <span key={serie.key}><i style={{ background: serie.color }} />{serie.label}</span>)}
      </div>
    </div>
  );
}

function ActivityHeatmap({ data }: { data: Row[] }) {
  if (!data.length) return <div className="empty" role="status">暂无热力数据。</div>;
  const width = 620;
  const height = 210;
  const cell = 18;
  const gap = 5;
  const left = 38;
  const top = 18;
  const max = Math.max(1, ...data.map((item) => heatValue(item)));
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];

  return (
    <div className="chart-wrap">
      <svg className="heatmap-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="按星期和小时统计的活跃热力图">
        {weekdays.map((day, weekday) => (
          <text key={day} x="8" y={top + weekday * (cell + gap) + 14} className="chart-label">{day}</text>
        ))}
        {[0, 6, 12, 18, 23].map((hour) => (
          <text key={hour} x={left + hour * (cell + gap) + cell / 2} y={height - 8} textAnchor="middle" className="chart-label">{hour}</text>
        ))}
        {data.map((item) => {
          const value = heatValue(item);
          const opacity = 0.12 + (value / max) * 0.78;
          return (
            <rect
              key={`${item.weekday}-${item.hour}`}
              x={left + Number(item.hour) * (cell + gap)}
              y={top + Number(item.weekday) * (cell + gap)}
              width={cell}
              height={cell}
              rx="5"
              fill="var(--color-primary)"
              opacity={opacity}
            />
          );
        })}
      </svg>
    </div>
  );
}

function CategoryBars({ data }: { data: Row[] }) {
  return (
    <HorizontalBars
      data={data}
      empty="暂无分类数据。"
      label={(item) => item.category ?? "未分类"}
      value={(item) => Number(item.posts) || 0}
      suffix="帖"
      ariaLabel="帖子分类分布柱状图"
    />
  );
}

function FeedbackAging({ data }: { data: Row[] }) {
  return (
    <HorizontalBars
      data={data}
      empty="暂无待处理反馈。"
      label={(item) => item.label ?? item.key}
      value={(item) => Number(item.count) || 0}
      suffix="条"
      ariaLabel="待处理反馈老化柱状图"
    />
  );
}

function TeacherRatingBars({ data }: { data?: Row | null }) {
  const stars = data?.stars ?? [];
  return (
    <div className="mini-stack">
      <div className="metric-line">
        <strong>{data?.average ?? 0}</strong>
        <span>平均分 · {data?.totalRatings ?? 0} 次评分</span>
      </div>
      <HorizontalBars
        data={stars}
        empty="暂无评分数据。"
        label={(item) => `${item.star} 星`}
        value={(item) => Number(item.count) || 0}
        suffix="次"
        ariaLabel="教师评分星级分布柱状图"
      />
    </div>
  );
}

function TeacherWatchList({ data }: { data: Row[] }) {
  return (
    <SimpleList
      items={data}
      primary={(item) => item.name ?? "未知教师"}
      secondary={(item) => `${Number(item.rating_average ?? 0).toFixed(1)} 分 · ${item.rating_count ?? 0} 次评分 · ${item.unit ?? "未设置单位"}`}
    />
  );
}

function HorizontalBars({
  data,
  label,
  value,
  suffix,
  empty,
  ariaLabel
}: {
  data: Row[];
  label: (item: Row) => string;
  value: (item: Row) => number;
  suffix: string;
  empty: string;
  ariaLabel: string;
}) {
  if (!data.length) return <div className="empty" role="status">{empty}</div>;
  const rows = data.slice(0, 6);
  const width = 420;
  const rowHeight = 34;
  const height = rows.length * rowHeight + 12;
  const max = Math.max(1, ...rows.map(value));

  return (
    <svg className="bar-chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label={ariaLabel}>
      {rows.map((item, index) => {
        const current = value(item);
        const barWidth = (current / max) * 220;
        const y = index * rowHeight + 12;
        return (
          <g key={`${label(item)}-${index}`}>
            <text x="0" y={y + 15} className="chart-label">{brief(label(item), 10)}</text>
            <rect x="112" y={y} width="230" height="20" rx="6" className="bar-track" />
            <rect x="112" y={y} width={barWidth} height="20" rx="6" className="bar-fill" />
            <text x="356" y={y + 15} className="chart-label">{current} {suffix}</text>
          </g>
        );
      })}
    </svg>
  );
}

function ModerationSummary({ data, showRecent }: { data?: Row | null; showRecent: boolean }) {
  const items = [
    ["待处理举报", data?.openReports ?? 0],
    ["超时举报", data?.overdueReports ?? 0],
    ["下架帖子", data?.hiddenPosts ?? 0],
    ["下架评论", data?.hiddenComments ?? 0],
    ["禁言用户", data?.mutedProfiles ?? 0],
    ["待审帖子", data?.pendingPosts ?? 0]
  ];
  return (
    <div className="mini-stack">
      {items.map(([label, value]) => (
        <div className="metric-line" key={String(label)}>
          <strong>{value}</strong>
          <span>{label}</span>
        </div>
      ))}
      {!showRecent && <p className="muted-note">最新高风险操作仅超级管理员可见。</p>}
    </div>
  );
}

function SimpleList({
  items,
  primary,
  secondary
}: {
  items: Row[];
  primary: (item: Row) => string;
  secondary: (item: Row) => string;
}) {
  if (!items.length) return <div className="empty" role="status">暂无数据。</div>;
  return (
    <div className="item-list">
      {items.map((item, index) => (
        <article className="list-item" key={item.id ?? index}>
          <div>
            <strong>{primary(item)}</strong>
            <span>{secondary(item)}</span>
          </div>
        </article>
      ))}
    </div>
  );
}

function PostDrawer({
  data,
  onClose,
  onPinGlobal,
  onPinCategory,
  onUnpin
}: {
  data: Row;
  onClose: () => void;
  onPinGlobal?: (post: Row) => void;
  onPinCategory?: (post: Row) => void;
  onUnpin?: (post: Row) => void;
}) {
  const post = data.post;
  const comments = data.comments ?? [];

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <aside className="drawer" onClick={(event) => event.stopPropagation()}>
        <div className="drawer-head">
          <div>
            <h2>{post.title}</h2>
            <p>{profileName(post.author)} · {formatDate(post.created_at)}</p>
          </div>
          <div className="actions">
            {post.status === "published" && (
              <>
                <button onClick={() => onPinGlobal?.(post)}>全局置顶</button>
                <button onClick={() => onPinCategory?.(post)}>分类置顶</button>
                {post.pin && <button onClick={() => onUnpin?.(post)}>取消置顶</button>}
              </>
            )}
            <button className="button secondary" onClick={onClose}>
              <X aria-hidden="true" size={16} />
              关闭
            </button>
          </div>
        </div>
        {post.pin && (
          <p className="pin-note drawer-note">
            {pinScopeLabel(post.pin.scope)} · 优先级 {post.pin.priority ?? 0}
            {post.pin.ends_at ? ` · 至 ${formatDate(post.pin.ends_at)}` : ""}
          </p>
        )}
        <p className="body-text">{post.body}</p>
        {post.images?.length ? (
          <div className="image-grid">
            {post.images.map((image: Row) => image.signed_url ? <img key={image.id} src={image.signed_url} alt="" /> : null)}
          </div>
        ) : null}
        <h3>评论</h3>
        <div className="item-list">
          {comments.map((comment: Row) => (
            <article className="list-item" key={comment.id}>
              <div>
                <strong>{profileName(comment.author)}</strong>
                <span>{comment.body}</span>
              </div>
              <StatusPill status={comment.status} />
            </article>
          ))}
        </div>
      </aside>
    </div>
  );
}

function PinPostDialog({
  state,
  onClose,
  onSubmit
}: {
  state: { post: Row; scope: PinScope };
  onClose: () => void;
  onSubmit: (payload: Record<string, unknown>, scope: PinScope) => Promise<boolean>;
}) {
  const { post, scope } = state;
  const [priority, setPriority] = useState(String(post.pin?.priority ?? 0));
  const [category, setCategory] = useState(scope === "category" ? String(post.category ?? post.pin?.category ?? "") : "");
  const [startsAt, setStartsAt] = useState(toDatetimeLocalValue(post.pin?.starts_at));
  const [endsAt, setEndsAt] = useState(toDatetimeLocalValue(post.pin?.ends_at));
  const [reason, setReason] = useState(post.pin?.reason ?? "");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);

    const priorityNumber = Number(priority);
    if (!Number.isFinite(priorityNumber)) {
      setError("优先级必须是数字。");
      return;
    }

    const normalizedCategory = category.trim();
    if (scope === "category" && !normalizedCategory) {
      setError("分类置顶需要填写分类。");
      return;
    }

    const startsAtISO = optionalLocalDateISOString(startsAt);
    if (startsAt && !startsAtISO) {
      setError("开始时间格式无效。");
      return;
    }

    const endsAtISO = optionalLocalDateISOString(endsAt);
    if (endsAt && !endsAtISO) {
      setError("结束时间格式无效。");
      return;
    }

    if (startsAtISO && endsAtISO && new Date(endsAtISO).getTime() <= new Date(startsAtISO).getTime()) {
      setError("结束时间必须晚于开始时间。");
      return;
    }

    const payload: Record<string, unknown> = {
      postID: post.id,
      scope,
      priority: Math.trunc(priorityNumber),
      startsAt: startsAtISO,
      endsAt: endsAtISO,
      reason: reason.trim() || null
    };

    if (scope === "category") {
      payload.category = normalizedCategory;
    }

    setIsSubmitting(true);
    try {
      const didSubmit = await onSubmit(payload, scope);
      if (!didSubmit) {
        setError("置顶提交失败，请根据页面提示检查后重试。");
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <aside className="dialog-panel" role="dialog" aria-modal="true" aria-labelledby="pin-dialog-title" onClick={(event) => event.stopPropagation()}>
        <form className="pin-form" onSubmit={submit}>
          <div className="drawer-head">
            <div>
              <p className="eyebrow">社区置顶</p>
              <h2 id="pin-dialog-title">{scope === "global" ? "全局置顶" : "分类置顶"}</h2>
              <p>{brief(post.title, 48)}</p>
            </div>
            <button className="button secondary compact" type="button" onClick={onClose}>
              <X aria-hidden="true" size={16} />
              关闭
            </button>
          </div>

          <div className="pin-summary">
            <Pin aria-hidden="true" size={16} />
            <span>{scope === "global" ? "全社区 Feed 顶部展示" : "仅在所选分类 Feed 顶部展示"}</span>
          </div>

          <div className="form-grid">
            <label>
              优先级
              <input type="number" step="1" min="-1000" max="1000" value={priority} onChange={(event) => setPriority(event.target.value)} required />
            </label>
            {scope === "category" && (
              <label>
                分类
                <input value={category} onChange={(event) => setCategory(event.target.value)} required />
              </label>
            )}
            <label>
              开始时间
              <input type="datetime-local" value={startsAt} onChange={(event) => setStartsAt(event.target.value)} />
            </label>
            <label>
              结束时间
              <input type="datetime-local" value={endsAt} onChange={(event) => setEndsAt(event.target.value)} />
            </label>
          </div>

          <label>
            置顶原因
            <textarea rows={3} value={reason} onChange={(event) => setReason(event.target.value)} placeholder="可留空；会进入后台审计参数。" />
          </label>

          {error && <div className="notice error" role="alert">{error}</div>}

          <div className="actions form-actions">
            <button className="button primary" disabled={isSubmitting} aria-busy={isSubmitting}>
              {isSubmitting ? <LoaderCircle aria-hidden="true" className="icon-spin" size={16} /> : <Pin aria-hidden="true" size={16} />}
              {isSubmitting ? "提交中..." : "确认置顶"}
            </button>
            <button className="button secondary" type="button" onClick={onClose}>取消</button>
          </div>
        </form>
      </aside>
    </div>
  );
}

function PollDrawer({ data, onClose }: { data: Row; onClose: () => void }) {
  const totalVotes = Number(data.total_vote_count) || 0;
  const options = Array.isArray(data.options) ? data.options : [];

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <aside className="drawer" onClick={(event) => event.stopPropagation()}>
        <div className="drawer-head">
          <div>
            <h2>{data.question}</h2>
            <p>{profileName(data.author)} · {formatDate(data.created_at)}</p>
          </div>
          <button className="button secondary" onClick={onClose}>
            <X aria-hidden="true" size={16} />
            关闭
          </button>
        </div>
        {data.detail && <p className="body-text">{data.detail}</p>}
        <div className="detail-grid">
          <StatCard title="总票数" value={totalVotes} detail="只展示聚合结果" />
          <StatCard title="选项" value={options.length} detail="单选投票" />
          <StatCard title="状态" value={data.status === "published" ? 1 : 0} detail={`${statusLabel(data.status)} · ${deletionStatusLabel(data.deletion_status)}`} />
        </div>
        <section className="drawer-section">
          <h3>选项统计</h3>
          <SimpleList
            items={options}
            primary={(item) => item.text}
            secondary={(item) => `${item.vote_count ?? 0} 票 · ${pollOptionPercent(item.vote_count, totalVotes)}`}
          />
        </section>
      </aside>
    </div>
  );
}

function ProfileDrawer({ data, onClose }: { data: Row; onClose: () => void }) {
  const profile = data.profile ?? {};
  const recentPosts = data.recentPosts ?? [];
  const recentComments = data.recentComments ?? [];
  const auditLogs = data.auditLogs ?? [];

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <aside className="drawer" onClick={(event) => event.stopPropagation()}>
        <div className="drawer-head">
          <div>
            <h2>{profileName(profile)}</h2>
            <p>{profile.edu_id ?? "无学号"} · {profile.bound_email || profile.pending_bound_email || "未绑定邮箱"}</p>
          </div>
          <button className="button secondary" onClick={onClose}>
            <X aria-hidden="true" size={16} />
            关闭
          </button>
        </div>
        <div className="detail-grid">
          <StatCard title="帖子" value={profile.post_count} detail="该用户累计发帖" />
          <StatCard title="评论" value={profile.comment_count} detail="该用户累计评论" />
          <StatCard title="资料" value={profile.is_profile_complete ? 1 : 0} detail={profile.is_profile_complete ? "已完善资料" : "未完善资料"} />
          <StatCard title="禁言" value={profile.is_muted ? 1 : 0} detail={profile.is_muted ? `至 ${formatDate(profile.muted_until)}` : "当前正常"} />
        </div>
        <section className="drawer-section">
          <h3>近期帖子</h3>
          <SimpleList
            items={recentPosts}
            primary={(item) => item.title}
            secondary={(item) => `${statusLabel(item.status)} · ${formatDate(item.created_at)}`}
          />
        </section>
        <section className="drawer-section">
          <h3>近期评论</h3>
          <SimpleList
            items={recentComments}
            primary={(item) => brief(item.body, 80)}
            secondary={(item) => `${statusLabel(item.status)} · ${item.post?.title ?? "帖子不可见"} · ${formatDate(item.created_at)}`}
          />
        </section>
        <section className="drawer-section">
          <h3>相关审计</h3>
          <SimpleList
            items={auditLogs}
            primary={(item) => riskActionLabel(item.action)}
            secondary={(item) => `${item.admin?.display_name ?? "管理员"} · ${formatDate(item.created_at)}`}
          />
        </section>
      </aside>
    </div>
  );
}

function StatusPill({ status }: { status?: string }) {
  return <span className={`pill ${status ?? "default"}`}>{statusLabel(status)}</span>;
}

function readStoredSession(): AdminSession | null {
  try {
    const raw = localStorage.getItem(storageKey);
    return raw ? JSON.parse(raw) as AdminSession : null;
  } catch {
    return null;
  }
}

function profileName(profile?: Row | null) {
  if (!profile) return "未知用户";
  return profile.nickname || profile.display_name || profile.edu_id || profile.username || "未知用户";
}

function formatDate(value?: string | null) {
  if (!value) return "未设置";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatShortDate(value?: string | null) {
  if (!value) return "";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return String(value).slice(5);
  return new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit" }).format(date);
}

function brief(value?: string | null, max = 80) {
  const text = value?.trim() ?? "";
  if (text.length <= max) return text || "无内容";
  return `${text.slice(0, max)}...`;
}

function pollOptionPercent(value: unknown, total: number) {
  const count = Number(value) || 0;
  if (total <= 0) return "0%";
  return `${Math.round((count / total) * 100)}%`;
}

function deletionStatusLabel(status?: string | null) {
  switch (status) {
    case "pending": return "删除待审核";
    case "approved": return "删除已批准";
    case "rejected": return "删除被拒";
    case "none":
    case undefined:
    case null:
    case "": return "无删除申请";
    default: return status;
  }
}

function pollOptionSummary(poll: Row) {
  const options = Array.isArray(poll.options) ? poll.options : [];
  if (!options.length) return "无选项";
  const total = Number(poll.total_vote_count) || 0;
  return options
    .slice(0, 4)
    .map((option: Row) => `${option.text} ${option.vote_count ?? 0}票/${pollOptionPercent(option.vote_count, total)}`)
    .join(" · ");
}

function reportTargetLabel(item: Row) {
  if (item.target_type === "post") return `帖子：${item.post?.title ?? item.post_id ?? "未知"}`;
  if (item.target_type === "comment") return `评论：${brief(item.comment?.body, 28)}`;
  return `用户：${profileName(item.reported_user)}`;
}

function reportTargetBody(item: Row) {
  if (item.target_type === "post") return brief(item.post?.body, 90);
  if (item.target_type === "comment") return item.post?.title ? `来自帖子：${item.post.title}` : "评论举报";
  return item.reported_user?.edu_id ? `学号 ${item.reported_user.edu_id}` : "用户举报";
}

function reportSlaText(value?: string | null) {
  if (!value) return "未知";
  const ageHours = Math.max(0, (Date.now() - new Date(value).getTime()) / 36e5);
  if (!Number.isFinite(ageHours)) return "未知";
  if (ageHours > 24) return `超时 ${Math.floor(ageHours - 24)}h`;
  return `剩余 ${Math.max(0, Math.ceil(24 - ageHours))}h`;
}

function suggestionTypeLabel(type?: string | null) {
  if (type === "teacher") return "老师";
  if (type === "course") return "课程";
  if (type === "dish") return "菜品";
  return "未知";
}

function catalogSuggestionDetail(item: Row) {
  if (item.suggestion_type === "course") {
    return [item.unit, item.teacher_name, item.category ?? "公选课", formatCredit(item.credit)].filter(Boolean).join(" · ");
  }
  if (item.suggestion_type === "dish") {
    return item.unit;
  }
  return item.unit;
}

function postgraduateKindLabel(kind?: string | null) {
  return postgraduateSourceKinds.find((item) => item.value === kind)?.label ?? "其他";
}

function postgraduateTrustLabel(level?: string | null) {
  return postgraduateTrustLevels.find((item) => item.value === level)?.label ?? "运营整理";
}

function postgraduateScopeText(item: Row) {
  const parts = [item.school, item.unit, item.major, item.exam_year ? `${item.exam_year}` : ""]
    .map((value) => String(value ?? "").trim())
    .filter(Boolean);
  return parts.length ? parts.join(" · ") : "通用信息";
}

function formatCredit(value?: string | number | null) {
  if (value === null || value === undefined || value === "") return "0 学分";
  const number = Number(value);
  if (!Number.isFinite(number)) return `${value} 学分`;
  const text = Number.isInteger(number) ? String(number) : number.toFixed(1).replace(/\.0$/, "");
  return `${text} 学分`;
}

function toDatetimeLocalValue(value?: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const offsetDate = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return offsetDate.toISOString().slice(0, 16);
}

function optionalLocalDateISOString(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const date = new Date(trimmed);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function heatValue(item: Row) {
  return (Number(item.posts) || 0) + (Number(item.comments) || 0) + (Number(item.feedback) || 0);
}

function uniqueStrings(values: string[]) {
  return Array.from(new Set(values));
}

function roleLabel(role: string) {
  if (role === "super_admin") return "超级管理员";
  if (role === "viewer") return "只读";
  return "运营";
}

function levelLabel(level: string) {
  if (level === "urgent") return "紧急";
  if (level === "warning") return "重要";
  return "普通";
}

function statusLabel(status?: string) {
  switch (status) {
    case "published": return "已发布";
    case "pending_review": return "待审核";
    case "hidden": return "已下架";
    case "deleted": return "已删除";
    case "pending": return "待处理";
    case "deletion_pending": return "删除待审核";
    case "deletion_approved": return "删除已批准";
    case "deletion_rejected": return "删除被拒";
    case "draft": return "草稿";
    case "archived": return "已下线";
    case "open": return "待处理";
    case "approved": return "已通过";
    case "reviewed": return "已查看";
    case "closed": return "已关闭";
    case "resolved": return "已处理";
    case "rejected": return "已驳回";
    case "active": return "启用";
    case "disabled": return "停用";
    default: return status ?? "未知";
  }
}

function isBJFUSchoolName(value?: string | null) {
  const normalized = String(value ?? "").replace(/\s+/g, "").toLowerCase();
  return normalized === "北京林业大学" || normalized === "北林" || normalized === "bjfu";
}

function pinScopeLabel(scope?: string) {
  switch (scope) {
    case "global": return "全局置顶";
    case "category": return "分类置顶";
    default: return "置顶";
  }
}

function riskActionLabel(action?: string) {
  switch (action) {
    case "moderatePost": return "审核帖子";
    case "bulkModeratePosts": return "批量审核帖子";
    case "moderatePoll": return "审核投票";
    case "reviewPollDeletion": return "审核投票删除";
    case "pinPost": return "置顶帖子";
    case "unpinPost": return "取消置顶";
    case "moderateComment": return "审核评论";
    case "bulkModerateComments": return "批量审核评论";
    case "muteProfile": return "禁言用户";
    case "unmuteProfile": return "解除禁言";
    case "resolveModerationReport": return "处理举报";
    case "upsertPostgraduateSource": return "维护考研来源";
    case "setPostgraduateSourceStatus": return "调整考研来源状态";
    case "approvePostgraduateSuggestion": return "通过考研线索";
    case "rejectPostgraduateSuggestion": return "驳回考研线索";
    case "approveCatalogSuggestion": return "通过名录建议";
    case "rejectCatalogSuggestion": return "驳回名录建议";
    case "upsertCourse": return "维护课程";
    case "setCourseStatus": return "调整课程状态";
    case "upsertDish": return "维护菜品";
    case "setDishStatus": return "调整菜品状态";
    case "deleteTeacherRating": return "删除评分";
    case "deleteDishRating": return "删除菜品评分";
    case "disableAdmin": return "停用管理员";
    case "updateFeedback": return "处理反馈";
    default: return action ?? "操作";
  }
}

function errorText(error: unknown) {
  return error instanceof Error ? error.message : "操作失败。";
}

export default function AdminConsole() {
  useEffect(() => {
    document.body.classList.add("leafy-admin-active");
    return () => document.body.classList.remove("leafy-admin-active");
  }, []);

  return (
    <div className="admin-console">
      <AdminApp />
    </div>
  );
}
