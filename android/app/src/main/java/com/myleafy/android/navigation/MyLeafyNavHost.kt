package com.myleafy.android.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.features.auth.LoginScreen
import com.myleafy.android.features.campus.CampusScreen
import com.myleafy.android.features.campus.CampusCalendarScreen
import com.myleafy.android.features.campus.ClassroomScreen
import com.myleafy.android.features.campus.ExamsScreen
import com.myleafy.android.features.campus.GradesScreen
import com.myleafy.android.features.community.CommunityScreen
import com.myleafy.android.features.community.CommunitySearchScreen
import com.myleafy.android.features.community.CommunityNotificationsScreen
import com.myleafy.android.features.community.ComposePostScreen
import com.myleafy.android.features.community.PostDetailScreen
import com.myleafy.android.features.profile.ProfileScreen
import com.myleafy.android.features.profile.AboutMyLeafyScreen
import com.myleafy.android.features.profile.FeedbackScreen
import com.myleafy.android.features.profile.HelpCenterScreen
import com.myleafy.android.features.profile.PermissionsInfoScreen
import com.myleafy.android.features.profile.ProfileEditScreen
import com.myleafy.android.features.profile.ProfilePreferencesScreen
import com.myleafy.android.features.profile.ProfileSyncScreen
import com.myleafy.android.features.schedule.ScheduleScreen
import com.myleafy.android.features.timetable.TimetableScreen
import com.myleafy.android.ui.components.FeaturePlaceholder
import com.myleafy.android.ui.components.LeafyEmptyState

object Routes {
    const val LOGIN = "login"
    const val COMMUNITY_POST_DETAIL = "community/post/{postId}"
    const val COMMUNITY_COMPOSE = "community/compose"
    const val CLASSROOM = "campus/classroom"
    const val GRADES = "campus/grades"
    const val EXAMS = "campus/exams"
    const val PROFILE_EDIT = "profile/edit"
    const val DEEP_LINK_COMMUNITY_POST = "myleafy://community-post?id={postId}"
    const val DEEP_LINK_TIMETABLE_INVITE = "myleafy://timetable-invite?code={code}"

    fun communityPostDetail(postId: String) = "community/post/$postId"
}

/**
 * 根导航壳：Scaffold + NavigationBar + NavHost。
 * 5 个固定 Tab + 登录路由；社区/共享课表深链挂靠对应 Tab。
 */
@Composable
fun MyLeafyNavHost(
    navController: NavHostController,
    activeAppScopeStore: ActiveAppScopeStore,
) {
    val activeScope by activeAppScopeStore.scope.collectAsStateWithLifecycle()
    val canUseCommunity = activeScope.supports(CampusCapabilities.COMMUNITY)
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination
    val rootRoutes = RootTab.entries.mapTo(mutableSetOf()) { it.route }
    val showsBottomBar = currentDestination?.route in rootRoutes
    val visibleRootTabs = RootTab.entries.filter { it != RootTab.COMMUNITY || canUseCommunity }

    LaunchedEffect(canUseCommunity, currentDestination?.route) {
        if (!canUseCommunity && currentDestination?.route == RootTab.COMMUNITY.route) {
            navController.navigate(RootTab.TIMETABLE.route) {
                popUpTo(navController.graph.findStartDestination().id) { inclusive = false }
                launchSingleTop = true
            }
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showsBottomBar) {
                NavigationBar {
                    visibleRootTabs.forEach { tab ->
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
                )
            }
            composable(RootTab.COMMUNITY.route) {
                if (canUseCommunity) {
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
                } else {
                    CommunityUnavailableContent()
                }
            }
            composable(Routes.COMMUNITY_COMPOSE) {
                if (canUseCommunity) {
                    ComposePostScreen(
                        onBack = { navController.popBackStack() },
                        onPublished = {
                            navController.popBackStack()
                        },
                    )
                } else {
                    CommunityUnavailableContent()
                }
            }
            composable(
                route = Routes.COMMUNITY_POST_DETAIL,
                arguments = listOf(navArgument("postId") { type = NavType.StringType }),
                deepLinks = listOf(
                    navDeepLink { uriPattern = Routes.DEEP_LINK_COMMUNITY_POST },
                ),
            ) { entry ->
                val postId = entry.arguments?.getString("postId").orEmpty()
                if (canUseCommunity) {
                    PostDetailScreen(
                        postId = postId,
                        onBack = { navController.popBackStack() },
                    )
                } else {
                    CommunityUnavailableContent()
                }
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
                    onEditProfileClick = { navController.navigate(Routes.PROFILE_EDIT) },
                    onFeatureClick = { navController.navigate(it.route) },
                )
            }
            composable(Routes.PROFILE_EDIT) {
                ProfileEditScreen(
                    onBack = { navController.popBackStack() },
                    onSaved = { navController.popBackStack() },
                )
            }
            composable(Routes.LOGIN) {
                LoginScreen(onBack = { navController.popBackStack() })
            }
            FeatureDestination.entries.forEach { destination ->
                composable(destination.route) {
                    when (destination) {
                        FeatureDestination.COMMUNITY_SEARCH -> CommunitySearchScreen(
                            onBack = { navController.popBackStack() },
                            onPostClick = { postId ->
                                navController.navigate(Routes.communityPostDetail(postId))
                            },
                        )
                        FeatureDestination.COMMUNITY_NOTIFICATIONS -> CommunityNotificationsScreen(
                            onBack = { navController.popBackStack() },
                            onPostClick = { postId ->
                                navController.navigate(Routes.communityPostDetail(postId))
                            },
                        )
                        FeatureDestination.CAMPUS_CALENDAR -> CampusCalendarScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_HELP -> HelpCenterScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_FEEDBACK -> FeedbackScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_PERMISSIONS -> PermissionsInfoScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_PERSONALIZATION -> ProfilePreferencesScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_SYNC -> ProfileSyncScreen(
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

@Composable
private fun CommunityUnavailableContent() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        LeafyEmptyState(
            title = "社区暂不可用",
            message = "登录支持社区的校园身份后即可进入。",
        )
    }
}
