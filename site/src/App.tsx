import { lazy, Suspense, useEffect, useState } from "react";
import {
  ArrowRight,
  CalendarBlank,
  CaretRight,
  ChatsCircle,
  CheckCircle,
  DeviceMobile,
  EnvelopeSimple,
  House,
  Lifebuoy,
  LockKey,
  ShieldCheck
} from "@phosphor-icons/react";
import {
  appScreenshots,
  appStoreLinks,
  capabilityStats,
  footerGroups,
  homeDataBoundaries,
  navItems,
  privacySections,
  privacySummaryCards,
  productCards,
  resourceLinks,
  site,
  supportChecklist,
  supportTopics,
  workflowCards
} from "./content";
import type { IconComponent } from "./types";
import { CopyEmailButton } from "./components/CopyEmailButton";
import { StaggerReveal, TapButton } from "./components/MotionBits";

const AdminConsole = lazy(() => import("./admin/AdminConsole"));

const pageTitles: Record<string, string> = {
  "/": "MyLeafy | 校园课表与校园工具",
  "/support": "MyLeafy 技术支持",
  "/privacy": "MyLeafy 隐私政策",
  "/admin": "MyLeafy Admin",
  "/share/timetable": "MyLeafy 共享课表",
  "/share/community/post": "MyLeafy 社区帖子"
};

const primaryButtonClass = "border border-primary bg-primary text-white shadow-primary hover:bg-primary-strong";
const secondaryButtonClass = "border border-black/10 bg-white text-text hover:border-black/30 hover:bg-paper";
const panelClass = "rounded-md border border-black/10 bg-white p-6 shadow-[0_18px_50px_rgba(23,23,23,0.04)]";
const featuredPanelClass = "rounded-md border border-primary/25 bg-primary-wash p-6";
const ruleStackClass = "divide-y divide-black/10 rounded-md border border-black/10 bg-white";

function normalizedPath(pathname: string) {
  if (pathname === "/") {
    return "/";
  }

  return pathname.replace(/\/+$/, "");
}

function routeFromHref(href: string) {
  if (href.startsWith("mailto:")) {
    return href;
  }

  try {
    const url = new URL(href, window.location.origin);
    return `${normalizedPath(url.pathname)}${url.hash}`;
  } catch {
    return href;
  }
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
        : path === "/support" || path === "/privacy"
          ? path
          : "/";
  const timetableInviteCode = isShareTimetablePath ? path.split("/").pop() ?? "" : "";
  const communityPostID = isShareCommunityPostPath ? path.split("/").pop() ?? "" : "";

  useEffect(() => {
    document.title = pageTitles[activePath];
  }, [activePath]);

  function navigate(href: string) {
    if (href.startsWith("mailto:") || href.startsWith("http")) {
      window.location.href = href;
      return;
    }

    const next = routeFromHref(href);
    const [nextPath, hash = ""] = next.split("#");
    const targetPath = normalizedPath(nextPath || "/");
    window.history.pushState({}, "", `${targetPath}${hash ? `#${hash}` : ""}`);
    setPath(targetPath);

    window.setTimeout(() => {
      if (hash) {
        document.getElementById(hash)?.scrollIntoView({ behavior: "smooth", block: "start" });
      } else {
        window.scrollTo({ top: 0, behavior: "smooth" });
      }
    }, 0);
  }

  if (activePath === "/admin") {
    return (
      <Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">加载后台...</main>}>
        <AdminConsole />
      </Suspense>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-paper text-text">
      <Header activePath={activePath} navigate={navigate} />
      <main>
        {activePath === "/" && <HomePage navigate={navigate} />}
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
  return (
    <header className="sticky top-0 z-30 border-b border-black/10 bg-white/90 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-3 px-4 py-3 md:px-6">
        <a
          href="/"
          onClick={(event) => {
            event.preventDefault();
            navigate("/");
          }}
          className="flex min-w-fit items-center gap-3"
          aria-label="MyLeafy 首页"
        >
          <img className="h-8 w-8 rounded-md border border-black/10" src="/app-icon.png" alt="MyLeafy 应用图标" />
          <strong className="text-xl font-semibold leading-none text-text">MyLeafy</strong>
        </a>

        <nav className="leafy-scrollbar-none order-3 flex w-full min-w-0 gap-1 overflow-x-auto md:order-none md:ml-6 md:w-auto md:flex-1 md:items-center">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route !== "/" && activePath === route;

            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  event.preventDefault();
                  navigate(item.href);
                }}
                className={`whitespace-nowrap rounded-md px-2 py-2 text-[13px] font-medium transition-colors sm:px-3 sm:text-sm ${
                  isActive ? "bg-primary-wash text-primary-ink" : "text-text/68 hover:bg-paper hover:text-text"
                }`}
              >
                {item.label}
              </a>
            );
          })}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <a
            href={`mailto:${site.supportEmail}`}
            className="hidden rounded-md px-3 py-2 text-sm font-medium text-text/68 transition-colors hover:bg-paper hover:text-text sm:inline-flex"
          >
            Contact
          </a>
          <button
            type="button"
            onClick={() => navigate("/support")}
            className="inline-flex min-h-10 items-center justify-center rounded-md border border-primary bg-primary px-4 text-sm font-medium text-white shadow-primary transition-colors hover:bg-primary-strong"
          >
            技术支持
          </button>
        </div>
      </div>
    </header>
  );
}

