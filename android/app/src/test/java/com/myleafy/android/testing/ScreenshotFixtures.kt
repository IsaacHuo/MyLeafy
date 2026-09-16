package com.myleafy.android.testing

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.SemanticsNodeInteractionsProvider
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import com.myleafy.android.core.data.local.CourseEntity
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryEntity
import com.myleafy.android.core.data.local.ScheduleEventEntity
import com.myleafy.android.core.data.local.ScheduleMemoEntity
import com.myleafy.android.features.timetable.domain.TimetableGridItem
import com.myleafy.android.features.timetable.domain.TimetableGridItemType
import com.myleafy.android.features.timetable.domain.TimetableGridSnapshot
import com.myleafy.android.features.timetable.domain.TimetableWeekRange
import com.myleafy.android.shared.model.PostDto
import com.myleafy.android.shared.model.ProfileDto
import com.myleafy.android.ui.theme.MyLeafyTheme
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/**
 * Deterministic fixture data shared by the Roborazzi goldens.
 *
 * Everything here is fixed: date, clock, identity and content strings. Screenshot
 * tests must never read the real clock, network, or account state.
 */
object ScreenshotData {
    val campusZone: ZoneId = ZoneId.of("Asia/Shanghai")

    /** Fixed Monday of academic week 1, used as the timetable origin. */
    val monday: LocalDate = LocalDate.of(2026, 9, 7)

    val courseStartTime: LocalTime = LocalTime.of(9, 10)

    fun day(offset: Int): LocalDate = monday.plusDays(offset.toLong())

    /** A refresh error long enough to wrap several lines on a 360dp screen. */
    const val LONG_ERROR_MESSAGE: String =
        "刷新失败：无法连接教务系统（连接超时 30 秒），已保留上次同步的课程、成绩与考试数据。" +
            "请检查校园网或学校 VPN 后重试；如果长时间没有恢复，可以在“缓存与同步”里查看最近一次成功同步时间。"

    const val LONG_EMPTY_MESSAGE: String =
        "本学期还没有任何课程记录。完成一次教务同步后，课表、成绩与考试会一起出现在这里。"

    const val LONG_COURSE_TITLE: String = "森林生态学野外综合实习（含群落调查与数据处理）"

    const val LONG_POST_TITLE: String =
        "关于本学期图书馆延长开放时间与自习座位预约规则的整理说明（含周末与考试周安排）"

    const val LONG_SNACKBAR_MESSAGE: String =
        "同步失败：连接教务系统超时，已保留上次内容。请检查校园网后重试。"
}

fun gridItem(
    id: String,
    title: String,
    subtitle: String?,
    dayIndex: Int,
    startPeriod: Int,
    periodSpan: Int,
    type: TimetableGridItemType = TimetableGridItemType.COURSE,
    lane: Int = 0,
    laneCount: Int = 1,
) = TimetableGridItem(
    stableId = "${type.name.lowercase()}::$id::1",
    sourceId = id,
    type = type,
    title = title,
    subtitle = subtitle,
    dayIndex = dayIndex,
    startPeriod = startPeriod,
    periodSpan = periodSpan,
    lane = lane,
    laneCount = laneCount,
)

fun timetableSnapshot(
    week: Int = 1,
    items: List<TimetableGridItem>,
) = TimetableGridSnapshot(
    weekRange = TimetableWeekRange(week = week, startDate = ScreenshotData.monday),
    items = items,
)

/** Week 1 grid with a today marker, live timeline and one two-column conflict. */
fun weekOneSnapshot(longNames: Boolean = false): TimetableGridSnapshot {
    val long = longNames
    return timetableSnapshot(
        items = listOf(
            gridItem(
                id = "forest",
                title = if (long) ScreenshotData.LONG_COURSE_TITLE else "森林生态学",
                subtitle = "一教 101",
                dayIndex = 0,
                startPeriod = 1,
                periodSpan = 2,
            ),
            gridItem(
                id = "math",
                title = if (long) "高等数学（概率统计与线性代数基础）" else "高等数学",
                subtitle = "二教 305",
                dayIndex = 1,
                startPeriod = 3,
                periodSpan = 2,
                lane = 0,
                laneCount = 2,
            ),
            gridItem(
                id = "lab",
                title = if (long) "植物学实验（显微观察与标本制作）" else "植物实验",
                subtitle = "实验楼 B204",
                dayIndex = 1,
                startPeriod = 3,
                periodSpan = 3,
                lane = 1,
                laneCount = 2,
            ),
            gridItem(
                id = "english",
                title = "大学英语",
                subtitle = "学研 A206",
                dayIndex = 3,
                startPeriod = 7,
                periodSpan = 2,
            ),
            gridItem(
                id = "sport",
                title = "体育",
                subtitle = "田径场",
                dayIndex = 4,
                startPeriod = 10,
                periodSpan = 2,
            ),
            gridItem(
                id = "exam",
                title = "生态学基础",
                subtitle = "二教 501",
                dayIndex = 5,
                startPeriod = 5,
                periodSpan = 2,
                type = TimetableGridItemType.EXAM,
            ),
        ),
    )
}

