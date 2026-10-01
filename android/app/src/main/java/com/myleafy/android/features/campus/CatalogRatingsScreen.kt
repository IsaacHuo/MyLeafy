package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.services.cloudflare.RatingCatalogKind
import com.myleafy.android.ui.components.*

@Composable fun CatalogRatingsScreen(onBack: () -> Unit, embedded: Boolean = false, initialSearch: String = "", modifier: Modifier = Modifier,
    available: Boolean, viewModel: CatalogRatingsViewModel = viewModel(factory = appViewModelFactory { CatalogRatingsViewModel(it.catalogRatingRepository) })) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var suggesting by rememberSaveable(state.scopeKey) { mutableStateOf(false) }
    var selected by remember(state.kind, state.scopeKey) { mutableStateOf<CatalogRatingItem?>(null) }
    var choosing by rememberSaveable(state.scopeKey) { mutableStateOf(false) }
    LaunchedEffect(available, initialSearch, state.scopeKey) { if (available) viewModel.initialize(initialSearch) }
    LeafySecondaryScaffold("评价相关", onBack = onBack, embedded = embedded, modifier = modifier,
        actions = { if (available) TextButton(onClick = { suggesting = true }) { Text("建议新增") } }) { content ->
        if (!available) LeafyEmptyState("评价服务暂不可用", "登录并完善社区资料后，可查看和参与评价。", modifier = content)
        else Column(content.padding(horizontal = 20.dp)) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) { RatingCatalogKind.entries.forEachIndexed { index, kind ->
                SegmentedButton(state.kind == kind, { viewModel.selectKind(kind) }, shape = SegmentedButtonDefaults.itemShape(index, 3), modifier = Modifier.weight(1f)) { Text(kind.title()) }
            } }
            LeafyTextField(state.search, viewModel::search, label = { Text("搜索${state.kind.title()}") }, singleLine = true, modifier = Modifier.fillMaxWidth(), trailingIcon = { TextButton(onClick = viewModel::refresh) { Text("搜索") } })
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { item { FilterChip(state.stars == null, { viewModel.setStars(null) }, { Text("全部星级") }) }; items(5) { index -> val star = index + 1; FilterChip(state.stars == star, { viewModel.setStars(star) }, { Text("$star 星") }) } }
            if (state.kind == RatingCatalogKind.DISH) LazyRow { items(listOf("全部食堂", "东区食堂", "西区食堂")) { canteen -> FilterChip((state.canteen ?: "全部食堂") == canteen, { viewModel.setCanteen(canteen.takeIf { it != "全部食堂" }) }, { Text(canteen) }) } }
            Row { TextButton(onClick = { choosing = true }) { Text(state.filterValue ?: state.kind.filterLabel()) }; TextButton(onClick = viewModel::clearFilters) { Text("清除筛选") }; TextButton(onClick = viewModel::refresh, enabled = !state.loading) { Text("刷新") } }
            state.error?.let { LeafyStatusBanner(it, isError = true) }
            val visible = state.items.filter { state.stars == null || it.profile.rating_count > 0 && kotlin.math.floor(it.profile.rating_average + 0.5).toInt().coerceIn(1, 5) == state.stars }
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp), contentPadding = PaddingValues(vertical = 12.dp)) {
                if (visible.isEmpty() && !state.loading) item { Text(if (state.hasMore) "已加载内容中没有匹配结果，可继续加载" else "没有找到结果，可调整筛选或建议新增") }
                items(visible, key = { it.profile.id }) { item -> Surface(onClick = { selected = item }, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surfaceContainerLow) {
                    Column(Modifier.padding(16.dp)) {
                        Text(item.profile.name, style = MaterialTheme.typography.titleMedium)
                        Text(listOfNotNull(item.profile.unit, item.profile.category, item.profile.location, item.profile.credit?.let { "$it 学分" }).joinToString(" · "), style = MaterialTheme.typography.bodySmall)
                        Text(if (item.profile.rating_count == 0) "暂无评分" else "%.1f 分 · %d 人评分".format(item.profile.rating_average, item.profile.rating_count))
                        item.myStars?.let { Text("我的评分 $it 星", color = MaterialTheme.colorScheme.primary) }
                    }
                } }
                if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                else if (state.hasMore) item { LeafyPrimaryButton(onClick = viewModel::loadMore, modifier = Modifier.fillMaxWidth()) { Text("加载更多") } }
            }
        }
    }
    if (choosing) {
        val options = when (state.kind) {
            RatingCatalogKind.TEACHER -> (state.options + ComprehensiveQualityRuleCatalog.participatingCollegeNames).distinct().sorted()
            RatingCatalogKind.COURSE -> state.options
            RatingCatalogKind.DISH -> (diningLocations + state.options).distinct().filter { state.canteen == null || it.startsWith(state.canteen!!) }
        }
        LeafyAlertDialog(onDismissRequest = { choosing = false }, title = { Text(state.kind.filterLabel()) }, text = {
            LazyColumn { item { TextButton(onClick = { viewModel.setFilter(null); choosing = false }) { Text("全部") } }; items(options) { value -> TextButton(onClick = { viewModel.setFilter(value); choosing = false }) { Text(value) } } }
        }, confirmButton = { TextButton(onClick = { choosing = false }) { Text("取消") } })
    }
    selected?.let { original ->
        val current = state.items.firstOrNull { it.profile.id == original.profile.id } ?: original
        RatingDetail(current, state.saving, state.error, { selected = null }, viewModel::rate)
    }
    if (suggesting) key(state.kind, state.scopeKey) { CatalogSuggestionDialog(state.kind, state.saving, state.error, { suggesting = false }) { name, unit, teacher, category, credit, stars, note ->
        viewModel.suggest(name, unit, teacher, category, credit, stars, note) { suggesting = false }
    } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun RatingDetail(item: CatalogRatingItem, saving: Boolean, error: String?, onDismiss: () -> Unit, onRate: (Long, Int) -> Unit) {
    var stars by rememberSaveable(item.profile.id, item.myStars) { mutableIntStateOf(item.myStars ?: 0) }
    val profile = item.profile
    LeafyModalBottomSheet(onDismissRequest = onDismiss) {
        LazyColumn(Modifier.fillMaxWidth(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Text(profile.name, style = MaterialTheme.typography.titleLarge); Text("%.1f 分 · %d 人评分".format(profile.rating_average, profile.rating_count)); Text(listOfNotNull(profile.unit, profile.category, profile.location, profile.credit?.let { "$it 学分" }).joinToString(" · ")) }
            if (item.localTeachers.isNotEmpty()) item { Text("本机课表教师：${item.localTeachers.joinToString("、")}", style = MaterialTheme.typography.bodySmall) }
            items((5 downTo 1).toList()) { star ->
                val count = when (star) { 5 -> profile.rating_5_count; 4 -> profile.rating_4_count; 3 -> profile.rating_3_count; 2 -> profile.rating_2_count; else -> profile.rating_1_count }
                Text("$star 星 · $count 人"); LinearProgressIndicator(progress = { if (profile.rating_count == 0) 0f else count.toFloat() / profile.rating_count }, modifier = Modifier.fillMaxWidth())
            }
            item { Text("我的评分：${item.myStars?.let { "$it 星" } ?: "未评分"}"); FlowRow { (1..5).forEach { value -> FilterChip(stars == value, { stars = value }, { Text("$value 星") }, enabled = !saving) } }
                LeafyPrimaryButton(enabled = stars in 1..5 && !saving, onClick = { onRate(profile.id, stars) }, modifier = Modifier.fillMaxWidth()) { Text(if (saving) "提交中…" else if (item.myStars == null) "提交评分" else "更新评分") }
                error?.let { LeafyStatusBanner(it, isError = true) }
            }
        }
    }
}

@Composable private fun CatalogSuggestionDialog(kind: RatingCatalogKind, saving: Boolean, error: String?, onDismiss: () -> Unit,
    onSubmit: (String, String, String?, String?, Double?, Int?, String?) -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }; var unit by rememberSaveable { mutableStateOf("") }
    var teacher by rememberSaveable { mutableStateOf("") }; var category by rememberSaveable { mutableStateOf("") }
    var credit by rememberSaveable { mutableStateOf("") }; var stars by rememberSaveable { mutableIntStateOf(0) }; var note by rememberSaveable { mutableStateOf("") }
    var canteen by rememberSaveable { mutableStateOf("东区食堂") }
    val valid = name.isNotBlank() && unit.isNotBlank() && (kind != RatingCatalogKind.COURSE || teacher.isNotBlank()) && (credit.isBlank() || credit.toDoubleOrNull()?.let { it.isFinite() && it in 0.0..999.9 } == true)
    val exit = rememberEditorExit(name.isNotBlank() || unit.isNotBlank() || teacher.isNotBlank() || category.isNotBlank() || credit.isNotBlank() || stars != 0 || note.isNotBlank(), saving, onDismiss)
    LeafyAlertDialog(onDismissRequest = exit, title = { Text("建议新增${kind.title()}") }, text = {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            error?.let { item { LeafyStatusBanner(it, isError = true) } }
            item { LeafyTextField(name, { name = it }, label = { Text("名称") }, singleLine = true) }
            if (kind == RatingCatalogKind.DISH) {
                item { FlowRow { listOf("东区食堂", "西区食堂").forEach { value -> FilterChip(canteen == value, { canteen = value; unit = "" }, { Text(value) }) } } }
                item { FlowRow { diningLocations.filter { it.startsWith(canteen) }.forEach { value -> FilterChip(unit == value, { unit = value }, { Text(value.substringAfter(" · ")) }) } } }
            } else item { LeafyTextField(unit, { unit = it }, label = { Text("学院 / 单位") }, singleLine = true) }
            if (kind == RatingCatalogKind.COURSE) {
                item { LeafyTextField(teacher, { teacher = it }, label = { Text("授课教师（必填）") }) }
                item { LeafyTextField(category, { category = it }, label = { Text("课程分类") }) }
                item { LeafyTextField(credit, { credit = it }, label = { Text("学分（可选）") }) }
            }
            item { Text("初始评分（可选）"); FlowRow { FilterChip(stars == 0, { stars = 0 }, { Text("不评分") }); (1..5).forEach { value -> FilterChip(stars == value, { stars = value }, { Text("$value 星") }) } } }
            item { LeafyTextField(note, { note = it }, label = { Text("补充说明") }) }
        }
    }, confirmButton = { TextButton(enabled = valid && !saving, onClick = { onSubmit(name, unit, teacher.takeIf(String::isNotBlank), category.takeIf(String::isNotBlank), credit.toDoubleOrNull(), stars.takeIf { it > 0 }, note.takeIf(String::isNotBlank)) }) { Text(if (saving) "提交中…" else "提交建议") } }, dismissButton = { TextButton(onClick = exit, enabled = !saving) { Text("取消") } })
}

private fun RatingCatalogKind.title() = when (this) { RatingCatalogKind.TEACHER -> "评教"; RatingCatalogKind.COURSE -> "评课"; RatingCatalogKind.DISH -> "评菜" }
private fun RatingCatalogKind.filterLabel() = when (this) { RatingCatalogKind.TEACHER -> "学院 / 单位"; RatingCatalogKind.COURSE -> "课程分类"; RatingCatalogKind.DISH -> "食堂 / 位置" }
