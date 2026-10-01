package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.data.local.*
import com.myleafy.android.ui.components.*
import java.time.LocalDate
import java.io.File

@Composable internal fun MedicalPolicyContent(modifier: Modifier) {
    val context = LocalContext.current
    val policy = remember { MedicalPolicy.load(context) }
    LazyColumn(modifier, contentPadding = PaddingValues(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            LeafySectionHeader(policy.sourceTitle, supportingText = "政策资料 ${policy.policyUpdatedAt} · 医院资料 ${policy.hospitalInfoUpdatedAt}")
            Text("本页为有出处的本地资料快照，实际办理以学校最新通知及审核为准。", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { openExternalUrl(context, policy.sourceURL) }) { Text("查看政策出处") }
            TextButton(onClick = { openExternalUrl(context, policy.sourceImageURL) }) { Text("查看原始政策图") }
        }
        item { LeafySectionHeader("就医前先看") }
        items(policy.reimbursementRates, key = { it.id }) { rate ->
            LeafyContentSurface(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
                Text("${rate.target} · ${rate.rate}%", style = MaterialTheme.typography.titleMedium)
                Text("${rate.category} · ${rate.note}")
            } }
        }
        item { Text("常见病先到校医院；合同医院及其他医院按对应转诊规则办理；急危重症按急诊路径就医。详细步骤见报销指引。") }
        item {
            LeafySectionHeader("报销前准备")
            Text(policy.hospitalName, style = MaterialTheme.typography.titleMedium)
            Text(policy.hospitalAddress)
            Text("电话：${policy.hospitalPhones}")
            Text("门诊：${policy.outpatientHours}")
            Text("报销：${policy.reimbursementHours}")
            TextButton(onClick = { openExternalUrl(context, policy.hospitalInfoURL) }) { Text("查看医院公开信息") }
            Text("按就医场景准备有效票据、费用明细、处方、病历及转诊或证明材料。")
        }
        item { LeafySectionHeader("用药规则") }
        items(policy.medicationRules) { Text("• $it") }
        item { LeafySectionHeader("不予报销项目") }
        items(policy.excludedExpenses) { Text("• $it") }
        item { LeafySectionHeader("物理与康复治疗") }
        items(policy.rehabRules) { Text("• $it") }
    }
}

