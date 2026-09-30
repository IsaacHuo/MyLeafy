import { useEffect, useState, type PropsWithChildren } from "react";
import { Link } from "react-router-dom";
import { ArrowDown, ArrowUpRight, AndroidLogo, AppleLogo } from "@phosphor-icons/react";
import { downloads } from "./content";

export function DownloadButtons() {
  return <div className="download-buttons">
    <a className="button button-primary" href={downloads.ios.url}><AppleLogo weight="fill" size={21} aria-hidden />App Store 下载<ArrowUpRight size={16} aria-hidden /></a>
    <a className="button button-secondary" href={downloads.android.url}><AndroidLogo size={21} aria-hidden />Android 下载<ArrowDown size={16} aria-hidden /></a>
  </div>;
}

export function DownloadSection() {
  const [release, setRelease] = useState<{versionName:string;githubReleaseUrl:string}|null>(null);
  useEffect(()=>{
    const controller=new AbortController();
    fetch(downloads.android.latestUrl,{signal:controller.signal})
      .then(response=>{if(!response.ok)throw new Error('版本信息暂不可用');return response.json();})
      .then(body=>setRelease(body.release)).catch(()=>setRelease(null));
    return ()=>controller.abort();
  },[]);
  return <section id="download" className="download-section section-pad" aria-labelledby="download-title" tabIndex={-1}>
    <div className="container download-layout">
      <div><img src="/media/optimized/app-icon.webp" width="64" height="64" className="download-icon" alt="MyLeafy" loading="lazy" />
        <h2 id="download-title">下载 MyLeafy</h2><p className="muted">选择对应的平台下载安装。</p></div>
      <div className="download-options"><DownloadButtons />
        <div className="download-meta"><p><strong>iPhone 与 iPad</strong><span>{downloads.ios.requirement}</span></p><p><strong>Android {release?.versionName}</strong><span>{downloads.android.requirement}</span></p></div>
        <div className="download-links"><a href={release?.githubReleaseUrl??downloads.android.releaseUrl}>Android 发布说明<ArrowUpRight size={14} aria-hidden /></a><a href={downloads.android.checksumUrl}>SHA-256 校验文件<ArrowDown size={14} aria-hidden /></a><Link to="/support">安装与使用帮助<ArrowUpRight size={14} aria-hidden /></Link></div>
      </div>
    </div>
  </section>;
}

export function CampusPhoto({ name, alt = "", className = "", eager = false }: { name: string; alt?: string; className?: string; eager?: boolean }) {
  return <img className={className} src={`/media/optimized/${name}-1280.webp`} srcSet={[640,1280,...(name === "rainy-woodland-path" ? [1920] : [])].map(w => `/media/optimized/${name}-${w}.webp ${w}w`).join(", ")} sizes="100vw" width="1920" height="1280" alt={alt} loading={eager ? "eager" : "lazy"} {...{ fetchpriority: eager ? "high" : "auto" }} decoding="async" />;
}

export function ProductShot({ image, alt, caption, eager = false }: { image: string; alt: string; caption: string; eager?: boolean }) {
  const [failed, setFailed] = useState(false);
  return <figure className="product-shot"><div className="phone-frame">
    <div className="phone-screen">
      {failed ? <div className="image-unavailable" role="status">界面预览暂时无法加载。<br />你仍可阅读功能介绍。</div> : <img src={image} width="738" height="1606" alt={alt} loading={eager ? "eager" : "lazy"} decoding="async" onError={() => setFailed(true)} />}
    </div>
    <img className="phone-bezel" src="/media/iphone-17-pro-silver-portrait.png" alt="" aria-hidden loading={eager ? "eager" : "lazy"} decoding="async" />
    </div><figcaption>{caption}</figcaption></figure>;
}

export function PageIntro({ title, children, label }: PropsWithChildren<{ title: string; label: string }>) {
  return <div className="container page-intro"><p className="eyebrow">{label}</p><h1 tabIndex={-1}>{title}</h1>{children}</div>;
}

export function TextLink({ to, children }: PropsWithChildren<{ to: string }>) {
  return <Link className="text-link" to={to}>{children}<ArrowUpRight size={18} aria-hidden /></Link>;
}

