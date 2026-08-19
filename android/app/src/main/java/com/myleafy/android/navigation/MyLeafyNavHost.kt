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
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.navArgument
import androidx.navigation.navDeepLink
import com.myleafy.android.features.auth.LoginScreen
import com.myleafy.android.features.campus.CampusScreen
import com.myleafy.android.features.community.CommunityScreen
import com.myleafy.android.features.community.PostDetailScreen
import com.myleafy.android.features.profile.ProfileScreen
import com.myleafy.android.features.schedule.ScheduleScreen
import com.myleafy.android.features.timetable.TimetableScreen

object Routes {
    const val LOGIN = "login"
    const val COMMUNITY_POST_DETAIL = "community/post/{postId}"
    const val DEEP_LINK_COMMUNITY_POST = "myleafy://community-post?id={postId}"
    const val DEEP_LINK_TIMETABLE_INVITE = "myleafy://timetable-invite?code={code}"

    fun communityPostDetail(postId: String) = "community/post/$postId"
}

/**
 * 根导航壳：Scaffold + NavigationBar + NavHost。
 * 5 个固定 Tab + 登录路由；社区/共享课表深链挂靠对应 Tab。
 */
@Composable
fun MyLeafyNavHost(navController: NavHostController) {
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
            composable(RootTab.COMMUNITY.route) {
                CommunityScreen(
                    onPostClick = { postId ->
                        navController.navigate(Routes.communityPostDetail(postId))
                    },
                )
            }
            composable(
                route = Routes.COMMUNITY_POST_DETAIL,
                arguments = listOf(navArgument("postId") { type = NavType.StringType }),
                deepLinks = listOf(
                    navDeepLink { uriPattern = Routes.DEEP_LINK_COMMUNITY_POST },
                ),
            ) { entry ->
                val postId = entry.arguments?.getString("postId").orEmpty()
                PostDetailScreen(
                    postId = postId,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(RootTab.SCHEDULE.route) { ScheduleScreen() }
            composable(RootTab.CAMPUS.route) { CampusScreen() }
            composable(
                route = RootTab.PROFILE.route,
                deepLinks = listOf(
                    navDeepLink { uriPattern = Routes.DEEP_LINK_TIMETABLE_INVITE },
                ),
            ) {
                ProfileScreen(onLoginClick = { navController.navigate(Routes.LOGIN) })
            }
            composable(Routes.LOGIN) {
                LoginScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}
