package com.myleafy.android.features.campus

import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.data.local.ComprehensiveEvidenceEntity
import com.myleafy.android.ui.components.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.flatMapLatest
import java.io.File
import java.util.UUID

@OptIn(ExperimentalCoroutinesApi::class)
@Composable internal fun ComprehensiveEvidencePanel(college: String, cohort: String, component: String) {
    val context = LocalContext.current
    val container = (context.applicationContext as MyLeafyApplication).container
    val records by remember(college, cohort) { container.activeAppScopeStore.scope.flatMapLatest { container.campusPersonalDao.evidence(it.scopeKey, college, cohort) } }.collectAsStateWithLifecycle(emptyList())
    val owner = rememberCoroutineScope()
    var importing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf<ComprehensiveEvidenceEntity?>(null) }
    var deleting by remember { mutableStateOf<ComprehensiveEvidenceEntity?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) {
            val scope = container.activeAppScopeStore.current.scopeKey
            importing = true
            owner.launch {
                val failures = mutableListOf<String>()
                try { withContext(Dispatchers.IO) { uris.forEach { uri ->
                    var target: File? = null
                    try {
                        val mime = context.contentResolver.getType(uri) ?: error("无法确认文件类型")
                        require(mime == "application/pdf" || mime.startsWith("image/")) { "只支持 PDF 和图片" }
                        val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "材料"
                        val id = UUID.randomUUID().toString()
                        val suffix = if (mime == "application/pdf") "pdf" else name.substringAfterLast('.', "img").filter(Char::isLetterOrDigit).ifEmpty { "img" }
                        target = File(context.filesDir, "comprehensive-evidence/$scope/$id.$suffix").apply { parentFile?.mkdirs() }
                        context.contentResolver.openInputStream(uri)?.use { input -> target.outputStream().use { input.copyTo(it) } } ?: error("无法读取 $name")
                        check(scope == container.activeAppScopeStore.current.scopeKey) { "账号已切换" }
                        container.campusPersonalDao.save(ComprehensiveEvidenceEntity(scope, id, college, cohort, component, name, target.absolutePath, mime, System.currentTimeMillis()))
                    } catch (cancelled: CancellationException) { target?.delete(); throw cancelled }
                    catch (failure: Exception) { target?.delete(); failures += failure.message ?: "材料导入失败" }
                } } }
                finally { importing = false; error = failures.takeIf { it.isNotEmpty() }?.joinToString("；") }
            }
        }
    }
    TextButton(enabled = !importing, onClick = { picker.launch(arrayOf("application/pdf", "image/*")) }) { Text(if (importing) "导入中…" else "导入此项 PDF／图片材料") }
    records.filter { it.component == component }.forEach { record -> Row {
        TextButton(onClick = { preview = record }, modifier = Modifier.weight(1f)) { Text(record.originalFilename) }
        TextButton(onClick = { deleting = record }) { Text("删除") }
    } }
    error?.let { LeafyStatusBanner(it, isError = true, onDismiss = { error = null }) }
    preview?.let { CampusFilePreview(File(it.localFilename), it.contentType) { preview = null } }
    deleting?.let { record -> LeafyAlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除材料？") }, confirmButton = { TextButton(onClick = { owner.launch {
        try { withContext(Dispatchers.IO) {
            check(record.scopeKey == container.activeAppScopeStore.current.scopeKey) { "账号已切换" }
            val file = File(record.localFilename); check(!file.exists() || file.delete()) { "文件删除失败" }; container.campusPersonalDao.delete(record)
        }; deleting = null } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "删除失败" }
    } }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
}
