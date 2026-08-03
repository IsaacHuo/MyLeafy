import { lazy, Suspense, useEffect, useRef, useState } from "react";
import type { MouseEvent, ReactNode } from "react";
import {
  ArrowRight,
  Buildings,
  CalendarBlank,
  ChatsCircle,
  CheckCircle,
  CloudCheck,
  Database,
  DeviceMobile,
  EnvelopeSimple,
  GraduationCap,
  Headset,
  House,
  List,
  LockKey,
  ShieldCheck,
  WarningCircle,
  X
} from "@phosphor-icons/react";
import {
  appStoreLinks,
  appScreenshots,
  capabilityStats,
  featureBands,
  featureShowcases,
  footerGroups,
  homeDataBoundaries,
  navItems,
  privacySections,
  privacySummaryCards,
  resourceLinks,
  site,
  supportChecklist,
  supportTopics,
  workflowCards
} from "./content";
import type { IconComponent } from "./types";
import { CopyEmailButton } from "./components/CopyEmailButton";
import { ScrollReveal, StaggerReveal, TapButton } from "./components/MotionBits";

const AdminConsole = lazy(() => import("./admin/AdminConsole"));

const pageTitles: Record<string, string> = {
  "/": "MyLeafy｜校园课表与校园工具",
  "/features": "MyLeafy 功能",
  "/support": "MyLeafy 技术支持",
  "/privacy": "MyLeafy 隐私政策",
  "/admin": "MyLeafy Admin",
  "/share/timetable": "MyLeafy 共享课表",
  "/share/community/post": "MyLeafy 社区帖子"
};

const primaryButtonClass =
  "border border-accent bg-accent text-forest shadow-[0_8px_24px_rgba(120,182,132,0.12)] hover:border-accent-strong hover:bg-accent-strong";
const secondaryButtonClass =
  "border border-white/20 bg-forest-elevated/80 text-ivory shadow-deep backdrop-blur-xl hover:border-white/30 hover:bg-forest-elevated";
const panelClass =
  "rounded-[24px] border border-white/10 bg-forest-elevated/80 p-6 shadow-deep backdrop-blur-xl";
const featuredPanelClass =
  "rounded-[24px] border border-accent/25 bg-accent-muted/50 p-6 shadow-deep";
const ruleStackClass =
  "overflow-hidden rounded-[24px] border border-white/10 bg-forest-elevated/70 shadow-deep";

function normalizedPath(pathname: string) {
  if (pathname === "/") return "/";
  return pathname.replace(/\/+$/, "");
}

function routeFromHref(href: string) {
  if (href.startsWith("mailto:")) return href;

  try {
    const url = new URL(href, window.location.origin);
    return normalizedPath(url.pathname) + url.hash;
  } catch {
    return href;
  }
}

