package com.myleafy.android.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.myleafy.android.features.campus.CampusScreen
import com.myleafy.android.features.community.CommunityScreen
import com.myleafy.android.features.profile.ProfileScreen
import com.myleafy.android.features.schedule.ScheduleScreen
import com.myleafy.android.features.timetable.TimetableScreen

/**
 * 根导航壳：Scaffold + NavigationBar（Material 3）+ NavHost。
 * Tab 切换使用 saveState / restoreState 保留各页状态。
 */
@Composable
fun MyLeafyNavHost() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination

    Scaffold(
        bottomBar = {
            NavigationBar {
                RootTab.entries.forEach { tab ->
                    val selected = currentDestination
                        ?.hierarchy
                        ?.any { it.route == tab.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Icon(
                                imageVector = if (selected) tab.selectedIcon else tab.icon,
                                contentDescription = stringResource(tab.labelRes),
                            )
                        },
                        label = { Text(stringResource(tab.labelRes)) },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = RootTab.TIMETABLE.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(RootTab.TIMETABLE.route) { TimetableScreen() }
            composable(RootTab.COMMUNITY.route) { CommunityScreen() }
            composable(RootTab.SCHEDULE.route) { ScheduleScreen() }
            composable(RootTab.CAMPUS.route) { CampusScreen() }
            composable(RootTab.PROFILE.route) { ProfileScreen() }
        }
    }
}
