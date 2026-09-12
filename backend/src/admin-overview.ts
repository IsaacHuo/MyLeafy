import type { BackendEnv } from './auth';
import type { AdminContext } from './admin-auth';
import { adminList } from './admin-data';
import { buildOverviewSummary } from './admin-overview-shape';
import { rows, type Bind, type Row } from './db';
import { ApiError, integer, text } from './http';

export async function overview(env:BackendEnv,context:AdminContext,params:Row){
  const days=integer(params.days,1,90,30),timezone=text(params.timezone??'Asia/Shanghai',100),campus=text(params.campusID??params.campus_id,64,false)||null;
  let formatter:Intl.DateTimeFormat;
  try{formatter=new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'});}catch{throw new ApiError(400,'bad_request','时区无效。');}
  const parts=(value:string|Date)=>Object.fromEntries(formatter.formatToParts(new Date(value)).map(p=>[p.type,p.value]));
  const dateKey=(p:Record<string,string>)=>`${p.year}-${p.month}-${p.day}`;
  const today=dateKey(parts(new Date())),startDate=new Date(Date.parse(`${today}T00:00:00Z`)-(days-1)*86400000).toISOString().slice(0,10);
  // Fetch only bounded timestamps for timezone grouping. Intl preserves DST and
  // IANA timezone behavior without approximating it using today's UTC offset.
  const since=new Date(Date.parse(`${startDate}T00:00:00Z`)-86400000).toISOString().replace('Z','000Z');
  const scope=(column:string)=>campus&&campus!=='all'?`${column}=?`:'1=1',scopeParams:Bind[]=campus&&campus!=='all'?[campus]:[];
  const queries=[
    ['profiles',`SELECT created_at FROM profiles WHERE ${scope('community_campus_id')} AND created_at>=?`],
    ['posts',`SELECT id,title,category,author_id,status,created_at,comment_count,(SELECT count(*) FROM post_likes WHERE post_id=p.id) AS like_count,(SELECT count(*) FROM comments WHERE post_id=p.id) AS all_comment_count FROM posts p WHERE ${scope('campus_id')} AND created_at>=?`],
    ['comments',`SELECT c.created_at FROM comments c JOIN posts p ON p.id=c.post_id WHERE ${scope('p.campus_id')} AND c.created_at>=?`],
    ['feedback',`SELECT created_at FROM feedback_submissions WHERE ${scope('campus_id')} AND created_at>=?`],
    ['ratings',`SELECT r.created_at FROM teacher_ratings r JOIN teachers t ON t.id=r.teacher_id WHERE ${scope('t.campus_id')} AND r.created_at>=?`],
  ];
  const datasets=await Promise.all(queries.map(async([kind,sql])=>{
    const records=await rows(env.DB,`${sql} LIMIT 100001`,[...scopeParams,since]);
    if(records.length>100000)throw new ApiError(413,'analytics_range_too_large','请缩小统计时间范围。');
    return [kind,records] as const;
  }));
  const daily=Array.from({length:days},(_,i)=>({bucket_date:new Date(Date.parse(`${startDate}T00:00:00Z`)+i*86400000).toISOString().slice(0,10),profiles:0,posts:0,comments:0,feedback:0,ratings:0}));
  const byDate=new Map(daily.map(row=>[row.bucket_date,row]));
  const heatmap=Array.from({length:7*24},(_,i)=>({weekday:Math.floor(i/24),hour:i%24,posts:0,comments:0,feedback:0}));
  const filteredPosts:Row[]=[];
  for(const [kind,records] of datasets)for(const record of records){
    const local=parts(record.created_at as string),key=dateKey(local);if(key<startDate)continue;
    const bucket=byDate.get(key);if(bucket)bucket[kind as 'profiles'|'posts'|'comments'|'feedback'|'ratings']++;
    if(kind==='posts')filteredPosts.push(record);
    if(kind==='posts'||kind==='comments'||kind==='feedback')heatmap[new Date(`${key}T00:00:00Z`).getUTCDay()*24+Number(local.hour)][kind]++;
  }
  const categoryCounts=new Map<string,{category:string;posts:number;comments:number}>();
  for(const post of filteredPosts){const category=String(post.category??'').trim()||'未分类',current=categoryCounts.get(category)??{category,posts:0,comments:0};current.posts++;current.comments+=Number(post.all_comment_count);categoryCounts.set(category,current);}
  const categories=[...categoryCounts.values()].sort((a,b)=>b.posts-a.posts||b.comments-a.comments||a.category.localeCompare(b.category)).slice(0,10);
  const topPosts=filteredPosts.filter(p=>p.status!=='deleted').map(p=>({...p,created_at:p.created_at,category:String(p.category??'').trim()||'未分类',score:Number(p.comment_count)*3+Number(p.like_count)})).sort((a,b)=>b.score-a.score||String(b.created_at).localeCompare(String(a.created_at))).slice(0,8);
  const now=new Date().toISOString().replace('Z','000Z'),yesterday=new Date(Date.now()-86400000).toISOString().replace('Z','000Z');
  const countQueries=[
    `SELECT count(*) total,coalesce(sum(is_profile_complete),0) complete,coalesce(sum(muted_until>'${now}'),0) muted FROM profiles WHERE ${scope('community_campus_id')}`,
    `SELECT count(*) total,coalesce(sum(status='published'),0) published,coalesce(sum(status='hidden'),0) hidden,coalesce(sum(status='pending_review'),0) pending FROM posts WHERE ${scope('campus_id')}`,
    `SELECT count(*) total,coalesce(sum(c.status='published'),0) published,coalesce(sum(c.status='hidden'),0) hidden FROM comments c JOIN posts p ON p.id=c.post_id WHERE ${scope('p.campus_id')}`,
    `SELECT coalesce(sum(r.status='open'),0) open,coalesce(sum(r.status='open' AND r.created_at<'${yesterday}'),0) overdue FROM community_reports r LEFT JOIN posts p ON p.id=r.post_id LEFT JOIN profiles u ON u.id=r.reported_user_id WHERE ${scope('coalesce(p.campus_id,u.community_campus_id)')}`,
    `SELECT coalesce(sum(status='open'),0) open,coalesce(sum(status='reviewed'),0) reviewed,coalesce(sum(status='closed'),0) closed FROM feedback_submissions WHERE ${scope('campus_id')}`,
    `SELECT count(*) total,coalesce(sum(status='hidden'),0) hidden FROM teachers WHERE ${scope('campus_id')}`,
    `SELECT coalesce(sum(status='published'),0) published,coalesce(sum(status='draft'),0) draft,coalesce(sum(status='archived'),0) archived FROM site_announcements WHERE ${scope('campus_id')}`,
  ];
  const [profiles,posts,comments,reports,feedback,teachers,announcements]=await Promise.all(countQueries.map(async sql=>(await rows(env.DB,sql,scopeParams))[0]));
  const [agingRows,rated,lowScoreTeachers]=await Promise.all([
    rows(env.DB,`SELECT created_at FROM feedback_submissions WHERE status IN('open','reviewed') AND ${scope('campus_id')}`,scopeParams),
    rows(env.DB,`SELECT rating_1_count,rating_2_count,rating_3_count,rating_4_count,rating_5_count FROM teachers WHERE rating_count>0 AND ${scope('campus_id')}`,scopeParams),
    rows(env.DB,`SELECT id,name,unit,status,rating_average,rating_count FROM teachers WHERE status='published' AND rating_count>0 AND ${scope('campus_id')} ORDER BY rating_average,rating_count DESC,id LIMIT 6`,scopeParams),
  ]);
  const feedbackAging=[{key:'0-24h',label:'24 小时内',count:0},{key:'1-3d',label:'1-3 天',count:0},{key:'3-7d',label:'3-7 天',count:0},{key:'7d+',label:'7 天以上',count:0}];
  for(const row of agingRows){const age=(Date.now()-Date.parse(row.created_at as string))/3600000;feedbackAging[age<=24?0:age<=72?1:age<=168?2:3].count++;}
  const stars=[1,2,3,4,5].map(star=>({star,count:rated.reduce((sum,row)=>sum+Number(row[`rating_${star}_count`]),0)})),totalRatings=stars.reduce((sum,row)=>sum+row.count,0),weighted=stars.reduce((sum,row)=>sum+row.star*row.count,0);
  const riskActions=['moderatePost','retryPostPublish','bulkModeratePosts','pinPost','unpinPost','moderatePoll','reviewPollDeletion','moderateComment','bulkModerateComments','muteProfile','unmuteProfile','resolveModerationReport','deleteTeacherRating','deleteDishRating','disableAdmin'];
  const recentRiskActions=context.role==='super_admin'?await rows(env.DB,`SELECT id,admin_id,action,target_type,target_id,created_at FROM admin_audit_logs WHERE created_at>=? AND action IN(${riskActions.map(()=>'?').join(',')}) ORDER BY created_at DESC,id DESC LIMIT 8`,[since,...riskActions]):[];
  const moderationQueries=[
    `SELECT count(*) n FROM posts WHERE status='hidden' AND moderated_at>=? AND ${scope('campus_id')}`,
    `SELECT count(*) n FROM comments c JOIN posts p ON p.id=c.post_id WHERE c.status='hidden' AND c.moderated_at>=? AND ${scope('p.campus_id')}`,
    `SELECT count(*) n FROM profiles WHERE muted_at>=? AND ${scope('community_campus_id')}`,
    `SELECT count(*) n FROM feedback_submissions WHERE status='closed' AND reviewed_at>=? AND ${scope('campus_id')}`,
  ];
  const moderationSince=new Date(Date.now()-(days-1)*86400000).toISOString().replace('Z','000Z');
  const moderationCounts=await Promise.all(moderationQueries.map(async sql=>Number((await rows(env.DB,sql,[moderationSince,...scopeParams]))[0].n)));
  const analytics={daily,heatmap,categories,topPosts,feedbackAging,teacherRatings:{teacherCount:rated.length,totalRatings,average:totalRatings?Number((weighted/totalRatings).toFixed(1)):0,stars,lowScoreTeachers},moderation:{hiddenPosts:moderationCounts[0],hiddenComments:moderationCounts[1],mutedProfiles:moderationCounts[2],openReports:Number(reports.open),overdueReports:Number(reports.overdue),closedFeedback:moderationCounts[3],recentRiskActions}};
  const summary=buildOverviewSummary({days,profileTotal:Number(profiles.total),profileComplete:Number(profiles.complete),profileMuted:Number(profiles.muted),postTotal:Number(posts.total),postPublished:Number(posts.published),postHidden:Number(posts.hidden),postPendingReview:Number(posts.pending),commentTotal:Number(comments.total),commentPublished:Number(comments.published),commentHidden:Number(comments.hidden),reportOpen:Number(reports.open),reportOverdue:Number(reports.overdue),feedbackOpen:Number(feedback.open),feedbackReviewed:Number(feedback.reviewed),feedbackClosed:Number(feedback.closed),teacherTotal:Number(teachers.total),teacherHidden:Number(teachers.hidden),analytics});
  return {summary,cards:{profiles:{total:profiles.total,today:summary.operations.newProfilesToday,complete:profiles.complete,muted:profiles.muted},posts:{total:posts.total,today:summary.operations.postsToday,published:posts.published,hidden:posts.hidden,pendingReview:posts.pending},comments:{total:comments.total,today:summary.operations.commentsToday,published:comments.published,hidden:comments.hidden},reports:{open:reports.open,overdue:reports.overdue},feedback,announcements,teachers},analytics,analyticsMeta:{days,timezone},recentFeedback:(await adminList(env,context,'listFeedback',{campusID:campus,pageSize:8})).items,recentPosts:(await adminList(env,context,'listPosts',{campusID:campus,pageSize:8})).items};
}
