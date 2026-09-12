// Preserve the existing React-admin dashboard response contract.
export function buildOverviewSummary(input: {
  days: number;
  profileTotal: number;
  profileComplete: number;
  profileMuted: number;
  postTotal: number;
  postPublished: number;
  postHidden: number;
  postPendingReview: number;
  commentTotal: number;
  commentPublished: number;
  commentHidden: number;
  reportOpen: number;
  reportOverdue: number;
  feedbackOpen: number;
  feedbackReviewed: number;
  feedbackClosed: number;
  teacherTotal: number;
  teacherHidden: number;
  analytics: any;
}) {
  const daily = Array.isArray(input.analytics?.daily) ? input.analytics.daily : [];
  const moderation = input.analytics?.moderation ?? {};
  const feedbackAging = Array.isArray(input.analytics?.feedbackAging) ? input.analytics.feedbackAging : [];
  const topPosts = Array.isArray(input.analytics?.topPosts) ? input.analytics.topPosts : [];
  const teacherRatings = input.analytics?.teacherRatings ?? {};
  const topPost = topPosts[0] ?? null;
  const latestDaily = [...daily]
    .sort((left, right) => String(left?.bucket_date ?? "").localeCompare(String(right?.bucket_date ?? "")))
    .at(-1) ?? {};

  return {
    operations: {
      totalProfiles: input.profileTotal,
      activeProfiles: input.profileComplete,
      newProfilesToday: Number(latestDaily.profiles) || 0,
      mutedProfiles: input.profileMuted,
      postsToday: Number(latestDaily.posts) || 0,
      commentsToday: Number(latestDaily.comments) || 0,
      postsInRange: sumMetric(daily, "posts"),
      commentsInRange: sumMetric(daily, "comments"),
      profilesInRange: sumMetric(daily, "profiles"),
      daily,
    },
    moderation: {
      openReports: input.reportOpen,
      overdueReports: input.reportOverdue,
      hiddenPosts: moderation.hiddenPosts ?? input.postHidden,
      hiddenComments: moderation.hiddenComments ?? input.commentHidden,
      mutedProfiles: moderation.mutedProfiles ?? input.profileMuted,
      pendingPosts: input.postPendingReview,
      publishedPosts: input.postPublished,
      publishedComments: input.commentPublished,
      recentRiskActions: moderation.recentRiskActions ?? [],
    },
    feedback: {
      open: input.feedbackOpen,
      reviewed: input.feedbackReviewed,
      pending: input.feedbackOpen + input.feedbackReviewed,
      closed: input.feedbackClosed,
      closedInRange: moderation.closedFeedback ?? 0,
      overdue: overdueFeedbackCount(feedbackAging),
      aging: feedbackAging,
    },
    content: {
      topPosts,
      topPostCount: topPosts.length,
      leadingScore: Number(topPost?.score) || 0,
      postsTotal: input.postTotal,
      commentsTotal: input.commentTotal,
    },
    teachers: {
      total: input.teacherTotal,
      hidden: input.teacherHidden,
      ratedTeachers: teacherRatings.teacherCount ?? 0,
      totalRatings: teacherRatings.totalRatings ?? 0,
      average: teacherRatings.average ?? 0,
      stars: teacherRatings.stars ?? [],
      lowScoreTeachers: teacherRatings.lowScoreTeachers ?? [],
    },
    meta: {
      days: input.days,
    },
  };
}

function sumMetric(rows: any[], key: string) {
  return rows.reduce((sum, row) => sum + (Number(row?.[key]) || 0), 0);
}

function overdueFeedbackCount(rows: any[]) {
  return rows.reduce((sum, row) => {
    const key = String(row?.key ?? "");
    return key === "3-7d" || key === "7d+" ? sum + (Number(row?.count) || 0) : sum;
  }, 0);
}

