package com.myleafy.android.features.timetable

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material.icons.outlined.AcUnit
import androidx.compose.material.icons.outlined.Thunderstorm
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.core.content.FileProvider
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.features.schedule.ScheduleEventDraft
import com.myleafy.android.features.schedule.ScheduleEventEditorSheet
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import com.myleafy.android.features.timetable.presentation.CourseDetailsDialog
import com.myleafy.android.features.timetable.presentation.ExamDetailsDialog
import com.myleafy.android.features.timetable.presentation.TimetableGrid
import com.myleafy.android.features.timetable.weather.WeatherCondition
import com.myleafy.android.features.timetable.weather.WeatherUiState
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafySnackbarHost
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.leafySurfaces
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Composable
fun TimetableScreen(
    onShareClick: () -> Unit = {},
    viewModel: TimetableViewModel = viewModel(
        factory = appViewModelFactory { container ->
            TimetableViewModel(
                repository = container.timetableRepository,
                academicRepository = container.academicRepository,
                scheduleRepository = container.scheduleRepository,
                settingsStore = container.settingsStore,
                weatherRepository = container.weatherRepository,
                onScheduleEventsChanged = container.scheduleNotificationScheduler::requestReconcile,
                semesterId = SemesterConfig.currentSemesterId,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()
    val mutationState by viewModel.scheduleMutationState.collectAsStateWithLifecycle()
    val exportState by viewModel.exportState.collectAsStateWithLifecycle()
    val weatherState by viewModel.weatherState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context.findActivity()
    val snackbarHostState = remember { SnackbarHostState() }
    var menuExpanded by rememberSaveable { mutableStateOf(false) }
    var editorDraft by rememberSaveable(stateSaver = scheduleDraftSaver) {
        mutableStateOf<ScheduleEventDraft?>(null)
    }
    var selectedCourse by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedExam by rememberSaveable { mutableStateOf<Int?>(null) }
    var showWeatherPermissionDialog by rememberSaveable { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            viewModel.refreshWeather(forceRefresh = true)
        } else {
            coroutineScope.launch {
                val permanentlyDenied = activity?.let {
                    !ActivityCompat.shouldShowRequestPermissionRationale(
                        it,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    )
                } == true
                val result = snackbarHostState.showSnackbar(
                    message = if (permanentlyDenied) "粗略位置权限已关闭，可在系统设置中重新开启" else "未授权位置，课表仍可正常使用",
                    actionLabel = if (permanentlyDenied) "设置" else null,
                )
                if (permanentlyDenied && result == SnackbarResult.ActionPerformed) {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${context.packageName}"),
                        ),
                    )
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            viewModel.refreshWeather()
        }
    }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        snackbarHost = { LeafySnackbarHost(snackbarHostState) },
        topBar = {
            LeafyRootTopBar(
                titleContent = {
                    TimetableWeatherTitle(
                        state = weatherState,
                        hasPermission = ContextCompat.checkSelfPermission(
                            context,
                            Manifest.permission.ACCESS_COARSE_LOCATION,
                        ) == PackageManager.PERMISSION_GRANTED,
                        onClick = {
                            if (ContextCompat.checkSelfPermission(
                                    context,
                                    Manifest.permission.ACCESS_COARSE_LOCATION,
                                ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                viewModel.refreshWeather(forceRefresh = true)
                            } else {
                                showWeatherPermissionDialog = true
                            }
                        },
                    )
                },
                actions = {
                    LeafyActionIconButton(
                        onClick = {
                            val state = uiState as? TimetableUiState.Loaded ?: return@LeafyActionIconButton
                            editorDraft = defaultDraft(state)
                        },
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = "添加日程")
                    }
                    Box {
                        LeafyActionIconButton(onClick = { menuExpanded = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "课表操作")
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("回到本周") },
                                leadingIcon = { Icon(Icons.Outlined.Today, contentDescription = null) },
                                enabled = (uiState as? TimetableUiState.Loaded)?.let {
                                    it.selectedWeek != it.currentWeek
                                } == true,
                                onClick = {
                                    menuExpanded = false
                                    viewModel.goToCurrentWeek()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(if (syncState is TimetableSyncState.Syncing) "同步中…" else "同步课表")
                                },
                                leadingIcon = { Icon(Icons.Outlined.CloudSync, contentDescription = null) },
                                enabled = uiState is TimetableUiState.Loaded &&
                                    syncState !is TimetableSyncState.Syncing,
                                onClick = {
                                    menuExpanded = false
                                    viewModel.refresh()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("共享课表") },
                                leadingIcon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                                onClick = {
                                    menuExpanded = false
                                    onShareClick()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("导出 ICS") },
                                leadingIcon = { Icon(Icons.Outlined.FileUpload, contentDescription = null) },
                                enabled = exportState !is TimetableExportState.Exporting,
                                onClick = {
                                    menuExpanded = false
                                    viewModel.exportCalendar(File(context.cacheDir, "calendar-exports"))
                                },
                            )
                        }
                    }
                },
            )
        },
    ) { contentPadding ->
        when (val state = uiState) {
            TimetableUiState.Loading -> Box(
                modifier = Modifier.fillMaxSize().padding(contentPadding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }
            is TimetableUiState.Error -> LeafyStatusBanner(
                message = state.message,
                isError = true,
                modifier = Modifier.padding(contentPadding).padding(LeafySpacing.card),
            )
            is TimetableUiState.Loaded -> TimetableScreenContent(
                state = state,
                syncState = syncState,
                onSelectWeek = viewModel::selectWeek,
                onEmptyCellClick = { date, period -> editorDraft = draftForCell(date, period) },
                onItemClick = { item ->
                    when (item.type) {
                        TimetableGridItemType.COURSE -> selectedCourse = item.sourceId
                        TimetableGridItemType.EXAM -> selectedExam = item.sourceId.toIntOrNull()
                        TimetableGridItemType.SCHEDULE -> {
                            editorDraft = state.scheduleEvents.firstOrNull { it.id == item.sourceId }?.toDraft()
                        }
                    }
                },
                onConsumeSync = viewModel::consumeSyncResult,
                modifier = Modifier.padding(contentPadding),
            )
        }
    }

    LaunchedEffect(exportState) {
        when (val state = exportState) {
            is TimetableExportState.Ready -> {
                val result = runCatching {
                    val uri = FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        state.file,
                    )
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/calendar"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri("MyLeafy 课表", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "分享课表 ICS"))
                }
                if (result.isFailure) {
                    snackbarHostState.showSnackbar(result.exceptionOrNull()?.message ?: "无法打开系统分享")
                }
                viewModel.consumeExportResult()
            }
            is TimetableExportState.Error -> {
                snackbarHostState.showSnackbar(state.message)
                viewModel.consumeExportResult()
            }
            else -> Unit
        }
    }

    val loaded = uiState as? TimetableUiState.Loaded
    selectedCourse?.let { id ->
        loaded?.courses?.firstOrNull { it.id == id }?.let { course ->
            CourseDetailsDialog(course = course, onDismiss = { selectedCourse = null })
        }
    }
    selectedExam?.let { id ->
        loaded?.exams?.firstOrNull { it.id == id }?.let { exam ->
            ExamDetailsDialog(exam = exam, onDismiss = { selectedExam = null })
        }
    }
    editorDraft?.let { initial ->
        ScheduleEventEditorSheet(
            initial = initial,
            mutationState = mutationState,
            onSave = viewModel::saveScheduleEvent,
            onDelete = initial.id?.let { { id -> viewModel.deleteScheduleEvent(id) } },
            onConsumeMutation = viewModel::consumeScheduleMutation,
            onDismiss = {
                viewModel.consumeScheduleMutation()
                editorDraft = null
            },
        )
    }
    if (showWeatherPermissionDialog) {
        LeafyAlertDialog(
            onDismissRequest = { showWeatherPermissionDialog = false },
            title = { Text("显示当地天气") },
            text = { Text("MyLeafy 只使用设备提供的粗略位置直接请求 Open-Meteo；位置不会上传到 MyLeafy 或 Supabase，也不会影响课表使用。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    showWeatherPermissionDialog = false
                    locationPermissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
                }) { Text("继续") }
            },
            dismissButton = {
                LeafyTextButton(onClick = { showWeatherPermissionDialog = false }) { Text("取消") }
            },
        )
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

