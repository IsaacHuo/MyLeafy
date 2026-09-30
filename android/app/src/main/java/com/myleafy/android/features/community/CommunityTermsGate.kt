package com.myleafy.android.features.community

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class CommunityTermsModel(val repository: CommunityRepository) : ViewModel()

/** Check on an explicit write action; browsing does not require accepting terms. */
@Composable
fun rememberCommunityWriteAction(
    model: CommunityTermsModel = viewModel(factory = appViewModelFactory { CommunityTermsModel(it.communityRepository) }),
): (() -> Unit) -> Unit {
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    var busy by remember { mutableStateOf(false) }
    var checked by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var needsAgreement by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun check() {
        busy = true
        error = null
        scope.launch {
            try {
                if (model.repository.hasAcceptedTerms()) {
                    val action = pending
                    pending = null
                    action?.invoke()
                } else needsAgreement = true
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.toCommunityMessage("社区条款加载失败") }
            finally { busy = false }
        }
    }
    if (pending != null) AlertDialog(
        onDismissRequest = { if (!busy) pending = null },
        title = { Text("MyLeafy 社区条款") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (needsAgreement) {
                    Text("使用社区代表你同意遵守以下规则。MyLeafy 对违规内容和滥用用户采取零容忍政策。")
                    Text("不得发布辱骂、骚扰、歧视、威胁、色情低俗、违法、侵权、侵犯隐私或其他令人反感的内容。")
                    Text("不得滥用匿名发布、冒充他人、刷屏、恶意引战或规避审核。")
                    Text("MyLeafy 会过滤违规内容；用户可以举报内容、屏蔽用户，并可删除自己发布的帖子和评论。")
                    Text("开发者会在 24 小时内处理违规举报，必要时移除内容并禁言或移除违规用户。")
                    Text("社区安全联系邮箱：support@myleafy.space。")
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(checked, enabled = !busy, onValueChange = { checked = it })) {
                        Checkbox(checked, onCheckedChange = null)
                        Text("我已阅读并同意社区条款", Modifier.padding(8.dp))
                    }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy && (!needsAgreement || checked), onClick = {
                if (!needsAgreement) check() else {
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            model.repository.acceptTerms()
                            val action = pending
                            pending = null
                            action?.invoke()
                        } catch (cancelled: CancellationException) { throw cancelled }
                        catch (failure: Exception) { error = failure.toCommunityMessage("操作失败") }
                        finally { busy = false }
                    }
                }
            }) { Text(if (busy) "请稍候" else if (needsAgreement) "同意并继续" else "重试") }
        },
        dismissButton = { TextButton(enabled = !busy, onClick = { pending = null }) { Text("关闭") } },
    )
    return { action ->
        if (pending == null) { pending = action; checked = false; needsAgreement = false; check() }
    }
}
