package com.myleafy.android.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.School
import androidx.compose.ui.graphics.vector.ImageVector
import com.myleafy.android.R

/**
 * 根 Tab（对齐 iOS：课表 / 校园 / 我的）。
 * 校园社区与日迹记录不再占用根 Tab，它们是校园一级领域里的内容。
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
