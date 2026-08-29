package com.myleafy.android.parsers

import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in parser probe. Live HTML stays outside the repository. */
class LiveSchoolHtmlProbeTest {
    private val parser = JsoupHtmlParser()
    private val probeDirectory = System.getenv("MYLEAFY_LIVE_PROBE_DIR")

    @Test
    fun currentTimetableParses() = withProbe("timetable-current.html") {
        parser.parseTimetable(it)
    }

    @Test
    fun previousTimetableParses() = withProbe("timetable-previous.html") {
        check(parser.parseTimetable(it).isNotEmpty())
    }

    @Test
    fun gradesParse() = withProbe("grades.html") {
        check(parser.parseGrades(it).isNotEmpty())
    }

    @Test
    fun gradeRankingsAndSummaryParse() = withProbe("grades.html") {
        check(parser.parseGradeRankings(it).isNotEmpty())
        parser.parseGradeSummary(it)
    }

    @Test
    fun examsParse() = withProbe("exams.html") {
        parser.parseExams(it)
    }

    @Test
    fun classroomsParse() = withProbe("classrooms.html") {
        check(parser.parseEmptyClassrooms(it).isNotEmpty())
    }

    private fun withProbe(name: String, block: (String) -> Unit) {
        assumeTrue("MYLEAFY_LIVE_PROBE_DIR is not set", !probeDirectory.isNullOrBlank())
        val file = File(requireNotNull(probeDirectory), name)
        check(file.isFile) { "Missing live probe: $name" }
        block(file.readText(Charsets.UTF_8))
    }
}
