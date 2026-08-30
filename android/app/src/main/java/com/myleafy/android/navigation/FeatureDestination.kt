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
        description = "帖子、话题与用户搜索将在后续阶段接入。",
    ),
    COMMUNITY_NOTIFICATIONS(
        route = "community/notifications",
        title = "社区通知",
        description = "通知列表与实时提醒将在后续阶段接入。",
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
    CAMPUS_LEARNING_SPACE(
        route = "campus/learning-space",
        title = "学习空间",
        description = "学习项目、资料与专注记录将在后续阶段接入。",
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
    PROFILE_ABOUT(
        route = "profile/about",
        title = "关于 MyLeafy",
        description = "版本信息、开源许可与项目介绍将在后续阶段补齐。",
    ),
}
