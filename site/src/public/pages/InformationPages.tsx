import { CaretDown, EnvelopeSimple } from "@phosphor-icons/react";
import { Link } from "react-router-dom";
import { CopyEmailButton } from "../../components/CopyEmailButton";
import { DownloadButtons, PageIntro, TextLink } from "../components";
import { downloads, faqs, supportEmail } from "../content";
import { privacySections, privacyUpdatedAt } from "../privacy";

export function SupportPage() {
  return <><PageIntro label="支持" title="支持与常见问题"><p>如遇安装、同步、课表或分享问题，请先查阅常见问题，或通过邮件联系我们。</p><a className="contact-email" href={`mailto:${supportEmail}`}>{supportEmail}<EnvelopeSimple size={25} aria-hidden /></a><CopyEmailButton email={supportEmail} /></PageIntro>
    <div className="container support-layout"><aside><h2>常见问题</h2><p className="muted">常见问题与解答。</p><TextLink to="/#download">获取 MyLeafy</TextLink></aside><div className="faq-list">{faqs.map(faq => <details key={faq.question}><summary>{faq.question}<CaretDown size={19} aria-hidden /></summary><p>{faq.answer}</p></details>)}</div></div>
    <section id="in-app" className="container support-checklist" tabIndex={-1}><div><p className="eyebrow">提交反馈</p><h2>请提供以下信息</h2><p className="muted">可通过 App 内反馈或邮件提交。<br />请勿发送学校密码、验证码或身份证件。</p></div><ol><li>设备型号、系统版本与 MyLeafy 版本。</li><li>问题出现的页面，以及可重复的操作步骤。</li><li>完整错误信息；截图请遮盖不必要的个人信息。</li><li>同步问题请说明网络环境与上次成功同步时间。</li></ol></section>
    <section className="container support-download"><h2>下载与安装</h2><DownloadButtons /><p className="muted">Android 安装包通过 MyLeafy 下载服务分发，GitHub Releases 同步发布。首次安装具有新更新流程的版本后，可在“我的 → 检查更新”下载并覆盖安装。请按系统提示允许安装来源，无需先卸载。</p><a className="text-link" href={downloads.android.releaseUrl}>查看 Android 发布说明</a></section></>;
}

export function PrivacyPage() {
  return <><PageIntro label="隐私" title="隐私政策"><p>以下说明 MyLeafy 如何处理学校登录、本机记录与社区内容。<br />最后更新：{privacyUpdatedAt}。</p><TextLink to="#privacy-rights">查看隐私选择</TextLink></PageIntro>
    <div className="container privacy-layout"><nav className="privacy-toc" aria-label="隐私政策目录">{privacySections.map((section,index) => <Link key={section.id} to={`#${section.id}`}><span aria-hidden>0{index+1}</span>{section.title}</Link>)}</nav><article className="privacy-content">{privacySections.map(section => <section id={section.id} tabIndex={-1} key={section.id}><h2>{section.title}</h2>{section.items.map(item => <p key={item}>{item}</p>)}</section>)}</article></div></>;
}
