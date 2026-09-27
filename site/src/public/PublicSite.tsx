import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { Link, NavLink, Route, Routes, useLocation, useNavigationType } from "react-router-dom";
import { ArrowDown, ArrowUpRight, List, X } from "@phosphor-icons/react";
import { HomePage } from "./pages/HomePage";
import { FeaturesPage } from "./pages/FeaturesPage";
import { SupportPage, PrivacyPage } from "./pages/InformationPages";
import { ShareCommunityPage, ShareTimetablePage } from "./pages/SharePages";
import { PageIntro, TextLink } from "./components";
import { supportEmail } from "./content";

const navigation = [{ to: "/", label: "首页" }, { to: "/features", label: "功能" }, { to: "/support", label: "支持" }, { to: "/privacy", label: "隐私" }];
const metadata: Record<string, [string, string]> = {
  "/": ["MyLeafy｜校园课表与校园工具", "为北京林业大学学生提供课表、教务工具、校园社区与个人日程，支持 iOS 与 Android。"],
  "/features": ["MyLeafy 功能", "了解 MyLeafy 的课表、社区、日迹、校园和个人设置，以及 iOS 与 Android 的功能差异。"],
  "/support": ["MyLeafy 技术支持", "获取 MyLeafy 安装、更新、教务同步与分享帮助，通过邮件或 App 内反馈联系支持。"],
  "/privacy": ["MyLeafy 隐私政策", "了解 MyLeafy 的学校登录、本地数据、社区内容、权限与隐私选择。"],
};

function RouteEffects() {
  const location = useLocation();
  const navigationType = useNavigationType();
  const positions = useRef(new Map<string, number>());
  const previousPath = useRef(location.pathname);
  useLayoutEffect(() => {
    const { pathname, hash, key } = location;
    const [title, description] = metadata[pathname] ?? (pathname.startsWith("/share/") ? ["MyLeafy 分享", "在 MyLeafy 中打开分享内容，或获取 iOS 与 Android 版本。"] : ["页面不存在 · MyLeafy", "返回 MyLeafy 官网或联系支持。"]);
    document.title = title;
    document.documentElement.lang = "zh-CN";
    document.querySelector('meta[name="description"]')?.setAttribute("content", description);
    document.querySelector('meta[property="og:title"]')?.setAttribute("content", title);
    document.querySelector('meta[property="og:description"]')?.setAttribute("content", description);
    document.querySelector('meta[property="og:url"]')?.setAttribute("content", `https://myleafy.space${pathname}`);
    document.querySelector('link[rel="canonical"]')?.setAttribute("href", `https://myleafy.space${pathname}`);
    const changedPage = previousPath.current !== pathname;
    previousPath.current = pathname;
    const frame = requestAnimationFrame(() => {
      let anchor = hash.slice(1);
      try { anchor = decodeURIComponent(anchor); } catch { /* Malformed URL fragments are simply unmatched. */ }
      const target = anchor ? document.getElementById(anchor) : null;
      if (navigationType === "POP" && positions.current.has(key)) {
        window.scrollTo({ top: positions.current.get(key)!, behavior: "instant" });
      } else if (target) {
        target.scrollIntoView({ block: "start", behavior: navigationType === "PUSH" && !window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "smooth" : "instant" });
      } else {
        window.scrollTo({ top: 0, behavior: "instant" });
      }
      if (target) target.focus({ preventScroll: true });
      else if (changedPage) document.querySelector<HTMLElement>("#main-content h1")?.focus({ preventScroll: true });
    });
    return () => { cancelAnimationFrame(frame); positions.current.set(key, window.scrollY); };
  }, [location, navigationType]);
  useEffect(() => {
    const original = window.history.scrollRestoration;
    window.history.scrollRestoration = "manual";
    return () => { window.history.scrollRestoration = original; };
  }, []);
  return null;
}

function Header() {
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const header = useRef<HTMLElement>(null);
  const location = useLocation();
  useEffect(() => setOpen(false), [location]);
  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 768px)");
    const resize = () => { if (desktop.matches) setOpen(false); };
    desktop.addEventListener("change", resize);
    return () => desktop.removeEventListener("change", resize);
  }, []);
  useEffect(() => {
    if (!open) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") { setOpen(false); button.current?.focus(); }
    };
    const closeOutside = (event: PointerEvent) => { if (!header.current?.contains(event.target as Node)) setOpen(false); };
    document.addEventListener("keydown", closeOnEscape);
    document.addEventListener("pointerdown", closeOutside);
    return () => { document.removeEventListener("keydown", closeOnEscape); document.removeEventListener("pointerdown", closeOutside); };
  }, [open]);
  return <header className="site-header" ref={header}>
    <div className="header-bar container">
      <Link className="brand" to="/" aria-label="MyLeafy 首页"><img src="/media/optimized/app-icon.webp" width="32" height="32" alt="" /><span>MyLeafy</span></Link>
      <nav className="desktop-navigation" aria-label="主导航">{navigation.map(item => <NavLink key={item.to} to={item.to} end>{item.label}</NavLink>)}</nav>
      <div className="header-actions"><Link className="button header-download" to="/#download">下载<ArrowDown size={15} aria-hidden /></Link><button ref={button} type="button" className="menu-toggle" onClick={() => setOpen(value => !value)} aria-expanded={open} aria-controls="mobile-navigation" aria-label={open ? "关闭导航菜单" : "打开导航菜单"}>{open ? <X size={21} aria-hidden /> : <List size={21} aria-hidden />}</button></div>
    </div>
    <nav id="mobile-navigation" className="mobile-navigation" aria-label="移动端导航" aria-hidden={!open} data-open={open}>
      {navigation.map(item => <NavLink key={item.to} to={item.to} end tabIndex={open ? 0 : -1}>{item.label}<ArrowUpRight size={16} aria-hidden /></NavLink>)}
      <a href={`mailto:${supportEmail}`} tabIndex={open ? 0 : -1}>联系支持<ArrowUpRight size={16} aria-hidden /></a>
    </nav>
  </header>;
}

function Footer() {
  return <footer className="site-footer"><div className="container footer-main"><div><Link className="brand" to="/"><img src="/media/optimized/app-icon.webp" width="32" height="32" alt="" />MyLeafy</Link><p>为北京林业大学学生提供的校园 App。</p></div><nav aria-label="页脚导航"><Link to="/features">探索功能</Link><Link to="/support">技术支持</Link><Link to="/privacy">隐私政策</Link><a href={`mailto:${supportEmail}`}>联系我们</a></nav></div><div className="container footer-bottom"><span>© {new Date().getFullYear()} MyLeafy</span><span>支持 iOS 与 Android</span></div></footer>;
}

export function PublicSite() {
  return <div className="public-site"><a className="skip-link" href="#main-content">跳到主要内容</a><RouteEffects /><Header /><main id="main-content" tabIndex={-1}>
    <Routes>
      <Route path="/" element={<HomePage />} /><Route path="/features" element={<FeaturesPage />} />
      <Route path="/support" element={<SupportPage />} /><Route path="/privacy" element={<PrivacyPage />} />
      <Route path="/share/timetable/:code?" element={<ShareTimetablePage />} /><Route path="/share/community/post/:postID?" element={<ShareCommunityPage />} />
      <Route path="*" element={<PageIntro label="404" title="页面不存在"><p>该链接没有对应的页面，请返回首页。</p><TextLink to="/">返回首页</TextLink></PageIntro>} />
    </Routes>
  </main><Footer /></div>;
}