function HomePage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <section className="relative overflow-hidden border-b border-black/10 bg-paper">
        <div className="mx-auto flex min-h-[calc(82dvh-65px)] max-w-7xl flex-col items-center justify-center px-4 py-14 text-center md:min-h-[calc(100dvh-65px)] md:px-6 lg:py-20">
          <StaggerReveal className="w-full max-w-5xl">
            <a
              href="#product"
              onClick={(event) => {
                event.preventDefault();
                navigate("/#product");
              }}
              className="mb-7 inline-flex items-center gap-3 rounded-full border border-black/10 bg-white px-4 py-2 text-sm font-medium text-text shadow-[0_10px_28px_rgba(23,23,23,0.08)]"
            >
              <span className="inline-block h-2 w-2 rounded-full bg-primary shadow-[0_0_0_4px_rgba(79,143,103,0.16)]" />
              MyLeafy 1.8 正在整理校园工作流
              <CaretRight size={15} weight="bold" aria-hidden />
            </a>
            <h1 className="text-5xl font-semibold leading-none tracking-normal text-text md:text-7xl lg:text-8xl">
              校园日常
              <span className="block text-primary">从课表开始</span>
            </h1>
            <p className="mx-auto mt-7 max-w-[72ch] text-lg font-normal leading-relaxed text-text/70 md:text-xl">
              MyLeafy 把校园同学每天会查的课表、成绩、考试、空教室、社区、评教和反馈整理在一起；当前支持北京林业大学。
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <TapButton href="/support" className={primaryButtonClass}>
                <Lifebuoy size={18} weight="bold" aria-hidden />
                获取技术支持
              </TapButton>
              <TapButton href="/privacy" className={secondaryButtonClass}>
                <ShieldCheck size={18} weight="bold" aria-hidden />
                查看隐私政策
              </TapButton>
            </div>
          </StaggerReveal>
        </div>
        <CapabilityRail />
      </section>

      <ProductPreview />

      <SectionShell id="product" eyebrow="Product" title="为校园日常保留清晰入口">
        <div className="grid auto-rows-fr gap-4 md:grid-cols-2 xl:grid-cols-4">
          {productCards.map((feature, index) => (
            <ProductCard key={feature.label} feature={feature} featured={index === 0} />
          ))}
        </div>
      </SectionShell>

      <ScreenshotsSection />

      <SectionShell id="data" eyebrow="Data boundaries" title="数据在哪里，官网就说到哪里">
        <div className={ruleStackClass}>
          {homeDataBoundaries.map((item) => (
            <div key={item.label} className="grid gap-3 px-5 py-6 md:grid-cols-[0.72fr_0.68fr_1.6fr] md:items-start">
              <p className="text-sm font-medium text-text/58">{item.label}</p>
              <p className="text-sm font-semibold text-text">{item.value}</p>
              <p className="max-w-[72ch] text-sm font-normal leading-relaxed text-text/68">{item.body}</p>
            </div>
          ))}
        </div>
      </SectionShell>

      <section id="community" className="border-y border-black/10 bg-white">
        <div className="mx-auto grid max-w-7xl gap-4 px-4 py-14 md:px-6 md:py-20 lg:grid-cols-3">
          {workflowCards.map((item) => {
            const Icon = item.icon;
            return (
              <article key={item.title} className="rounded-md border border-black/10 bg-paper p-6">
                <div className="grid h-10 w-10 place-items-center rounded-md border border-black/10 bg-white text-primary-ink">
                  <Icon size={21} weight="bold" aria-hidden />
                </div>
                <h3 className="mt-6 text-xl font-semibold leading-tight text-text">{item.title}</h3>
                <p className="mt-3 text-sm font-normal leading-relaxed text-text/68">{item.body}</p>
              </article>
            );
          })}
        </div>
      </section>

      <SectionShell eyebrow="Resources" title="公开支持与 App Store 信息">
        <div className="grid gap-4 lg:grid-cols-[0.9fr_1.35fr]">
          <div className={featuredPanelClass}>
            <LockKey size={24} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-5 text-lg font-semibold text-text">官网信息清晰透明</p>
            <p className="mt-3 text-sm font-normal leading-relaxed text-text/68">
              站点提供产品说明、邮件入口和 App Store 所需链接，同时说明 MyLeafy 的数据处理方式和联系方式。
            </p>
          </div>
          <div className="grid gap-4 md:grid-cols-3">
            {resourceLinks.map((link) => (
              <a key={link.title} href={link.href} className="group rounded-md border border-black/10 bg-white p-5 transition-colors hover:bg-primary-soft">
                <p className="text-sm font-medium text-text/58">{link.title}</p>
                <p className="mt-3 min-h-20 text-sm font-normal leading-relaxed text-text/68">{link.body}</p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-semibold text-primary-ink">
                  {link.cta}
                  <ArrowRight size={16} weight="bold" className="transition-transform group-hover:translate-x-1" aria-hidden />
                </span>
              </a>
            ))}
          </div>
        </div>
        <div className={`${ruleStackClass} mt-4`}>
          {appStoreLinks.map((link) => (
            <a
              key={link.label}
              href={link.value}
              className="group grid gap-2 px-5 py-5 transition-colors hover:bg-primary-soft md:grid-cols-[0.9fr_1.4fr_auto] md:items-center"
            >
              <span className="text-sm font-medium text-text/58">{link.label}</span>
              <span className="break-all text-sm font-medium text-text">{link.value}</span>
              <ArrowRight
                size={18}
                weight="bold"
                className="text-primary-ink transition-transform group-hover:translate-x-1"
                aria-hidden
              />
            </a>
          ))}
        </div>
      </SectionShell>
    </>
  );
}