@Composable internal fun MedicalGuideContent(modifier: Modifier) {
    val context = LocalContext.current
    val policy = remember { MedicalPolicy.load(context) }
    var scenario by rememberSaveable { mutableStateOf(policy.scenarioAdvices.first().id) }
    var amount by rememberSaveable { mutableStateOf("") }
    val advice = policy.scenarioAdvices.first { it.id == scenario }
    LazyColumn(modifier, contentPadding = PaddingValues(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { policy.scenarioAdvices.forEach { FilterChip(scenario == it.id, { scenario = it.id }, { Text(it.id) }) } } }
        item {
            LeafySectionHeader(advice.title, supportingText = advice.rateText)
            LeafyTextField(amount, { amount = it }, label = { Text("费用金额（可选）") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            val value = amount.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
            advice.rate?.let { rate -> if (value != null) Text("参考估算 ¥%.2f；实际按审核结算".format(value * rate)) }
        }
        item { LeafySectionHeader("办理步骤") }
        itemsIndexed(advice.steps) { index, step -> Text("${index + 1}. $step") }
        item { LeafySectionHeader("材料清单") }
        items(advice.materials) { Text("• $it") }
        item { LeafySectionHeader("注意事项") }
        items(advice.notes) { Text(it) }
        item { Text("资料版本 ${policy.policyUpdatedAt}", style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable internal fun MedicalLedgerContent(entries: List<MedicalLedgerEntryEntity>, photos: List<MedicalLedgerPhotoEntity>,
    onDelete: (MedicalLedgerEntryEntity) -> Unit, onEdit: (MedicalLedgerEntryEntity) -> Unit,
    onDeletePhoto: (MedicalLedgerPhotoEntity) -> Unit, onAddPhoto: (String) -> Unit, modifier: Modifier) {
    var filter by rememberSaveable { mutableStateOf("全部") }
    var deleting by remember { mutableStateOf<MedicalLedgerEntryEntity?>(null) }
    var preview by remember { mutableStateOf<File?>(null) }
    var deletingPhoto by remember { mutableStateOf<MedicalLedgerPhotoEntity?>(null) }
    val active = entries.filterNot { it.status in listOf("已报销", "已归档") }
    val attention = active.filter { (it.reimbursementDeadline?.minus(LocalDate.now().toEpochDay()) ?: Long.MAX_VALUE) <= 14 || it.status == "被退回" }
    val visible = when (filter) { "处理中" -> active; "需关注" -> attention; "已结案" -> entries - active.toSet(); else -> entries }
    LazyColumn(modifier, contentPadding = PaddingValues(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("共 ${entries.size} 项 · 处理中 ${active.size} 项 · 需关注 ${attention.size} 项")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf("全部", "处理中", "需关注", "已结案").forEach { FilterChip(filter == it, { filter = it }, { Text(it) }) } }
        }
        if (visible.isEmpty()) item { Text("当前筛选没有台账记录") }
        items(visible, key = { it.id }) { entry ->
            LeafyContentSurface(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(entry.hospitalName, style = MaterialTheme.typography.titleMedium)
                Text("${LocalDate.ofEpochDay(entry.visitDate)} · ${entry.scenario}")
                Text("${entry.status} · ${medicalDeadline(entry)}", color = MaterialTheme.colorScheme.primary)
                Text("费用 ¥${entry.totalExpense} · 预估 ${entry.estimatedReimbursement?.let { "¥$it" } ?: "未确认"} · 实际 ${entry.actualReimbursement?.let { "¥$it" } ?: "未填写"}")
                if (entry.department.isNotBlank() || entry.diagnosisNote.isNotBlank()) Text("${entry.department} ${entry.diagnosisNote}")
                if (entry.materialChecklist.isNotBlank()) Text("材料：${entry.materialChecklist.replace('|', '、')}")
                if (entry.note.isNotBlank()) Text(entry.note)
                Row { TextButton(onClick = { onEdit(entry) }) { Text("编辑") }; TextButton(onClick = { onAddPhoto(entry.id) }) { Text("加照片") }; TextButton(onClick = { deleting = entry }) { Text("删除") } }
                LazyRow { items(photos.filter { it.entryId == entry.id }, key = { it.id }) { photo -> Column {
                    coil.compose.AsyncImage(model = File(photo.localFilename), contentDescription = photo.originalFilename, modifier = Modifier.size(96.dp).clickable { preview = File(photo.localFilename) })
                    TextButton(onClick = { preview = File(photo.localFilename) }) { Text(photo.originalFilename) }
                    TextButton(onClick = { deletingPhoto = photo }) { Text("移除照片") }
                } } }
            } }
        }
    }
    deletingPhoto?.let { photo -> LeafyAlertDialog(onDismissRequest = { deletingPhoto = null }, title = { Text("移除这张照片？") },
        confirmButton = { TextButton(onClick = { onDeletePhoto(photo); deletingPhoto = null }) { Text("移除") } }, dismissButton = { TextButton(onClick = { deletingPhoto = null }) { Text("取消") } }) }
    preview?.let { CampusFilePreview(it, "image/jpeg") { preview = null } }
    deleting?.let { entry -> LeafyAlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除台账及照片？") },
        confirmButton = { TextButton(onClick = { onDelete(entry); deleting = null }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
}

@Composable internal fun MedicalEditorDialog(initial: MedicalLedgerEntryEntity?, saving: Boolean, error: String?, onDismiss: () -> Unit, onSave: (MedicalLedgerDraft) -> Unit) {
    val context = LocalContext.current
    val policy = remember { MedicalPolicy.load(context) }
    var date by rememberSaveable { mutableStateOf(initial?.visitDate?.let { LocalDate.ofEpochDay(it).toString() } ?: LocalDate.now().toString()) }
    var hospital by rememberSaveable { mutableStateOf(initial?.hospitalName.orEmpty()) }
    var department by rememberSaveable { mutableStateOf(initial?.department.orEmpty()) }
    var diagnosis by rememberSaveable { mutableStateOf(initial?.diagnosisNote.orEmpty()) }
    var expense by rememberSaveable { mutableStateOf(initial?.totalExpense?.toString().orEmpty()) }
    var estimated by rememberSaveable { mutableStateOf(initial?.estimatedReimbursement?.toString().orEmpty()) }
    var actual by rememberSaveable { mutableStateOf(initial?.actualReimbursement?.toString().orEmpty()) }
    var deadline by rememberSaveable { mutableStateOf(initial?.reimbursementDeadline?.let { LocalDate.ofEpochDay(it).toString() }.orEmpty()) }
    var scenario by rememberSaveable { mutableStateOf(initial?.scenario ?: policy.scenarioAdvices.first().id) }
    var status by rememberSaveable { mutableStateOf(initial?.status ?: "待整理") }
    var materials by rememberSaveable { mutableStateOf(initial?.materialChecklist.orEmpty()) }
    var note by rememberSaveable { mutableStateOf(initial?.note.orEmpty()) }
    val suggested = policy.scenarioAdvices.firstOrNull { it.id == scenario }
    fun moneyValid(value: String) = value.isBlank() || value.toDoubleOrNull()?.let { it.isFinite() && it >= 0 } == true
    val valid = runCatching { LocalDate.parse(date); if (deadline.isNotBlank()) LocalDate.parse(deadline) }.isSuccess && hospital.isNotBlank() && expense.isNotBlank() && moneyValid(expense) && moneyValid(estimated) && moneyValid(actual)
    val initialDate = remember { initial?.visitDate?.let { LocalDate.ofEpochDay(it).toString() } ?: LocalDate.now().toString() }
    val dirty = date != initialDate || hospital != initial?.hospitalName.orEmpty() || department != initial?.department.orEmpty() || diagnosis != initial?.diagnosisNote.orEmpty() || expense != initial?.totalExpense?.toString().orEmpty() || estimated != initial?.estimatedReimbursement?.toString().orEmpty() || actual != initial?.actualReimbursement?.toString().orEmpty() || deadline != initial?.reimbursementDeadline?.let { LocalDate.ofEpochDay(it).toString() }.orEmpty() || scenario != (initial?.scenario ?: policy.scenarioAdvices.first().id) || status != (initial?.status ?: "待整理") || materials != initial?.materialChecklist.orEmpty() || note != initial?.note.orEmpty()
    val requestExit = rememberEditorExit(dirty, saving, onDismiss)
    LeafyAlertDialog(onDismissRequest = requestExit, title = { Text(if (initial == null) "新增医疗台账" else "编辑医疗台账") }, text = {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            error?.let { item { LeafyStatusBanner(it, isError = true) } }
            listOf(Triple(date, { v: String -> date = v }, "就诊日期 YYYY-MM-DD"), Triple(hospital, { v: String -> hospital = v }, "医院"), Triple(department, { v: String -> department = v }, "科室"), Triple(diagnosis, { v: String -> diagnosis = v }, "诊断摘要"), Triple(expense, { v: String -> expense = v }, "总费用"), Triple(estimated, { v: String -> estimated = v }, "预计报销（可选）"), Triple(actual, { v: String -> actual = v }, "实际报销（可选）"), Triple(deadline, { v: String -> deadline = v }, "截止日期 YYYY-MM-DD（可选）")).forEach { (value, change, label) -> item { LeafyTextField(value, change, label = { Text(label) }, singleLine = true) } }
            item { FlowRow { policy.scenarioAdvices.forEach { FilterChip(scenario == it.id, { scenario = it.id }, { Text(it.id) }) } } }
            item { Text("参考估算：${expense.toDoubleOrNull()?.let { value -> suggested?.rate?.let { "¥%.2f".format(value * it) } } ?: "需审核"}") }
            item { FlowRow { policy.statuses.forEach { FilterChip(status == it, { status = it }, { Text(it) }) } } }
            item { TextButton(onClick = { materials = suggested?.materials?.joinToString("|").orEmpty() }) { Text("使用场景建议材料") } }
            item { Column { policy.materials.forEach { material -> Row { Checkbox(material in materials.split('|'), { checked -> materials = (if (checked) materials.split('|').filter(String::isNotBlank) + material else materials.split('|') - material).distinct().joinToString("|") }); Text(material, Modifier.padding(top = 12.dp)) } } } }
            item { LeafyTextField(materials, { materials = it }, label = { Text("材料清单（保留已有自定义内容）") }) }
            item { LeafyTextField(note, { note = it }, label = { Text("备注") }) }
        }
    }, confirmButton = { TextButton(enabled = valid && !saving, onClick = { onSave(MedicalLedgerDraft(initial?.id, LocalDate.parse(date), hospital, department, diagnosis, scenario, expense.toDouble(), estimated.toDoubleOrNull() ?: expense.toDoubleOrNull()?.let { value -> suggested?.rate?.let { kotlin.math.round(value * it * 100) / 100 } }, actual.toDoubleOrNull(), status, deadline.takeIf(String::isNotBlank)?.let(LocalDate::parse), materials, note)) }) { Text(if (saving) "保存中" else "保存") } }, dismissButton = { TextButton(onClick = requestExit) { Text("取消") } })
}
