package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.campus.AcademicRefreshResult
import com.myleafy.android.features.campus.AcademicRepository
import com.myleafy.android.features.schedule.ScheduleRepository
import com.myleafy.android.features.timetable.TimetableRepository
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class CacheSummary(
    val courses: Int = 0,
    val grades: Int = 0,
    val exams: Int = 0,
    val memos: Int = 0,
    val schedules: Int = 0,
)

enum class SyncKind { TIMETABLE, GRADES, EXAMS }
sealed interface SyncItemState {
    data object Idle : SyncItemState
    data object Running : SyncItemState
    data class Success(val message: String) : SyncItemState
    data class Error(val message: String) : SyncItemState
}

class ProfileSyncViewModel(
    private val timetableRepository: TimetableRepository,
    private val academicRepository: AcademicRepository,
    scheduleRepository: ScheduleRepository,
    private val semesterId: String,
) : ViewModel() {
    private val academicCounts = combine(
        timetableRepository.coursesForSemester(semesterId),
        academicRepository.grades(),
        academicRepository.exams(),
    ) { courses, grades, exams -> Triple(courses.size, grades.size, exams.size) }
    private val localCounts = combine(scheduleRepository.memos(), scheduleRepository.events()) { memos, events ->
        memos.size to events.size
    }
    val summary: StateFlow<CacheSummary> = combine(academicCounts, localCounts) { academic, local ->
        CacheSummary(academic.first, academic.second, academic.third, local.first, local.second)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CacheSummary())

    private val _states = MutableStateFlow(SyncKind.entries.associateWith { SyncItemState.Idle as SyncItemState })
    val states: StateFlow<Map<SyncKind, SyncItemState>> = _states.asStateFlow()

    fun sync(kind: SyncKind) {
        if (_states.value[kind] is SyncItemState.Running) return
        _states.value = _states.value + (kind to SyncItemState.Running)
        viewModelScope.launch {
            runCatching {
                when (kind) {
                    SyncKind.TIMETABLE -> {
                        timetableRepository.refresh(semesterId)
                        "课表同步完成"
                    }
                    SyncKind.GRADES -> academicRepository.refreshGradesAndRankings().requireSuccess("成绩与排名")
                    SyncKind.EXAMS -> academicRepository.refreshExams(semesterId).requireSuccess("考试安排")
                }
            }.fold(
                onSuccess = { message -> _states.value = _states.value + (kind to SyncItemState.Success(message)) },
                onFailure = { error ->
                    _states.value = _states.value + (kind to SyncItemState.Error(error.message ?: "同步失败"))
                },
            )
        }
    }

    private fun AcademicRefreshResult.requireSuccess(label: String): String {
        if (!hasAnySuccess && failures.isNotEmpty()) error(failures.joinToString("；"))
        return buildString {
            append("$label 同步完成")
            grades?.let { append("：$it 条成绩") }
            rankings?.let { append("，$it 条排名") }
            exams?.let { append("：$it 场考试") }
            if (failures.isNotEmpty()) append("；${failures.joinToString("；")}")
        }
    }
}

@Composable
fun ProfileSyncScreen(
    onBack: () -> Unit,
    viewModel: ProfileSyncViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ProfileSyncViewModel(
                container.timetableRepository,
                container.academicRepository,
                container.scheduleRepository,
                SemesterConfig.currentSemesterId,
            )
        },
    ),
) {
    val summary by viewModel.summary.collectAsStateWithLifecycle()
    val states by viewModel.states.collectAsStateWithLifecycle()
    LeafySecondaryScaffold(title = "缓存与同步", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item { LeafySectionHeader("学校数据", supportingText = "每个按钮只请求对应范围，失败时保留最近成功缓存。") }
            item { SyncCard("课表", "当前学期 ${summary.courses} 门课程", states[SyncKind.TIMETABLE], { viewModel.sync(SyncKind.TIMETABLE) }) }
            item { SyncCard("成绩与排名", "本地 ${summary.grades} 条成绩", states[SyncKind.GRADES], { viewModel.sync(SyncKind.GRADES) }) }
            item { SyncCard("考试安排", "本地 ${summary.exams} 场考试", states[SyncKind.EXAMS], { viewModel.sync(SyncKind.EXAMS) }) }
            item { LeafySectionHeader("本机数据", supportingText = "随记与个人日程以本机为权威，不会在这里上传。") }
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(LeafySpacing.card),
                        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                    ) {
                        Text("${summary.memos} 条随记", style = MaterialTheme.typography.titleMedium)
                        Text("${summary.schedules} 个个人日程", style = MaterialTheme.typography.titleMedium)
                        Text("退出登录会保留这些身份作用域数据。", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun SyncCard(title: String, summary: String, state: SyncItemState?, onSync: () -> Unit) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(LeafySpacing.card),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(summary, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                when (state) {
                    is SyncItemState.Success -> Text(state.message, color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
                    is SyncItemState.Error -> Text(state.message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    else -> Unit
                }
            }
            LeafyPrimaryButton(
                onClick = onSync,
                enabled = state !is SyncItemState.Running,
            ) {
                if (state is SyncItemState.Running) {
                    CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.standard), strokeWidth = LeafyStroke.progress)
                }
                else Text("同步")
            }
        }
    }
}
