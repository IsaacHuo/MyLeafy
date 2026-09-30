package com.myleafy.android.navigation

import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.material3.Surface
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyMotion
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Icon
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
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
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.features.auth.LoginScreen
import com.myleafy.android.features.auth.EntryScreen
import com.myleafy.android.features.campus.CampusScreen
import com.myleafy.android.features.campus.CatalogRatingsScreen
import com.myleafy.android.features.campus.CampusCalendarScreen
import com.myleafy.android.features.campus.ComprehensiveQualityScreen
import com.myleafy.android.features.campus.HonorRecordsScreen
import com.myleafy.android.features.campus.TrainingProgramScreen
import com.myleafy.android.features.campus.ClassroomScreen
import com.myleafy.android.features.campus.ExamsScreen
import com.myleafy.android.features.campus.GradeAnalysisScreen
import com.myleafy.android.features.campus.GradesScreen
import com.myleafy.android.features.campus.FitnessTestScreen
import com.myleafy.android.features.campus.MedicalScreen
import com.myleafy.android.features.campus.SunshineRunScreen
import com.myleafy.android.features.campus.VenueOpeningsScreen
import com.myleafy.android.features.community.CommunityScreen
import com.myleafy.android.features.community.CommunitySearchScreen
import com.myleafy.android.features.community.CommunityNotificationsScreen
import com.myleafy.android.features.community.ComposePostScreen
import com.myleafy.android.features.community.PostDetailScreen
import com.myleafy.android.features.profile.ProfileScreen
import com.myleafy.android.features.profile.AboutMyLeafyScreen
import com.myleafy.android.features.profile.CheckUpdatesScreen
import com.myleafy.android.features.profile.FeedbackScreen
import com.myleafy.android.features.profile.HelpCenterScreen
import com.myleafy.android.features.profile.PermissionsInfoScreen
import com.myleafy.android.features.profile.ProfileEditScreen
import com.myleafy.android.features.profile.ProfilePreferencesScreen
import com.myleafy.android.features.profile.ProfileSyncScreen
import com.myleafy.android.features.profile.TimetableBackgroundScreen
import com.myleafy.android.features.schedule.ScheduleScreen
import com.myleafy.android.features.schedule.ScheduleExportScreen
import com.myleafy.android.features.schedule.ScheduleReviewScreen
import com.myleafy.android.features.schedule.ScheduleStatisticsScreen
import com.myleafy.android.features.schedule.ScheduleTagsScreen
import com.myleafy.android.features.schedule.ScheduleTrashScreen
import com.myleafy.android.features.timetable.TimetableScreen
import com.myleafy.android.features.timetable.TimetableIdentity
import com.myleafy.android.features.timetable.sharing.TimetableSharingScreen
import com.myleafy.android.ui.components.FeaturePlaceholder
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.theme.leafySurfaces

object Routes {
    const val LOGIN = "login"
    const val COMMUNITY_POST_DETAIL = "community/post/{postId}"
    const val COMMUNITY_COMPOSE = "community/compose"
    const val CLASSROOM = "campus/classroom"
    const val GRADE_ANALYSIS = "campus/grades/analysis"
    const val GRADES = "campus/grades"
    const val EXAMS = "campus/exams"
    const val PROFILE_EDIT = "profile/edit"
    const val SCHEDULE_NOTIFICATION = "schedule/notification?eventId={eventId}&mode={mode}"
    const val TIMETABLE_SHARE_INVITE = "timetable/share/invite?code={code}"
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
    val initialRoute = remember {
        if (activeAppScopeStore.current.campusId == null) Routes.LOGIN else RootTab.TIMETABLE.route
    }
    val canUseCommunity = activeScope.supports(CampusCapabilities.COMMUNITY)
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination
    val rootRoutes = RootTab.entries.mapTo(mutableSetOf()) { it.route }
    val showsBottomBar = currentDestination?.route in rootRoutes
    val selectedTab = currentDestination?.let { destination ->
        RootTab.entries.firstOrNull { tab -> destination.hierarchy.any { it.route == tab.route } }
    }

