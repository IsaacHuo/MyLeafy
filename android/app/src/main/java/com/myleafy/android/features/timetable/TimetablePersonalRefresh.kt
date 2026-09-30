package com.myleafy.android.features.timetable

import com.myleafy.android.core.data.local.*

/** Preflight before the Room transaction replaces courses. Mirrors iOS teacher/period split rules. */
data class TimetablePersonalRefresh(val notes: List<CourseNoteEntity>, val reminders: List<CourseReminderEntity>) {
    companion object {
        fun prepare(old: List<CourseEntity>, fresh: List<CourseEntity>, notes: List<CourseNoteEntity>, reminders: List<CourseReminderEntity>): TimetablePersonalRefresh {
            val finalNotes = notes.associateBy { it.courseKey to it.week }.toMutableMap()
            val finalReminders = reminders.associateBy { it.courseKey }.toMutableMap()
            fun conflict(name: String): Nothing = error("“$name”的备注或提醒存在冲突，课表未更新。请检查相关记录后重试。")
            fun add(note: CourseNoteEntity) {
                val target = note.courseKey to note.week
                finalNotes[target]?.let { if (it.text != note.text) conflict(note.courseKey.split('|').getOrNull(1).orEmpty()) }
                finalNotes[target] = note
            }
            fun add(reminder: CourseReminderEntity) {
                finalReminders[reminder.courseKey]?.let {
                    if (it.minutes != reminder.minutes || it.anchorPeriod != reminder.anchorPeriod) conflict(reminder.courseKey.split('|').getOrNull(1).orEmpty())
                }
                finalReminders[reminder.courseKey] = reminder
            }
            for ((key, originals) in old.groupBy { it.stableCourseKey() }) {
                val stillCovered = originals.all { item -> item.weeks.all { week -> fresh.any { it.stableCourseKey() == key && sameArrangement(it, item) && week in it.weeks } } }
                if (stillCovered) continue
                val candidates = fresh.filter { next -> originals.any { previous ->
                    samePlaceAndClass(next, previous) && next.duration.isNotEmpty() && previous.duration.containsAll(next.duration) && next.weeks.any { it in previous.weeks }
                } }.distinctBy { it.stableCourseKey() }
                if (candidates.none { it.stableCourseKey() != key }) continue
                val sourceNotes = notes.filter { it.courseKey == key }
                val sourceReminder = reminders.firstOrNull { it.courseKey == key }
                if ((sourceNotes.isNotEmpty() || sourceReminder != null) && originals.any { !sameArrangement(it, originals.first()) }) conflict(originals.first().courseName)
                sourceNotes.forEach { note ->
                    val targets = if (note.week == 0) candidates else candidates.filter { note.week in it.weeks }
                    if (note.week != 0 && targets.size != 1) error("无法确定“${originals.first().courseName}”第 ${note.week} 周备注对应的课次，课表未更新。原课表和备注已保留。")
                    targets.forEach { add(note.copy(courseKey = it.stableCourseKey(), orphaned = false)) }
                }
                sourceReminder?.let { reminder -> candidates.forEach {
                    // Preserve a valid selected anchor; an invalid anchor stays pending instead of silently moving.
                    if (reminder.anchorPeriod in it.duration || reminder.minutes == 0) add(reminder.copy(courseKey = it.stableCourseKey(), orphaned = false))
                } }
            }
            val byKey = fresh.groupBy { it.stableCourseKey() }
            return TimetablePersonalRefresh(finalNotes.values.map { note -> note.copy(orphaned = byKey[note.courseKey].orEmpty().none { note.week == 0 || note.week in it.weeks }) },
                finalReminders.values.map { reminder -> reminder.copy(orphaned = byKey[reminder.courseKey].orEmpty().none { reminder.minutes == 0 || reminder.anchorPeriod in it.duration }) })
        }
        private fun normalized(value: String) = value.trim().replace(Regex("\\s+"), " ")
        private fun samePlaceAndClass(a: CourseEntity, b: CourseEntity) = a.sourceSemesterID == b.sourceSemesterID && normalized(a.courseName) == normalized(b.courseName) &&
            normalized(a.classInfo) == normalized(b.classInfo) && a.dayOfWeek == b.dayOfWeek && normalized(a.room) == normalized(b.room) && normalized(a.location) == normalized(b.location)
        private fun sameArrangement(a: CourseEntity, b: CourseEntity) = samePlaceAndClass(a, b) && a.duration.sorted() == b.duration.sorted()
    }
}