function shouldUseClientNavigation(event: MouseEvent<HTMLAnchorElement>) {
  return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

function usePathname() {
  const [path, setPath] = useState(() => normalizedPath(window.location.pathname));

  useEffect(() => {
    function syncPath() {
      setPath(normalizedPath(window.location.pathname));
    }

    window.addEventListener("popstate", syncPath);
    return () => window.removeEventListener("popstate", syncPath);
  }, []);

  return [path, setPath] as const;
}

export default function App() {
  const [path, setPath] = usePathname();
  const isAdminPath = path === "/admin" || path.startsWith("/admin/");
  const isShareTimetablePath = path === "/share/timetable" || path.startsWith("/share/timetable/");
  const isShareCommunityPostPath = path === "/share/community/post" || path.startsWith("/share/community/post/");
  const activePath = isAdminPath
    ? "/admin"
    : isShareTimetablePath
      ? "/share/timetable"
      : isShareCommunityPostPath
        ? "/share/community/post"
        : path === "/features" || path === "/support" || path === "/privacy"
          ? path
          : "/";
  const timetableInviteCode = isShareTimetablePath ? path.split("/").pop() ?? "" : "";
  const communityPostID = isShareCommunityPostPath ? path.split("/").pop() ?? "" : "";
  const previousPath = useRef(activePath);

  useEffect(() => {
    document.title = pageTitles[activePath];
    document.documentElement.lang = activePath === "/admin" ? "en" : "zh-CN";
    if (previousPath.current !== activePath) {
      window.setTimeout(() => {
        document.querySelector<HTMLElement>("#main-content h1")?.focus({ preventScroll: true });
      }, 0);
    }
    previousPath.current = activePath;
  }, [activePath]);

  function navigate(href: string) {
    if (href.startsWith("mailto:")) {
      window.location.href = href;
      return;
    }

    if (href.startsWith("http")) {
      try {
        const url = new URL(href);
        const isLocalRoute = url.hostname === window.location.hostname || url.hostname === site.domain;
        if (!isLocalRoute) {
          window.location.href = href;
          return;
        }
      } catch {
        window.location.href = href;
        return;
      }
    }

    const next = routeFromHref(href);
    const [nextPath, hash = ""] = next.split("#");
    const targetPath = normalizedPath(nextPath || "/");
    window.history.pushState({}, "", targetPath + (hash ? "#" + hash : ""));
    setPath(targetPath);

    window.setTimeout(() => {
      const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
      if (hash) {
        document.getElementById(hash)?.scrollIntoView({ behavior, block: "start" });
      } else {
        window.scrollTo({ top: 0, behavior });
      }
    }, 0);
  }

  if (activePath === "/admin") {
    return (
      <Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">Loading admin...</main>}>
        <AdminConsole />
      </Suspense>
    );
  }

  return (
    <div className="public-site min-h-[100dvh] bg-paper text-text">
      <a className="skip-link" href="#main-content">跳到主要内容</a>
      <Header activePath={activePath} navigate={navigate} />
      <main id="main-content" tabIndex={-1}>
        {activePath === "/" && <HomePage navigate={navigate} />}
        {activePath === "/features" && <FeaturesPage navigate={navigate} />}
        {activePath === "/support" && <SupportPage />}
        {activePath === "/privacy" && <PrivacyPage />}
        {activePath === "/share/timetable" && <ShareTimetablePage code={timetableInviteCode} />}
        {activePath === "/share/community/post" && <ShareCommunityPostPage postID={communityPostID} />}
      </main>
      <Footer navigate={navigate} />
    </div>
  );
}

function Header({ activePath, navigate }: { activePath: string; navigate: (href: string) => void }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuButtonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => setMenuOpen(false), [activePath]);

  useEffect(() => {
    if (!menuOpen) return undefined;

    function closeOnEscape(event: KeyboardEvent) {
      if (event.key !== "Escape") return;
      setMenuOpen(false);
      menuButtonRef.current?.focus();
    }

    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [menuOpen]);

  function go(href: string) {
    setMenuOpen(false);
    navigate(href);
  }

  return (
    <header className="fixed top-0 z-40 w-full px-3 pt-3 md:px-5 md:pt-4">
      <div className="mx-auto flex h-16 max-w-7xl items-center rounded-full border border-white/10 bg-forest/80 px-4 shadow-deep backdrop-blur-2xl md:px-5">
        <a
          href="/"
          onClick={(event) => {
            if (!shouldUseClientNavigation(event)) return;
            event.preventDefault();
            go("/");
          }}
          className="leafy-pressable flex min-h-11 min-w-fit items-center gap-3 rounded-full"
          aria-label="MyLeafy 首页"
        >
          <img className="h-9 w-9 rounded-[11px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy 应用图标" />
          <strong className="text-lg font-semibold leading-none tracking-[-0.025em] text-ivory">MyLeafy</strong>
        </a>

        <nav aria-label="主导航" className="ml-8 hidden flex-1 items-center justify-center gap-1 md:flex">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route === "/" ? activePath === "/" : activePath === route;
            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  if (!shouldUseClientNavigation(event)) return;
                  event.preventDefault();
                  go(item.href);
                }}
                aria-current={isActive ? "page" : undefined}
                className={
                  "leafy-pressable inline-flex min-h-11 items-center whitespace-nowrap rounded-full px-4 py-2 text-sm font-medium transition-colors " +
                  (isActive ? "bg-white/10 text-ivory" : "text-ivory/60 hover:bg-white/[0.07] hover:text-ivory")
                }
              >
                {item.label}
              </a>
            );
          })}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <a
            href={"mailto:" + site.supportEmail}
            className="leafy-pressable hidden min-h-11 items-center rounded-full px-3 py-2 text-sm font-medium text-ivory/60 hover:bg-white/[0.07] hover:text-ivory lg:inline-flex"
          >
            联系我们
          </a>
          <div className="hidden sm:block">
            <AppStoreBadge compact />
          </div>
          <button
            ref={menuButtonRef}
            type="button"
            className="leafy-pressable grid h-11 w-11 place-items-center rounded-full border border-white/10 bg-white/[0.06] text-ivory md:hidden"
            aria-label={menuOpen ? "关闭导航菜单" : "打开导航菜单"}
            aria-expanded={menuOpen}
            aria-controls="mobile-navigation"
            onClick={() => setMenuOpen((value) => !value)}
          >
            {menuOpen ? <X size={21} weight="bold" aria-hidden /> : <List size={21} weight="bold" aria-hidden />}
          </button>
        </div>
      </div>

      {menuOpen && (
        <nav id="mobile-navigation" aria-label="移动端导航" className="mx-auto mt-2 grid max-w-7xl gap-1 rounded-[24px] border border-white/10 bg-forest/95 p-3 shadow-deep backdrop-blur-2xl md:hidden">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route === "/" ? activePath === "/" : activePath === route;
            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  if (!shouldUseClientNavigation(event)) return;
                  event.preventDefault();
                  go(item.href);
                }}
                aria-current={isActive ? "page" : undefined}
                className={
                  "leafy-pressable flex min-h-11 items-center rounded-2xl px-4 py-3 text-sm font-medium hover:bg-white/[0.07] hover:text-ivory " +
                  (isActive ? "bg-white/10 text-ivory" : "text-ivory/80")
                }
              >
                {item.label}
              </a>
            );
          })}
          <a className="leafy-pressable rounded-2xl px-4 py-3 text-sm font-medium text-accent" href={"mailto:" + site.supportEmail}>
            联系支持
          </a>
        </nav>
      )}
    </header>
  );
}

