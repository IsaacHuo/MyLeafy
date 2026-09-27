import { Check } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { DownloadSection, PageIntro, ProductShot } from "../components";
import { features } from "../content";
import { DataTrust, ScheduleStory } from "./HomePage";
import { ScrollReveal } from "../../components/MotionBits";

export function FeaturesPage() {
  return <><PageIntro label="功能" title="功能概览"><p>MyLeafy 提供课表、社区、日迹、校园与个人设置五个入口。</p><nav className="feature-index" aria-label="功能目录">{features.map(feature => <Link key={feature.id} to={`#${feature.id}`}>{feature.label}</Link>)}<Link to="#profile">我的</Link></nav></PageIntro>
    <div className="container feature-details">{features.map((feature,index) => <section className="feature-detail" id={feature.id} key={feature.id} tabIndex={-1}><ScrollReveal className={`feature-detail-layout ${index % 2 ? "reverse" : ""}`}><div className="feature-copy"><p className="eyebrow">0{index+1} / {feature.label}</p><h2>{feature.title}</h2><p className="muted">{feature.description}</p><ul className="check-list">{feature.details.map(detail => <li key={detail}><Check size={17} aria-hidden />{detail}</li>)}</ul></div><div className="feature-media">{feature.image ? <ProductShot image={feature.image} alt={feature.alt} caption={feature.caption} /> : <ScheduleStory />}</div></ScrollReveal></section>)}</div>
    <section id="profile" className="container profile-section" tabIndex={-1}><p className="eyebrow">05 / 我的</p><h2>个人设置</h2><p className="muted">个人资料、共享课表、主题偏好、数据同步、帮助与隐私设置集中在“我的”。</p></section>
    <section className="container platform-section" aria-labelledby="platform-title"><h2 id="platform-title">iOS 与 Android</h2><p className="muted">两个平台均提供课表、社区、日迹与校园工具，系统能力与部分扩展功能有所不同。</p><div className="platform-comparison"><div><h3>iOS 与 iPadOS</h3><p>系统小组件、原生日历集成，与 Apple 设备的日常使用习惯相连。</p></div><div><h3>Android</h3><p>原生 Android 体验，日程通过 ICS 文件导出，在 App 内检查新版本。</p></div></div><p className="caption">网页中的界面截图来自 iOS 版；具体功能以当前版本和校园身份为准。</p></section>
    <DataTrust /><DownloadSection /></>;
}
