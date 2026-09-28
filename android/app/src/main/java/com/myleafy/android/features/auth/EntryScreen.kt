package com.myleafy.android.features.auth

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.ui.components.*
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

@Composable
fun EntryScreen(onComplete: () -> Unit, onBack: (() -> Unit)? = null) {
    val container = (LocalContext.current.applicationContext as MyLeafyApplication).container
    var schoolForm by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    if (schoolForm) {
        BackHandler { schoolForm = false }
        LoginScreen(onBack = { schoolForm = false }, onLoggedIn = onComplete)
    } else {
        EntryContent(
            busy = busy,
            error = error,
            onBack = onBack,
            onSchool = {
                scope.launch(Dispatchers.Main.immediate) {
                    busy = true
                    error = null
                    try {
                        if (container.schoolSessionState.identity != null) container.signOut()
                        schoolForm = true
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        error = failure.message ?: "无法切换学校账号，请重试"
                    } finally {
                        busy = false
                    }
                }
            },
            onLocal = {
                scope.launch(Dispatchers.Main.immediate) {
                    busy = true
                    error = null
                    try {
                        container.enterLocalMode()
                        onComplete()
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        error = failure.message ?: "无法进入免登录模式，请重试"
                    } finally {
                        busy = false
                    }
                }
            },
        )
    }
}

@Composable
fun EntryContent(
    busy: Boolean,
    error: String?,
    onSchool: () -> Unit,
    onLocal: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    Scaffold(containerColor = MaterialTheme.leafySurfaces.page) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            Column(
                Modifier.widthIn(max = LeafyComponentSize.formMaxWidth).fillMaxWidth()
                    .verticalScroll(rememberScrollState()).padding(LeafySpacing.page),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.card),
            ) {
                Text("MyLeafy", style = MaterialTheme.typography.headlineLarge)
                Text("选择入口", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(LeafySpacing.card))
                LeafyPrimaryButton(onClick = onSchool, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text("北京林业大学")
                }
                Text("已接入教务系统，可使用校园账号登录。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                LeafySecondaryButton(onClick = onLocal, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text(if (busy) "正在进入…" else "免登录入口")
                }
                Text("无需账号和密码，数据全部保存在本机，不连接任何后台。",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                error?.let { LeafyStatusBanner(it, isError = true) }
                onBack?.let { LeafyTextButton(onClick = it, enabled = !busy) { Text("返回") } }
            }
        }
    }
}