    LaunchedEffect(activeScope.campusId, currentDestination?.route) {
        if (activeScope.campusId == null && currentDestination?.route != null && currentDestination.route != Routes.LOGIN) {
            navController.navigate(Routes.LOGIN) {
                popUpTo(navController.graph.id) { inclusive = false }
                launchSingleTop = true
            }
        }
    }

    val navigationContent: @Composable () -> Unit = {
        NavHost(
            navController = navController,
            startDestination = initialRoute,
            enterTransition = {
                if (initialState.destination.route in rootRoutes && targetState.destination.route in rootRoutes) androidx.compose.animation.EnterTransition.None
                else fadeIn(tween(LeafyMotion.emphasized)) + slideInHorizontally(tween(LeafyMotion.emphasized, easing = LeafyMotion.easing)) { it / 8 }
            },
            exitTransition = {
                if (initialState.destination.route in rootRoutes && targetState.destination.route in rootRoutes) androidx.compose.animation.ExitTransition.None else fadeOut(tween(LeafyMotion.quick))
            },
            popEnterTransition = { fadeIn(tween(LeafyMotion.quick)) },
            popExitTransition = {
                fadeOut(tween(LeafyMotion.quick)) + slideOutHorizontally(tween(LeafyMotion.emphasized, easing = LeafyMotion.easing)) { it / 8 }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            composable(RootTab.TIMETABLE.route) { entry ->
                val reauthenticated by entry.savedStateHandle.getStateFlow("schoolReauthenticated", false).collectAsStateWithLifecycle()
                val reminder by entry.savedStateHandle.getStateFlow<String?>("courseReminder", null).collectAsStateWithLifecycle()
                TimetableScreen(
                    reminderRequest = reminder,
                    onConsumeReminder = { entry.savedStateHandle["courseReminder"] = null },
                    onTeacher = { navController.navigate("campus/teacher?name=${android.net.Uri.encode(it)}") },
                    reauthenticated = reauthenticated,
                    onConsumeReauthentication = { entry.savedStateHandle["schoolReauthenticated"] = false },
                    onReauthenticate = { navController.navigate("school-reauth") },
                    onShareClick = { navController.navigate(FeatureDestination.TIMETABLE_SHARE.route) },
                    identity = TimetableIdentity(
                        signedOut = activeScope.campusId == null,
                        isGuest = activeScope.isGuest,
                        // 教务同步入口按真实学校连接器判断，而不是课表展示能力：
                        // Android 的教务登录与抓取目前只实现北林，
                        // TIMETABLE / AUTHENTICATION 都只是入口能力，不代表存在可用连接器。
                        canSyncFromSchool = !activeScope.isGuest &&
                            activeScope.campusId == com.myleafy.android.core.campus.CampusID.bjfu,
                    ),
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
                    CommunityUnavailableContent(
                        isSignedOut = activeScope.campusId == null,
                        onLoginClick = { navController.navigate(Routes.LOGIN) },
                    )
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
                    CommunityUnavailableContent(
                        isSignedOut = activeScope.campusId == null,
                        onLoginClick = { navController.navigate(Routes.LOGIN) },
                    )
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
                    CommunityUnavailableContent(
                        isSignedOut = activeScope.campusId == null,
                        onLoginClick = { navController.navigate(Routes.LOGIN) },
                    )
                }
            }
            composable(RootTab.SCHEDULE.route) {
                ScheduleScreen(onFeatureClick = { navController.navigate(it.route) })
            }
            composable(
                route = Routes.SCHEDULE_NOTIFICATION,
                arguments = listOf(
                    navArgument("eventId") { type = NavType.StringType; defaultValue = "" },
                    navArgument("mode") { type = NavType.StringType; defaultValue = "reports" },
                ),
            ) { entry ->
                ScheduleScreen(
                    onFeatureClick = { navController.navigate(it.route) },
                    initialSection = entry.arguments?.getString("mode"),
                    initialEventId = entry.arguments?.getString("eventId"),
                )
            }
            composable(RootTab.CAMPUS.route) {
                CampusScreen(
                    onGradesClick = { navController.navigate(Routes.GRADES) },
                    onExamsClick = { navController.navigate(Routes.EXAMS) },
                    onClassroomClick = { navController.navigate(Routes.CLASSROOM) },
                    onFeatureClick = { navController.navigate(it.route) },
                    campusId = activeScope.campusId,
                )
            }
            composable("campus/teacher?name={name}", arguments = listOf(navArgument("name") { defaultValue = "" })) { entry ->
                CatalogRatingsScreen(onBack = { navController.popBackStack() }, available = activeScope.campusId == CampusID.bjfu,
                    initialSearch = entry.arguments?.getString("name").orEmpty())
            }
            composable(Routes.CLASSROOM) {
                ClassroomScreen(onBack = { navController.popBackStack() })
            }
            composable(Routes.GRADE_ANALYSIS) {
                GradeAnalysisScreen(onBack = { navController.popBackStack() }, canSync = activeScope.campusId == CampusID.bjfu)
            }
            composable(Routes.GRADES) {
                GradesScreen(onBack = { navController.popBackStack() }, onAnalysis = { navController.navigate(Routes.GRADE_ANALYSIS) }, canSync = activeScope.campusId == CampusID.bjfu)
            }
            composable(Routes.EXAMS) {
                ExamsScreen(onBack = { navController.popBackStack() }, canSync = activeScope.campusId == CampusID.bjfu)
            }
            composable(RootTab.PROFILE.route) {
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
            composable("school-reauth") {
                LoginScreen(onBack = { navController.popBackStack() }, onLoggedIn = {
                    val sync = (navController.context.applicationContext as com.myleafy.android.MyLeafyApplication).container.initialAcademicSync
                    if (sync.state.value.needsAuthentication) sync.resumeAfterAuthentication()
                    else navController.previousBackStackEntry?.savedStateHandle?.set("schoolReauthenticated", true)
                    navController.popBackStack()
                })
            }
            composable(Routes.LOGIN) {
                EntryScreen(
                    onComplete = {
                        navController.navigate(RootTab.TIMETABLE.route) {
                            popUpTo(navController.graph.id) { inclusive = false }
                            launchSingleTop = true
                        }
                    },
                    onBack = if (activeScope.campusId != null) {
                        { navController.popBackStack(); Unit }
                    } else null,
                )
            }
            composable(
                route = Routes.TIMETABLE_SHARE_INVITE,
                arguments = listOf(navArgument("code") {
                    type = NavType.StringType
                    defaultValue = ""
                }),
                deepLinks = listOf(navDeepLink { uriPattern = Routes.DEEP_LINK_TIMETABLE_INVITE }),
            ) { entry ->
                TimetableSharingScreen(
                    onBack = { navController.popBackStack() },
                    initialCode = entry.arguments?.getString("code"),
                )
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
                        FeatureDestination.SCHEDULE_TAGS -> ScheduleTagsScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.SCHEDULE_STATISTICS -> ScheduleStatisticsScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.SCHEDULE_REVIEW -> ScheduleReviewScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.SCHEDULE_EXPORT -> ScheduleExportScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.SCHEDULE_TRASH -> ScheduleTrashScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_TRAINING_PLAN -> TrainingProgramScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_COMPREHENSIVE -> ComprehensiveQualityScreen(
                            onBack = { navController.popBackStack() },
                            available = activeScope.campusId == com.myleafy.android.core.campus.CampusID.bjfu,
                        )
                        FeatureDestination.CAMPUS_HONOR_RECORDS -> HonorRecordsScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_SUNSHINE_RUN -> SunshineRunScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_FITNESS_TEST -> FitnessTestScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_VENUES -> VenueOpeningsScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.CAMPUS_MEDICAL -> MedicalScreen(
                            onBack = { navController.popBackStack() },
                            available = activeScope.supports(CampusCapabilities.MEDICAL_SERVICES),
                        )
                        FeatureDestination.CAMPUS_RATINGS -> CatalogRatingsScreen(
                            onBack = { navController.popBackStack() },
                            available = activeScope.supports(CampusCapabilities.COMMUNITY) &&
                                activeScope.supports(CampusCapabilities.CATALOG_RATINGS),
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
                            canSync = activeScope.campusId == CampusID.bjfu,
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_ABOUT -> AboutMyLeafyScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.PROFILE_UPDATE -> CheckUpdatesScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.TIMETABLE_BACKGROUND -> TimetableBackgroundScreen(
                            onBack = { navController.popBackStack() },
                        )
                        FeatureDestination.TIMETABLE_SHARE,
                        FeatureDestination.PROFILE_SHARING,
                        -> TimetableSharingScreen(
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

    LeafyNavigationScaffold(
            selectedTab = selectedTab ?: RootTab.TIMETABLE,
            showNavigation = showsBottomBar && selectedTab != null,
            onTabSelected = { tab ->
                navController.navigate(tab.route) {
                    popUpTo(RootTab.TIMETABLE.route) {
                        saveState = true
                    }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            content = navigationContent,
        )
}

/**
 * 根部导航壳（纯 chrome，无状态）：只负责导航组件的外观与选中态，
 * 不持有路由、不发起导航，业务回调仍由 [MyLeafyNavHost] 提供。
 * 截图测试可以复用同一实现，避免出现与真实外壳不一致的假壳。
 */
@Composable
fun LeafyNavigationScaffold(
    selectedTab: RootTab,
    onTabSelected: (RootTab) -> Unit,
    modifier: Modifier = Modifier,
    showNavigation: Boolean = true,
    content: @Composable () -> Unit,
) {
    BoxWithConstraints(modifier.fillMaxSize().background(MaterialTheme.leafySurfaces.page)) {
        if (maxWidth < 600.dp) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).consumeWindowInsets(WindowInsets.navigationBars)) { content() }
                if (showNavigation) Surface(
                    modifier = Modifier.navigationBarsPadding().padding(horizontal = LeafySpacing.card, vertical = LeafySpacing.micro),
                    shape = RoundedCornerShape(28.dp),
                    color = MaterialTheme.leafySurfaces.elevated.copy(alpha = 0.96f),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.35f)),
                    shadowElevation = 2.dp,
                ) {
                    Row(Modifier.fillMaxWidth().selectableGroup().padding(vertical = 4.dp)) {
                        RootTab.entries.forEach { tab ->
                            val selected = tab == selectedTab
                            val tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                            Column(
                                Modifier.weight(1f).heightIn(min = 52.dp)
                                    .testTag("root-tab-${tab.route}")
                                    .selectable(selected = selected, role = Role.Tab, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = { onTabSelected(tab) })
                                    .padding(vertical = 4.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
                            ) {
                                Box(Modifier.size(36.dp).background(
                                    if (selected) MaterialTheme.colorScheme.secondaryContainer else androidx.compose.ui.graphics.Color.Transparent,
                                    androidx.compose.foundation.shape.CircleShape,
                                ), contentAlignment = Alignment.Center) {
                                    Icon(if (selected) tab.selectedIcon else tab.icon, null, Modifier.size(22.dp), tint)
                                }
                                Text(stringResource(tab.labelRes), color = tint, style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }
            }
        } else {
            NavigationSuiteScaffold(
                navigationSuiteItems = {
                    if (showNavigation) RootTab.entries.forEach { tab ->
                        val selected = tab == selectedTab
                        item(
                            modifier = Modifier.testTag("root-tab-${tab.route}"),
                            selected = selected,
                            onClick = { onTabSelected(tab) },
                            icon = {
                                Icon(
                                    imageVector = if (selected) tab.selectedIcon else tab.icon,
                                    contentDescription = stringResource(tab.labelRes),
                                )
                            },
                            label = { Text(stringResource(tab.labelRes)) },
                        )
                    }
                },
                modifier = modifier,
                containerColor = MaterialTheme.leafySurfaces.page,
                contentColor = MaterialTheme.colorScheme.onSurface,
                content = content,
            )
        }
    }
}

@Composable
private fun CommunityUnavailableContent(
    isSignedOut: Boolean,
    onLoginClick: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        LeafyEmptyState(
            title = "社区暂不可用",
            message = if (isSignedOut) {
                "登录支持社区的校园身份后即可进入。"
            } else {
                "当前校园入口暂不提供社区服务。"
            },
            action = if (isSignedOut) {
                { Button(onClick = onLoginClick) { Text("登录学校账号") } }
            } else {
                null
            },
        )
    }
}