function CapabilityRail() {
  return (
    <div className="overflow-hidden border-t border-black/10 bg-white py-3">
      <div className="mx-auto flex max-w-7xl gap-3 overflow-x-auto px-4 md:px-6">
        {capabilityStats.map((metric) => (
          <div
            key={metric.label}
            className="flex min-w-44 items-center justify-between gap-7 rounded-md border border-black/10 bg-paper px-4 py-3"
          >
            <span className="text-sm font-medium text-text/58">{metric.label}</span>
            <span className="text-sm font-medium text-text">{metric.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function ProductPreview() {
  const primaryShot = appScreenshots[0];

  return (
    <section className="bg-white">
      <div className="mx-auto grid max-w-7xl gap-8 px-4 py-14 md:px-6 md:py-20 lg:grid-cols-[0.82fr_1.18fr] lg:items-center">
        <div>
          <p className="text-sm font-medium text-primary-ink">Build for BJFU</p>
          <h2 className="mt-4 max-w-3xl text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">
            每天要查的东西，打开就能找到
          </h2>
          <p className="mt-5 max-w-[64ch] text-base font-normal leading-relaxed text-text/68">
            MyLeafy 围绕校园里的高频场景组织信息：打开 App 先看到今天的课，网络波动时继续查看缓存，遇到问题也可以从 App 内反馈并带上必要上下文。
          </p>
          <div className="mt-7 grid gap-3 sm:grid-cols-2">
            {["课表是默认入口", "教务登录独立处理", "官网提供公开链接", "支持信息可直接查看"].map((item) => (
              <div key={item} className="flex items-center gap-3 rounded-md border border-black/10 bg-paper px-4 py-3 text-sm font-medium text-text">
                <CheckCircle size={18} weight="bold" className="text-primary-ink" aria-hidden />
                {item}
              </div>
            ))}
          </div>
        </div>
        <div className="rounded-md border border-black/10 bg-paper p-4 shadow-[0_28px_90px_rgba(23,23,23,0.08)]">
          <div className="flex items-center justify-between border-b border-black/10 px-2 pb-3 text-xs font-medium text-text/58">
            <span>MyLeafy.app</span>
            <span>App screens</span>
          </div>
          <div className="grid gap-4 pt-4 lg:grid-cols-[0.92fr_1.08fr]">
            <PhoneFrame image={primaryShot.image} alt={primaryShot.alt} />
            <div className="grid content-between gap-4">
              <div className={panelClass}>
                <p className="text-sm font-medium text-text/58">Live surface</p>
                <h3 className="mt-3 text-2xl font-semibold leading-tight text-text">来自 MyLeafy 的真实界面</h3>
                <p className="mt-4 text-sm font-normal leading-relaxed text-text/68">
                  这些画面展示了 MyLeafy 当前的课表、社区、学业和个人资料入口，方便你快速了解 App 的信息结构。
                </p>
              </div>
              <div className="grid gap-2">
                {appScreenshots.slice(1).map((shot) => (
                  <div key={shot.label} className="flex items-center justify-between rounded-md border border-black/10 bg-white px-4 py-3">
                    <div>
                      <p className="text-sm font-semibold text-text">{shot.title}</p>
                      <p className="mt-1 text-xs font-medium text-text/58">{shot.body}</p>
                    </div>
                    <ArrowRight size={17} weight="bold" className="text-primary-ink" aria-hidden />
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function ScreenshotsSection() {
  return (
    <section className="border-y border-black/10 bg-paper">
      <div className="mx-auto max-w-7xl px-4 py-14 md:px-6 md:py-20">
        <div className="mb-8 grid gap-4 md:grid-cols-[0.72fr_1.28fr] md:items-end">
          <p className="text-sm font-medium text-primary-ink">Screens</p>
          <h2 className="max-w-4xl text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">
            四个主入口，覆盖课表、社区、学业和个人资料
          </h2>
        </div>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {appScreenshots.map((shot) => (
            <article key={shot.label} className="overflow-hidden rounded-md border border-black/10 bg-white">
              <div className="border-b border-black/10 bg-paper p-5">
                <PhoneFrame image={shot.image} alt={shot.alt} compact />
              </div>
              <div className="p-5">
                <p className="text-xs font-semibold uppercase text-primary-ink">{shot.label}</p>
                <h3 className="mt-2 text-xl font-semibold leading-tight text-text">{shot.title}</h3>
                <p className="mt-3 text-sm font-normal leading-relaxed text-text/68">{shot.body}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function PhoneFrame({ image, alt, compact = false }: { image: string; alt: string; compact?: boolean }) {
  return (
    <div className={`mx-auto rounded-[2rem] border border-black/10 bg-[#f4f5f2] p-2 shadow-[0_24px_70px_rgba(23,23,23,0.12)] ${compact ? "max-w-[210px]" : "max-w-[260px]"}`}>
      <div className="overflow-hidden rounded-[1.45rem] border border-black/10 bg-white">
        <img className="aspect-[369/800] w-full object-cover" src={image} alt={alt} loading="lazy" decoding="async" />
      </div>
    </div>
  );
}

function ProductCard({
  feature,
  featured = false
}: {
  feature: (typeof productCards)[number];
  featured?: boolean;
}) {
  const Icon = feature.icon;

  return (
    <section className={`${featured ? "border-primary/25 bg-primary-wash" : "border-black/10 bg-white"} flex min-h-72 flex-col justify-between rounded-md border p-6`}>
      <div>
        <div className="mb-8 flex items-center justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-md border border-black/10 bg-white text-primary-ink">
            <Icon size={23} weight="bold" aria-hidden />
          </div>
          <span className="rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-medium text-text/58">{feature.detail}</span>
        </div>
        <p className="text-sm font-medium text-text/58">{feature.label}</p>
        <h3 className="mt-3 max-w-xl text-2xl font-semibold leading-tight text-text">{feature.title}</h3>
      </div>
      <p className="mt-8 max-w-[68ch] text-sm font-normal leading-relaxed text-text/68">{feature.body}</p>
    </section>
  );
}

function SupportPage() {
  const mailto = `mailto:${site.supportEmail}?subject=MyLeafy 技术支持`;

  return (
    <>
      <PageHero
        icon={Lifebuoy}
        label="Support"
        title="技术支持"
        body="遇到登录、同步、课表解析、社区或评教问题时，可以通过邮件或 App 内意见反馈联系。反馈时提供页面路径、错误提示和设备信息会更方便定位。"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={mailto} className={primaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            发送邮件
          </TapButton>
          <CopyEmailButton email={site.supportEmail} />
        </div>
      </PageHero>

      <SectionShell eyebrow="Contact" title="公开联系方式">
        <div className="grid gap-4 lg:grid-cols-[1.25fr_0.75fr]">
          <div className={panelClass}>
            <p className="text-sm font-medium text-text/58">支持邮箱</p>
            <a className="mt-3 block break-all text-2xl font-semibold leading-tight text-text hover:text-primary-ink" href={mailto}>
              {site.supportEmail}
            </a>
            <p className="mt-4 max-w-[68ch] text-sm font-normal leading-relaxed text-text/68">
              这个邮箱用于 App Store 技术支持、一般反馈和功能建议。隐私访问、更正、删除请求也可以通过该邮箱提交。
            </p>
          </div>
          <div id="in-app" className={`${featuredPanelClass} scroll-mt-24`}>
            <CheckCircle size={24} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-4 text-lg font-semibold text-text">App 内反馈更适合排查问题</p>
            <p className="mt-3 text-sm font-normal leading-relaxed text-text/68">
              App 内反馈会附带设备型号、系统版本、App 版本、登录状态和最近同步时间，定位同步问题更快。
            </p>
          </div>
        </div>
      </SectionShell>

      <SectionShell eyebrow="Before sending" title="建议提供的信息">
        <div className={ruleStackClass}>
          {supportChecklist.map((item, index) => (
            <div key={item} className="grid grid-cols-[44px_1fr] gap-4 px-5 py-5">
              <span className="text-sm font-medium text-primary-ink">{String(index + 1).padStart(2, "0")}</span>
              <p className="text-sm font-normal leading-relaxed text-text/68">{item}</p>
            </div>
          ))}
        </div>
      </SectionShell>

      <SectionShell eyebrow="Scope" title="常见支持范围">
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
        label="Privacy"
        title="隐私政策"
        body={`本政策说明 MyLeafy 如何处理教务登录、本地缓存、社区、反馈、评教和官网相关数据。最近更新：${site.updatedAt}。`}
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href="#privacy-rights" className={primaryButtonClass}>
            <LockKey size={18} weight="bold" aria-hidden />
            查看隐私选择
          </TapButton>
          <TapButton href={`mailto:${site.supportEmail}?subject=MyLeafy 隐私请求`} className={secondaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            提交隐私请求
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Quick read" title="先读这四点">
        <AsymmetricIconGrid items={privacySummaryCards} />
      </SectionShell>

      <article className="mx-auto max-w-5xl px-4 py-14 md:px-6">
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
  const [copied, setCopied] = useState(false);
  const normalizedCode = code.toUpperCase().replace(/[^A-Z2-7]/g, "");

  async function copyCode() {
    await navigator.clipboard?.writeText(normalizedCode);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <>
      <PageHero
        icon={CalendarBlank}
        label="Shared timetable"
        title="共享课表邀请"
        body="请复制邀请码，在 MyLeafy 内进入 我的 -> 共享课表 -> 右上角 +，粘贴后接受邀请。"
      >
        <div className="mt-8 grid max-w-xl gap-4">
          <div className={featuredPanelClass}>
            <p className="text-sm font-medium text-text/58">邀请码</p>
            <p className="mt-3 break-all text-5xl font-semibold tracking-normal text-text">{normalizedCode || "未识别"}</p>
            <p className="mt-4 text-sm font-normal leading-relaxed text-text/68">
              邀请码 7 天内有效，且只能被一位同学接受。接受后对方仍可随时撤销查看权限。
            </p>
          </div>
          <button type="button" onClick={copyCode} className={`${primaryButtonClass} inline-flex min-h-11 w-fit items-center gap-2 rounded-md px-5 text-sm font-medium`}>
            <CheckCircle size={18} weight="bold" aria-hidden />
            {copied ? "已复制" : "复制邀请码"}
          </button>
        </div>
      </PageHero>

      <SectionShell eyebrow="Accept" title="在 App 内接受">
        <div className={ruleStackClass}>
          {["打开 MyLeafy。", "进入 我的 -> 共享课表。", "点右上角 +。", "粘贴邀请码并接受。"].map((item, index) => (
            <div key={item} className="grid grid-cols-[44px_1fr] gap-4 px-5 py-5">
              <span className="text-sm font-medium text-primary-ink">{String(index + 1).padStart(2, "0")}</span>
              <p className="text-sm font-normal leading-relaxed text-text/68">{item}</p>
            </div>
          ))}
        </div>
      </SectionShell>
    </>
  );
}

function ShareCommunityPostPage({ postID }: { postID: string }) {
  const normalizedPostID = postID.match(/^[0-9a-fA-F-]{36}$/) ? postID : "";
  const appURL = normalizedPostID ? `https://${site.domain}/share/community/post/${normalizedPostID}?open=1` : site.homeUrl;

  return (
    <>
      <PageHero
        icon={ChatsCircle}
        label="Community post"
        title="MyLeafy 社区帖子"
        body="这是一条 MyLeafy 社区分享链接。已安装最新版 MyLeafy 时会直接打开帖子详情；如果浏览器仍停留在本页，请先获取或更新 App。"
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={appURL} className={primaryButtonClass}>
            <DeviceMobile size={18} weight="bold" aria-hidden />
            打开 MyLeafy
          </TapButton>
          <TapButton href={site.appStoreUrl || site.supportUrl} className={secondaryButtonClass}>
            <ArrowRight size={18} weight="bold" aria-hidden />
            获取/更新 MyLeafy
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Privacy" title="社区内容只在 App 内查看">
        <div className={ruleStackClass}>
          {["分享卡片会展示帖子标题和短摘要，评论仍只在 App 内查看。", "登录 MyLeafy 后会进入该帖子详情。", "如果 App 已打开但没有进入详情，说明当前版本过旧，请更新后再打开。", "如果帖子已删除或不可见，App 会提示无法打开。"].map((item, index) => (
            <div key={item} className="grid grid-cols-[44px_1fr] gap-4 px-5 py-5">
              <span className="text-sm font-medium text-primary-ink">{String(index + 1).padStart(2, "0")}</span>
              <p className="text-sm font-normal leading-relaxed text-text/68">{item}</p>
            </div>
          ))}
        </div>
      </SectionShell>
    </>
  );
}

function PageHero({
  icon: Icon,
  label,
  title,
  body,
  children
}: {
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  children?: React.ReactNode;
}) {
  return (
    <section className="border-b border-black/10 bg-paper">
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-16 md:px-6 lg:grid-cols-[0.58fr_1.42fr] lg:py-20">
        <div>
          <div className="inline-grid h-12 w-12 place-items-center rounded-md border border-primary/25 bg-primary-wash text-primary-ink">
            <Icon size={24} weight="bold" aria-hidden />
          </div>
        </div>
        <div>
          <p className="text-sm font-medium text-primary-ink">{label}</p>
          <h1 className="mt-4 text-5xl font-semibold leading-none tracking-normal text-text md:text-7xl">{title}</h1>
          <p className="mt-6 max-w-[72ch] text-lg font-normal leading-relaxed text-text/68">{body}</p>
          {children}
        </div>
      </div>
    </section>
  );
}

function SectionShell({ eyebrow, title, children, id }: { eyebrow: string; title: string; children: React.ReactNode; id?: string }) {
  return (
    <section id={id} className="mx-auto max-w-7xl scroll-mt-24 px-4 py-14 md:px-6 md:py-20">
      <div className="mb-8 grid gap-4 md:grid-cols-[0.58fr_1.42fr] md:items-end">
        <p className="text-sm font-medium text-primary-ink">{eyebrow}</p>
        <h2 className="max-w-4xl text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">{title}</h2>
      </div>
      {children}
    </section>
  );
}

function AsymmetricIconGrid({ items }: { items: Array<{ icon: IconComponent; title: string; body: string }> }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {items.map((item) => {
        const Icon = item.icon;

        return (
          <section key={item.title} className={panelClass}>
            <div className="grid h-11 w-11 place-items-center rounded-md border border-primary/25 bg-primary-wash text-primary-ink">
              <Icon size={23} weight="bold" aria-hidden />
            </div>
            <h3 className="mt-6 text-xl font-semibold text-text">{item.title}</h3>
            <p className="mt-3 max-w-[68ch] text-sm font-normal leading-relaxed text-text/68">{item.body}</p>
          </section>
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
    <section id={section.id} className="grid gap-6 scroll-mt-24 px-5 py-8 md:grid-cols-[0.42fr_1fr]">
      <div className="flex items-center gap-3 md:items-start">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-md border border-primary/25 bg-primary-wash text-primary-ink">
          <Icon size={21} weight="bold" aria-hidden />
        </span>
        <h2 className="text-2xl font-semibold leading-tight text-text">{section.title}</h2>
      </div>
      <div className="space-y-4">
        {section.items.map((item) => (
          <p key={item} className="text-sm font-normal leading-relaxed text-text/68">
            {item}
          </p>
        ))}
      </div>
    </section>
  );
}

function Footer({ navigate }: { navigate: (href: string) => void }) {
  return (
    <footer className="border-t border-black/10 bg-white">
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-12 md:px-6 lg:grid-cols-[1.2fr_1.8fr]">
        <div>
          <div className="flex items-center gap-3">
            <img className="h-10 w-10 rounded-md border border-black/10" src="/app-icon.png" alt="MyLeafy 应用图标" />
            <div>
              <p className="text-xl font-semibold leading-none text-text">MyLeafy</p>
              <p className="mt-1 text-sm font-medium text-text/58">BJFU campus tool</p>
            </div>
          </div>
          <div className="mt-8 flex max-w-md overflow-hidden rounded-md border border-black/10 bg-paper">
            <span className="flex-1 px-4 py-3 text-sm font-medium text-text/45">Your email</span>
            <a href={`mailto:${site.supportEmail}`} className="border-l border-black/10 bg-primary px-4 py-3 text-sm font-medium text-white hover:bg-primary-strong">
              Contact
            </a>
          </div>
          <p className="mt-5 max-w-[64ch] text-sm font-normal leading-relaxed text-text/58">
            MyLeafy 是通用型校园课表与校园工具，当前支持北京林业大学。官网用于提供公开介绍、技术支持、隐私政策和 App Store Connect 可填写网址。
          </p>
        </div>

        <nav className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
          {footerGroups.map((group) => (
            <div key={group.title}>
              <h2 className="text-sm font-semibold text-text">{group.title}</h2>
              <div className="mt-4 grid gap-3">
                {group.links.map((link) => (
                  <a
                    key={`${group.title}-${link.label}`}
                    href={link.href}
                    onClick={(event) => {
                      if (link.href.startsWith("http") || link.href.startsWith("mailto:")) {
                        return;
                      }
                      event.preventDefault();
                      navigate(link.href);
                    }}
                    className="break-words text-sm font-medium leading-relaxed text-text/58 hover:text-primary-ink"
                  >
                    {link.label}
                  </a>
                ))}
              </div>
            </div>
          ))}
        </nav>
      </div>
      <div className="border-t border-black/10 px-4 py-4 md:px-6">
        <div className="mx-auto flex max-w-7xl flex-col gap-2 text-xs font-medium text-text/58 md:flex-row md:items-center md:justify-between">
          <span>最近更新：{site.updatedAt}</span>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            <a className="inline-flex items-center gap-2 hover:text-primary-ink" href="/" onClick={(event) => { event.preventDefault(); navigate("/"); }}>
              <House size={15} aria-hidden />
              首页
            </a>
            <a className="inline-flex items-center gap-2 hover:text-primary-ink" href={`mailto:${site.supportEmail}`}>
              <EnvelopeSimple size={15} aria-hidden />
              {site.supportEmail}
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
