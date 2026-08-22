import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testTimetableResponsiveLayoutSwitchesToAgendaWhenSevenDayGridIsTooNarrow() {
        let widths: [CGFloat] = [320, 375, 507, 700, 1024, 1366]
        let modes = widths.map { width in
            timetableMetrics(width: width, height: 800, dayCount: 7, allowsAgendaList: true).mode
        }

        XCTAssertEqual(modes, [.agendaList, .agendaList, .agendaList, .weekGrid, .weekGrid, .weekGrid])
    }

    func testTimetableResponsiveLayoutKeepsPhoneGridWhenAgendaIsDisabled() {
        let metrics = timetableMetrics(width: 320, height: 800, dayCount: 7, allowsAgendaList: false)

        XCTAssertEqual(metrics.mode, .weekGrid)
    }

    func testTimetableResponsiveLayoutKeepsWeekdayGridAtMediumSplitWidth() {
        let metrics = timetableMetrics(width: 507, height: 800, dayCount: 5)

        XCTAssertEqual(metrics.mode, .weekGrid)
        XCTAssertGreaterThanOrEqual(metrics.dayColumnWidth, 72)
    }

    func testTimetableResponsiveLayoutAllowsVerticalScrollWhenHeightIsSmall() {
        let metrics = timetableMetrics(width: 700, height: 320, dayCount: 5)

        XCTAssertEqual(metrics.mode, .agendaList)
        XCTAssertEqual(metrics.rowHeight, 26)
        XCTAssertTrue(metrics.allowsVerticalScroll)
        XCTAssertGreaterThan(metrics.gridHeight, 320 - 52)
    }

    func testTimetableResponsiveLayoutHandlesDisplayScaleChanges() {
        let widths: [CGFloat] = [320, 375, 430, 700]
        let dayCounts = [5, 7]
        let controlScales: [CGFloat] = [0.88, 0.94, 1.0, 1.06]
        let height: CGFloat = 800

        for controlScale in controlScales {
            for dayCount in dayCounts {
                for width in widths {
                    let metrics = timetableMetrics(
                        width: width,
                        height: height,
                        dayCount: dayCount,
                        controlScale: controlScale
                    )
                    let repeatedMetrics = timetableMetrics(
                        width: width,
                        height: height,
                        dayCount: dayCount,
                        controlScale: controlScale
                    )

                    XCTAssertEqual(metrics, repeatedMetrics)
                    XCTAssertGreaterThan(metrics.rowHeight, 0)
                    XCTAssertGreaterThan(metrics.weekStride, 0)
                    XCTAssertGreaterThan(metrics.containerWidth, 0)
                    XCTAssertEqual(metrics.containerHeight, height)
                    XCTAssertGreaterThan(metrics.gridHeight, 0)
                    XCTAssertLessThan(metrics.rowHeight, height)
                    XCTAssertLessThan(metrics.gridHeight, height * 2)
                }
            }
        }
    }

    @MainActor
    func testOverlappingCoursesShareLaneCount() {
        let first = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let second = Course(
            courseName: "B",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [2, 3]
        )
        let third = Course(
            courseName: "C",
            teacher: "T",
            room: "103",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [5]
        )

        let layouts = DayCourseLayoutBuilder.layouts(for: [first, second, third].sortedByStartPeriod())

        XCTAssertEqual(layouts.count, 3)
        XCTAssertEqual(layouts[0].laneCount, 2)
        XCTAssertEqual(layouts[1].laneCount, 2)
        XCTAssertEqual(layouts[2].laneCount, 1)
    }

    @MainActor
    func testGridSnapshotHidesWeekendsAndKeepsLatestReminder() {
        let mondayCourse = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1]
        )
        let saturdayCourse = Course(
            courseName: "B",
            teacher: "T",
            room: "102",
            location: "",
            dayOfWeek: 6,
            weeks: [1],
            duration: [1]
        )
        let oldReminder = TimetableCellReminder(
            week: 1,
            dayOfWeek: 1,
            period: 2,
            title: "Old",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newReminder = TimetableCellReminder(
            week: 1,
            dayOfWeek: 1,
            period: 2,
            title: "New",
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let snapshot = TimetableGridSnapshot.make(
            courses: [mondayCourse, saturdayCourse],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [oldReminder, newReminder],
            hidesWeekends: true,
            totalWeeks: 1
        )

        XCTAssertEqual(snapshot.visibleDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(snapshot.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertEqual(snapshot.layouts(day: 6, week: 1).map(\.course.courseName), ["B"])
        XCTAssertEqual(snapshot.cellReminder(week: 1, day: 1, period: 2)?.title, "New")
        XCTAssertEqual(snapshot.cellReminders(week: 1, day: 1).map(\.title), ["New"])
    }

    func testThreeDayTimelineStartsAroundAnchorAndPagesByThreeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let friday = try XCTUnwrap(formatter.date(from: "2026-08-21"))
        let saturday = try XCTUnwrap(formatter.date(from: "2026-08-22"))
        let rangeStart = try XCTUnwrap(formatter.date(from: "2026-01-01"))
        let rangeEnd = try XCTUnwrap(formatter.date(from: "2027-12-31"))

        let fridayTimeline = TimetableThreeDayTimeline(
            anchorDate: friday,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: calendar
        )
        XCTAssertEqual(
            fridayTimeline.page(fridayTimeline.initialPage, calendar: calendar).dates.map { formatter.string(from: $0) },
            ["2026-08-20", "2026-08-21", "2026-08-22"]
        )
        XCTAssertEqual(
            fridayTimeline.page(fridayTimeline.initialPage + 1, calendar: calendar).dates.map { formatter.string(from: $0) },
            ["2026-08-23", "2026-08-24", "2026-08-25"]
        )
        XCTAssertEqual(
            fridayTimeline.page(fridayTimeline.initialPage - 1, calendar: calendar).dates.map { formatter.string(from: $0) },
            ["2026-08-17", "2026-08-18", "2026-08-19"]
        )

        let saturdayTimeline = TimetableThreeDayTimeline(
            anchorDate: saturday,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: calendar
        )
        XCTAssertEqual(
            saturdayTimeline.page(saturdayTimeline.initialPage, calendar: calendar).dates.map { formatter.string(from: $0) },
            ["2026-08-21", "2026-08-22", "2026-08-23"]
        )
    }

    func testThreeDayTimelineHandlesMonthAndYearBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let anchor = try XCTUnwrap(formatter.date(from: "2026-12-31"))
        let timeline = TimetableThreeDayTimeline(
            anchorDate: anchor,
            rangeStart: try XCTUnwrap(formatter.date(from: "2026-09-01")),
            rangeEnd: try XCTUnwrap(formatter.date(from: "2027-08-31")),
            calendar: calendar
        )

        let page = timeline.page(timeline.initialPage, calendar: calendar)
        XCTAssertEqual(
            page.dates.map { formatter.string(from: $0) },
            ["2026-12-30", "2026-12-31", "2027-01-01"]
        )
        XCTAssertEqual(formatter.string(from: page.centerDate), "2026-12-31")
        XCTAssertEqual(timeline.page(containingCenterDate: page.centerDate, calendar: calendar), timeline.initialPage)
        XCTAssertEqual(
            formatter.string(from: timeline.page(timeline.initialPage + 1, calendar: calendar).centerDate),
            "2027-01-03"
        )
    }

    func testZoomTransitionPolicySupportsCommitCancelAndReverseProgress() {
        XCTAssertEqual(
            TimetableZoomTransitionPolicy.progress(direction: .zoomIn, magnification: 1),
            0,
            accuracy: 0.001
        )
        XCTAssertTrue(
            TimetableZoomTransitionPolicy.shouldCommit(
                direction: .zoomIn,
                magnification: 1.13,
                progress: 0.2
            )
        )
        XCTAssertFalse(
            TimetableZoomTransitionPolicy.shouldCommit(
                direction: .zoomIn,
                magnification: 1.05,
                progress: 0.2
            )
        )
        let reversedZoomOut = TimetableZoomTransitionPolicy.progress(
            direction: .zoomOut,
            magnification: 0.98
        )
        XCTAssertGreaterThan(reversedZoomOut, 0.55)
        XCTAssertFalse(
            TimetableZoomTransitionPolicy.shouldCommit(
                direction: .zoomOut,
                magnification: 0.98,
                progress: reversedZoomOut
            )
        )
        XCTAssertTrue(
            TimetableZoomTransitionPolicy.shouldCommit(
                direction: .zoomOut,
                magnification: 0.87,
                progress: 0.7
            )
        )
    }

    func testZoomAnchorUsesGestureColumnForSevenAndFiveDayWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let monday = try XCTUnwrap(formatter.date(from: "2026-08-17"))
        let sevenDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        let fiveDays = Array(sevenDays.prefix(5))

        let sevenDayAnchor = try XCTUnwrap(TimetableZoomAnchorResolver.anchorDate(
            gestureX: 10 + 4 * 52 + 20,
            contentStartX: 10,
            dayColumnWidth: 48,
            daySpacing: 4,
            visibleDates: sevenDays,
            hidesWeekends: false,
            isCurrentWeek: true,
            today: monday,
            calendar: calendar
        ))
        XCTAssertEqual(formatter.string(from: sevenDayAnchor), "2026-08-21")

        let fiveDayAnchor = try XCTUnwrap(TimetableZoomAnchorResolver.anchorDate(
            gestureX: 10 + 2 * 52 + 20,
            contentStartX: 10,
            dayColumnWidth: 48,
            daySpacing: 4,
            visibleDates: fiveDays,
            hidesWeekends: true,
            isCurrentWeek: true,
            today: monday,
            calendar: calendar
        ))
        XCTAssertEqual(formatter.string(from: fiveDayAnchor), "2026-08-19")
    }

    func testZoomAnchorUsesWeekendTodayWhenWeekendColumnsAreHidden() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let monday = try XCTUnwrap(formatter.date(from: "2026-08-17"))
        let saturday = try XCTUnwrap(formatter.date(from: "2026-08-22"))
        let weekdays = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }

        let anchor = try XCTUnwrap(TimetableZoomAnchorResolver.anchorDate(
            gestureX: 10,
            contentStartX: 10,
            dayColumnWidth: 48,
            daySpacing: 4,
            visibleDates: weekdays,
            hidesWeekends: true,
            isCurrentWeek: true,
            today: saturday,
            calendar: calendar
        ))
        XCTAssertEqual(formatter.string(from: anchor), "2026-08-22")
    }

    @MainActor
    func testGridSnapshotRemainsReadableAfterManagedModelsAreDeleted() throws {
        let schema = Schema([Course.self, TimetableCellReminder.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let course = Course(
            courseName: "数据库原理",
            teacher: "教师",
            room: "101",
            location: "学研中心",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let reminder = TimetableCellReminder(
            week: 1,
            dayOfWeek: 1,
            period: 3,
            title: "提交作业"
        )
        context.insert(course)
        context.insert(reminder)
        try context.save()

        let snapshot = TimetableGridSnapshot.make(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [reminder],
            hidesWeekends: false,
            totalWeeks: 1
        )

        context.delete(course)
        context.delete(reminder)
        try context.save()

        XCTAssertEqual(snapshot.layouts(day: 1, week: 1).first?.course.courseName, "数据库原理")
        XCTAssertEqual(snapshot.layouts(day: 1, week: 1).first?.course.duration, [1, 2])
        XCTAssertEqual(snapshot.cellReminder(week: 1, day: 1, period: 3)?.title, "提交作业")
    }

    @MainActor
    func testCourseReminderAnchorDefaultsToFirstPeriodForOldSettings() {
        let course = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [2, 3]
        )
        let oldSetting = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 20)

        XCTAssertNil(oldSetting.anchorPeriod)
        XCTAssertEqual(TimetableNotificationManager.resolvedAnchorPeriod(oldSetting.anchorPeriod, for: course), 2)
    }

    @MainActor
    func testCourseReminderTriggerDateUsesSelectedAnchorPeriod() throws {
        let course = Course(
            courseName: "森林生态学",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        let triggerDate = try XCTUnwrap(TimetableNotificationManager.reminderTriggerDate(
            for: course,
            week: 1,
            minutesBefore: 5,
            anchorPeriod: 2
        ))
        let expectedDate = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 9, hour: 8, minute: 45)
        ))

        XCTAssertEqual(triggerDate, expectedDate)
    }

    func testCustomReminderMinutesAreClampedToSupportedRange() {
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(-5), 0)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(0), 0)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(1), 1)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(180), 180)
        XCTAssertEqual(TimetableNotificationManager.normalizedReminderMinutes(181), 180)
    }

    @MainActor
    func testGridSnapshotDistinguishesCourseAndOccurrenceNotes() {
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: "带球鞋"
        )

        let allWeeksSnapshot = TimetableGridSnapshot.make(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        XCTAssertTrue(allWeeksSnapshot.hasNote(for: course, week: 1))
        XCTAssertTrue(allWeeksSnapshot.hasNote(for: course, week: 2))
        XCTAssertEqual(allWeeksSnapshot.note(for: course, week: 1), "带衣服")

        let occurrenceOnlySnapshot = TimetableGridSnapshot.make(
            courses: [course],
            notes: [],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 2
        )
        XCTAssertTrue(occurrenceOnlySnapshot.hasNote(for: course, week: 1))
        XCTAssertFalse(occurrenceOnlySnapshot.hasNote(for: course, week: 2))
        XCTAssertEqual(occurrenceOnlySnapshot.note(for: course, week: 1), "带球鞋")
    }

    func testEffectiveCourseNotePrefersOccurrenceThenFallsBackToCourse() {
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 2),
            week: 2,
            dayOfWeek: 1,
            text: "带球鞋"
        )
        let emptyOccurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: " "
        )

        XCTAssertEqual(
            TimetableNoteResolver.effectiveNote(
                for: course,
                week: 2,
                courseNotes: [courseNote],
                occurrenceNotes: [occurrenceNote]
            ),
            "带球鞋"
        )
        XCTAssertEqual(
            TimetableNoteResolver.effectiveNote(
                for: course,
                week: 1,
                courseNotes: [courseNote],
                occurrenceNotes: [emptyOccurrenceNote]
            ),
            "带衣服"
        )
    }

    func testNearestAvailableWeekPrefersExactThenClosest() {
        let records = [
            ParsedCourseRecord(courseName: "A", teacher: "", classInfo: "", room: "", location: "", dayOfWeek: 1, weeks: [2, 6], duration: [1]),
            ParsedCourseRecord(courseName: "B", teacher: "", classInfo: "", room: "", location: "", dayOfWeek: 2, weeks: [10], duration: [2])
        ]

        XCTAssertEqual(TimetableRefreshUseCase.nearestAvailableWeek(from: records, preferredWeek: 6), 6)
        XCTAssertEqual(TimetableRefreshUseCase.nearestAvailableWeek(from: records, preferredWeek: 8), 6)
    }

    @MainActor
    func testTimetableRefreshSummaryDistinguishesCurrentAndChangedData() {
        let existing = Course(
            courseName: "数据结构",
            teacher: "林老师",
            classInfo: "计科 1 班",
            room: "205",
            location: "二教",
            dayOfWeek: 1,
            weeks: [1, 2, 3],
            duration: [1, 2],
            sourceSemesterID: "2026-2027-1"
        )
        let unchangedRecord = ParsedCourseRecord(
            courseName: "数据结构",
            teacher: "林老师",
            classInfo: "计科 1 班",
            room: "205",
            location: "二教",
            dayOfWeek: 1,
            weeks: [3, 2, 1],
            duration: [2, 1]
        )

        let unchanged = TimetableRefreshSummary.compare(
            records: [unchangedRecord],
            existingCourses: [existing],
            semesterID: "2026-2027-1"
        )
        XCTAssertEqual(unchanged.courseCount, 1)
        XCTAssertEqual(unchanged.scheduleCount, 1)
        XCTAssertFalse(unchanged.hasChanges)

        let changedRecord = ParsedCourseRecord(
            courseName: unchangedRecord.courseName,
            teacher: unchangedRecord.teacher,
            classInfo: unchangedRecord.classInfo,
            room: "306",
            location: unchangedRecord.location,
            dayOfWeek: unchangedRecord.dayOfWeek,
            weeks: unchangedRecord.weeks,
            duration: unchangedRecord.duration
        )
        let changed = TimetableRefreshSummary.compare(
            records: [changedRecord],
            existingCourses: [existing],
            semesterID: "2026-2027-1"
        )
        XCTAssertTrue(changed.hasChanges)
    }

    @MainActor
    func testTimetableRefreshSummaryReportsEmptyResponse() {
        let summary = TimetableRefreshSummary.compare(
            records: [],
            existingCourses: [],
            semesterID: "2026-2027-1"
        )

        XCTAssertEqual(summary.courseCount, 0)
        XCTAssertEqual(summary.scheduleCount, 0)
        XCTAssertFalse(summary.hasChanges)
    }

    @MainActor
    func testTimetableRefreshPersistsCoursesPerSemester() throws {
        let schema = Schema([Course.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let useCase = TimetableRefreshUseCase()

        let courseA = ParsedCourseRecord(
            courseName: "学期 A 课程",
            teacher: "教师 A",
            classInfo: "",
            room: "101",
            location: "教学楼",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1]
        )
        let courseB = ParsedCourseRecord(
            courseName: "学期 B 课程",
            teacher: "教师 B",
            classInfo: "",
            room: "202",
            location: "教学楼",
            dayOfWeek: 2,
            weeks: [2],
            duration: [2]
        )

        try useCase.persist(records: [courseA], existingCourses: [], modelContext: context, semesterID: "A")
        var courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(courses.map(\.sourceSemesterID), ["A"])

        try useCase.persist(records: [courseB], existingCourses: courses, modelContext: context, semesterID: "B")
        courses = try context.fetch(FetchDescriptor<Course>())
        XCTAssertEqual(Set(courses.map(\.sourceSemesterID)), ["A", "B"])
        let courseBID = try XCTUnwrap(courses.first(where: { $0.sourceSemesterID == "B" })?.id)

        let replacementA = ParsedCourseRecord(
            courseName: "学期 A 新课程",
            teacher: "教师 A2",
            classInfo: "",
            room: "303",
            location: "教学楼",
            dayOfWeek: 3,
            weeks: [3],
            duration: [3]
        )
        try useCase.persist(records: [replacementA], existingCourses: courses, modelContext: context, semesterID: "A")
        courses = try context.fetch(FetchDescriptor<Course>())

        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses.filter { $0.sourceSemesterID == "A" }.map(\.courseName), ["学期 A 新课程"])
        XCTAssertEqual(courses.first(where: { $0.sourceSemesterID == "B" })?.id, courseBID)
    }

    @MainActor
    func testSchoolNetworkRequestsBypassLocalCache() throws {
        let manager = SchoolNetworkManager.shared
        let url = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do"))

        let request = manager.makeRequest(url: url)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")

        let preparedRequest = manager.preparedRequest(from: URLRequest(url: url))
        XCTAssertEqual(preparedRequest.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(preparedRequest.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(preparedRequest.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    @MainActor
    func testTimetableQueryFormPrefersCurrentSemesterOption() throws {
        let html = """
        <form action="/jsxsd/xskb/xskb_list.do" method="post">
          <input type="hidden" name="zc" value="">
          <select name="xnxq01id">
            <option value="2025-2026-2" selected>旧学期</option>
            <option value="2026-2027-1">当前学期</option>
          </select>
        </form>
        """

        let request = try XCTUnwrap(
            SchoolNetworkManager.shared.resolveTimetableRequest(
                from: html,
                preferredSemesterID: "2026-2027-1"
            )
        )
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(body.contains("xnxq01id=2026-2027-1"))
        XCTAssertFalse(body.contains("xnxq01id=2025-2026-2"))
    }

    func testNextSemesterTimetableFixtureUsesExistingParser() throws {
        let html = """
        <html>
          <body>
            <div id="kbcontent_1_1">
              森林生态学<br>
              王老师<br>
              1-18周<br>
              二教205
            </div>
            <div id="kbcontent_3_2">
              数据结构<br>
              李老师<br>
              2-16周<br>
              第二教学楼301
            </div>
          </body>
        </html>
        """

        let courses = try HTMLParser.parseTimetable(html: html)
        let debugDescription = courses.map {
            "\($0.courseName)|\($0.location)|\($0.room)|\($0.weeks.sorted())"
        }.joined(separator: "; ")

        XCTAssertEqual(courses.map(\.courseName).sorted(), ["数据结构", "森林生态学"])
        XCTAssertTrue(courses.contains { $0.location == "二教" && $0.room == "205" && $0.weeks.contains(18) }, debugDescription)
        XCTAssertTrue(courses.contains { $0.location == "二教" && $0.room == "301" && $0.weeks.contains(16) }, debugDescription)
        XCTAssertFalse(courses.contains { $0.weeks.contains(20) })
    }

    func testRecognizedEmptyTimetableParsesAsEmptyCourseList() throws {
        let html = """
        <html><body><div id="kbcontent_1_1"></div></body></html>
        """

        XCTAssertEqual(try HTMLParser.parseTimetable(html: html).count, 0)
    }

    func testRecognizedEmptyGraduateTimetableParsesAsEmptyCourseList() throws {
        XCTAssertEqual(try HTMLParser.parseTimetable(html: #"{"rows":[]}"#).count, 0)
    }

    func testUnrecognizedTimetablePageThrowsInsteadOfReturningEmptyList() {
        let html = "<html><body><form id=\"login\"></form></body></html>"

        XCTAssertThrowsError(try HTMLParser.parseTimetable(html: html)) { error in
            guard case HTMLParserError.timetableTableNotFound = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMalformedTimetableContentThrowsInsteadOfReturningEmptyList() {
        let html = """
        <html><body><div id="kbcontent_1_1">无法识别的课程结构</div></body></html>
        """

        XCTAssertThrowsError(try HTMLParser.parseTimetable(html: html)) { error in
            guard case HTMLParserError.tableRowsUnparseable("课表") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testGradeParserRejectsMissingTable() {
        XCTAssertThrowsError(try HTMLParser.parseGrades(html: "<html><body></body></html>")) { error in
            guard case HTMLParserError.tableNotFound("成绩") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testGradeParserAcceptsRecognizedEmptyTable() throws {
        let html = """
        <table id="dataList">
          <tr><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>成绩</th><th>学分</th></tr>
        </table>
        """

        XCTAssertTrue(try HTMLParser.parseGrades(html: html).isEmpty)
    }

    func testAcademicParserFixturesDistinguishVerifiedEmptyFromMalformedRows() throws {
        XCTAssertTrue(
            try HTMLParser.parseExams(html: jwxtFixture("exams_empty_table.html")).isEmpty
        )
        XCTAssertThrowsError(
            try HTMLParser.parseExams(html: jwxtFixture("exams_malformed_rows.html"))
        ) { error in
            guard case HTMLParserError.tableRowsUnparseable("考试安排") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let teachingPlan = try HTMLParser.parseTeachingPlan(
            html: jwxtFixture("teaching_plan_with_rows.html")
        )
        XCTAssertEqual(teachingPlan.map(\.term), ["2026-2027-1"])
        XCTAssertEqual(teachingPlan.first?.courses.map(\.name), ["森林生态学"])
        XCTAssertTrue(
            try HTMLParser.parseTeachingPlan(
                html: jwxtFixture("teaching_plan_empty_table.html")
            ).isEmpty
        )
        XCTAssertThrowsError(
            try HTMLParser.parseTeachingPlan(
                html: jwxtFixture("teaching_plan_malformed_rows.html")
            )
        ) { error in
            guard case HTMLParserError.tableRowsUnparseable("教学计划") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertTrue(
            try HTMLParser.parseEmptyClassrooms(
                html: jwxtFixture("empty_classrooms_no_available.html")
            ).isEmpty
        )
        XCTAssertTrue(
            try HTMLParser.parseEmptyClassrooms(
                html: jwxtFixture("empty_classrooms_empty_table.html")
            ).isEmpty
        )
        XCTAssertThrowsError(
            try HTMLParser.parseEmptyClassrooms(
                html: jwxtFixture("empty_classrooms_malformed_rows.html")
            )
        ) { error in
            guard case HTMLParserError.tableRowsUnparseable("空教室") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testGradeParserRejectsNonemptyUnparseableFixture() throws {
        XCTAssertThrowsError(
            try HTMLParser.parseGrades(html: jwxtFixture("grades_malformed_rows.html"))
        ) { error in
            guard case HTMLParserError.tableRowsUnparseable("成绩") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func jwxtFixture(_ name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("contracts/jwxt/fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTimetableParserSkipsOutOfRangeContentDayIDs() throws {
        let html = """
        <html>
          <body>
            <div id="kbcontent_0_1">
              越界课程<br>
              王老师<br>
              1-18周<br>
              二教205
            </div>
            <div id="kbcontent_8_1">
              另一个越界课程<br>
              李老师<br>
              1-18周<br>
              二教301
            </div>
            <div id="kbcontent_1_1">
              有效课程<br>
              张老师<br>
              1-2周<br>
              二教101
            </div>
          </body>
        </html>
        """

        let courses = try HTMLParser.parseTimetable(html: html)

        XCTAssertEqual(courses.map(\.courseName), ["有效课程"])
        XCTAssertEqual(courses.first?.dayOfWeek, 1)
        XCTAssertEqual(courses.first?.duration, [1, 2])
    }

    @MainActor
    func testTimetableQueryFormFallsBackToSelectedSemesterWhenPreferredMissing() throws {
        let html = """
        <form action="/jsxsd/xskb/xskb_list.do" method="post">
          <select name="xnxq01id">
            <option value="2025-2026-2" selected>旧学期</option>
            <option value="2025-2026-1">更早学期</option>
          </select>
        </form>
        """

        let request = try XCTUnwrap(
            SchoolNetworkManager.shared.resolveTimetableRequest(
                from: html,
                preferredSemesterID: "2026-2027-1"
            )
        )
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertTrue(body.contains("xnxq01id=2025-2026-2"))
    }

    @MainActor
    func testCachedTimetableLandingURLRejectsMismatchedSemester() throws {
        let manager = SchoolNetworkManager.shared
        let baseURL = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do"))
        let currentURL = manager.timetableURL(baseURL, applyingSemesterID: "2026-2027-1")
        let oldURL = try XCTUnwrap(URL(string: "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do?xnxq01id=2025-2026-2"))

        XCTAssertTrue(manager.shouldUseCachedTimetableLandingURL(baseURL, preferredSemesterID: "2026-2027-1"))
        XCTAssertTrue(manager.shouldUseCachedTimetableLandingURL(currentURL, preferredSemesterID: "2026-2027-1"))
        XCTAssertFalse(manager.shouldUseCachedTimetableLandingURL(oldURL, preferredSemesterID: "2026-2027-1"))
    }

    @MainActor
    func testTimetableSemesterValidationRejectsExplicitMismatch() throws {
        let html = """
        <html>
          <body>
            <select name="xnxq01id">
              <option value="2025-2026-2" selected>旧学期</option>
              <option value="2026-2027-1">新学期</option>
            </select>
            <div id="kbcontent_1_1">课程</div>
          </body>
        </html>
        """

        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.validateTimetableSemester(
                html: html,
                responseURL: nil,
                expectedSemesterID: "2026-2027-1"
            )
        ) { error in
            guard case SchoolNetworkError.timetableSemesterMismatch(let expected, let actual) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(expected, "2026-2027-1")
            XCTAssertEqual(actual, "2025-2026-2")
        }
    }

    func testExamParserAcceptsBackendShape() throws {
        let html = """
        <table id="dataList">
          <tr><th>序号</th><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>考试时间</th><th>考试地点</th></tr>
          <tr><td>1</td><td>2025-2026-2</td><td>DS-001</td><td>数据结构</td><td>2026-06-20 09:00~11:00</td><td>二教 205</td></tr>
        </table>
        """

        let exams = try HTMLParser.parseExams(html: html)

        XCTAssertEqual(exams, [
            ExamArrangement(id: 1, courseID: "DS-001", name: "数据结构", date: "2026-06-20", start: "09:00", end: "11:00", location: "二教 205")
        ])
    }

    func testExamParserAcceptsSplitDateAndTimeColumns() throws {
        let html = """
        <table id="dataList">
          <tr><th>序号</th><th>课程代码</th><th>课程名称</th><th>考试日期</th><th>考试时段</th><th>教室</th></tr>
          <tr><td>2</td><td>MATH-001</td><td>高等数学 A</td><td>2026/06/21</td><td>14:00-16:00</td><td>主楼 112</td></tr>
        </table>
        """

        let exams = try HTMLParser.parseExams(html: html)

        XCTAssertEqual(exams, [
            ExamArrangement(id: 2, courseID: "MATH-001", name: "高等数学 A", date: "2026-06-21", start: "14:00", end: "16:00", location: "主楼 112")
        ])
    }

    func testWidgetSignatureIgnoresGeneratedAtOnlyChanges() {
        let archiveA = makeWidgetSignatureArchive(generatedAt: Date(timeIntervalSince1970: 1))
        var archiveB = archiveA
        archiveB.generatedAt = Date(timeIntervalSince1970: 2)
        archiveB.snapshots[0].snapshot.generatedAt = Date(timeIntervalSince1970: 2)

        XCTAssertEqual(WidgetSnapshotSignature(archive: archiveA), WidgetSnapshotSignature(archive: archiveB))
    }

    func testWidgetSignatureTracksVisibleSnapshotTextChanges() {
        let baseline = makeWidgetSignatureArchive()

        var changedDisplayDate = baseline
        changedDisplayDate.snapshots[0].snapshot.displayDate = "Tomorrow"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedDisplayDate))

        var changedWeek = baseline
        changedWeek.snapshots[0].snapshot.weekText = "Week 2"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedWeek))

        var changedDay = baseline
        changedDay.snapshots[0].snapshot.dayText = "Tue"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedDay))

        var changedExam = baseline
        changedExam.snapshots[0].snapshot.nextExamText = "考试：高数 · 6月1日"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedExam))
    }

    func testWidgetSignatureTracksVisibleCourseChanges() {
        let baseline = makeWidgetSignatureArchive()

        var changedTitle = baseline
        changedTitle.snapshots[0].snapshot.courses[0].title = "B"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedTitle))

        var changedTime = baseline
        changedTime.snapshots[0].snapshot.courses[0].timeText = "09:00"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedTime))

        var changedLocation = baseline
        changedLocation.snapshots[0].snapshot.courses[0].locationText = "202"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedLocation))

        var changedNote = baseline
        changedNote.snapshots[0].snapshot.courses[0].noteText = "带教材"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedNote))

        var changedReminder = baseline
        changedReminder.snapshots[0].snapshot.courses[0].reminderText = "提前 10 分钟"
        XCTAssertNotEqual(WidgetSnapshotSignature(archive: baseline), WidgetSnapshotSignature(archive: changedReminder))
    }

    @MainActor
    func testWidgetSnapshotKeepsMoreThanFourCourses() throws {
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8)))
        let courses = (1...5).map { index in
            Course(
                courseName: "Course \(index)",
                teacher: "T",
                room: "\(index)01",
                location: "Building",
                dayOfWeek: 1,
                weeks: [1],
                duration: [index]
            )
        }

        let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: courses,
            isAuthenticated: true,
            date: date
        )
        let snapshot = try XCTUnwrap(archive.snapshot(for: 0))

        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.courses.count, 5)
        XCTAssertEqual(snapshot.courses.map(\.title), ["Course 1", "Course 2", "Course 3", "Course 4", "Course 5"])
    }

    @MainActor
    func testWidgetSnapshotUsesOccurrenceNoteBeforeCourseNote() throws {
        let firstWeekDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8)))
        let secondWeekDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let course = Course(
            courseName: "体育",
            teacher: "T",
            room: "操场",
            location: "",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带衣服")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 1),
            week: 1,
            dayOfWeek: 1,
            text: "带球鞋"
        )

        let firstWeekArchive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            isAuthenticated: true,
            date: firstWeekDate
        )
        let secondWeekArchive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: [course],
            notes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            isAuthenticated: true,
            date: secondWeekDate
        )

        XCTAssertEqual(try XCTUnwrap(firstWeekArchive.snapshot(for: 0)).courses.first?.noteText, "带球鞋")
        XCTAssertEqual(try XCTUnwrap(secondWeekArchive.snapshot(for: 0)).courses.first?.noteText, "带衣服")
    }

    @MainActor
    func testCalendarExportBuilderBuildsRangeAndLeafyURL() throws {
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let course = Course(
            courseName: "森林生态学",
            teacher: "陈老师",
            room: "101",
            location: "二教",
            dayOfWeek: 1,
            weeks: [1, 2, 3],
            duration: [1, 2]
        )
        let courseNote = CourseNote(courseKey: course.stableCourseKey, text: "带教材")
        let occurrenceNote = CourseOccurrenceNote(
            courseKey: course.stableCourseKey,
            occurrenceKey: course.occurrenceKey(week: 2),
            week: 2,
            dayOfWeek: 1,
            text: "交作业"
        )
        let reminder = TimetableCellReminder(
            week: 2,
            dayOfWeek: 1,
            period: 3,
            endPeriod: 4,
            title: "预习植物分类",
            location: "图书馆二层",
            note: "带笔记本",
            minutesBefore: 20
        )
        let exam = ExamArrangement(
            id: 7,
            courseID: "FOREST-001",
            name: "森林生态学",
            date: "2026-03-16",
            start: "09:00",
            end: "10:30",
            location: "二教 201"
        )

        let currentWeekDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [reminder],
            exams: [exam],
            range: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let remainingDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .remainingSemester,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let fullDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .fullSemester,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )
        let customSingleWeekDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            range: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 3...3
        )
        let customRangeDrafts = TimetableCalendarExportBuilder.drafts(
            courses: [course],
            courseNotes: [courseNote],
            occurrenceNotes: [occurrenceNote],
            cellReminders: [reminder],
            exams: [exam],
            range: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 1...2
        )

        XCTAssertEqual(currentWeekDrafts.map(\.occurrenceKey), [
            course.occurrenceKey(week: 2),
            "exam:7",
            "cellReminder:\(reminder.cellKey)"
        ])
        XCTAssertEqual(remainingDrafts.map(\.occurrenceKey), [course.occurrenceKey(week: 2), course.occurrenceKey(week: 3)])
        XCTAssertEqual(fullDrafts.count, 3)
        XCTAssertEqual(customSingleWeekDrafts.map(\.occurrenceKey), [course.occurrenceKey(week: 3)])
        XCTAssertEqual(customRangeDrafts.map(\.occurrenceKey), [
            course.occurrenceKey(week: 1),
            course.occurrenceKey(week: 2),
            "exam:7",
            "cellReminder:\(reminder.cellKey)"
        ])
        XCTAssertEqual(TimetableCalendarExportBuilder.weekRange(
            for: .customWeeks,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3,
            customWeeks: 0...8
        ), 1...3)

        let draft = try XCTUnwrap(currentWeekDrafts.first)
        XCTAssertEqual(draft.title, "森林生态学")
        XCTAssertEqual(draft.location, "二教 101")
        XCTAssertTrue(draft.notes.contains("教师：陈老师"))
        XCTAssertTrue(draft.notes.contains("节次：第 1-2 节"))
        XCTAssertTrue(draft.notes.contains("周次：第 2 周"))
        XCTAssertTrue(draft.notes.contains("备注：交作业"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: draft.url), draft.occurrenceKey)

        let reminderDraft = try XCTUnwrap(currentWeekDrafts.first { $0.occurrenceKey == "cellReminder:\(reminder.cellKey)" })
        XCTAssertEqual(reminderDraft.title, "预习植物分类")
        XCTAssertEqual(reminderDraft.location, "图书馆二层")
        XCTAssertTrue(reminderDraft.notes.contains("类型：日程"))
        XCTAssertTrue(reminderDraft.notes.contains("地点：图书馆二层"))
        XCTAssertTrue(reminderDraft.notes.contains("节次：第 3-4 节"))
        XCTAssertTrue(reminderDraft.notes.contains("备注：带笔记本"))
        XCTAssertTrue(reminderDraft.notes.contains("本地通知：提前 20 分钟"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: reminderDraft.url), reminderDraft.occurrenceKey)

        let examDraft = try XCTUnwrap(currentWeekDrafts.first { $0.occurrenceKey == "exam:7" })
        XCTAssertEqual(examDraft.title, "考试：森林生态学")
        XCTAssertEqual(examDraft.location, "二教 201")
        XCTAssertTrue(examDraft.notes.contains("类型：考试"))
        XCTAssertTrue(examDraft.notes.contains("课程编号：FOREST-001"))
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: examDraft.url), examDraft.occurrenceKey)

        let currentWeekInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let remainingInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .remainingSemester,
            currentWeek: 1,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let fullInterval = try XCTUnwrap(TimetableCalendarExportBuilder.exportInterval(
            for: .fullSemester,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        ))
        let calendar = Calendar.current
        let semesterStart = calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
        XCTAssertEqual(currentWeekInterval.start, try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: semesterStart)))
        XCTAssertEqual(currentWeekInterval.end, try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: semesterStart)))
        XCTAssertEqual(remainingInterval.start, currentWeekInterval.start)
        XCTAssertEqual(remainingInterval.end, try XCTUnwrap(calendar.date(byAdding: .day, value: 21, to: semesterStart)))
        XCTAssertEqual(fullInterval.start, semesterStart)
        XCTAssertEqual(fullInterval.end, remainingInterval.end)
    }

    @MainActor
    func testCalendarExportBuilderBuildsExamAndReminderDraftsWithoutCourses() throws {
        let referenceDate = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8)))
        let reminder = TimetableCellReminder(week: 2, dayOfWeek: 1, period: 3, title: "社团面试")
        let exam = ExamArrangement(
            id: 8,
            courseID: "MATH-001",
            name: "高等数学",
            date: "2026-03-16",
            start: "14:00",
            end: "16:00",
            location: "主楼 112"
        )

        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: [],
            courseNotes: [],
            occurrenceNotes: [],
            cellReminders: [reminder],
            exams: [exam],
            range: .currentWeek,
            currentWeek: 2,
            referenceDate: referenceDate,
            totalWeeks: 3
        )

        XCTAssertEqual(drafts.map(\.occurrenceKey), [
            "cellReminder:\(reminder.cellKey)",
            "exam:8"
        ])
        XCTAssertEqual(drafts.map(\.title), ["社团面试", "考试：高等数学"])
    }

    @MainActor
    func testManualCourseWeekSelectionNormalizesGapsAndBuildsSummary() {
        XCTAssertEqual(
            ManualCourseWeekSelection.normalized([16, 1, 8, 10, 8, 21, 0, 15, 2, 3, 4, 5, 6, 7, 11, 12, 13, 14]),
            Array(1...8) + Array(10...16)
        )
        XCTAssertEqual(
            ManualCourseWeekSelection.summary(Array(1...8) + Array(10...16)),
            "1–8、10–16 周"
        )
        XCTAssertEqual(ManualCourseWeekSelection.summary([]), "未选择")
    }

    func testCustomCampusCSVParserParsesTimetableGradesAndExams() throws {
        let timetableCSV = """
        courseName,teacher,classInfo,room,location,dayOfWeek,weeks,duration
        数据结构,林青,演示班,二教 205,二教,1,"1-4","1,2"
        """
        let timetable = try CustomCampusCSVParser.parseTimetable(timetableCSV)
        XCTAssertEqual(timetable.count, 1)
        XCTAssertEqual(timetable[0].courseName, "数据结构")
        XCTAssertEqual(timetable[0].dayOfWeek, 1)
        XCTAssertEqual(timetable[0].weeks, [1, 2, 3, 4])
        XCTAssertEqual(timetable[0].duration, [1, 2])

        let gradeCSV = """
        term,courseName,credit,score,type
        2025-2026-2,数据结构,3.0,92,必修
        """
        let grades = try CustomCampusCSVParser.parseGrades(gradeCSV)
        XCTAssertEqual(grades, [
            CustomCampusImportedGrade(term: "2025-2026-2", courseName: "数据结构", credit: "3.0", score: "92", type: "必修")
        ])

        let examCSV = """
        courseID,name,date,start,end,location
        DS-001,数据结构,2026-06-20,09:00,11:00,二教 205
        """
        let exams = try CustomCampusCSVParser.parseExams(examCSV)
        XCTAssertEqual(exams, [
            ExamArrangement(id: 1, courseID: "DS-001", name: "数据结构", date: "2026-06-20", start: "09:00", end: "11:00", location: "二教 205")
        ])
    }
}