function HomePage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <section className="hero-canvas relative isolate flex min-h-[min(100dvh,860px)] items-end overflow-hidden pt-24 lg:min-h-[760px]">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover object-[48%_center]"
          src="/media/campus/rainy-woodland-path.jpg"
          alt=""
          aria-hidden
          decoding="async"
        />
        <div className="hero-scrim absolute inset-0 -z-10" aria-hidden />
        <div className="mx-auto grid w-full max-w-7xl items-end gap-8 px-4 pb-10 md:px-6 md:pb-14 lg:grid-cols-[0.88fr_1.12fr] lg:gap-4">
          <StaggerReveal className="relative z-10 max-w-xl pb-4 lg:pb-12">
            <p className="mb-5 text-sm font-semibold text-accent">为北林学生而做</p>
            <h1 tabIndex={-1} className="max-w-[720px] text-[clamp(2.75rem,6.25vw,5.8rem)] font-semibold leading-[0.98] tracking-[-0.025em] text-ivory">
              <span className="whitespace-nowrap">把校园生活，</span><br /><span className="whitespace-nowrap">放进一处。</span>
            </h1>
            <p className="mt-6 max-w-[500px] text-base leading-relaxed text-ivory/70 md:text-lg">
              课表、教务、社区与校园问答，集中在一款简洁的 iPhone App 中。
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <AppStoreBadge />
              <TapButton onClick={() => navigate("/features")} className={secondaryButtonClass + " px-5 text-[15px] font-semibold"}>
                查看功能
                <ArrowRight size={17} weight="bold" aria-hidden />
              </TapButton>
            </div>
          </StaggerReveal>

          <HeroPhones />
        </div>
      </section>

      <CampusIdentitySection />
      <AppExperienceSection />
      <HomeDataTrust />

      <section className="relative isolate overflow-hidden px-4 py-24 md:px-6 md:py-32">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover"
          src="/media/campus/campus-skyline-dusk.jpg"
          alt=""
          aria-hidden
          loading="lazy"
          decoding="async"
        />
        <div className="absolute inset-0 -z-10 bg-forest/90" aria-hidden />
        <ScrollReveal className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-9 md:flex-row md:items-end">
          <div className="max-w-3xl">
            <img className="h-16 w-16 rounded-[18px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy 应用图标" />
            <h2 className="mt-8 text-3xl font-semibold leading-[1.04] tracking-[-0.025em] text-ivory md:text-5xl">
              <span className="whitespace-nowrap">校园日常，</span><br /><span className="whitespace-nowrap">触手可及。</span>
            </h2>
            <p className="mt-5 max-w-xl text-base leading-relaxed text-ivory/60">
              打开 MyLeafy，从眼前这一周开始。
            </p>
          </div>
          <AppStoreBadge />
        </ScrollReveal>
      </section>
    </>
  );
}

function AppStoreBadge({ compact = false }: { compact?: boolean }) {
  return (
    <a
      href={site.appStoreUrl}
      className="app-store-badge leafy-pressable inline-flex min-h-11 shrink-0 items-center"
      aria-label="在 App Store 下载 MyLeafy"
    >
      <img className={(compact ? "h-10" : "h-12") + " w-auto max-w-none"} src="/media/download-on-the-app-store.svg" alt="" />
    </a>
  );
}

function PhoneFrame({
  image,
  alt,
  className = "",
  loading = "eager"
}: {
  image: string;
  alt: string;
  className?: string;
  loading?: "eager" | "lazy";
}) {
  return (
    <div className={"phone-frame relative aspect-[1350/2760] " + className}>
      <div className="phone-screen absolute overflow-hidden bg-forest">
        <img className="h-full w-full bg-white object-fill" src={image} alt={alt} loading={loading} decoding="async" />
      </div>
      <img
        className="pointer-events-none absolute inset-0 h-full w-full max-w-none"
        src="/media/iphone-17-pro-silver-portrait.png"
        alt=""
        aria-hidden
        loading={loading}
        decoding="async"
      />
    </div>
  );
}

function HeroPhones() {
  return (
    <div className="relative mx-auto min-h-[500px] w-full max-w-[650px] sm:min-h-[590px] lg:min-h-[650px]" aria-label="MyLeafy App 界面预览">
      <div className="hero-phone absolute bottom-0 left-[3%] z-10 w-[min(48vw,292px)]">
        <PhoneFrame image={appScreenshots[0].image} alt={appScreenshots[0].alt} />
      </div>
      <div className="hero-phone absolute bottom-[-8%] right-[4%] w-[min(48vw,292px)]">
        <PhoneFrame image={appScreenshots[1].image} alt={appScreenshots[1].alt} />
      </div>
    </div>
  );
}

function CampusIdentitySection() {
  return (
    <section className="bg-paper px-4 py-20 md:px-6 md:py-28">
      <div className="mx-auto max-w-7xl">
        <ScrollReveal className="grid gap-8 lg:grid-cols-[0.72fr_1.28fr] lg:items-end">
          <div>
            <h2 className="max-w-xl text-3xl font-semibold leading-[1.1] tracking-[-0.02em] text-ivory md:text-4xl">
              <span className="whitespace-nowrap">从正在发生的</span><br /><span className="whitespace-nowrap">校园生活出发。</span>
            </h2>
            <p className="mt-5 max-w-lg text-base leading-relaxed text-ivory/60">
              MyLeafy 将学校系统与校园日常汇在一起，让每次查看都更从容。
            </p>
          </div>
          <div className="overflow-hidden rounded-[28px] border border-white/10 bg-forest-elevated shadow-deep">
            <img
              className="aspect-[16/9] h-full w-full object-cover"
              src="/media/campus/classroom-at-dusk.jpg"
              alt="暮色窗景中的北京林业大学教室"
              loading="lazy"
              decoding="async"
            />
          </div>
        </ScrollReveal>
        <div className="mt-10 grid gap-x-8 sm:grid-cols-2 lg:grid-cols-4">
          {featureBands.map((item) => {
            const Icon = item.icon;
            return (
              <ScrollReveal key={item.label} className="border-t border-white/10 py-6">
                <Icon size={21} weight="bold" className="text-accent" aria-hidden />
                <p className="mt-4 text-sm font-semibold text-accent">{item.label}</p>
                <p className="mt-2 text-sm leading-relaxed text-ivory/60">{item.body}</p>
              </ScrollReveal>
            );
          })}
        </div>
      </div>
    </section>
  );
}