fun postFixture(
    id: String,
    title: String,
    category: String,
    body: String = "固定测试内容用于验证作者、时间、分类、正文与互动数据的视觉节奏。",
    likes: Int = 12,
    comments: Int = 4,
    nickname: String = "北林同学",
    createdAt: String = "2026-09-04T08:30:00+08:00",
) = PostDto(
    id = id,
    author_id = "author-$id",
    title = title,
    body = body,
    category = category,
    created_at = createdAt,
    like_count = likes,
    comment_count = comments,
    author = ProfileDto(id = "author-$id", nickname = nickname),
)

fun profileFixture(
    nickname: String = "北林同学",
    displayName: String? = null,
    bio: String? = "生态学与摄影爱好者，常出没于实验楼与田径场。",
    major: String? = "林学",
    grade: String? = "2024 级",
    isComplete: Boolean = true,
) = ProfileDto(
    id = "profile-1",
    edu_id = "20240101",
    campus_id = "bjfu",
    nickname = nickname,
    display_name = displayName,
    bio = bio,
    major = major,
    grade = grade,
    is_profile_complete = isComplete,
)

fun memoEntity(
    id: String,
    title: String?,
    body: String,
    updatedAt: Long = 1_788_000_000_000L,
    pinnedAt: Long? = null,
) = ScheduleMemoEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    body = body,
    kind = "quickMemo",
    title = title,
    tags = "学习\n实验",
    createdAt = updatedAt,
    updatedAt = updatedAt,
    pinnedAt = pinnedAt,
    trashedAt = null,
    linkedScheduleKind = null,
    linkedScheduleId = null,
)

fun eventEntity(
    id: String,
    title: String,
    startsAt: Long = 1_788_000_000_000L,
    location: String? = "二教 305",
    note: String? = "带上实验记录本",
) = ScheduleEventEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    title = title,
    startsAt = startsAt,
    endsAt = startsAt + 90 * 60 * 1000L,
    location = location,
    note = note,
    minutesBefore = 30,
)

fun courseEntity(
    id: String = "course-1",
    courseName: String = "森林生态学",
    teacher: String = "李老师",
    room: String = "101",
    location: String = "一教",
) = CourseEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    sourceSemesterID = "2026-2027-1",
    courseName = courseName,
    teacher = teacher,
    classInfo = "林学 24-1 班",
    room = room,
    location = location,
    dayOfWeek = 1,
    weeks = listOf(1, 2, 3, 5, 7, 9, 11, 13, 15),
    duration = listOf(1, 2),
)

fun examEntity(
    id: Int = 1,
    name: String = "生态学基础",
    date: String = "2026-01-12",
) = ExamEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    courseId = "course-1",
    name = name,
    date = date,
    start = "09:00",
    end = "11:00",
    location = "二教 501",
)

fun gradeEntity(
    id: String,
    courseName: String,
    credit: String = "3.0",
    score: String = "92",
    term: String = "2025-2026-2",
) = GradeEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    term = term,
    courseName = courseName,
    credit = credit,
    score = score,
    type = "必修",
)

fun rankingEntity(
    id: String = "ranking-1",
    term: String = "2025-2026-2",
    rank: Int = 12,
    totalCount: Int? = 120,
) = GradeRankingEntity(
    scopeKey = "bjfu:20240101",
    id = id,
    term = term,
    rankingRange = "专业排名",
    rank = rank,
    totalCount = totalCount,
    metricText = "加权平均 88.6",
)

fun gradeSummary(
    gpa: Double? = 3.72,
    weightedAverage: Double? = 88.6,
    creditPoint: Double? = 142.5,
) = GradeSummaryEntity(
    scopeKey = "bjfu:20240101",
    officialGpa = gpa,
    officialWeightedAverage = weightedAverage,
    officialCreditPoint = creditPoint,
)

/**
 * Screenshot wrapper: theme + opaque page background so dialog scrims and sheet
 * surfaces composite over a realistic page instead of a transparent window.
 */
@Composable
fun LeafyScreenshotTheme(
    darkTheme: Boolean = false,
    fontScale: Float = 1f,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    CompositionLocalProvider(
        LocalDensity provides Density(density.density, fontScale),
    ) {
        MyLeafyTheme(darkTheme = darkTheme) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = MaterialTheme.colorScheme.background,
                content = content,
            )
        }
    }
}

/**
 * Asserts the node's text layout does not overflow its constraints, i.e. the text
 * is not ellipsized or clipped. This is the semantic counterpart to eyeballing a
 * large-font screenshot.
 */
fun SemanticsNodeInteraction.assertTextLayoutFits(): SemanticsNodeInteraction {
    val node = fetchSemanticsNode()
    val action = requireNotNull(node.config.getOrNull(SemanticsActions.GetTextLayoutResult)) {
        "Node has no text layout result: ${node.config}"
    }
    val results = mutableListOf<TextLayoutResult>()
    requireNotNull(action.action).invoke(results)
    val layout = requireNotNull(results.firstOrNull()) { "Text layout result was empty" }
    check(!layout.hasVisualOverflow) {
        "Text overflows its layout: \"${node.config}\" " +
            "(${layout.lineCount} lines, size=${layout.size})"
    }
    return this
}

/**
 * Resolves the scrollable container that owns [descendantTag], so large-font tests
 * can scroll to off-screen content instead of only asserting the first screen.
 */
fun SemanticsNodeInteractionsProvider.scrollableContaining(
    descendantTag: String,
): SemanticsNodeInteraction = onNode(hasScrollAction() and hasAnyDescendant(hasTestTag(descendantTag)))
