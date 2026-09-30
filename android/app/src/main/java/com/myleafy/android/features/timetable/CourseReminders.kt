package com.myleafy.android.features.timetable

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.myleafy.android.MainActivity
import com.myleafy.android.MyLeafyApplication
import com.myleafy.android.R
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.security.MessageDigest
import java.time.*

data class CourseAlarm(val id: String, val courseKey: String, val week: Int, val startsAt: Instant, val firesAt: Instant)

object CourseReminderPlanner {
    fun alarms(courses: List<CourseEntity>, reminders: List<CourseReminderEntity>, config: SemesterRuntimeConfig,
        now: Instant = Instant.now()): List<CourseAlarm> = reminders.filter { it.minutes in 1..180 && !it.orphaned }.flatMap { reminder ->
        courses.filter { it.scopeKey == reminder.scopeKey && it.sourceSemesterID == reminder.semesterId && it.stableCourseKey() == reminder.courseKey }.flatMap { course ->
            if (reminder.anchorPeriod !in course.duration) return@flatMap emptyList()
            val time = TimetablePeriodSchedule.slot(reminder.anchorPeriod)?.startText?.let(LocalTime::parse) ?: return@flatMap emptyList()
            course.weeks.distinct().filter { it in 1..config.supportedWeeks }.mapNotNull { week ->
                val date = config.semesterStartDate.plusWeeks((week - 1).toLong()).plusDays((course.dayOfWeek - 1).toLong())
                val starts = date.atTime(time).atZone(TimetableGridProjection.campusZone).toInstant()
                val fire = starts.minusSeconds(reminder.minutes * 60L)
                if (!fire.isAfter(now)) null else CourseAlarm(digest("${course.scopeKey}|${reminder.courseKey}|$week|${reminder.anchorPeriod}"), reminder.courseKey, week, starts, fire)
            }
        }
    }.distinctBy { it.id }.sortedBy { it.firesAt }

    private fun digest(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
}

class CourseReminderScheduler(private val context: Context, private val scopes: ActiveAppScopeStore,
    private val dao: TimetablePersonalDao, private val timetable: TimetableRepository) {
    private val manager = context.getSystemService(AlarmManager::class.java)
    private val preferences = context.getSharedPreferences("course-alarm-delivery", Context.MODE_PRIVATE)
    private val mutex = Mutex()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    fun permissionProblem(): String? = when {
        !NotificationManagerCompat.from(context).areNotificationsEnabled() -> "提醒未启用，请允许通知"
        context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE -> "提醒未启用，请允许课前提醒通知"
        Build.VERSION.SDK_INT >= 31 && !manager.canScheduleExactAlarms() -> "提醒未启用，请允许闹钟和提醒"
        else -> null
    }

    suspend fun reconcile() = mutex.withLock {
        try {
            val identity = scopes.current
            val config = SemesterConfig.current
            val courses = timetable.coursesForSemester(config.semesterId).first()
            val reminders = dao.reminders(identity.scopeKey, config.semesterId).first()
            if (scopes.current.scopeKey != identity.scopeKey) return@withLock
            preferences.getStringSet("scheduled", emptySet()).orEmpty().forEach { manager.cancel(pending(it)) }
            check(preferences.edit().putStringSet("scheduled", emptySet()).commit()) { "无法保存提醒状态" }
            mutableError.value = null
            if (identity.campusId == null || permissionProblem() != null) return@withLock
            val drafts = CourseReminderPlanner.alarms(courses, reminders, config)
            check(drafts.size <= 450) { "待提醒课次过多，请减少启用提醒的课程" }
            // Persist before scheduling, so a killed process can still cancel every partially scheduled alarm.
            check(preferences.edit().putStringSet("scheduled", drafts.map { it.id }.toSet()).commit()) { "无法保存提醒状态" }
            drafts.forEach { draft ->
                currentCoroutineContext().ensureActive()
                if (scopes.current.scopeKey != identity.scopeKey) throw CancellationException("Identity changed")
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, draft.firesAt.toEpochMilli(), pending(draft.id,
                    Intent().putExtra("scope", identity.scopeKey).putExtra("semester", config.semesterId)
                        .putExtra("course", draft.courseKey).putExtra("week", draft.week).putExtra("fire", draft.firesAt.toEpochMilli())))
            }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) {
            mutableError.value = failure.message ?: "提醒排期失败，请重试"
            android.util.Log.e("CourseReminders", "Unable to schedule course reminders", failure)
        }
    }

    private fun pending(id: String, extras: Intent = Intent()): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, CourseAlarmReceiver::class.java).setAction(ACTION_DELIVER).setData(Uri.parse("myleafy-internal://course-alarm/$id"))
            .putExtras(extras), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    suspend fun deliver(intent: Intent) {
        val scope = intent.getStringExtra("scope") ?: return
        val semester = intent.getStringExtra("semester") ?: return
        val key = intent.getStringExtra("course") ?: return
        val week = intent.getIntExtra("week", 0)
        if (scopes.current.scopeKey != scope || semester != SemesterConfig.currentSemesterId || permissionProblem() != null) return
        val courses = timetable.coursesForSemester(semester).first()
        val reminder = dao.reminders(scope, semester).first().firstOrNull { it.courseKey == key } ?: return
        val fire = intent.getLongExtra("fire", 0)
        val expected = CourseReminderPlanner.alarms(courses, listOf(reminder), SemesterConfig.current, Instant.ofEpochMilli(fire - 1))
            .firstOrNull { it.week == week && it.firesAt.toEpochMilli() == fire } ?: return
        if (!expected.startsAt.isAfter(Instant.now()) || scopes.current.scopeKey != scope) return
        val course = courses.firstOrNull { it.stableCourseKey() == key && week in it.weeks } ?: return
        val notifications = context.getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "课前提醒", NotificationManager.IMPORTANCE_DEFAULT))
        val open = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("myleafy-internal://course/${expected.id}"))
            .putExtra("courseReminder", true).putExtra("scope", scope).putExtra("semester", semester)
            .putExtra("course", key).putExtra("week", week)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        notifications.notify(expected.id, 0, NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(course.courseName).setContentText("${reminder.minutes} 分钟后开始 · ${course.location.ifBlank { course.room }}")
            .setContentIntent(content).setAutoCancel(true).build())
    }

    companion object {
        const val ACTION_DELIVER = "com.myleafy.android.COURSE_REMINDER"
        private const val CHANNEL = "course-reminders"
    }
}

class CourseAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val container = (context.applicationContext as MyLeafyApplication).container
                container.restoreIdentity()
                if (intent.action == CourseReminderScheduler.ACTION_DELIVER) container.courseReminderScheduler.deliver(intent)
                else container.courseReminderScheduler.reconcile()
            } catch (failure: Exception) { android.util.Log.e("CourseReminders", "Reminder delivery/recovery failed", failure) }
            finally { pending.finish() }
        }
    }
}