function AppExperienceSection() {
  const items = [
    { icon: CalendarBlank, title: "课表优先", body: "一眼查看当前周、课程、教室、提醒与考试。" },
    { icon: GraduationCap, title: "教务集中", body: "成绩、学习计划、学分、教室与校历有序归纳。" },
    { icon: ChatsCircle, title: "社区独立", body: "校园帖子与公告拥有独立空间，与学校登录数据分开。" }
  ];

  return (
    <section className="overflow-hidden border-y border-white/[0.07] bg-forest-low px-4 py-24 md:px-6 md:py-36">
      <div className="mx-auto max-w-7xl">
        <ScrollReveal className="max-w-3xl">
          <p className="text-sm font-semibold text-accent">MyLeafy 里面有什么</p>
          <h2 className="mt-5 text-3xl font-semibold leading-[1.08] tracking-[-0.025em] text-ivory md:text-5xl">
            <span className="whitespace-nowrap">先看这一周，</span><br /><span className="whitespace-nowrap">其他事情也不远。</span>
          </h2>
        </ScrollReveal>

        <div className="mt-16 grid gap-12 lg:grid-cols-[0.7fr_1.3fr] lg:items-center">
          <div className="border-t border-white/10">
            {items.map((item) => {
              const Icon = item.icon;
              return (
                <ScrollReveal key={item.title} className="grid grid-cols-[44px_1fr] gap-4 border-b border-white/10 py-6">
                  <span className="grid h-10 w-10 place-items-center rounded-xl bg-accent-muted text-accent">
                    <Icon size={20} weight="bold" aria-hidden />
                  </span>
                  <div>
                    <h3 className="text-base font-semibold text-ivory">{item.title}</h3>
                    <p className="mt-2 text-sm leading-relaxed text-ivory/60">{item.body}</p>
                  </div>
                </ScrollReveal>
              );
            })}
          </div>

          <ScrollReveal className="leafy-scrollbar-none -mx-4 flex snap-x snap-mandatory gap-5 overflow-x-auto px-4 pb-6 md:-mx-6 md:px-6 lg:mx-0 lg:px-0">
            {appScreenshots.slice(0, 3).map((shot, index) => (
              <div
                key={shot.label}
                className={"shrink-0 snap-center " + (index === 1 ? "mt-14 w-[min(62vw,260px)]" : "w-[min(62vw,285px)]")}
              >
                <PhoneFrame image={shot.image} alt={shot.alt} loading={index === 0 ? "eager" : "lazy"} />
              </div>
            ))}
          </ScrollReveal>
        </div>
      </div>
    </section>
  );
}

function HomeDataTrust() {
  const icons = [Buildings, Database, CloudCheck, ShieldCheck];

  return (
    <section className="border-t border-white/[0.07] bg-forest-low px-4 py-24 md:px-6 md:py-32">
      <ScrollReveal className="mx-auto grid max-w-7xl gap-14 lg:grid-cols-[0.72fr_1.28fr] lg:gap-24">
        <div>
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-accent-muted text-accent">
            <LockKey size={24} weight="bold" aria-hidden />
          </span>
          <h2 className="mt-8 max-w-lg text-3xl font-semibold leading-[1.08] tracking-[-0.025em] text-ivory md:text-4xl">
            <span className="whitespace-nowrap">每类数据，</span><br /><span className="whitespace-nowrap">都有清晰边界。</span>
          </h2>
          <p className="mt-5 max-w-md text-base leading-relaxed text-ivory/60">
            学校数据、本地存储、社区服务与公共官网各自独立，来源和用途清楚可见。
          </p>
        </div>
        <div className="grid gap-x-10 gap-y-9 sm:grid-cols-2">
          {homeDataBoundaries.map((item, index) => {
            const Icon = icons[index] ?? ShieldCheck;
            return (
              <div key={item.label} className="border-t border-white/10 pt-5">
                <Icon size={22} weight="bold" className="text-accent" aria-hidden />
                <p className="mt-5 text-sm font-semibold text-ivory/50">{item.label}</p>
                <h3 className="mt-2 text-2xl font-semibold tracking-[-0.025em] text-ivory">{item.value}</h3>
                <p className="mt-3 text-sm leading-relaxed text-ivory/50">{item.body}</p>
              </div>
            );
          })}
        </div>
      </ScrollReveal>
    </section>
  );
}

function FeaturesPage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <section className="relative isolate overflow-hidden px-4 pb-20 pt-32 md:px-6 md:pb-28 md:pt-40">
        <img
          className="absolute inset-0 -z-20 h-full w-full object-cover object-[center_54%]"
          src="/media/campus/autumn-campus-canopy.jpg"
          alt=""
          aria-hidden
          decoding="async"
        />
        <div className="hero-scrim absolute inset-0 -z-10" aria-hidden />
        <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[1fr_0.7fr] lg:items-end">
          <StaggerReveal className="max-w-3xl">
            <p className="text-sm font-semibold text-accent">功能</p>
            <h1 tabIndex={-1} className="mt-5 text-[clamp(2.75rem,6.25vw,5.7rem)] font-semibold leading-[0.98] tracking-[-0.025em] text-ivory">
              <span className="whitespace-nowrap">围绕校园节奏，</span><br /><span className="whitespace-nowrap">安排每一天。</span>
            </h1>
            <p className="mt-6 max-w-xl text-base leading-relaxed text-ivory/70 md:text-lg">
              从第一节课到当天最后一条校园通知，MyLeafy 让日程始终清楚。
            </p>
          </StaggerReveal>
          <div className="mx-auto w-[min(58vw,285px)] lg:mr-12">
            <PhoneFrame image={appScreenshots[2].image} alt={appScreenshots[2].alt} />
          </div>
        </div>
      </section>

      <CapabilityRail />

      <SectionShell id="product" title={<><span className="whitespace-nowrap">四个入口，</span><br /><span className="whitespace-nowrap">一条日常动线</span></>} body="每个入口各有职责，需要的信息一眼就能找到。">
        <FeatureBandList />
      </SectionShell>

      <FeatureImageShowcase />

      <section id="data" className="scroll-mt-24 border-y border-white/[0.07] bg-forest-low">
        <SectionShell title="数据保存在哪里" body="每类数据的来源与用途都清楚可见。">
          <DataBoundaryTable />
        </SectionShell>
      </section>

      <section id="community" className="scroll-mt-24 bg-paper">
        <SectionShell title="为每天反复查看而设计">
          <WorkflowList />
        </SectionShell>
      </section>

      <ResourcesSection navigate={navigate} />
    </>
  );
}

