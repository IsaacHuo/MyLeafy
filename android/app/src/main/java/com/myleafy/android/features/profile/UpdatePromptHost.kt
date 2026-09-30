package com.myleafy.android.features.profile

import androidx.compose.runtime.*
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import com.myleafy.android.navigation.RootTab
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.ui.components.UpdatePresentationGate
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner

@Composable
fun UpdatePromptHost(manager: AppUpdateManager, navController: NavHostController, gate: UpdatePresentationGate) {
    val info by manager.prompt.collectAsStateWithLifecycle()
    val entry by navController.currentBackStackEntryAsState()
    val route = entry?.destination?.route
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    // Secondary pages include all login and full-screen editors. Sheets/dialogs register a blocker.
    if (lifecycleState == Lifecycle.State.RESUMED && info != null && RootTab.entries.any { it.route == route } && gate.blockers == 0) {
        val offered = info!!
        AlertDialog(
            onDismissRequest = { manager.later(offered) },
            title = { Text("发现新版本 ${offered.versionName}") },
            text = { androidx.compose.foundation.layout.Column {
                Text("${"%.1f".format(offered.sizeBytes / 1048576.0)} MB")
                Text(offered.releaseNotes)
            } },
            confirmButton = { TextButton(onClick = {
                manager.download(offered)
                navController.navigate(FeatureDestination.PROFILE_UPDATE.route) { launchSingleTop = true }
            }) { Text("更新") } },
            dismissButton = { TextButton(onClick = { manager.later(offered) }) { Text("稍后") } },
        )
    }
}
