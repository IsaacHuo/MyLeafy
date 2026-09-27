import { useParams } from "react-router-dom";
import { CopyButton } from "../../components/CopyEmailButton";
import { DownloadButtons, PageIntro, TextLink } from "../components";

export function ShareTimetablePage() {
  const { code = "" } = useParams();
  const normalized = code.toUpperCase().replace(/[^A-Z2-7]/g, "");
  const valid = /^[A-Z2-7]{12}$/.test(normalized);
  return <><PageIntro label="共享课表" title={valid ? "查看共享课表" : "这条共享课表链接不完整。"}><p>{valid ? "在 App 中接受邀请，或复制邀请码手动添加。" : "请让分享者重新发送完整链接。"}</p></PageIntro><section className="container share-content">
    {valid ? <><div className="invite-block"><span>课表邀请码</span><p className="invite-code">{normalized}</p><p>7 天内有效，仅可由一人接受。分享者之后仍可撤销访问。</p></div><div className="share-actions"><a className="button button-primary" href={`leafy://timetable-invite?code=${normalized}`}>在 App 中接受</a><CopyButton value={normalized} label="复制邀请码" success="邀请码已复制到剪贴板。" /></div><h2>也可以手动添加</h2><p>进入“我的 → 共享课表 → 添加同学课表”，粘贴邀请码并确认。</p><h2>尚未安装 MyLeafy？</h2><DownloadButtons /></> : <div role="alert"><p>链接无效。有效邀请码应包含 12 个字符。</p><TextLink to="/support">联系支持</TextLink></div>}
  </section></>;
}

export function ShareCommunityPage() {
  const { postID = "" } = useParams();
  const valid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(postID);
  return <><PageIntro label="社区帖子" title={valid ? "查看社区帖子" : "这条社区帖子链接无效。"}><p>{valid ? "帖子详情与评论请在 App 中查看。" : "帖子 ID 缺失或格式不正确，请让分享者重新发送链接。"}</p></PageIntro><section className="container share-content">{valid ? <><a className="button button-primary" href={`leafy://community-post?id=${encodeURIComponent(postID)}`}>打开 MyLeafy</a><p>请安装最新版本并登录。如果帖子已删除或不可见，App 会说明原因。</p><h2>尚未安装 MyLeafy？</h2><DownloadButtons /></> : <div role="alert"><p>无法通过此链接打开帖子。</p><TextLink to="/support">联系支持</TextLink></div>}</section></>;
}
