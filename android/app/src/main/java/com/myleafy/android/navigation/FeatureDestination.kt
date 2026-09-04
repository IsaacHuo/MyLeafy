package com.myleafy.android.navigation

/**
 * 尚未接入真实能力的二级功能目录。
 *
 * 路由只负责把已经规划的产品入口落到明确的占位页；它不会返回假数据，
 * 也不会用成功状态掩盖尚未实现的功能。
 */
enum class FeatureDestination(
    val route: String,
    val title: String,
    val description: String,
) {
    TIMETABLE_SHARE(
        route = "timetable/share",
        title = "共享课表",
        description = "邀请同学查看课表的 Android 版本正在接入。",
    ),
    COMMUNITY_SEARCH(
        route = "community/search",
        title = "搜索社区",
        description = "搜索当前校园的帖子标题和正文。",
    ),
    COMMUNITY_NOTIFICATIONS(
        route = "community/notifications",
        title = "社区通知",
        description = "查看社区互动通知并管理已读状态。",
    ),
    SCHEDULE_TAGS(
        route = "schedule/tags",
        title = "标签",
        description = "标签整理与筛选界面正在建设。",
    ),
    SCHEDULE_STATISTICS(
        route = "schedule/statistics",
        title = "记录日迹",
        description = "本机统计、热力图与分享卡片将在后续阶段接入。",
    ),
    SCHEDULE_TRASH(
        route = "schedule/trash",
        title = "回收站",
        description = "已删除随记的恢复与清理界面正在建设。",
    ),
    SCHEDULE_REPORTS(
        route = "schedule/reports",
        title = "日程推送",
        description = "日程报告与通知规则将在后续阶段接入。",
    ),
    CAMPUS_TRAINING_PLAN(
        route = "campus/training-plan",
        title = "培养方案",
        description = "培养方案与毕业要求的 Android 界面正在迁移。",
    ),
    CAMPUS_CALENDAR(
        route = "campus/calendar",
        title = "校历",
        description = "学期事件、节假日与校历浏览将在后续阶段接入。",
    ),
    CAMPUS_SUNSHINE_RUN(
        route = "campus/sports/sunshine-run",
        title = "阳光长跑",
        description = "记录跑步并按教学周查看完成进度。",
    ),
    CAMPUS_FITNESS_TEST(
        route = "campus/sports/fitness-test",
        title = "体测记录",
        description = "记录、筛选并观察各体测项目变化。",
    ),
    CAMPUS_VENUES(
        route = "campus/sports/venues",
        title = "场馆开放",
        description = "查看北林场馆的静态开放、预约与收费说明。",
    ),
    CAMPUS_MEDICAL(
        route = "campus/medical",
        title = "医疗事项",
        description = "查看医疗政策、报销指引并管理本机台账。",
    ),
    CAMPUS_RATINGS(
        route = "campus/ratings",
        title = "评价相关",
        description = "评教、评课与评菜依赖社区身份和评价服务。",
    ),
    PROFILE_SYNC(
        route = "profile/sync",
        title = "缓存与同步",
        description = "统一的数据检查与重新同步界面正在建设。",
    ),
    PROFILE_SHARING(
        route = "profile/sharing",
        title = "共享课表",
        description = "共享成员与邀请管理将在后续阶段接入。",
    ),
    PROFILE_PERSONALIZATION(
        route = "profile/personalization",
        title = "个性化",
        description = "主题、密度与课表背景设置将在后续阶段接入。",
    ),
    TIMETABLE_BACKGROUND(
        route = "profile/timetable-background",
        title = "课表背景",
        description = "设置照片或纯色背景以及课表可读性参数。",
    ),
    PROFILE_PERMISSIONS(
        route = "profile/permissions",
        title = "系统权限",
        description = "通知、媒体与日历权限管理将在后续阶段接入。",
    ),
    PROFILE_HELP(
        route = "profile/help",
        title = "帮助中心",
        description = "使用指南、常见问题与数据安全说明正在整理。",
    ),
    PROFILE_FEEDBACK(
        route = "profile/feedback",
        title = "反馈与支持",
        description = "通过邮件或在线支持渠道提交问题与建议。",
    ),
    PROFILE_ABOUT(
        route = "profile/about",
        title = "关于 MyLeafy",
        description = "版本信息、开源许可与项目介绍将在后续阶段补齐。",
    ),
}
