package com.myleafy.android.features.schedule.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.myleafy.android.MainActivity
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.R
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleEventReminderEntity
import com.myleafy.android.core.data.local.ScheduleNotificationDao
import com.myleafy.android.core.data.local.ScheduleReportSettingEntity
import com.myleafy.android.features.campus.AcademicRepository
import com.myleafy.android.features.schedule.ScheduleRepository
import com.myleafy.android.features.timetable.TimetableRepository
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.features.timetable.domain.TimetableGridProjection
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map

enum class ScheduleReportMode(val title: String, val defaultHour: Int, val defaultMinute: Int) {
    MORNING("今日早报", 7, 30),
    EVENING("明日晚报", 21, 30),
    EXAM("考试提醒", 20, 0),
}

data class ScheduleReportSetting(
    val mode: ScheduleReportMode,
    val enabled: Boolean,
    val hour: Int,
    val minute: Int,
)

data class ScheduledNotificationDraft(
    val id: String,
    val fireAt: Instant,
    val title: String,
    val body: String,
    val eventId: String? = null,
)

@OptIn(ExperimentalCoroutinesApi::class)
class ScheduleNotificationRepository(
    private val dao: ScheduleNotificationDao,
    private val scopeStore: ActiveAppScopeStore,
) {
    val settings: Flow<List<ScheduleReportSetting>> = scopeStore.scope.flatMapLatest { scope ->
        dao.settings(scope.scopeKey)
    }.map { rows ->
        ScheduleReportMode.entries.map { mode ->
            val row = rows.firstOrNull { it.mode == mode.name }
            ScheduleReportSetting(
                mode = mode,
                enabled = row?.enabled ?: false,
                hour = row?.hour ?: mode.defaultHour,
                minute = row?.minute ?: mode.defaultMinute,
            )
        }
    }

    val reminders: Flow<List<ScheduleEventReminderEntity>> = scopeStore.scope.flatMapLatest { scope ->
        dao.reminders(scope.scopeKey)
    }

    suspend fun setMode(mode: ScheduleReportMode, enabled: Boolean, hour: Int, minute: Int) {
        dao.upsert(
            ScheduleReportSettingEntity(
                scopeKey = scopeStore.current.scopeKey,
                mode = mode.name,
                enabled = enabled,
                hour = hour.coerceIn(0, 23),
                minute = minute.coerceIn(0, 59),
            ),
        )
    }

    suspend fun setEventReminder(eventId: String, enabled: Boolean, leadMinutes: Int) {
        val scopeKey = scopeStore.current.scopeKey
        if (!enabled) {
            dao.deleteReminder(scopeKey, eventId)
            return
        }
        val now = System.currentTimeMillis()
        dao.upsert(
            ScheduleEventReminderEntity(
                id = "$scopeKey:$eventId",
                scopeKey = scopeKey,
                eventId = eventId,
                leadMinutes = leadMinutes.coerceIn(0, 1_440),
                enabled = true,
                createdAt = now,
                updatedAt = now,
            ),
        )
    }
}

object ScheduleNotificationPlanner {
    private val zone = TimetableGridProjection.campusZone

    fun drafts(
        settings: List<ScheduleReportSetting>,
        reminders: List<ScheduleEventReminderEntity>,
        courses: List<CourseEntity>,
        exams: List<ExamEntity>,
        events: List<ScheduleEventEntity>,
        now: ZonedDateTime = ZonedDateTime.now(zone),
    ): List<ScheduledNotificationDraft> {
        val drafts = mutableListOf<ScheduledNotificationDraft>()
        val byMode = settings.associateBy { it.mode }
        repeat(7) { offset ->
            val date = now.toLocalDate().plusDays(offset.toLong())
            byMode[ScheduleReportMode.MORNING]?.takeIf { it.enabled }?.let { setting ->
                addDailyDraft(drafts, setting, date, date, "今天", courses, exams, events, now)
            }
            byMode[ScheduleReportMode.EVENING]?.takeIf { it.enabled }?.let { setting ->
                addDailyDraft(drafts, setting, date, date.plusDays(1), "明天", courses, exams, events, now)
            }
        }
        byMode[ScheduleReportMode.EXAM]?.takeIf { it.enabled }?.let { setting ->
            exams.forEach { exam ->
                val examDate = runCatching { LocalDate.parse(exam.date) }.getOrNull() ?: return@forEach
                listOf(7L, 3L, 1L).forEach { leadDays ->
                    val fire = ZonedDateTime.of(examDate.minusDays(leadDays), LocalTime.of(setting.hour, setting.minute), zone)
                    if (fire.isAfter(now) && Duration.between(now, fire) <= Duration.ofDays(8)) {
                        drafts += ScheduledNotificationDraft(
                            id = "exam-${exam.id}-$leadDays",
                            fireAt = fire.toInstant(),
                            title = "考试提醒",
                            body = "${exam.name}还有 $leadDays 天 · ${exam.start} · ${exam.location}",
                        )
                    }
                }
            }
        }
        val reminderByEvent = reminders.filter { it.enabled }.associateBy { it.eventId }
        events.forEach { event ->
            val reminder = reminderByEvent[event.id] ?: return@forEach
            val fire = Instant.ofEpochMilli(event.startsAt).minusSeconds(reminder.leadMinutes * 60L)
            if (fire.isAfter(now.toInstant()) && Duration.between(now.toInstant(), fire) <= Duration.ofDays(8)) {
                drafts += ScheduledNotificationDraft(
                    id = "event-${event.id}-${reminder.leadMinutes}",
                    fireAt = fire,
                    title = event.title,
                    body = leadText(reminder.leadMinutes) + event.location?.takeIf(String::isNotBlank)?.let { " · $it" }.orEmpty(),
                    eventId = event.id,
                )
            }
        }
        return drafts.distinctBy { it.id }.sortedBy { it.fireAt }
    }