@Composable
private fun TimetableWeatherTitle(
    state: WeatherUiState,
    hasPermission: Boolean,
    onClick: () -> Unit,
) {
    val loaded = state as? WeatherUiState.Loaded
    val label = when (state) {
        WeatherUiState.Idle -> if (hasPermission) "天气" else "获取天气"
        WeatherUiState.Loading -> "天气…"
        is WeatherUiState.Loaded -> buildString {
            append(state.snapshot.condition.label)
            append(' ')
            append(state.snapshot.temperatureCelsius.roundToInt())
            append('°')
            if (state.snapshot.isStale) append(" · 旧")
        }
        is WeatherUiState.Error -> "天气不可用"
    }
    val icon = when (loaded?.snapshot?.condition) {
        WeatherCondition.CLEAR -> Icons.Outlined.WbSunny
        WeatherCondition.SNOW -> Icons.Outlined.AcUnit
        WeatherCondition.THUNDERSTORM -> Icons.Outlined.Thunderstorm
        WeatherCondition.DRIZZLE, WeatherCondition.RAIN -> Icons.Outlined.WaterDrop
        else -> Icons.Outlined.Cloud
    }
    Row(
        modifier = Modifier
            .heightIn(min = LeafyComponentSize.minimumTouchTarget)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "天气，$label" }
            .padding(horizontal = LeafySpacing.micro),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(LeafySpacing.tiny),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(LeafyIconSize.compact))
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
        )
    }
}

