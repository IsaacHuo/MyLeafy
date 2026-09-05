package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.services.supabase.RatingCatalogKind
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces

@Composable
fun CatalogRatingsScreen(
    onBack: () -> Unit,
    available: Boolean,
    viewModel: CatalogRatingsViewModel = viewModel(
        factory = appViewModelFactory { CatalogRatingsViewModel(it.catalogRatingRepository) },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var suggestionVisible by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(available) { if (available) viewModel.refresh() }
    LeafySecondaryScaffold(
        title = "评价相关",
        onBack = onBack,
        actions = {
            if (available) LeafyActionIconButton(onClick = { suggestionVisible = true }) {
                Icon(Icons.Filled.Add, contentDescription = "建议新增评价对象")
            }
        },
    ) { contentModifier ->
        if (!available) {
            Box(modifier = contentModifier, contentAlignment = Alignment.Center) {
                LeafyEmptyState(
                    title = "评价服务暂不可用",
                    message = "需要已登录、已完善资料的社区身份，且后端 catalog_ratings capability 可用。",
                    icon = Icons.Outlined.StarBorder,
                )
            }
        } else {
            Column(modifier = contentModifier.padding(horizontal = LeafySpacing.page)) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    RatingCatalogKind.entries.forEachIndexed { index, kind ->
                        SegmentedButton(
                            selected = state.kind == kind,
                            onClick = { viewModel.selectKind(kind) },
                            shape = SegmentedButtonDefaults.itemShape(index, RatingCatalogKind.entries.size),
                            modifier = Modifier.weight(1f),
                            label = { Text(kind.title()) },
                        )
                    }
                }
                OutlinedTextField(
                    value = state.search,
                    onValueChange = viewModel::search,
                    label = { Text("搜索${state.kind.title()}") },
                    leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                    trailingIcon = { LeafyTextButton(onClick = viewModel::refresh) { Text("搜索") } },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.filterValue.orEmpty(),
                    onValueChange = { viewModel.setFilter(it.takeIf(String::isNotBlank)) },
                    label = { Text(state.kind.filterLabel()) },
                    supportingText = { Text("留空显示全部") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                if (state.error != null) LeafyStatusBanner(state.error.orEmpty(), isError = true)
                CatalogList(state, viewModel::rate, viewModel::loadMore, Modifier.weight(1f))
            }
        }
    }
    if (suggestionVisible) {
        CatalogSuggestionDialog(
            kind = state.kind,
            onDismiss = { suggestionVisible = false },
            onSubmit = { name, unit, teacher, category, credit, stars, note ->
                viewModel.suggest(name, unit, teacher, category, credit, stars, note)
                suggestionVisible = false
            },
        )
    }
}

@Composable
private fun CatalogList(
    state: CatalogRatingsUiState,
    onRate: (Long, Int) -> Unit,
    onLoadMore: () -> Unit,
    modifier: Modifier,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(vertical = LeafySpacing.compact),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        if (state.items.isEmpty() && !state.loading) {
            item { LeafyEmptyState("没有找到结果", "可调整搜索和筛选，或从右上角建议新增。") }
        }
        items(state.items, key = { it.profile.id }) { item -> RatingItemRow(item, onRate) }
        if (state.loading) {
            item { Box(Modifier.fillMaxWidth().padding(LeafySpacing.page), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        } else if (state.hasMore) {
            item { LeafyPrimaryButton(onClick = onLoadMore, modifier = Modifier.fillMaxWidth()) { Text("加载更多") } }
        }
    }
}

@Composable
private fun RatingItemRow(item: CatalogRatingItem, onRate: (Long, Int) -> Unit) {
    val profile = item.profile
    Surface(color = MaterialTheme.leafySurfaces.content, shape = MaterialTheme.shapes.large) {
        Column(modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card), verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny)) {
            Text(profile.name, style = MaterialTheme.typography.titleMedium)
            Text(
                listOfNotNull(profile.unit, profile.category, profile.location, profile.credit?.let { "$it 学分" }).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("%.1f 分 · %d 人 · 5/4/3/2/1 星：%d/%d/%d/%d/%d".format(
                profile.rating_average,
                profile.rating_count,
                profile.rating_5_count,
                profile.rating_4_count,
                profile.rating_3_count,
                profile.rating_2_count,
                profile.rating_1_count,
            ), style = MaterialTheme.typography.bodySmall)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("我的评分：", style = MaterialTheme.typography.bodySmall)
                (1..5).forEach { star ->
                    LeafyActionIconButton(onClick = { onRate(profile.id, star) }) {
                        Icon(
                            if ((item.myStars ?: 0) >= star) Icons.Filled.Star else Icons.Outlined.StarBorder,
                            contentDescription = "$star 星",
                            tint = if ((item.myStars ?: 0) >= star) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CatalogSuggestionDialog(
    kind: RatingCatalogKind,
    onDismiss: () -> Unit,
    onSubmit: (String, String, String?, String?, Double?, Int, String?) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var unit by remember { mutableStateOf("") }
    var teacher by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }
    var credit by remember { mutableStateOf("") }
    var stars by remember { mutableStateOf(5) }
    var note by remember { mutableStateOf("") }
    val valid = name.isNotBlank() && unit.isNotBlank() && (kind != RatingCatalogKind.COURSE || teacher.isNotBlank())
    LeafyAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("建议新增${kind.title()}") },
        text = {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact)) {
                item { RatingField(name, { name = it }, "名称") }
                item { RatingField(unit, { unit = it }, kind.filterLabel()) }
                if (kind == RatingCatalogKind.COURSE) {
                    item { RatingField(teacher, { teacher = it }, "授课教师") }
                    item { RatingField(category, { category = it }, "课程分类") }
                    item { RatingField(credit, { credit = it }, "学分") }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("初始评分")
                        (1..5).forEach { star ->
                            LeafyActionIconButton(onClick = { stars = star }) {
                                Icon(if (stars >= star) Icons.Filled.Star else Icons.Outlined.StarBorder, "$star 星")
                            }
                        }
                    }
                }
                item { RatingField(note, { note = it }, "补充说明") }
            }
        },
        confirmButton = {
            LeafyTextButton(enabled = valid, onClick = {
                onSubmit(name, unit, teacher.takeIf(String::isNotBlank), category.takeIf(String::isNotBlank), credit.toDoubleOrNull(), stars, note.takeIf(String::isNotBlank))
            }) { Text("提交") }
        },
        dismissButton = { LeafyTextButton(onClick = onDismiss) { Text("取消") } },
    )
}

@Composable
private fun RatingField(value: String, onValueChange: (String) -> Unit, label: String) {
    OutlinedTextField(value, onValueChange, label = { Text(label) }, singleLine = true, modifier = Modifier.fillMaxWidth())
}

private fun RatingCatalogKind.title() = when (this) {
    RatingCatalogKind.TEACHER -> "评教"
    RatingCatalogKind.COURSE -> "评课"
    RatingCatalogKind.DISH -> "评菜"
}

private fun RatingCatalogKind.filterLabel() = when (this) {
    RatingCatalogKind.TEACHER -> "学院 / 单位"
    RatingCatalogKind.COURSE -> "课程分类"
    RatingCatalogKind.DISH -> "食堂 / 位置"
}