    private fun addDailyDraft(
        output: MutableList<ScheduledNotificationDraft>,
        setting: ScheduleReportSetting,
        fireDate: LocalDate,
        reportDate: LocalDate,
        label: String,
        courses: List<CourseEntity>,
        exams: List<ExamEntity>,
        events: List<ScheduleEventEntity>,
        now: ZonedDateTime,
    ) {
        val fire = ZonedDateTime.of(fireDate, LocalTime.of(setting.hour, setting.minute), zone)
        if (!fire.isAfter(now)) return
        val week = (ChronoUnit.DAYS.between(SemesterConfig.current.semesterStartDate, reportDate) / 7L + 1L).toInt()
        val courseCount = courses.count { it.dayOfWeek == reportDate.dayOfWeek.value && week in it.weeks }
        val examCount = exams.count { it.date == reportDate.toString() }
        val eventCount = events.count { Instant.ofEpochMilli(it.startsAt).atZone(zone).toLocalDate() == reportDate }
        output += ScheduledNotificationDraft(
            id = "${setting.mode.name.lowercase()}-$fireDate",
            fireAt = fire.toInstant(),
            title = setting.mode.title,
            body = "$label $courseCount 门课程 · $examCount 场考试 · $eventCount 个日程",
        )
    }

    private fun leadText(minutes: Int): String = when (minutes) {
        0 -> "现在开始"
        10, 30 -> "$minutes 分钟后开始"
        60 -> "1 小时后开始"
        1_440 -> "1 天后开始"
        else -> "$minutes 分钟后开始"
    }
}

class ScheduleNotificationScheduler(
    private val context: Context,
    private val repository: ScheduleNotificationRepository,
    private val timetableRepository: TimetableRepository,
    private val academicRepository: AcademicRepository,
    private val scheduleRepository: ScheduleRepository,
) {
    private val workManager = WorkManager.getInstance(context)

    fun enqueuePeriodicReconcile() {
        val request = PeriodicWorkRequestBuilder<ScheduleReconcileWorker>(4, TimeUnit.HOURS).build()
        workManager.enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun requestReconcile() {
        workManager.enqueueUniqueWork(
            RECONCILE_WORK,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<ScheduleReconcileWorker>().build(),
        )
    }

    suspend fun reconcile() {
        val drafts = ScheduleNotificationPlanner.drafts(
            settings = repository.settings.first(),
            reminders = repository.reminders.first(),
            courses = timetableRepository.coursesForSemester(SemesterConfig.currentSemesterId).first(),
            exams = academicRepository.exams().first(),
            events = scheduleRepository.events().first(),
        )
        workManager.cancelAllWorkByTag(NOTIFICATION_TAG)
        drafts.forEach { draft ->
            val delayMillis = Duration.between(Instant.now(), draft.fireAt).toMillis().coerceAtLeast(0L)
            val data = Data.Builder()
                .putString(NotificationDeliveryWorker.KEY_TITLE, draft.title)
                .putString(NotificationDeliveryWorker.KEY_BODY, draft.body)
                .putString(NotificationDeliveryWorker.KEY_EVENT_ID, draft.eventId)
                .putString(NotificationDeliveryWorker.KEY_NOTIFICATION_ID, draft.id)
                .build()
            val request = OneTimeWorkRequestBuilder<NotificationDeliveryWorker>()
                .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
                .setInputData(data)
                .addTag(NOTIFICATION_TAG)
                .build()
            workManager.enqueueUniqueWork("$NOTIFICATION_TAG:${draft.id}", ExistingWorkPolicy.REPLACE, request)
        }
    }

    companion object {
        const val NOTIFICATION_TAG = "schedule-notification"
        const val PERIODIC_WORK = "schedule-notification-reconcile-periodic"
        const val RECONCILE_WORK = "schedule-notification-reconcile-now"
    }
}

class ScheduleReconcileWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = runCatching {
        (applicationContext as MyLeafyApplication).container.scheduleNotificationScheduler.reconcile()
        Result.success()
    }.getOrElse { Result.retry() }
}

class NotificationDeliveryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return Result.success()
        ensureChannel()
        val id = inputData.getString(KEY_NOTIFICATION_ID) ?: UUID.randomUUID().toString()
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_NOTIFICATION_ROUTE, "schedule")
            putExtra(KEY_EVENT_ID, inputData.getString(KEY_EVENT_ID))
            putExtra(EXTRA_NOTIFICATION_MODE, if (inputData.getString(KEY_EVENT_ID).isNullOrBlank()) "reports" else "events")
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(inputData.getString(KEY_TITLE).orEmpty())
            .setContentText(inputData.getString(KEY_BODY).orEmpty())
            .setStyle(NotificationCompat.BigTextStyle().bigText(inputData.getString(KEY_BODY).orEmpty()))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(applicationContext).notify(id.hashCode(), notification)
        return Result.success()
    }

    private fun ensureChannel() {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "日程推送", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "课程、考试和个人日程的节能型提醒"
            },
        )
    }

    companion object {
        const val CHANNEL_ID = "schedule_reports"
        const val KEY_TITLE = "title"
        const val KEY_BODY = "body"
        const val KEY_EVENT_ID = "event_id"
        const val KEY_NOTIFICATION_ID = "notification_id"
        const val EXTRA_NOTIFICATION_ROUTE = "notification_route"
        const val EXTRA_NOTIFICATION_MODE = "notification_mode"
    }
}
