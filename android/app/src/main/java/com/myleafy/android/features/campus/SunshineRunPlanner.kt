package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.*
import com.myleafy.android.features.timetable.domain.*
import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class RunPeriod(val index: Int, val weeks: List<Int>, val start: LocalDate, val end: LocalDate, val count: Int, val target: Int)
object SunshineRunPlanner {
    fun semesterEnd(config: SemesterRuntimeConfig): LocalDate = config.calendarEvents.firstOrNull { it.academicCategory == SchoolCalendarEvent.AcademicCategory.SEMESTER_END }?.startDate
        ?: config.semesterStartDate.plusWeeks(config.supportedWeeks.toLong()).minusDays(1)
    fun periods(records: List<SunshineRunRecordEntity>, settings: SunshineRunSettingsEntity, config: SemesterRuntimeConfig): List<RunPeriod> {
        val end = semesterEnd(config)
        val totalWeeks = (ChronoUnit.DAYS.between(config.semesterStartDate, end) / 7 + 1).toInt().coerceAtLeast(0)
        val excluded = if (settings.skipsExcludedWeeks) settings.excludedWeeks.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet() else emptySet()
        val active = (1..totalWeeks).filterNot { it in excluded }
        return active.chunked(settings.weeksPerPeriod.coerceAtLeast(1)).mapIndexed { index, weeks ->
            val dates = records.map { LocalDate.ofEpochDay(it.dateEpochDay) }.distinct().filter { date ->
                date >= config.semesterStartDate && date <= end && (ChronoUnit.DAYS.between(config.semesterStartDate, date) / 7 + 1).toInt() in weeks
            }
            RunPeriod(index + 1, weeks, config.semesterStartDate.plusWeeks((weeks.first() - 1).toLong()),
                minOf(end, config.semesterStartDate.plusWeeks(weeks.last().toLong()).minusDays(1)), dates.size, settings.periodTarget)
        }
    }
    fun period(date: LocalDate, periods: List<RunPeriod>, config: SemesterRuntimeConfig): RunPeriod? {
        if (date < config.semesterStartDate || date > semesterEnd(config)) return null
        val week = (ChronoUnit.DAYS.between(config.semesterStartDate, date) / 7 + 1).toInt()
        return periods.firstOrNull { week in it.weeks }
    }
}
