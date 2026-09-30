package com.myleafy.android.features.profile

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.CancellationException

/** Resume authorization only after the user chose to install. Never launch from the background. */
@Composable
internal fun UpdateInstallationHost(manager: AppUpdateManager, onError: (String?) -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lifecycleState by lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    val requested by manager.requestingInstall.collectAsStateWithLifecycle()
    var permissionPending by remember { mutableStateOf(false) }
    var permissionRevision by remember { mutableIntStateOf(0) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        permissionPending = false
        if (!context.packageManager.canRequestPackageInstalls()) {
            manager.installationOpened()
            onError("尚未允许安装此来源的应用。授权后可继续安装。")
        }
        permissionRevision++
    }
    LaunchedEffect(requested, lifecycleState, permissionRevision) {
        if (!requested || lifecycleState != Lifecycle.State.RESUMED || permissionPending) return@LaunchedEffect
        try {
            // Check withdrawal and integrity even when returning from system settings.
            val file = manager.installationFile()
            if (!context.packageManager.canRequestPackageInstalls()) {
                permissionPending = true
                permissionLauncher.launch(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
            } else {
                onError(null)
                manager.installationOpened()
                launchInstaller(context, file)
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) {
            manager.installationOpened()
            onError(error.message ?: "无法打开安装程序")
        }
    }
}
