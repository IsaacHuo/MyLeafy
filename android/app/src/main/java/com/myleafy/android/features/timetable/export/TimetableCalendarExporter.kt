package com.myleafy.android.features.timetable.export

import com.myleafy.android.features.timetable.domain.TimetablePeriodSchedule
import java.io.File
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class CalendarExportCourse(
    val id: String,
    val title: String,
    val teacher: String,
    val classInfo: String,
    val location: String,
    val room: String,
    val dayOfWeek: Int,
    val weeks: List<Int>,
    val periods: List<Int>,
)

data class CalendarExportScheduleEvent(
    val id: String,
    val title: String,
    val startsAt: Long,
    val endsAt: Long?,
    val location: String?,
    val note: String?,
)

class TimetableCalendarExporter(
    private val clock: Clock = Clock.systemUTC(),
) {
    fun export(
        outputDirectory: File,
        semesterId: String,
        semesterStartDate: LocalDate,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
        courses: List<CalendarExportCourse>,
        scheduleEvents: List<CalendarExportScheduleEvent>,
    ): File {
        outputDirectory.mkdirs()
        require(outputDirectory.isDirectory) { "无法创建导出目录" }
        val file = File(outputDirectory, "MyLeafy-$semesterId.ics")
        file.writeText(
            render(
                semesterId = semesterId,
                semesterStartDate = semesterStartDate,
                rangeStart = rangeStart,
                rangeEndExclusive = rangeEndExclusive,
                courses = courses,
                scheduleEvents = scheduleEvents,
            ),
            Charsets.UTF_8,
        )
        return file
    }

    fun render(
        semesterId: String,
        semesterStartDate: LocalDate,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
        courses: List<CalendarExportCourse>,
        scheduleEvents: List<CalendarExportScheduleEvent>,
    ): String {
        require(rangeEndExclusive.isAfter(rangeStart)) { "导出结束日期必须晚于开始日期" }
        val events = buildList {
            courses.forEach courseLoop@ { course ->
                val periods = course.periods.filter { it in 1..13 }.distinct().sorted()
                val firstSlot = periods.firstOrNull()?.let(TimetablePeriodSchedule::slot)
                val lastSlot = periods.lastOrNull()?.let(TimetablePeriodSchedule::slot)
                if (course.dayOfWeek !in 1..7 || firstSlot == null || lastSlot == null) return@courseLoop
                course.weeks.distinct().sorted().forEach weekLoop@ { week ->
                    if (week < 1) return@weekLoop
                    val date = semesterStartDate
                        .plusWeeks((week - 1).toLong())
                        .plusDays((course.dayOfWeek - 1).toLong())
                    if (date.isBefore(rangeStart) || !date.isBefore(rangeEndExclusive)) return@weekLoop
                    add(
                        CalendarEvent(
                            uid = "course-${course.id}-week-$week@myleafy.android",
                            title = course.title,
                            startsAt = date.atTime(firstSlot.startHour, firstSlot.startMinute)
                                .atZone(campusZone).toInstant(),
                            endsAt = date.atTime(lastSlot.endHour, lastSlot.endMinute)
                                .atZone(campusZone).toInstant(),
                            location = listOf(course.location, course.room).filter(String::isNotBlank)
                                .joinToString(" ").ifBlank { null },
                            description = buildList {
                                course.teacher.takeIf(String::isNotBlank)?.let { add("教师：$it") }
                                course.classInfo.takeIf(String::isNotBlank)?.let { add("班级：$it") }
                                add("第${week}周 · 第${periods.first()}–${periods.last()}节")
                                add("由 MyLeafy Android 导出")
                            }.joinToString("\n"),
                        ),
                    )
                }
            }

            scheduleEvents.forEach scheduleLoop@ { event ->
                val start = Instant.ofEpochMilli(event.startsAt)
                val date = start.atZone(campusZone).toLocalDate()
                if (date.isBefore(rangeStart) || !date.isBefore(rangeEndExclusive)) return@scheduleLoop
                val end = event.endsAt?.takeIf { it > event.startsAt }?.let(Instant::ofEpochMilli)
                    ?: start.plusSeconds(45 * 60)
                add(
                    CalendarEvent(
                        uid = "schedule-${event.id}@myleafy.android",
                        title = event.title,
                        startsAt = start,
                        endsAt = end,
                        location = event.location,
                        description = event.note,
                    ),
                )
            }
        }.sortedWith(compareBy(CalendarEvent::startsAt, CalendarEvent::uid))

        val rawLines = buildList {
            add("BEGIN:VCALENDAR")
            add("VERSION:2.0")
            add("PRODID:-//MyLeafy//Android $semesterId//ZH-CN")
            add("CALSCALE:GREGORIAN")
            add("METHOD:PUBLISH")
            add("X-WR-CALNAME:${escapeText("MyLeafy $semesterId")}")
            add("X-WR-TIMEZONE:Asia/Shanghai")
            events.forEach { event ->
                add("BEGIN:VEVENT")
                add("UID:${escapeText(event.uid)}")
                add("DTSTAMP:${utcFormatter.format(clock.instant())}")
                add("DTSTART;TZID=Asia/Shanghai:${localFormatter.format(event.startsAt.atZone(campusZone))}")
                add("DTEND;TZID=Asia/Shanghai:${localFormatter.format(event.endsAt.atZone(campusZone))}")
                add("SUMMARY:${escapeText(event.title)}")
                event.location?.takeIf(String::isNotBlank)?.let { add("LOCATION:${escapeText(it)}") }
                event.description?.takeIf(String::isNotBlank)?.let { add("DESCRIPTION:${escapeText(it)}") }
                add("END:VEVENT")
            }
            add("END:VCALENDAR")
        }
        return rawLines.flatMap(::foldLine).joinToString("\r\n", postfix = "\r\n")
    }

    private fun escapeText(value: String): String = value
        .replace("\\", "\\\\")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
        .replace("\n", "\\n")
        .replace(";", "\\;")
        .replace(",", "\\,")

    private fun foldLine(line: String): List<String> {
        if (line.toByteArray(Charsets.UTF_8).size <= maxOctets) return listOf(line)
        val result = mutableListOf<String>()
        var current = StringBuilder()
        var currentBytes = 0
        var index = 0
        while (index < line.length) {
            val codePoint = line.codePointAt(index)
            val token = String(Character.toChars(codePoint))
            val tokenBytes = token.toByteArray(Charsets.UTF_8).size
            val capacity = if (result.isEmpty()) maxOctets else maxOctets - 1
            if (currentBytes + tokenBytes > capacity && current.isNotEmpty()) {
                result += (if (result.isEmpty()) "" else " ") + current.toString()
                current = StringBuilder()
                currentBytes = 0
            }
            current.append(token)
            currentBytes += tokenBytes
            index += Character.charCount(codePoint)
        }
        if (current.isNotEmpty()) result += (if (result.isEmpty()) "" else " ") + current.toString()
        return result
    }

    private data class CalendarEvent(
        val uid: String,
        val title: String,
        val startsAt: Instant,
        val endsAt: Instant,
        val location: String?,
        val description: String?,
    )

    private companion object {
        const val maxOctets = 75
        val campusZone: ZoneId = ZoneId.of("Asia/Shanghai")
        val localFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss")
        val utcFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
            .withZone(ZoneId.of("UTC"))
    }
}
