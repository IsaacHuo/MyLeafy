import type { BackendEnv } from './auth';
import { rows } from './db';
import { ApiError, sha256, uuid } from './http';

const origin='https://myleafy.space',imageURL=`${origin}/app-icon.png`;
export async function sharePreview(env:BackendEnv,url:URL){
  const kind=url.searchParams.get('kind');
  if(kind==='community-post'){
    const id=uuid(url.searchParams.get('id')),canonicalURL=`${origin}/share/community/post/${id}`;
    const post=(await rows(env.DB,"SELECT title,body,category,comment_count,like_count,(SELECT count(*) FROM post_attachments WHERE post_id=p.id) attachment_count FROM posts p WHERE p.id=? AND p.status='published'",[id]))[0];
    if(!post)return {kind,status:'not_found',title:'MyLeafy 社区帖子',description:'这条帖子已不存在、不可见，或链接格式不正确。',canonicalURL,imageURL};
    const body=String(post.body??'').replace(/\s+/g,' ').trim(),brief=[...body].length>110?[...body].slice(0,110).join('')+'...':body;
    const stats=`${post.category||'社区'} · ${post.comment_count} 条评论 · ${post.like_count} 个赞${Number(post.attachment_count)>0?' · 含附件':''}`;
    return {kind,status:'ok',title:post.title||'MyLeafy 社区帖子',description:brief?`${brief} · ${stats}`:stats,canonicalURL,imageURL};
  }
  if(kind==='timetable-invite'){
    const code=(url.searchParams.get('code')??'').toUpperCase().replace(/[\s-]/g,'');
    if(!/^[A-Z2-7]{12}$/.test(code))throw new ApiError(400,'invalid_invite','邀请码无效。');
    const canonicalURL=`${origin}/share/timetable/${code}`;
    const invite=(await rows(env.DB,'SELECT i.expires_at,i.accepted_by,p.nickname,p.display_name,s.course_count FROM timetable_invites i LEFT JOIN profiles p ON p.id=i.owner_id LEFT JOIN timetable_snapshots s ON s.owner_id=i.owner_id AND s.semester_id=i.semester_id AND s.campus_id=i.campus_id WHERE i.code_hash=?',[await sha256(code)]))[0];
    if(!invite)return {kind,status:'not_found',title:'MyLeafy 共享课表邀请',description:'复制邀请码，在 MyLeafy 的共享课表页面中接受邀请。',canonicalURL,imageURL};
    const status=invite.accepted_by?'used':Date.parse(String(invite.expires_at))<=Date.now()?'expired':'ok';
    const owner=[...String(invite.nickname||invite.display_name||'同学')].slice(0,8).join('');
    return {kind,status,title:`${owner} 邀请你查看共享课表`,description:status==='ok'?`邀请码 ${code} · ${invite.course_count??0} 门课程 · 7 天内有效且只能被一位同学接受。`:`邀请码 ${code} ${status==='used'?'已被接受':'已过期'}。请让对方重新生成共享课表邀请。`,canonicalURL,imageURL};
  }
  throw new ApiError(400,'bad_request','分享类型无效。');
}