@Composable
private fun TimetableScreenContent(
    state: TimetableUiState.Loaded,
    syncState: TimetableSyncState,
    onSelectWeek: (Int) -> Unit,
    onEmptyCellClick: (LocalDate, Int) -> Unit,
    onItemClick: (TimetableGridItem) -> Unit,
    onConsumeSync: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pagerState = rememberPagerState(
        initialPage = (state.selectedWeek - 1).coerceIn(0, state.supportedWeeks - 1),
        pageCount = { state.supportedWeeks },
    )
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }
            .distinctUntilChanged()
            .collect { page -> onSelectWeek(page + 1) }
    }
    LaunchedEffect(state.selectedWeek) {
        val targetPage = (state.selectedWeek - 1).coerceIn(0, state.supportedWeeks - 1)
        if (pagerState.settledPage != targetPage) pagerState.animateScrollToPage(targetPage)
    }

    val visiblePage = state.pages[pagerState.currentPage]
    Column(modifier = modifier.fillMaxSize().padding(horizontal = LeafySpacing.micro)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = LeafySpacing.tiny),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LeafyActionIconButton(
                onClick = {
                    coroutineScope.launch { pagerState.animateScrollToPage(pagerState.currentPage - 1) }
                },
                enabled = pagerState.currentPage > 0,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "上一周")
            }
            Row(
                modifier = Modifier.weight(1f),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (visiblePage.week == state.currentWeek) {
                        "本周 · 第 ${visiblePage.week} 周"
                    } else {
                        "第 ${visiblePage.week} 周"
                    },
                    style = MaterialTheme.typography.titleLarge,
                    maxLines = 1,
                )
                Text(
                    text = " · ${formatWeekRange(visiblePage.weekRange.startDate)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
            LeafyActionIconButton(
                onClick = {
                    coroutineScope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                },
                enabled = pagerState.currentPage < state.supportedWeeks - 1,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "下一周")
            }
        }
        TimetableSyncBanner(syncState = syncState, onConsume = onConsumeSync)
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clipToBounds(),
            key = { state.pages[it].week },
        ) { page ->
            TimetableGrid(
                snapshot = state.pages[page].grid,
                onEmptyCellClick = onEmptyCellClick,
                onItemClick = onItemClick,
                modifier = Modifier.fillMaxSize(),
                today = LocalDate.now(TimetableGridProjection.campusZone),
                currentTime = LocalTime.now(TimetableGridProjection.campusZone),
                showWeekends = state.showWeekends,
                background = state.background,
            )
        }
    }
}