function CapabilityRail() {
  return (
    <section className="border-y border-white/[0.07] bg-forest">
      <div className="leafy-scrollbar-none mx-auto flex max-w-7xl overflow-x-auto px-4 md:px-6">
        {capabilityStats.map((metric) => (
          <div key={metric.label} className="min-w-[220px] flex-1 border-r border-white/[0.08] px-5 py-7 first:pl-0 last:border-r-0 last:pr-0">
            <span className="block text-xs font-medium text-ivory/60">{metric.label}</span>
            <span className="mt-2 block text-sm font-semibold text-ivory">{metric.value}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function FeatureBandList() {
  return (
    <div className="grid gap-x-10 gap-y-0 lg:grid-cols-2">
      {featureBands.map((item) => {
        const Icon = item.icon;
        return (
          <ScrollReveal key={item.label} className="grid grid-cols-[48px_1fr] gap-5 border-t border-white/10 py-8">
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
              <Icon size={22} weight="bold" aria-hidden />
            </span>
            <div>
              <p className="text-sm font-semibold text-accent">{item.label}</p>
              <h3 className="mt-3 text-2xl font-semibold leading-tight tracking-[-0.025em] text-ivory">{item.title}</h3>
              <p className="mt-3 max-w-xl text-sm leading-relaxed text-ivory/60">{item.body}</p>
            </div>
          </ScrollReveal>
        );
      })}
    </div>
  );
}

function FeatureImageShowcase() {
  return (
    <section id="screens" className="scroll-mt-24 overflow-hidden border-y border-white/[0.07] bg-forest-low py-24 md:py-32">
      <div className="mx-auto max-w-7xl px-4 md:px-6">
        <ScrollReveal className="max-w-3xl">
          <p className="text-sm font-semibold text-accent">App 实景</p>
          <h2 className="mt-5 text-3xl font-semibold leading-[1.08] tracking-[-0.025em] text-ivory md:text-5xl">
            <span className="whitespace-nowrap">每个日常，</span><br /><span className="whitespace-nowrap">都有专注的视图。</span>
          </h2>
          <p className="mt-5 max-w-xl text-base leading-relaxed text-ivory/60">
            课表、社区、成绩、学习资料、校园信息与 MyLeafy AI。
          </p>
        </ScrollReveal>
      </div>

      <div className="leafy-scrollbar-none mt-14 flex snap-x snap-mandatory gap-5 overflow-x-auto px-[max(1rem,calc((100vw-80rem)/2))] pb-7 md:gap-7">
        {featureShowcases.map((shot, index) => (
          <article key={shot.label} className="w-[min(82vw,340px)] shrink-0 snap-start">
            <div className="flex min-h-[590px] items-center justify-center rounded-[28px] border border-white/10 bg-forest p-6 shadow-deep">
              <PhoneFrame image={shot.image} alt={shot.alt} className="w-[84%]" loading={index < 2 ? "eager" : "lazy"} />
            </div>
            <p className="mt-5 text-sm font-semibold text-accent">{shot.label}</p>
            <h3 className="mt-2 text-2xl font-semibold leading-tight tracking-[-0.025em] text-ivory">{shot.title}</h3>
            <p className="mt-3 text-sm leading-relaxed text-ivory/60">{shot.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function DataBoundaryTable() {
  return (
    <div className="grid gap-5 md:grid-cols-2">
      {homeDataBoundaries.map((item) => (
        <div key={item.label} className="rounded-[24px] border border-white/10 bg-forest-elevated/60 p-6">
          <p className="text-sm font-semibold text-accent">{item.label}</p>
          <h3 className="mt-4 text-3xl font-semibold tracking-[-0.03em] text-ivory">{item.value}</h3>
          <p className="mt-4 text-sm leading-relaxed text-ivory/60">{item.body}</p>
        </div>
      ))}
    </div>
  );
}

function WorkflowList() {
  return (
    <div className="grid gap-12 lg:grid-cols-[0.7fr_1.3fr]">
      <div className="overflow-hidden rounded-[28px] border border-white/10">
        <img
          className="h-full min-h-[430px] w-full object-cover"
          src="/media/campus/campus-entrance-bicycles.jpg"
          alt="北京林业大学校门旁停放的自行车"
          loading="lazy"
          decoding="async"
        />
      </div>
      <div className="border-t border-white/10">
        {workflowCards.map((item) => {
          const Icon = item.icon;
          return (
            <div key={item.title} className="grid grid-cols-[48px_1fr] gap-5 border-b border-white/10 py-7">
              <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
                <Icon size={22} weight="bold" aria-hidden />
              </span>
              <div>
                <h3 className="text-2xl font-semibold tracking-[-0.025em] text-ivory">{item.title}</h3>
                <p className="mt-3 max-w-2xl text-sm leading-relaxed text-ivory/60">{item.body}</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ResourcesSection({ navigate }: { navigate: (href: string) => void }) {
  return (
    <section className="border-t border-white/[0.07] bg-paper">
      <SectionShell title="支持与公共链接">
        <div className="grid gap-5 lg:grid-cols-[0.74fr_1.26fr]">
          <div className={featuredPanelClass}>
            <LockKey size={25} weight="bold" className="text-accent" aria-hidden />
            <p className="mt-6 text-2xl font-semibold leading-tight text-ivory">联系方式与政策链接</p>
            <p className="mt-4 text-sm leading-relaxed text-ivory/60">
              支持邮箱：{site.supportEmail}。隐私政策：{site.privacyUrl}。
            </p>
          </div>
          <div className="grid gap-4 md:grid-cols-3">
            {resourceLinks.map((link) => (
              <a
                key={link.title}
                href={link.href}
                onClick={(event) => {
                  if (!shouldUseClientNavigation(event)) return;
                  event.preventDefault();
                  navigate(link.href);
                }}
                className="group rounded-[24px] border border-white/10 bg-forest-elevated/70 p-5 transition-colors hover:border-accent/30 hover:bg-forest-elevated"
              >
                <p className="text-sm font-semibold text-ivory/50">{link.title}</p>
                <p className="mt-4 min-h-24 text-sm leading-relaxed text-ivory/60">{link.body}</p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-accent">
                  {link.cta}
                  <ArrowRight size={16} weight="bold" className="transition-transform group-hover:translate-x-1" aria-hidden />
                </span>
              </a>
            ))}
          </div>
        </div>

        <div className={ruleStackClass + " mt-5"}>
          {appStoreLinks.map((link) => (
            <a
              key={link.label}
              href={link.value}
              onClick={(event) => {
                if (link.value.includes(site.domain) && shouldUseClientNavigation(event)) {
                  event.preventDefault();
                  navigate(link.value);
                }
              }}
              className="group grid gap-2 border-b border-white/10 px-5 py-5 last:border-b-0 hover:bg-white/[0.035] md:grid-cols-[0.9fr_1.4fr_auto] md:items-center"
            >
              <span className="text-sm font-semibold text-ivory/50">{link.label}</span>
              <span className="break-all text-sm font-medium text-ivory">{link.value}</span>
              <ArrowRight size={18} weight="bold" className="text-accent transition-transform group-hover:translate-x-1" aria-hidden />
            </a>
          ))}
        </div>
      </SectionShell>
    </section>
  );
}

function SupportPage() {
  const mailto = "mailto:" + site.supportEmail + "?subject=MyLeafy 技术支持";

  return (
    <>
      <PageHero
        icon={Headset}
        label="技术支持"
        title={<><span className="whitespace-nowrap">校园数据</span><br className="xl:hidden" /><span className="whitespace-nowrap">遇到问题时，</span><br /><span className="whitespace-nowrap">我们在这里。</span></>}
        body="登录、同步、课表解析、社区、分享或评价出现问题时，可通过邮件或 App 内反馈联系我们。"
        image="/media/campus/snowy-campus-building.jpg"
        imageAlt="雪中的北京林业大学校园建筑"
      >
        <div className="mt-8 flex flex-col items-start gap-3 sm:flex-row">
          <TapButton href={mailto} className={primaryButtonClass + " min-h-12 px-5"}>
            <EnvelopeSimple size={20} weight="bold" aria-hidden />
            发送邮件
          </TapButton>
          <CopyEmailButton email={site.supportEmail} />
        </div>
      </PageHero>

      <SectionShell title="公开联系方式" body="一般支持与隐私请求可通过邮件提交；需要设备与同步上下文时，建议使用 App 内反馈。">
        <div className="grid gap-5 lg:grid-cols-[1.2fr_0.8fr]">
          <div className={panelClass}>
            <p className="text-sm font-semibold text-ivory/50">支持邮箱</p>
            <a className="mt-3 block break-all text-3xl font-semibold leading-tight text-ivory hover:text-accent" href={mailto}>
              {site.supportEmail}
            </a>
            <p className="mt-4 max-w-[68ch] text-sm leading-relaxed text-ivory/60">
              此邮箱用于 App Store 技术支持、一般反馈、功能建议与隐私请求。
            </p>
          </div>
          <div id="in-app" className={featuredPanelClass + " scroll-mt-24"}>
            <CheckCircle size={24} weight="bold" className="text-accent" aria-hidden />
            <p className="mt-4 text-xl font-semibold text-ivory">App 内反馈可附带必要上下文</p>
            <p className="mt-3 text-sm leading-relaxed text-ivory/60">
              可包含设备型号、系统版本、App 版本、登录状态与最近同步时间。
            </p>
          </div>
        </div>
      </SectionShell>

      <SectionShell title="建议提供的信息">
        <NumberedList items={supportChecklist} />
      </SectionShell>

      <SectionShell title="常见支持主题">
        <AsymmetricIconGrid items={supportTopics} />
      </SectionShell>
    </>
  );
}

function PrivacyPage() {
  return (
    <>
      <PageHero
        icon={ShieldCheck}
        label="隐私"
        title={<><span className="whitespace-nowrap">用清楚的话，</span><br /><span className="whitespace-nowrap">说明数据边界。</span></>}
        body={"了解 MyLeafy 如何处理学校登录、设备数据、社区、反馈、评价、分享与官网数据。最后更新于 " + site.updatedAt + "。"}
        image="/media/campus/classroom-at-dusk.jpg"
        imageAlt="暮色中的北京林业大学教室"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href="#privacy-rights" className={primaryButtonClass}>
            <LockKey size={18} weight="bold" aria-hidden />
            查看隐私选择
          </TapButton>
          <TapButton href={"mailto:" + site.supportEmail + "?subject=MyLeafy 隐私请求"} className={secondaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            发送隐私请求
          </TapButton>
        </div>
      </PageHero>

      <SectionShell title="四件需要了解的事">
        <AsymmetricIconGrid items={privacySummaryCards} />
      </SectionShell>

      <article className="mx-auto max-w-6xl px-4 pb-24 md:px-6 md:pb-32">
        <div className={ruleStackClass}>
          {privacySections.map((section) => (
            <PrivacySection key={section.title} section={section} />
          ))}
        </div>
      </article>
    </>
  );
}

function ShareTimetablePage({ code }: { code: string }) {
  const [copyState, setCopyState] = useState<"idle" | "copied" | "error">("idle");
  const normalizedCode = code.toUpperCase().replace(/[^A-Z2-7]/g, "");
  const isValidCode = /^[A-Z2-7]{12}$/.test(normalizedCode);

  async function copyCode() {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard API unavailable");
      await navigator.clipboard.writeText(normalizedCode);
      setCopyState("copied");
      window.setTimeout(() => setCopyState("idle"), 1800);
    } catch {
      setCopyState("error");
    }
  }

  return (
    <>
      <PageHero
        icon={CalendarBlank}
        label="共享课表"
        title={isValidCode ? "在 MyLeafy 中查看共享课表。" : "这条共享课表链接不完整。"}
        body={isValidCode ? "复制邀请码，然后打开“我的 → 共享课表 → 添加同学课表”。" : "请让分享者重新发送完整链接。有效邀请码应包含 12 个字符。"}
        image="/media/campus/spring-blossoms-cat.jpg"
        imageAlt="北京林业大学校园里的春花与猫"
      >
        <div className="mt-8 grid max-w-xl gap-4">
          <div className={featuredPanelClass} role={isValidCode ? undefined : "alert"}>
            <p className="text-sm font-semibold text-ivory/50">邀请码</p>
            <p className="mt-3 break-all text-4xl font-semibold tracking-[-0.02em] text-ivory sm:text-5xl">{isValidCode ? normalizedCode : "链接无效"}</p>
            <p className="mt-4 text-sm leading-relaxed text-ivory/60">
              {isValidCode
                ? "邀请码 7 天内有效，仅可由一人接受；分享者之后仍可撤销访问。"
                : "无法通过此链接打开课表。请返回收到分享链接的消息，确认链接是否完整。"}
            </p>
          </div>
          {isValidCode && (
            <button type="button" onClick={copyCode} className={primaryButtonClass + " leafy-pressable inline-flex min-h-11 w-fit items-center gap-2 rounded-full px-5 text-sm font-medium"}>
              {copyState === "error" ? <WarningCircle size={18} weight="bold" aria-hidden /> : <CheckCircle size={18} weight="bold" aria-hidden />}
              {copyState === "copied" ? "已复制" : copyState === "error" ? "复制失败，请重试" : "复制邀请码"}
            </button>
          )}
          <p className="min-h-6 text-sm text-ivory/60" role="status" aria-live="polite">
            {copyState === "copied" ? "邀请码已复制到剪贴板。" : copyState === "error" ? "无法访问剪贴板，请选中邀请码并手动复制。" : ""}
          </p>
        </div>
      </PageHero>

      <SectionShell title="在 App 中接受邀请">
        <NumberedList items={["打开 MyLeafy。", "进入“我的 → 共享课表”。", "选择“添加同学课表”。", "粘贴邀请码，然后添加并查看课表。"]} />
      </SectionShell>
    </>
  );
}

function ShareCommunityPostPage({ postID }: { postID: string }) {
  const normalizedPostID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(postID) ? postID : "";
  const appURL = normalizedPostID ? "leafy://community-post?id=" + encodeURIComponent(normalizedPostID) : "";

  return (
    <>
      <PageHero
        icon={ChatsCircle}
        label="社区帖子"
        title={normalizedPostID ? "在 MyLeafy 中继续讨论。" : "这条社区帖子链接无效。"}
        body={normalizedPostID ? "此分享链接会在最新版本的 MyLeafy 中打开帖子详情。" : "帖子 ID 缺失或格式不正确，请让分享者重新发送链接。"}
        image="/media/campus/campus-entrance-bicycles.jpg"
        imageAlt="北京林业大学校门旁停放的自行车"
      >
        {normalizedPostID ? (
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <TapButton href={appURL} className={primaryButtonClass}>
              <DeviceMobile size={18} weight="bold" aria-hidden />
              打开 MyLeafy
            </TapButton>
            <TapButton href={site.appStoreUrl || site.supportUrl} className={secondaryButtonClass}>
              <ArrowRight size={18} weight="bold" aria-hidden />
              获取 MyLeafy
            </TapButton>
          </div>
        ) : (
          <div className={featuredPanelClass + " mt-8 max-w-xl"} role="alert">
            <p className="font-semibold text-ivory">无法通过此链接打开帖子。</p>
            <a className="leafy-pressable mt-4 inline-flex min-h-11 items-center rounded-full text-sm font-semibold text-accent" href="/support">
              联系支持
            </a>
          </div>
        )}
      </PageHero>

      <SectionShell title="在 App 中查看社区内容">
        <NumberedList
          items={[
            "分享卡片可能显示帖子标题与简短摘要，评论仍需在 App 中查看。",
            "登录 MyLeafy 后，App 会打开帖子详情。",
            "如果 App 已打开但没有显示帖子，请更新 MyLeafy 后重试。",
            "如果帖子已删除或不可见，App 会说明无法打开的原因。"
          ]}
        />
      </SectionShell>
    </>
  );
}

function PageHero({
  icon: Icon,
  label,
  title,
  body,
  image,
  imageAlt,
  children
}: {
  icon: IconComponent;
  label: string;
  title: ReactNode;
  body: string;
  image: string;
  imageAlt: string;
  children?: ReactNode;
}) {
  return (
    <section className="overflow-hidden border-b border-white/[0.07] bg-forest-low px-4 pb-20 pt-32 md:px-6 md:pb-28 md:pt-40">
      <div className="mx-auto grid max-w-7xl gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
        <StaggerReveal className="max-w-2xl">
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-accent-muted text-accent">
            <Icon size={24} weight="regular" aria-hidden />
          </span>
          <p className="mt-7 text-sm font-semibold text-accent">{label}</p>
          <h1 tabIndex={-1} className="mt-5 text-4xl font-semibold leading-[1.06] tracking-[-0.02em] text-ivory md:text-5xl xl:text-6xl">{title}</h1>
          <p className="mt-6 max-w-xl text-base leading-relaxed text-ivory/60 md:text-lg">{body}</p>
          {children}
        </StaggerReveal>
        <ScrollReveal className="overflow-hidden rounded-[28px] border border-white/10 shadow-deep">
          <img className="aspect-[4/3] w-full object-cover" src={image} alt={imageAlt} decoding="async" />
        </ScrollReveal>
      </div>
    </section>
  );
}

function SectionShell({
  title,
  body,
  children,
  id
}: {
  title: ReactNode;
  body?: string;
  children: ReactNode;
  id?: string;
}) {
  return (
    <section id={id} className="mx-auto max-w-7xl scroll-mt-24 px-4 py-20 md:px-6 md:py-28">
      <ScrollReveal className="mb-12 max-w-4xl">
        <h2 className="text-3xl font-semibold leading-[1.08] tracking-[-0.025em] text-ivory md:text-5xl">{title}</h2>
        {body && <p className="mt-5 max-w-2xl text-base leading-relaxed text-ivory/60">{body}</p>}
      </ScrollReveal>
      {children}
    </section>
  );
}

function NumberedList({ items }: { items: string[] }) {
  return (
    <div className={ruleStackClass}>
      {items.map((item, index) => (
        <div key={item} className="grid grid-cols-[48px_1fr] gap-4 border-b border-white/10 px-5 py-5 last:border-b-0">
          <span className="text-sm font-semibold text-accent">{String(index + 1).padStart(2, "0")}</span>
          <p className="text-sm leading-relaxed text-ivory/60">{item}</p>
        </div>
      ))}
    </div>
  );
}

function AsymmetricIconGrid({ items }: { items: Array<{ icon: IconComponent; title: string; body: string }> }) {
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      {items.map((item) => {
        const Icon = item.icon;
        return (
          <article key={item.title} className={panelClass}>
            <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
              <Icon size={23} weight="bold" aria-hidden />
            </span>
            <h3 className="mt-6 text-xl font-semibold text-ivory">{item.title}</h3>
            <p className="mt-3 max-w-[68ch] text-sm leading-relaxed text-ivory/60">{item.body}</p>
          </article>
        );
      })}
    </div>
  );
}

function PrivacySection({
  section
}: {
  section: {
    id?: string;
    title: string;
    icon: IconComponent;
    items: string[];
  };
}) {
  const Icon = section.icon;

  return (
    <section id={section.id} className="grid scroll-mt-24 gap-7 border-b border-white/10 px-5 py-9 last:border-b-0 md:grid-cols-[0.42fr_1fr] md:px-8">
      <div className="flex items-start gap-3">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-accent-muted text-accent">
          <Icon size={21} weight="bold" aria-hidden />
        </span>
        <h2 className="text-2xl font-semibold leading-tight text-ivory">{section.title}</h2>
      </div>
      <div className="space-y-4">
        {section.items.map((item) => (
          <p key={item} className="text-sm leading-relaxed text-ivory/60">
            {item}
          </p>
        ))}
      </div>
    </section>
  );
}

function Footer({ navigate }: { navigate: (href: string) => void }) {
  return (
    <footer className="border-t border-white/[0.07] bg-forest-low">
      <div className="mx-auto grid max-w-7xl gap-12 px-4 py-14 md:px-6 lg:grid-cols-[1.05fr_1.95fr]">
        <div>
          <div className="flex items-center gap-3">
            <img className="h-11 w-11 rounded-[13px] border border-white/10 shadow-deep" src="/app-icon.png" alt="MyLeafy 应用图标" />
            <div>
              <p className="text-xl font-semibold leading-none text-ivory">MyLeafy</p>
              <p className="mt-1 text-sm font-medium text-ivory/50">北林校园工具</p>
            </div>
          </div>
          <p className="mt-6 max-w-sm text-sm leading-relaxed text-ivory/50">
            目前支持北京林业大学。
          </p>
          <a
            href={"mailto:" + site.supportEmail}
            className="leafy-pressable mt-6 inline-flex min-h-11 items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 text-sm font-semibold text-ivory hover:border-accent/30 hover:text-accent"
          >
            <EnvelopeSimple size={17} weight="bold" aria-hidden />
            {site.supportEmail}
          </a>
        </div>

        <nav aria-label="页脚导航" className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
          {footerGroups.map((group) => (
            <div key={group.title}>
              <h2 className="text-sm font-semibold text-ivory">{group.title}</h2>
              <div className="mt-4 grid gap-3">
                {group.links.map((link) => (
                  <a
                    key={group.title + "-" + link.label}
                    href={link.href}
                    onClick={(event) => {
                      if (link.href.startsWith("http") && !link.href.includes(site.domain)) return;
                      if (link.href.startsWith("mailto:")) return;
                      if (!shouldUseClientNavigation(event)) return;
                      event.preventDefault();
                      navigate(link.href);
                    }}
                    className="leafy-pressable flex min-h-11 items-center break-words text-sm font-medium leading-relaxed text-ivory/60 hover:text-accent"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            </div>
          ))}
        </nav>
      </div>
      <div className="border-t border-white/[0.07] px-4 py-5 md:px-6">
        <div className="mx-auto flex max-w-7xl flex-col gap-3 text-xs font-medium text-ivory/60 md:flex-row md:items-center md:justify-between">
          <div className="grid gap-1">
            <span>最后更新：{site.updatedAt}</span>
            <span>Apple、Apple 标志、App Store 与 iPhone 是 Apple Inc. 的商标。</span>
          </div>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            <a
              className="leafy-pressable inline-flex min-h-11 items-center gap-2 hover:text-accent"
              href="/"
              onClick={(event) => {
                if (!shouldUseClientNavigation(event)) return;
                event.preventDefault();
                navigate("/");
              }}
            >
              <House size={15} aria-hidden />
              首页
            </a>
            <a className="leafy-pressable inline-flex min-h-11 items-center gap-2 hover:text-accent" href={"mailto:" + site.supportEmail}>
              <EnvelopeSimple size={15} aria-hidden />
              联系我们
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
