package com.myleafy.android.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.EventNote
import androidx.compose.material.icons.automirrored.outlined.EventNote
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.School
import androidx.compose.ui.graphics.vector.ImageVector
import com.myleafy.android.R

/**
 * 根 Tab（对应 iOS `RootTab`，顺序固定：课表 / 社区 / 日迹 / 校园 / 我的）。
 * 阶段 1 固定显示 5 个 Tab；校园 capability 门控在后续阶段按
 * `ActiveCampusContext.descriptor` 决定是否隐藏社区入口。
 */
enum class RootTab(
    val route: String,
    @param:StringRes val labelRes: Int,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
) {
    TIMETABLE(
        route = "timetable",
        labelRes = R.string.tab_timetable,
        icon = Icons.Outlined.CalendarMonth,
        selectedIcon = Icons.Filled.CalendarMonth,
    ),
    COMMUNITY(
        route = "community",
        labelRes = R.string.tab_community,
        icon = Icons.Outlined.Groups,
        selectedIcon = Icons.Filled.Groups,
    ),
    SCHEDULE(
        route = "schedule",
        labelRes = R.string.tab_schedule,
        icon = Icons.AutoMirrored.Outlined.EventNote,
        selectedIcon = Icons.AutoMirrored.Filled.EventNote,
    ),
    CAMPUS(
        route = "campus",
        labelRes = R.string.tab_campus,
        icon = Icons.Outlined.School,
        selectedIcon = Icons.Filled.School,
    ),
    PROFILE(
        route = "profile",
        labelRes = R.string.tab_profile,
        icon = Icons.Outlined.Person,
        selectedIcon = Icons.Filled.Person,
    ),
}
