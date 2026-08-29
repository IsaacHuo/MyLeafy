package com.myleafy.android.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
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
import com.myleafy.android.features.campus.CampusCalendarScreen
import com.myleafy.android.features.campus.ClassroomScreen
import com.myleafy.android.features.campus.ExamsScreen
import com.myleafy.android.features.campus.GradesScreen
import com.myleafy.android.features.community.CommunityScreen
import com.myleafy.android.features.community.ComposePostScreen
import com.myleafy.android.features.community.PostDetailScreen
import com.myleafy.android.features.profile.ProfileScreen
import com.myleafy.android.features.profile.AboutMyLeafyScreen
import com.myleafy.android.features.profile.HelpCenterScreen
import com.myleafy.android.features.profile.PermissionsInfoScreen
import com.myleafy.android.features.schedule.ScheduleScreen
import com.myleafy.android.features.timetable.TimetableScreen
import com.myleafy.android.ui.components.FeaturePlaceholder

object Routes {
    const val LOGIN = "login"
    const val COMMUNITY_POST_DETAIL = "community/post/{postId}"
    const val COMMUNITY_COMPOSE = "community/compose"
    const val CLASSROOM = "campus/classroom"
    const val GRADES = "campus/grades"
    const val EXAMS = "campus/exams"
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
    val rootRoutes = RootTab.entries.mapTo(mutableSetOf()) { it.route }
    val showsBottomBar = currentDestination?.route in rootRoutes

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showsBottomBar) {
                NavigationBar {
                    RootTab.entries.forEach { tab ->
                        val selected = currentDestination
                            ?.hierarchy
                            ?.any { it.route == tab.route } == true
                        NavigationBarItem(
                            modifier = Modifier.testTag("root-tab-${tab.route}"),
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
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = RootTab.TIMETABLE.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(RootTab.TIMETABLE.route) {
                TimetableScreen(
                    onShareClick = { navController.navigate(FeatureDestination.TIMETABLE_SHARE.route) },
                    onExportClick = { navController.navigate(FeatureDestination.TIMETABLE_EXPORT.route) },
                    onAddScheduleClick = { navController.navigate(FeatureDestination.TIMETABLE_ADD_SCHEDULE.route) },
                )
            }
            composable(RootTab.COMMUNITY.route) {
                CommunityScreen(
                    onPostClick = { postId ->
                        navController.navigate(Routes.communityPostDetail(postId))
                    },
                    onComposeClick = {
                        navController.navigate(Routes.COMMUNITY_COMPOSE)
                    },
                    onSearchClick = { navController.navigate(FeatureDestination.COMMUNITY_SEARCH.route) },
                    onNotificationsClick = {
                        navController.navigate(FeatureDestination.COMMUNITY_NOTIFICATIONS.route)
                    },
                )
            }
            composable(Routes.COMMUNITY_COMPOSE) {
                ComposePostScreen(
                    onBack = { navController.popBackStack() },
                    onPublished = {
                        navController.popBackStack()
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
            composable(RootTab.SCHEDULE.route) {
                ScheduleScreen(onFeatureClick = { navController.navigate(it.route) })
            }
            composable(RootTab.CAMPUS.route) {
                CampusScreen(
                    onGradesClick = { navController.navigate(Routes.GRADES) },
                    onExamsClick = { navController.navigate(Routes.EXAMS) },
                    onClassroomClick = { navController.navigate(Routes.CLASSROOM) },
                    onFeatureClick = { navController.navigate(it.route) },
                )
            }
            composable(Routes.CLASSROOM) {
                ClassroomScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.GRADES) {
                GradesScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.EXAMS) {
                ExamsScreen(onBack = { navController.popBackStack() })
            }
            composable(
                route = RootTab.PROFILE.route,
                deepLinks = listOf(
                    navDeepLink { uriPattern = Routes.DEEP_LINK_TIMETABLE_INVITE },
                ),
            ) {
                ProfileScreen(
                    onLoginClick = { navController.navigate(Routes.LOGIN) },
                    onFeatureClick = { navController.navigate(it.route) },
                )
            }
            composable(Routes.LOGIN) {
                LoginScreen(onBack = { navController.popBackStack() })
            }
            FeatureDestination.entries.forEach { destination ->
                composable(destination.route) {
                    when (destination) {
                        FeatureDestination.CAMPUS_CALENDAR -> CampusCalendarScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_HELP -> HelpCenterScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_PERMISSIONS -> PermissionsInfoScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_ABOUT -> AboutMyLeafyScreen(
                            onBack = { navController.popBackStack() },
                        )
                        else -> FeaturePlaceholder(
                            destination = destination,
                            onBack = { navController.popBackStack() },
                        )
                    }
                }
            }
        }
    }
}
