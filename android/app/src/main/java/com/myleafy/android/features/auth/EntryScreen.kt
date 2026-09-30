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
    var schoolSelected by rememberSaveable { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val header: @Composable () -> Unit = {
        EntryHeader(schoolSelected, busy) { schoolSelected = it }
    }
    Scaffold(containerColor = MaterialTheme.leafySurfaces.page) { padding ->
        val contentModifier = Modifier.fillMaxSize().padding(padding)
        if (schoolSelected) {
            LoginScreen(onBack = { onBack?.invoke() }, onLoggedIn = onComplete,
                entryHeader = header, modifier = contentModifier, onBusyChanged = { busy = it })
        } else {
            Box(contentModifier, contentAlignment = Alignment.Center) {
                Column(Modifier.widthIn(max = LeafyComponentSize.formMaxWidth).fillMaxWidth()
                    .verticalScroll(rememberScrollState()).padding(LeafySpacing.page)) {
                    header()
                    LeafyPrimaryButton(enabled = !busy, modifier = Modifier.fillMaxWidth(), onClick = {
                        scope.launch(Dispatchers.Main.immediate) {
                            busy = true
                            error = null
                            try { container.enterLocalMode(); onComplete() }
                            catch (cancelled: CancellationException) { throw cancelled }
                            catch (failure: Exception) {
                                android.util.Log.e("EntryScreen", "Local entry failed", failure)
                                error = "无法进入免登录模式，请重试"
                            }
                            finally { busy = false }
                        }
                    }) { Text(if (busy) "正在进入…" else "直接进入") }
                    error?.let { LeafyStatusBanner(it, isError = true) }
                }
            }
        }
    }
}

@Composable
internal fun EntryHeader(schoolSelected: Boolean, busy: Boolean, onSelectSchool: (Boolean) -> Unit) {
        Text("MyLeafy", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(LeafySpacing.section))
        Text("选择入口", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        listOf(true to "北京林业大学", false to "免登录入口").forEach { (school, title) ->
            Surface(
                onClick = { onSelectSchool(school) }, enabled = !busy,
                shape = MaterialTheme.shapes.medium,
                color = if (schoolSelected == school) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.leafySurfaces.content,
                modifier = Modifier.fillMaxWidth().padding(vertical = LeafySpacing.tiny),
            ) {
                Row(Modifier.padding(LeafySpacing.card), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = schoolSelected == school, onClick = null)
                    Column(Modifier.weight(1f).padding(start = LeafySpacing.compact)) {
                        Text(title, style = MaterialTheme.typography.titleMedium)
                        Text(if (school) "已接入教务系统，可使用校园账号登录。" else "无需账号和密码，数据全部保存在本机，不连接任何后台。",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Spacer(Modifier.height(LeafySpacing.section))
}
