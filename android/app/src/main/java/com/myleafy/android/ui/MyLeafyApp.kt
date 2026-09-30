package com.myleafy.android.ui

import android.content.Intent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.rememberNavController
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.navigation.MyLeafyNavHost
import com.myleafy.android.features.schedule.notifications.NotificationDeliveryWorker

/**
 * 恢复本机身份后，进入双入口登录页或五个根 Tab 的导航壳。
 * 深链（myleafy://community-post / timetable-invite）在此转发给 NavHost。
 */
@Composable
fun MyLeafyApp(deepLinkIntent: Intent? = null) {
    val application = LocalContext.current.applicationContext as MyLeafyApplication
    var ready by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var retry by remember { mutableStateOf(0) }
    LaunchedEffect(retry) {
        error = null
        try {
            application.container.restoreIdentity()
            application.container.initialAcademicSync.start()
            ready = true
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            error = failure.message ?: "无法读取本机身份"
        }
    }
    if (!ready) {
        androidx.compose.material3.Surface {
            androidx.compose.foundation.layout.Box(
                modifier = androidx.compose.ui.Modifier.fillMaxSize(),
                contentAlignment = androidx.compose.ui.Alignment.Center,
            ) {
                if (error == null) androidx.compose.material3.CircularProgressIndicator()
                else com.myleafy.android.ui.components.LeafyErrorState(
                    title = "无法恢复本机身份",
                    message = error!!,
                    action = {
                        com.myleafy.android.ui.components.LeafyTextButton(onClick = { retry++ }) {
                            androidx.compose.material3.Text("重试")
                        }
                    },
                )
            }
        }
        return
    }
    val navController = rememberNavController()

    MyLeafyNavHost(
        navController = navController,
        activeAppScopeStore = application.container.activeAppScopeStore,
    )

    LaunchedEffect(deepLinkIntent) {
        if (deepLinkIntent?.getBooleanExtra("courseReminder", false) == true) {
            val uri = android.net.Uri.Builder().scheme("myleafy-internal").authority("course")
            listOf("scope", "semester", "course").forEach { uri.appendQueryParameter(it, deepLinkIntent.getStringExtra(it)) }
            uri.appendQueryParameter("week", deepLinkIntent.getIntExtra("week", 0).toString())
            navController.navigate(com.myleafy.android.navigation.RootTab.TIMETABLE.route) { launchSingleTop = true }
            navController.currentBackStackEntry?.savedStateHandle?.set("courseReminder", uri.build().toString())
        }
    }

    // 普通 Launcher Intent 没有 data，不应进入深链分发。把 effect 放在
    // NavHost 之后也确保导航图已经安装，避免冷启动时访问空 topGraph。
    LaunchedEffect(deepLinkIntent?.data) {
        if (deepLinkIntent?.data != null && !deepLinkIntent.getBooleanExtra("courseReminder", false)) {
            navController.handleDeepLink(deepLinkIntent)
        }
    }
    LaunchedEffect(
        deepLinkIntent?.getStringExtra(NotificationDeliveryWorker.EXTRA_NOTIFICATION_ROUTE),
        deepLinkIntent?.getStringExtra(NotificationDeliveryWorker.KEY_EVENT_ID),
        deepLinkIntent?.getStringExtra(NotificationDeliveryWorker.EXTRA_NOTIFICATION_MODE),
    ) {
        if (deepLinkIntent?.getStringExtra(NotificationDeliveryWorker.EXTRA_NOTIFICATION_ROUTE) == "schedule") {
            val eventId = android.net.Uri.encode(
                deepLinkIntent.getStringExtra(NotificationDeliveryWorker.KEY_EVENT_ID).orEmpty(),
            )
            val mode = android.net.Uri.encode(
                deepLinkIntent.getStringExtra(NotificationDeliveryWorker.EXTRA_NOTIFICATION_MODE) ?: "reports",
            )
            navController.navigate("schedule/notification?eventId=$eventId&mode=$mode")
        }
    }
}
