package com.myleafy.android.features.campus

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.core.data.local.*
import com.myleafy.android.ui.components.*
import kotlinx.coroutines.*
import java.io.File
import java.util.UUID

@Composable internal fun GuestAcademicActions(kind: GuestAcademicKind, grades: List<GradeEntity> = emptyList(), exams: List<ExamEntity> = emptyList()) {
    val context = LocalContext.current
    val container = (context.applicationContext as MyLeafyApplication).container
    val identity by container.activeAppScopeStore.scope.collectAsStateWithLifecycle()
    if (!identity.isGuest) return
    val scope = identity.scopeKey
    val owner = rememberCoroutineScope()
    var error by remember(scope) { mutableStateOf<String?>(null) }
    var busy by remember(scope) { mutableStateOf(false) }
    var showEditor by rememberSaveable(scope) { mutableStateOf(false) }
    var manage by rememberSaveable(scope) { mutableStateOf(false) }
    var editing by rememberSaveable(scope) { mutableStateOf<String?>(null) }
    var pending by remember(scope) { mutableStateOf<List<List<String>>?>(null) }
    var pendingDelete by remember(scope) { mutableStateOf<String?>(null) }
    fun mutate(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        owner.launch { try { check(container.activeAppScopeStore.current.scopeKey == scope && container.activeAppScopeStore.current.isGuest) { "身份已切换" }; block(); error = null }
            catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "操作失败" } finally { busy = false } }
    }
    fun grade(id: String, row: List<String>) = GradeEntity(scope, id, row[0], row[1], row[2], row[3], row[4])
    fun exam(id: Int, row: List<String>) = ExamEntity(scope, id, row[0], row[1], row[2], row[3], row[4], row[5])
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) mutate {
        val rows = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { GuestAcademicCsv.parse(it.readText(), kind) } ?: error("无法读取文件") }
        check(scope == container.activeAppScopeStore.current.scopeKey) { "身份已切换" }; pending = rows
    } }
    Column {
        FlowRow {
            TextButton(enabled = !busy, onClick = { editing = null; showEditor = true }) { Text("新增") }
            TextButton(enabled = !busy, onClick = { manage = true }) { Text("管理") }
            TextButton(enabled = !busy, onClick = { importer.launch(arrayOf("text/*", "application/csv", "application/vnd.ms-excel")) }) { Text("导入 CSV") }
            TextButton(enabled = !busy, onClick = { mutate { val file = withContext(Dispatchers.IO) { File(context.cacheDir, "campus-exports/${kind.name.lowercase()}-template.csv").apply { parentFile?.mkdirs(); writeText(GuestAcademicCsv.template(kind), Charsets.UTF_8) } }; shareCampusFile(context, file, "text/csv") } }) { Text("模板") }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        error?.let { LeafyStatusBanner(it, isError = true, onDismiss = { error = null }) }
    }
    if (manage) LeafyAlertDialog(onDismissRequest = { manage = false }, title = { Text("管理本地${kind.title}") }, text = {
        LazyColumn { if (kind == GuestAcademicKind.GRADE) items(grades, key = { it.id }) { row -> Row {
            TextButton(onClick = { editing = row.id; manage = false; showEditor = true }, Modifier.weight(1f)) { Text("${row.courseName} ${row.term}") }
            TextButton(onClick = { pendingDelete = row.id }) { Text("删除") }
        } } else items(exams, key = { it.id }) { row -> Row {
            TextButton(onClick = { editing = row.id.toString(); manage = false; showEditor = true }, Modifier.weight(1f)) { Text("${row.name} ${row.date}") }
            TextButton(onClick = { pendingDelete = row.id.toString() }) { Text("删除") }
        } } }
    }, confirmButton = { TextButton(onClick = { manage = false }) { Text("完成") } })
    if (showEditor) {
        val initial = if (kind == GuestAcademicKind.GRADE) grades.firstOrNull { it.id == editing }?.let { listOf(it.term, it.courseName, it.credit, it.score, it.type) }
            else exams.firstOrNull { it.id.toString() == editing }?.let { listOf(it.courseId, it.name, it.date, it.start, it.end, it.location) }
        key(scope, editing) { GuestAcademicEditor(kind, initial ?: List(kind.columns.size) { "" }, busy, error, { showEditor = false }) { row -> mutate {
            if (kind == GuestAcademicKind.GRADE) {
                val old = grades.firstOrNull { it.id == editing }
                val updated = old?.copy(term = row[0], courseName = row[1], credit = row[2], score = row[3], type = row[4])
                    ?: grade(UUID.randomUUID().toString(), row)
                container.gradeDao.upsertAll(listOf(updated))
            }
            else container.examDao.upsertAll(listOf(exam(editing?.toInt() ?: ((exams.maxOfOrNull { it.id } ?: 0) + 1), row)))
            showEditor = false
        } } }
    }
    pending?.let { rows -> LeafyAlertDialog(onDismissRequest = { if (!busy) pending = null }, title = { Text("替换本地${kind.title}？") }, text = { Text("已校验 ${rows.size} 条记录。确认后替换当前访客的${kind.title}，此操作无法撤销。") }, confirmButton = { TextButton(enabled = !busy, onClick = { mutate {
        if (kind == GuestAcademicKind.GRADE) container.gradeDao.replaceAll(scope, rows.map { grade(UUID.randomUUID().toString(), it) })
        else container.examDao.replaceAll(scope, rows.mapIndexed { index, row -> exam(index + 1, row) })
        pending = null
    } }) { Text("确认替换") } }, dismissButton = { TextButton(enabled = !busy, onClick = { pending = null }) { Text("取消") } }) }
    pendingDelete?.let { id -> LeafyAlertDialog(onDismissRequest = { pendingDelete = null }, title = { Text("删除这条记录？") }, confirmButton = { TextButton(enabled = !busy, onClick = { mutate {
        if (kind == GuestAcademicKind.GRADE) container.gradeDao.delete(scope, id) else container.examDao.delete(scope, id.toInt()); pendingDelete = null
    } }) { Text("删除") } }, dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("取消") } }) }
}

@Composable private fun GuestAcademicEditor(kind: GuestAcademicKind, initial: List<String>, saving: Boolean, error: String?, onDismiss: () -> Unit, onSave: (List<String>) -> Unit) {
    var fields by rememberSaveable { mutableStateOf(initial) }
    val exit = rememberEditorExit(fields != initial, saving, onDismiss)
    val normalized = fields.map(String::trim)
    val validation = runCatching { GuestAcademicCsv.validate(kind, normalized) }
    val valid = validation.isSuccess
    LeafyAlertDialog(onDismissRequest = exit, title = { Text("录入本地${kind.title}") }, text = {
        LazyColumn { error?.let { item { LeafyStatusBanner(it, isError = true) } }; items(kind.columns.size) { index -> LeafyTextField(fields[index], { value -> fields = fields.mapIndexed { i, old -> if (i == index) value else old } }, label = { Text(kind.labels[index]) }, singleLine = true) }; validation.exceptionOrNull()?.message?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } } }
    }, confirmButton = { TextButton(enabled = valid && !saving, onClick = { onSave(normalized) }) { Text(if (saving) "保存中" else "保存") } }, dismissButton = { TextButton(onClick = exit) { Text("取消") } })
}