@Composable
private fun TimetableSyncBanner(syncState: TimetableSyncState, onConsume: () -> Unit) {
    val message = when (syncState) {
        is TimetableSyncState.Success -> if (syncState.count == 0) {
            "教务已连接；学校暂未公布或尚未安排本学期课表"
        } else {
            "同步成功：${syncState.count} 门课程"
        }
        is TimetableSyncState.Error -> "同步失败：${syncState.message}"
        else -> null
    }
    if (message != null) {
        LeafyStatusBanner(
            message = message,
            isError = syncState is TimetableSyncState.Error,
            modifier = Modifier.padding(top = LeafySpacing.tiny),
        )
        LaunchedEffect(syncState) {
            delay(3_000)
            onConsume()
        }
    }
}

private fun defaultDraft(state: TimetableUiState.Loaded): ScheduleEventDraft {
    val today = LocalDate.now(TimetableGridProjection.campusZone)
    val date = if (!today.isBefore(state.weekRange.startDate) && today.isBefore(state.weekRange.endDateExclusive)) {
        today
    } else {
        state.weekRange.startDate
    }
    val period = if (date == today) {
        TimetablePeriodSchedule.defaultStudyPeriod(
            LocalTime.now(TimetableGridProjection.campusZone).let { it.hour * 60 + it.minute },
        )
    } else {
        1
    }
    return draftForCell(date, period)
}

private fun draftForCell(date: LocalDate, period: Int): ScheduleEventDraft {
    val slot = TimetablePeriodSchedule.slot(period) ?: TimetablePeriodSchedule.slots.first()
    return ScheduleEventDraft(
        title = "",
        date = date,
        startsAt = LocalTime.of(slot.startHour, slot.startMinute),
        endsAt = LocalTime.of(slot.endHour, slot.endMinute),
        location = "",
        note = "",
    )
}

private fun ScheduleEventEntity.toDraft(): ScheduleEventDraft {
    val start = Instant.ofEpochMilli(startsAt).atZone(TimetableGridProjection.campusZone)
    val end = endsAt
        ?.takeIf { it > startsAt }
        ?.let { Instant.ofEpochMilli(it).atZone(TimetableGridProjection.campusZone) }
        ?: start.plusMinutes(45)
    return ScheduleEventDraft(
        id = id,
        title = title,
        date = start.toLocalDate(),
        startsAt = start.toLocalTime(),
        endsAt = end.toLocalTime(),
        location = location.orEmpty(),
        note = note.orEmpty(),
    )
}

private fun formatWeekRange(start: LocalDate): String {
    val end = start.plusDays(6)
    return "${start.format(shortDateFormatter)}–${end.format(shortDateFormatter)}"
}

private val shortDateFormatter = DateTimeFormatter.ofPattern("M月d日")

private val scheduleDraftSaver = androidx.compose.runtime.saveable.Saver<ScheduleEventDraft?, List<String>>(
    save = { draft ->
        draft?.let {
            listOf(
                it.id.orEmpty(),
                it.title,
                it.date.toString(),
                it.startsAt.toString(),
                it.endsAt.toString(),
                it.location,
                it.note,
            )
        }
    },
    restore = { values ->
        ScheduleEventDraft(
            id = values[0].ifBlank { null },
            title = values[1],
            date = LocalDate.parse(values[2]),
            startsAt = LocalTime.parse(values[3]),
            endsAt = LocalTime.parse(values[4]),
            location = values[5],
            note = values[6],
        )
    },
)
