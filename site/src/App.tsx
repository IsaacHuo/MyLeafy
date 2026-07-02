import { lazy, Suspense, useEffect, useState } from "react";
import type { ReactNode } from "react";
import { ImageDithering } from "@paper-design/shaders-react";
import {
  ArrowRight,
  CalendarBlank,
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
  appStoreLinks,
  capabilityStats,
  featureShowcases,
  featureBands,
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
  "/": "MyLeafy | Campus Timetable and Student Tools",
  "/features": "MyLeafy Features",
  "/support": "MyLeafy Support",
  "/privacy": "MyLeafy Privacy Policy",
  "/admin": "MyLeafy Admin",
  "/share/timetable": "MyLeafy Shared Timetable",
  "/share/community/post": "MyLeafy Community Post"
};

const primaryButtonClass = "border border-primary bg-primary text-white shadow-primary hover:bg-primary-strong";
const secondaryButtonClass = "border border-black/10 bg-white/90 text-text shadow-soft hover:border-black/25 hover:bg-white";
const panelClass = "rounded-lg border border-black/10 bg-white/90 p-6 shadow-[0_18px_50px_rgba(24,32,26,0.06)] backdrop-blur";
const featuredPanelClass = "rounded-lg border border-primary/20 bg-primary-wash/80 p-6 shadow-[0_18px_50px_rgba(78,130,97,0.08)]";
const ruleStackClass = "overflow-hidden rounded-lg border border-black/10 bg-white/90 shadow-[0_18px_50px_rgba(24,32,26,0.05)] backdrop-blur";
const heroBackgroundImage = "/media/leafy-hero-leaves.png";

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
        : path === "/features" || path === "/support" || path === "/privacy"
          ? path
          : "/";
  const timetableInviteCode = isShareTimetablePath ? path.split("/").pop() ?? "" : "";
  const communityPostID = isShareCommunityPostPath ? path.split("/").pop() ?? "" : "";

  useEffect(() => {
    document.title = pageTitles[activePath];
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
      <Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">Loading admin...</main>}>
        <AdminConsole />
      </Suspense>
    );
  }

  return (
    <div className="min-h-[100dvh] bg-paper text-text">
      <Header activePath={activePath} navigate={navigate} />
      <main>
        {activePath === "/" && <HomePage />}
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
  const isHome = activePath === "/";

  return (
    <header className={`${isHome ? "absolute border-transparent bg-transparent" : "sticky border-black/10 bg-paper/90 backdrop-blur-2xl"} top-0 z-40 w-full border-b`}>
      <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-3 px-4 py-3 md:px-6">
        <a
          href="/"
          onClick={(event) => {
            event.preventDefault();
            navigate("/");
          }}
          className="flex min-w-fit items-center gap-3"
          aria-label="MyLeafy home"
        >
          <img className="h-9 w-9 rounded-lg border border-black/10 shadow-soft" src="/app-icon.png" alt="MyLeafy app icon" />
          <strong className={`text-2xl font-bold leading-none ${isHome ? "text-black" : "text-text"}`}>MyLeafy</strong>
        </a>

        <nav className="leafy-scrollbar-none order-3 flex w-full min-w-0 gap-1 overflow-x-auto md:order-none md:ml-7 md:w-auto md:flex-1 md:items-center">
          {navItems.map((item) => {
            const route = routeFromHref(item.href).split("#")[0];
            const isActive = route === "/" ? activePath === "/" : activePath === route;

            return (
              <a
                key={item.href}
                href={item.href}
                onClick={(event) => {
                  event.preventDefault();
                  navigate(item.href);
                }}
                className={`whitespace-nowrap rounded-lg px-3 py-2 text-[15px] font-semibold transition-colors ${
                  isHome
                    ? isActive
                      ? "bg-black/10 text-black"
                      : "text-black/75 hover:bg-black/10 hover:text-black"
                    : isActive
                      ? "bg-primary-wash text-primary-ink"
                      : "text-text/60 hover:bg-white/70 hover:text-text"
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
            className={`hidden rounded-lg px-3 py-2 text-base font-semibold transition-colors sm:inline-flex ${
              isHome ? "text-black/75 hover:bg-black/10 hover:text-black" : "text-text/60 hover:bg-white/70 hover:text-text"
            }`}
          >
            Contact
          </a>
          <button
            type="button"
            onClick={() => navigate("/support")}
            className={`inline-flex min-h-10 items-center justify-center rounded-lg border px-5 text-base font-semibold transition-colors ${
              isHome
                ? "border-black/15 bg-black/10 text-black shadow-none hover:bg-black/15"
                : "border-primary bg-primary text-white shadow-primary hover:bg-primary-strong"
            }`}
          >
            Support
          </button>
        </div>
      </div>
    </header>
  );
}

function HomePage() {
  return (
    <section className="relative isolate flex min-h-[100dvh] items-center overflow-hidden border-b border-black/10 bg-[#d8e8cc]">
      <HomeBackground />
      <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
        <StaggerReveal className="max-w-3xl">
          <p className="mb-5 text-sm font-semibold uppercase tracking-normal text-black/80">
            BJFU campus tool
          </p>
          <h1 className="text-6xl font-semibold leading-none tracking-normal text-black md:text-8xl lg:text-9xl">MyLeafy</h1>
          <p className="mt-7 max-w-[680px] text-lg font-normal leading-relaxed text-black/80 md:text-2xl">
            A campus timetable and student tools app for Beijing Forestry University.
          </p>
        </StaggerReveal>
      </div>
    </section>
  );
}

function FeaturesPage({ navigate }: { navigate: (href: string) => void }) {
  return (
    <>
      <CapabilityRail />

      <SectionShell
        id="product"
        eyebrow="Product"
        title="Built around campus routines"
      >
        <div className="grid gap-4 lg:grid-cols-4">
          {featureBands.map((item) => (
            <FeatureBandCard key={item.label} item={item} />
          ))}
        </div>
        <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {productCards.map((feature, index) => (
            <ProductCard key={feature.label} feature={feature} featured={index === 0} />
          ))}
        </div>
      </SectionShell>

      <FeatureImageShowcase />

      <section id="data" className="border-y border-black/10 bg-surface-high/70">
        <SectionShell
          eyebrow="Data"
          title="Data sources"
          flush
        >
          <DataBoundaryTable />
        </SectionShell>
      </section>

      <section id="community" className="bg-paper">
        <SectionShell
          eyebrow="Workflow"
          title="Daily paths"
          flush
        >
          <div className="grid gap-4 lg:grid-cols-3">
            {workflowCards.map((item) => (
              <WorkflowCard key={item.title} item={item} />
            ))}
          </div>
        </SectionShell>
      </section>

      <ResourcesSection navigate={navigate} />
    </>
  );
}

function HomeBackground() {
  return (
    <div className="absolute inset-0 -z-10 bg-[#d7eacb]" aria-hidden>
      <img
        className="h-full w-full object-cover"
        src={heroBackgroundImage}
        alt=""
        loading="eager"
        decoding="async"
      />
      <ImageDithering
        className="leafy-dither absolute inset-0 h-full w-full"
        image={heroBackgroundImage}
        colorBack="#253622"
        colorFront="#cce3b7"
        colorHighlight="#f2e79a"
        originalColors={false}
        inverted={false}
        type="8x8"
        size={2.4}
        colorSteps={3}
        fit="cover"
        minPixelRatio={1}
        maxPixelCount={1600000}
        width="100%"
        height="100%"
      />
    </div>
  );
}

function CapabilityRail() {
  return (
    <section className="border-b border-black/10 bg-white/80 py-3 backdrop-blur">
      <div className="leafy-scrollbar-none mx-auto flex max-w-7xl gap-3 overflow-x-auto px-4 md:px-6">
        {capabilityStats.map((metric) => (
          <div
            key={metric.label}
            className="flex min-w-52 items-center justify-between gap-7 rounded-lg border border-black/10 bg-paper/75 px-4 py-3"
          >
            <span className="text-sm font-medium text-text/60">{metric.label}</span>
            <span className="text-sm font-semibold text-text">{metric.value}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function FeatureImageShowcase() {
  return (
    <section id="screens" className="scroll-mt-24 border-y border-black/10 bg-white/70">
      <div className="mx-auto max-w-7xl px-4 py-16 md:px-6 md:py-24">
        <div className="mx-auto mb-12 max-w-4xl text-center">
          <p className="text-sm font-semibold uppercase text-primary-ink">Features</p>
          <h2 className="mt-4 text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">What MyLeafy covers</h2>
          <p className="mx-auto mt-5 max-w-[720px] text-base leading-relaxed text-text/70">
            Timetable, community, grades, credits, assessment, and timetable sharing.
          </p>
        </div>

        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {featureShowcases.map((shot, index) => (
            <article
              key={shot.label}
              className="overflow-hidden rounded-lg border border-black/10 bg-paper/90 shadow-soft"
            >
              <div className="aspect-[1284/2778] bg-[#d9edcc]">
                <img
                  className="h-full w-full object-contain"
                  src={shot.image}
                  alt={shot.alt}
                  loading={index < 2 ? "eager" : "lazy"}
                  decoding="async"
                />
              </div>
              <div className="p-5">
                <p className="text-xs font-semibold uppercase text-primary-ink">{shot.label}</p>
                <h3 className="mt-2 text-2xl font-semibold leading-tight text-text">{shot.title}</h3>
                <p className="mt-3 text-sm font-normal leading-relaxed text-text/70">{shot.body}</p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureBandCard({
  item
}: {
  item: {
    icon: IconComponent;
    label: string;
    title: string;
    body: string;
  };
}) {
  const Icon = item.icon;

  return (
    <article className="rounded-lg border border-black/10 bg-white/90 p-6 shadow-soft">
      <div className="mb-7 flex items-center justify-between gap-3">
        <span className="grid h-11 w-11 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink">
          <Icon size={23} weight="bold" aria-hidden />
        </span>
        <span className="rounded-lg border border-black/10 bg-paper px-3 py-1 text-xs font-semibold text-text/60">{item.label}</span>
      </div>
      <h3 className="text-xl font-semibold leading-tight text-text">{item.title}</h3>
      <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
    </article>
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
    <article className={`${featured ? "border-primary/25 bg-primary-wash/80" : "border-black/10 bg-white/90"} flex min-h-72 flex-col justify-between rounded-lg border p-6 shadow-soft`}>
      <div>
        <div className="mb-8 flex items-center justify-between gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-lg border border-black/10 bg-white text-primary-ink">
            <Icon size={23} weight="bold" aria-hidden />
          </div>
          <span className="rounded-lg border border-black/10 bg-white px-3 py-1 text-xs font-medium text-text/60">{feature.detail}</span>
        </div>
        <p className="text-sm font-medium text-text/60">{feature.label}</p>
        <h3 className="mt-3 max-w-xl text-2xl font-semibold leading-tight text-text">{feature.title}</h3>
      </div>
      <p className="mt-8 max-w-[68ch] text-sm font-normal leading-relaxed text-text/70">{feature.body}</p>
    </article>
  );
}

function DataBoundaryTable() {
  return (
    <div className={ruleStackClass}>
      {homeDataBoundaries.map((item) => (
        <div key={item.label} className="grid gap-3 border-b border-black/10 px-5 py-6 last:border-b-0 md:grid-cols-[0.7fr_0.65fr_1.65fr] md:items-start">
          <p className="text-sm font-semibold text-text/60">{item.label}</p>
          <p className="text-sm font-semibold text-text">{item.value}</p>
          <p className="max-w-[72ch] text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
        </div>
      ))}
    </div>
  );
}

function WorkflowCard({ item }: { item: { icon: IconComponent; title: string; body: string } }) {
  const Icon = item.icon;

  return (
    <article className="rounded-lg border border-black/10 bg-white/90 p-6 shadow-soft">
      <div className="grid h-11 w-11 place-items-center rounded-lg border border-black/10 bg-paper text-primary-ink">
        <Icon size={23} weight="bold" aria-hidden />
      </div>
      <h3 className="mt-7 text-2xl font-semibold leading-tight text-text">{item.title}</h3>
      <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
    </article>
  );
}

function ResourcesSection({ navigate }: { navigate: (href: string) => void }) {
  return (
    <section className="border-t border-black/10 bg-surface-high/70">
      <SectionShell
        eyebrow="Resources"
        title="Public support and App Store links"
        flush
      >
        <div className="grid gap-4 lg:grid-cols-[0.8fr_1.2fr]">
          <div className={featuredPanelClass}>
            <LockKey size={25} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-5 text-2xl font-semibold leading-tight text-text">Contact and policy links</p>
            <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">
              Support: {site.supportEmail}. Privacy policy: {site.privacyUrl}.
            </p>
          </div>

          <div className="grid gap-4 md:grid-cols-3">
            {resourceLinks.map((link) => (
              <a
                key={link.title}
                href={link.href}
                onClick={(event) => {
                  event.preventDefault();
                  navigate(link.href);
                }}
                className="group rounded-lg border border-black/10 bg-white/90 p-5 shadow-soft transition-colors hover:bg-primary-soft"
              >
                <p className="text-sm font-semibold text-text/60">{link.title}</p>
                <p className="mt-3 min-h-24 text-sm font-normal leading-relaxed text-text/70">{link.body}</p>
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
              onClick={(event) => {
                if (link.value.includes(site.domain)) {
                  event.preventDefault();
                  navigate(link.value);
                }
              }}
              className="group grid gap-2 border-b border-black/10 px-5 py-5 transition-colors last:border-b-0 hover:bg-primary-soft md:grid-cols-[0.9fr_1.4fr_auto] md:items-center"
            >
              <span className="text-sm font-semibold text-text/60">{link.label}</span>
              <span className="break-all text-sm font-medium text-text">{link.value}</span>
              <ArrowRight size={18} weight="bold" className="text-primary-ink transition-transform group-hover:translate-x-1" aria-hidden />
            </a>
          ))}
        </div>
      </SectionShell>
    </section>
  );
}

function SupportPage() {
  const mailto = `mailto:${site.supportEmail}?subject=MyLeafy Support`;

  return (
    <>
      <PageHero
        icon={Lifebuoy}
        label="Support"
        title="Support"
        body="For login, sync, timetable parsing, community, shared timetable, or rating issues, contact support by email or through in-app feedback."
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={mailto} className={primaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send email
          </TapButton>
          <CopyEmailButton email={site.supportEmail} />
        </div>
      </PageHero>

      <SectionShell eyebrow="Contact" title="Public contact" body="Email works for general support and privacy requests. In-app feedback is better for issues that need sync state, version, and device context.">
        <div className="grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <div className={panelClass}>
            <p className="text-sm font-semibold text-text/60">Support email</p>
            <a className="mt-3 block break-all text-3xl font-semibold leading-tight text-text hover:text-primary-ink" href={mailto}>
              {site.supportEmail}
            </a>
            <p className="mt-4 max-w-[68ch] text-sm font-normal leading-relaxed text-text/70">
              Use this address for App Store support, general feedback, feature requests, and privacy access, correction, or deletion requests.
            </p>
          </div>
          <div id="in-app" className={`${featuredPanelClass} scroll-mt-24`}>
            <CheckCircle size={24} weight="bold" className="text-primary-ink" aria-hidden />
            <p className="mt-4 text-xl font-semibold text-text">In-app feedback is better for diagnostics</p>
            <p className="mt-3 text-sm font-normal leading-relaxed text-text/70">
              In-app feedback can include device model, system version, app version, login state, and latest sync time.
            </p>
          </div>
        </div>
      </SectionShell>

      <SectionShell eyebrow="Before sending" title="Information to include">
        <NumberedList items={supportChecklist} />
      </SectionShell>

      <SectionShell eyebrow="Scope" title="Common support topics">
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
        title="Privacy Policy"
        body={`This policy explains how MyLeafy handles school login, local cache, community, feedback, ratings, shared timetable, and website data. Last updated: ${site.updatedAt}.`}
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href="#privacy-rights" className={primaryButtonClass}>
            <LockKey size={18} weight="bold" aria-hidden />
            View privacy choices
          </TapButton>
          <TapButton href={`mailto:${site.supportEmail}?subject=MyLeafy Privacy Request`} className={secondaryButtonClass}>
            <EnvelopeSimple size={18} weight="bold" aria-hidden />
            Send privacy request
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Quick read" title="Four things to know">
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
        title="Shared timetable invite"
        body="Copy the invite code, then open MyLeafy and accept it from Profile -> Shared Timetable -> +."
      >
        <div className="mt-8 grid max-w-xl gap-4">
          <div className={featuredPanelClass}>
            <p className="text-sm font-semibold text-text/60">Invite code</p>
            <p className="mt-3 break-all text-5xl font-semibold tracking-normal text-text">{normalizedCode || "Not recognized"}</p>
            <p className="mt-4 text-sm font-normal leading-relaxed text-text/70">
              Invite codes are valid for seven days and can be accepted by one person. Access can be revoked later.
            </p>
          </div>
          <button type="button" onClick={copyCode} className={`${primaryButtonClass} inline-flex min-h-11 w-fit items-center gap-2 rounded-lg px-5 text-sm font-medium`}>
            <CheckCircle size={18} weight="bold" aria-hidden />
            {copied ? "Copied" : "Copy invite code"}
          </button>
        </div>
      </PageHero>

      <SectionShell eyebrow="Accept" title="Accept in the app">
        <NumberedList items={["Open MyLeafy.", "Go to Profile -> Shared Timetable.", "Tap + in the top-right corner.", "Paste the invite code and accept it."]} />
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
        title="MyLeafy community post"
        body="This is a MyLeafy community share link. If the latest app is installed, it opens the post detail directly."
      >
        <div className="mt-8 flex flex-col gap-3 sm:flex-row">
          <TapButton href={appURL} className={primaryButtonClass}>
            <DeviceMobile size={18} weight="bold" aria-hidden />
            Open MyLeafy
          </TapButton>
          <TapButton href={site.appStoreUrl || site.supportUrl} className={secondaryButtonClass}>
            <ArrowRight size={18} weight="bold" aria-hidden />
            Get or update MyLeafy
          </TapButton>
        </div>
      </PageHero>

      <SectionShell eyebrow="Privacy" title="Community content opens in the app">
        <NumberedList
          items={[
            "Share cards may show the post title and a short summary. Comments stay in the app.",
            "After signing in to MyLeafy, the app opens the post detail.",
            "If the app opens but does not show the post, update MyLeafy and try again.",
            "If the post has been deleted or is no longer visible, the app will show that it cannot be opened."
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
  children
}: {
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  children?: ReactNode;
}) {
  return (
    <section className="relative isolate overflow-hidden border-b border-black/10 bg-paper">
      <div className="absolute inset-0 -z-10 opacity-20" aria-hidden>
        <img className="h-full w-full object-cover" src={heroBackgroundImage} alt="" loading="lazy" decoding="async" />
      </div>
      <div className="absolute inset-0 -z-10 bg-[linear-gradient(180deg,rgba(252,250,241,0.90),rgba(252,250,241,0.98))]" aria-hidden />
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-16 md:px-6 lg:grid-cols-[0.52fr_1.48fr] lg:py-24">
        <div>
          <div className="inline-grid h-12 w-12 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink shadow-soft">
            <Icon size={24} weight="bold" aria-hidden />
          </div>
        </div>
        <div>
          <p className="text-sm font-semibold uppercase text-primary-ink">{label}</p>
          <h1 className="mt-4 text-5xl font-semibold leading-none tracking-normal text-text md:text-7xl">{title}</h1>
          <p className="mt-6 max-w-[76ch] text-lg font-normal leading-relaxed text-text/70">{body}</p>
          {children}
        </div>
      </div>
    </section>
  );
}

function SectionShell({
  eyebrow,
  title,
  body,
  children,
  id,
  flush = false
}: {
  eyebrow: string;
  title: string;
  body?: string;
  children: ReactNode;
  id?: string;
  flush?: boolean;
}) {
  return (
    <section id={id} className={`${flush ? "" : "mx-auto max-w-7xl"} scroll-mt-24 px-4 py-14 md:px-6 md:py-20`}>
      <div className="mx-auto mb-9 grid max-w-7xl gap-4 md:grid-cols-[0.52fr_1.48fr] md:items-end">
        <p className="text-sm font-semibold uppercase text-primary-ink">{eyebrow}</p>
        <div>
          <h2 className="max-w-4xl text-4xl font-semibold leading-tight tracking-normal text-text md:text-6xl">{title}</h2>
          {body && <p className="mt-5 max-w-[760px] text-base font-normal leading-relaxed text-text/70">{body}</p>}
        </div>
      </div>
      <div className="mx-auto max-w-7xl">{children}</div>
    </section>
  );
}

function NumberedList({ items }: { items: string[] }) {
  return (
    <div className={ruleStackClass}>
      {items.map((item, index) => (
        <div key={item} className="grid grid-cols-[48px_1fr] gap-4 border-b border-black/10 px-5 py-5 last:border-b-0">
          <span className="text-sm font-semibold text-primary-ink">{String(index + 1).padStart(2, "0")}</span>
          <p className="text-sm font-normal leading-relaxed text-text/70">{item}</p>
        </div>
      ))}
    </div>
  );
}

function AsymmetricIconGrid({ items }: { items: Array<{ icon: IconComponent; title: string; body: string }> }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {items.map((item) => {
        const Icon = item.icon;

        return (
          <article key={item.title} className={panelClass}>
            <div className="grid h-11 w-11 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink">
              <Icon size={23} weight="bold" aria-hidden />
            </div>
            <h3 className="mt-6 text-xl font-semibold text-text">{item.title}</h3>
            <p className="mt-3 max-w-[68ch] text-sm font-normal leading-relaxed text-text/70">{item.body}</p>
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
    <section id={section.id} className="grid scroll-mt-24 gap-6 border-b border-black/10 px-5 py-8 last:border-b-0 md:grid-cols-[0.42fr_1fr]">
      <div className="flex items-center gap-3 md:items-start">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-lg border border-primary/20 bg-primary-wash text-primary-ink">
          <Icon size={21} weight="bold" aria-hidden />
        </span>
        <h2 className="text-2xl font-semibold leading-tight text-text">{section.title}</h2>
      </div>
      <div className="space-y-4">
        {section.items.map((item) => (
          <p key={item} className="text-sm font-normal leading-relaxed text-text/70">
            {item}
          </p>
        ))}
      </div>
    </section>
  );
}

function Footer({ navigate }: { navigate: (href: string) => void }) {
  return (
    <footer className="border-t border-black/10 bg-white/80">
      <div className="mx-auto grid max-w-7xl gap-10 px-4 py-12 md:px-6 lg:grid-cols-[1.05fr_1.95fr]">
        <div>
          <div className="flex items-center gap-3">
            <img className="h-10 w-10 rounded-lg border border-black/10 shadow-soft" src="/app-icon.png" alt="MyLeafy app icon" />
            <div>
              <p className="text-xl font-semibold leading-none text-text">MyLeafy</p>
              <p className="mt-1 text-sm font-medium text-text/60">BJFU campus tool</p>
            </div>
          </div>
          <p className="mt-6 max-w-[64ch] text-sm font-normal leading-relaxed text-text/60">
            Currently supports Beijing Forestry University. Support: {site.supportEmail}.
          </p>
          <a
            href={`mailto:${site.supportEmail}`}
            className="mt-6 inline-flex min-h-11 items-center gap-2 rounded-lg border border-black/10 bg-paper px-4 text-sm font-semibold text-text transition-colors hover:bg-primary-soft"
          >
            <EnvelopeSimple size={17} weight="bold" aria-hidden />
            {site.supportEmail}
          </a>
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
                      if (link.href.startsWith("http") && !link.href.includes(site.domain)) {
                        return;
                      }
                      if (link.href.startsWith("mailto:")) {
                        return;
                      }
                      event.preventDefault();
                      navigate(link.href);
                    }}
                    className="break-words text-sm font-medium leading-relaxed text-text/60 hover:text-primary-ink"
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
        <div className="mx-auto flex max-w-7xl flex-col gap-2 text-xs font-medium text-text/60 md:flex-row md:items-center md:justify-between">
          <span>Last updated: {site.updatedAt}</span>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            <a
              className="inline-flex items-center gap-2 hover:text-primary-ink"
              href="/"
              onClick={(event) => {
                event.preventDefault();
                navigate("/");
              }}
            >
              <House size={15} aria-hidden />
              Home
            </a>
            <a className="inline-flex items-center gap-2 hover:text-primary-ink" href={`mailto:${site.supportEmail}`}>
              <EnvelopeSimple size={15} aria-hidden />
              Contact
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
