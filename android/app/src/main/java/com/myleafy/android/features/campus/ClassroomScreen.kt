package com.myleafy.android.features.campus

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyButtonDefaults
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyErrorState
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing

@Composable
fun ClassroomScreen(
    onBack: () -> Unit,
    viewModel: ClassroomViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ClassroomViewModel(repository = container.classroomRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var week by rememberSaveable { mutableIntStateOf(viewModel.currentWeek) }
    var day by rememberSaveable { mutableIntStateOf(1) }

    LeafySecondaryScaffold(title = "空闲教室", onBack = onBack, modifier = modifier) { contentModifier ->
        Column(
            modifier = contentModifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.compact),
        ) {
        Text(text = "周次", style = MaterialTheme.typography.labelMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
            items((1..SemesterConfig.supportedWeeks).toList()) { candidate ->
                FilterChip(
                    selected = candidate == week,
                    onClick = { week = candidate },
                    label = { Text("第 $candidate 周") },
                )
            }
        }
        Spacer(modifier = Modifier.height(LeafySpacing.micro))
        Text(text = "星期", style = MaterialTheme.typography.labelMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
            items(listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日").withIndex().toList()) { (index, label) ->
                FilterChip(
                    selected = (index + 1) == day,
                    onClick = { day = index + 1 },
                    label = { Text(label) },
                )
            }
        }
        Spacer(modifier = Modifier.height(LeafySpacing.compact))

        Button(
            onClick = { viewModel.query(week, day, startPeriod = 1, endPeriod = 12) },
            enabled = uiState !is ClassroomUiState.Loading,
            modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
            shape = LeafyButtonDefaults.shape,
        ) {
            if (uiState is ClassroomUiState.Loading) {
                CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.compact), strokeWidth = 2.dp)
            } else {
                Text("查询全天空闲教室")
            }
        }
        Spacer(modifier = Modifier.height(LeafySpacing.compact))

        when (val state = uiState) {
            is ClassroomUiState.Idle -> {
                Text(
                    text = "选择周次与星期后查询",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.outline,
                )
            }

            is ClassroomUiState.Loading -> Unit

            is ClassroomUiState.Error -> {
                LeafyErrorState(
                    title = "查询失败",
                    message = state.message,
                )
            }

            is ClassroomUiState.Loaded -> {
                if (state.rooms.isEmpty()) {
                    LeafyEmptyState(
                        title = "没有空闲教室",
                        message = "学校在所选周次与星期未返回可用教室。",
                    )
                } else {
                    Column {
                        Text(
                            text = "共 ${state.rooms.size} 间",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = LeafySpacing.micro),
                        )
                        state.rooms.groupBy { it.building }.forEach { (building, rooms) ->
                            Text(
                                text = building,
                                style = MaterialTheme.typography.titleSmall,
                                modifier = Modifier.padding(top = LeafySpacing.tiny, bottom = LeafySpacing.tiny),
                            )
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                                items(rooms, key = { it.room }) { room ->
                                    Surface(
                                        modifier = Modifier.padding(bottom = LeafySpacing.micro),
                                        shape = MaterialTheme.shapes.medium,
                                        color = MaterialTheme.colorScheme.surfaceContainerLow,
                                    ) {
                                        Text(
                                            text = room.room,
                                            style = MaterialTheme.typography.bodyMedium,
                                            modifier = Modifier.padding(
                                                horizontal = LeafySpacing.compact,
                                                vertical = LeafySpacing.micro,
                                            ),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
