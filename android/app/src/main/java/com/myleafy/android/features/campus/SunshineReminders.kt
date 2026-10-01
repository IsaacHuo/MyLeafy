package com.myleafy.android.features.campus

import android.app.*
import android.content.*
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.myleafy.android.*
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.SemesterConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import java.time.*

class SunshineReminderScheduler(private val context: Context, private val scopes: ActiveAppScopeStore,
    private val dao: CampusPersonalDao, private val repository: CampusLifeRepository) {
    private val alarm = context.getSystemService(AlarmManager::class.java)
    private val registry = context.getSharedPreferences("sunshine-reminder-delivery", Context.MODE_PRIVATE)
    private val mutex = kotlinx.coroutines.sync.Mutex()
    private fun pending(id: String, scope: String? = null, fire: Long = 0L) = PendingIntent.getBroadcast(context, 0,
        Intent(context, SunshineReminderReceiver::class.java).setData(Uri.parse("myleafy-internal://sunshine/$id")).putExtra("scope", scope).putExtra("fire", fire),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    suspend fun reconcile() {
        mutex.lock()
        try {
            registry.getStringSet("scheduled", emptySet()).orEmpty().forEach { alarm.cancel(pending(it)) }
            check(registry.edit().putStringSet("scheduled", emptySet()).commit()) { "提醒排期保存失败" }
            val scope = scopes.current
            val reminder = dao.reminder(scope.scopeKey).first() ?: return
            if (!reminder.enabled || !NotificationManagerCompat.from(context).areNotificationsEnabled()) return
            val config = SemesterConfig.current
            val runs = repository.sunshineRuns.first()
            val periods = SunshineRunPlanner.periods(runs, repository.sunshineSettings.first(), config)
            val zone = ZoneId.of("Asia/Shanghai")
            val now = ZonedDateTime.now(zone)
            val days = reminder.weekdays.split(',').mapNotNull(String::toIntOrNull).toSet()
            val drafts = (0..13).mapNotNull { offset ->
                val date = now.toLocalDate().plusDays(offset.toLong())
                val period = SunshineRunPlanner.period(date, periods, config) ?: return@mapNotNull null
                if (date.dayOfWeek.value !in days || period.count >= period.target || runs.any { it.dateEpochDay == date.toEpochDay() }) return@mapNotNull null
                val fire = date.atTime(reminder.hour, reminder.minute).atZone(zone)
                if (!fire.isAfter(now)) return@mapNotNull null
                "${scope.scopeKey}:$date" to fire.toInstant().toEpochMilli()
            }
            if (scopes.current.scopeKey != scope.scopeKey) throw CancellationException("Identity changed")
            check(registry.edit().putStringSet("scheduled", drafts.map { it.first }.toSet()).commit()) { "提醒排期保存失败" }
            drafts.forEach { (id, fire) -> alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, pending(id, scope.scopeKey, fire)) }
        } finally { mutex.unlock() }
    }
    suspend fun deliver(intent: Intent) {
        val scope = intent.getStringExtra("scope") ?: return
        if (scope != scopes.current.scopeKey) return
        val reminder = dao.reminder(scope).first() ?: return
        val today = LocalDate.now(ZoneId.of("Asia/Shanghai"))
        val config = SemesterConfig.current
        val runs = repository.sunshineRuns.first()
        val period = SunshineRunPlanner.period(today, SunshineRunPlanner.periods(runs, repository.sunshineSettings.first(), config), config)
        if (!reminder.enabled || period == null || period.count >= period.target || runs.any { it.dateEpochDay == today.toEpochDay() } || today.dayOfWeek.value !in reminder.weekdays.split(',').mapNotNull(String::toIntOrNull)) return
        if (intent.getLongExtra("fire", 0) != today.atTime(reminder.hour, reminder.minute).atZone(ZoneId.of("Asia/Shanghai")).toInstant().toEpochMilli()) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("sunshine-runs", "阳光长跑", NotificationManager.IMPORTANCE_DEFAULT))
        if (android.os.Build.VERSION.SDK_INT >= 33 && androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return
        if (scope != scopes.current.scopeKey) return
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).putExtra("sunshineReminder", true).putExtra("scope", scope), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify("sunshine:$scope:$today", 0, NotificationCompat.Builder(context, "sunshine-runs").setSmallIcon(R.drawable.ic_launcher_foreground).setContentTitle("阳光长跑")
            .setContentText("本周期还需 ${(period.target - period.count).coerceAtLeast(0)} 次，完成后记得补记。") .setContentIntent(open).setAutoCancel(true).build())
        reconcile()
    }
}

class SunshineReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try { val container = (context.applicationContext as MyLeafyApplication).container; container.restoreIdentity()
                if (intent.hasExtra("scope")) container.sunshineReminderScheduler.deliver(intent) else container.sunshineReminderScheduler.reconcile()
            } catch (failure: Exception) { android.util.Log.e("SunshineReminder", "Reminder delivery/recovery failed", failure) }
            finally { result.finish() }
        }
    }
}
