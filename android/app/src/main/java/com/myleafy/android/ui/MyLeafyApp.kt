package com.myleafy.android.ui

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.rememberNavController
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.navigation.MyLeafyNavHost

/**
 * 根组合入口。阶段 1 固定 5 个 Tab 的导航壳；
 * 后续按身份状态在 Login 与主壳之间切换（对应 iOS leafyApp 的决策逻辑）。
 * 深链（myleafy://community-post / timetable-invite）在此转发给 NavHost。
 */
@Composable
fun MyLeafyApp(deepLinkIntent: Intent? = null) {
    val navController = rememberNavController()
    val application = LocalContext.current.applicationContext as MyLeafyApplication

    MyLeafyNavHost(
        navController = navController,
        activeAppScopeStore = application.container.activeAppScopeStore,
    )

    // 普通 Launcher Intent 没有 data，不应进入深链分发。把 effect 放在
    // NavHost 之后也确保导航图已经安装，避免冷启动时访问空 topGraph。
    LaunchedEffect(deepLinkIntent?.data) {
        if (deepLinkIntent?.data != null) {
            navController.handleDeepLink(deepLinkIntent)
        }
    }
}
