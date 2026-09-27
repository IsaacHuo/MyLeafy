import { useRef, useState, type KeyboardEvent } from "react";
import { ArrowDown, Check, LockKey } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { CampusPhoto, DownloadButtons, DownloadSection, ProductShot, TextLink } from "../components";
import { features } from "../content";
import { ScrollReveal } from "../../components/MotionBits";

export function ScheduleStory() {
  return <div className="schedule-story"><CampusPhoto name="classroom-at-dusk" alt="夕阳映照的北林教室" /><div><span>日程与随记</span><p>个人日程与随记<br />均保存在本机。</p><small>日程安排 · Markdown 随记 · 本机保存</small></div></div>;
}

export function FeatureExplorer() {
  const [active, setActive] = useState(0);
  const tabs = useRef<Array<HTMLButtonElement | null>>([]);
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next = index;
    if (event.key === "ArrowRight") next = (index + 1) % features.length;
    else if (event.key === "ArrowLeft") next = (index + features.length - 1) % features.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = features.length - 1;
    else return;
    event.preventDefault(); setActive(next); tabs.current[next]?.focus();
  }
  return <section id="explore" className="section-pad feature-explorer" aria-labelledby="explore-title" tabIndex={-1}>
    <div className="container"><div className="section-heading"><div><p className="eyebrow">功能</p><h2 id="explore-title">主要功能</h2></div><p className="muted">覆盖课表、教务、校园社区与个人日程。</p></div>
      <div className="feature-tabs" role="tablist" aria-label="探索 MyLeafy 功能">{features.map((feature, index) => <button type="button" key={feature.id} ref={node => { tabs.current[index] = node; }} id={`tab-${feature.id}`} role="tab" aria-selected={index === active} aria-controls={`panel-${feature.id}`} tabIndex={index === active ? 0 : -1} onClick={() => setActive(index)} onKeyDown={event => onKeyDown(event,index)}><span className="tab-number" aria-hidden>0{index + 1}</span>{feature.label}</button>)}</div>
      <div className="feature-panels">{features.map((feature,index) => <div className="feature-panel" key={feature.id} role="tabpanel" id={`panel-${feature.id}`} aria-labelledby={`tab-${feature.id}`} hidden={active !== index} tabIndex={0}>
        <div className="feature-copy"><p className="eyebrow">{feature.label}</p><h3>{feature.title}</h3><p className="muted">{feature.description}</p><ul className="check-list">{feature.details.map(detail => <li key={detail}><Check size={17} aria-hidden />{detail}</li>)}</ul><TextLink to={`/features#${feature.id}`}>深入了解{feature.label}</TextLink></div>
        <div className="feature-media">{feature.image ? <ProductShot image={feature.image} alt={feature.alt} caption={feature.caption} /> : <ScheduleStory />}</div>
      </div>)}</div>
    </div>
  </section>;
}

export function DataTrust() {
  return <section id="data" className="section-pad trust-section" tabIndex={-1}><div className="container trust-layout"><div><LockKey size={28} className="accent" aria-hidden /><h2>数据来源与存储</h2><TextLink to="/privacy">查看隐私政策</TextLink></div><dl className="trust-list"><div><dt>学校系统</dt><dd>课表、成绩、考试与教务信息来自学校教务系统，最近一次同步结果保存在本机。</dd></div><div><dt>本机存储</dt><dd>随记与个人日程保存在当前设备，不通过 MyLeafy 服务跨设备同步。</dd></div><div><dt>社区服务</dt><dd>社区资料、帖子、互动与共享课表由独立的 MyLeafy 社区服务保存。</dd></div></dl></div></section>;
}

export function HomePage() {
  return <>
    <section className="home-hero"><CampusPhoto className="hero-photo" name="rainy-woodland-path" eager /><div className="hero-shade" />
      <div className="container hero-layout"><div className="hero-copy"><p className="eyebrow">为北京林业大学学生设计</p><h1 tabIndex={-1}>校园日常<br />集中在一个 App</h1><p className="hero-description">课表、教务工具、校园社区与个人日程，<br />支持 iPhone、iPad 与 Android。</p><DownloadButtons /><p className="hero-platforms">支持 iPhone、iPad 与 Android</p><Link className="hero-explore text-link" to="/#explore">了解功能<ArrowDown size={16} aria-hidden /></Link></div>
        <div className="hero-product"><ProductShot image={features[0].image!} alt={features[0].alt} caption="MyLeafy iOS 版界面" eager /><div className="hero-note"><span>课表</span><p>当前周课程<br />与考试安排。</p></div></div>
      </div>
    </section>
    <FeatureExplorer />
    <section className="campus-section"><CampusPhoto name="classroom-at-dusk" alt="北林教室窗外的暮色" /><div className="campus-overlay" /><ScrollReveal className="container campus-copy"><p className="eyebrow">校园工具</p><h2>教务与校园工具</h2><p>成绩、考试、空闲教室、校历与作息等常用信息集中在一处。</p><TextLink to="/features">查看全部功能</TextLink></ScrollReveal></section>
    <DataTrust /><DownloadSection />
  </>;
}
