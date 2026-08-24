import Foundation
import XCTest
@testable import Leafy

final class AcademicYearTimetableTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testAcademicYearUsesFallBoundariesAndStartsWeeksOnMonday() throws {
        let fall = configuration(id: "2026-2027-1", start: "2026-09-07")
        let nextFall = configuration(id: "2027-2028-1", start: "2027-09-06")
        let timetable = AcademicYearTimetable(
            configurations: [fall, nextFall],
            referenceDate: date("2026-09-07"),
            calendar: calendar
        )
        let first = try XCTUnwrap(timetable.weeks.first)
        let last = try XCTUnwrap(timetable.weeks.last)

        XCTAssertEqual(timetable.academicYearID, "2026-2027")
        XCTAssertEqual(timetable.weeks.count, 52)
        XCTAssertEqual(day(first.id), 2) // Monday in Calendar.current's Gregorian calendar.
        XCTAssertEqual(dateString(first.id), "2026-09-07")
        XCTAssertEqual(dateString(last.id), "2027-08-30")
        XCTAssertTrue(timetable.contains(date("2027-01-18")))
        XCTAssertFalse(timetable.contains(date("2027-09-06")))
    }

    func testCrossYearSemesterContinuesTeachingWeekNumberIntoTargetYear() {
        let semester = configuration(id: "2025-2026-1", start: "2025-09-01")
        let timetable = AcademicYearTimetable(
            configurations: [semester],
            referenceDate: date("2026-01-01"),
            calendar: calendar
        )

        XCTAssertEqual(timetable.phase(for: date("2026-01-01")), .teaching(semesterID: "2025-2026-1", weekNumber: 18))
    }

    func testSemanticSummerBreakLabelsWeeksOutsideTeachingInterval() {
        let summer = event(
            id: "summer-2026",
            title: "暑假",
            start: "2026-07-13",
            end: "2026-08-30",
            category: .summerBreak
        )
        let timetable = AcademicYearTimetable(
            configurations: [],
            semanticEvents: [summer],
            referenceDate: date("2026-07-20"),
            calendar: calendar
        )

        XCTAssertEqual(timetable.phase(for: date("2026-07-20")), .vacation(title: "暑假", category: .summerBreak))
    }

    func testFutureSemesterWithoutCoursesStillStartsAtWeekOne() {
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let timetable = AcademicYearTimetable(
            configurations: [future],
            referenceDate: date("2026-09-07"),
            calendar: calendar
        )

        XCTAssertEqual(timetable.phase(for: date("2026-09-07")), .teaching(semesterID: "2026-2027-1", weekNumber: 1))
    }

    func testCurrentTimePositionUsesRowsAndBreakSpacingAtBoundaries() throws {
        let metrics = TimetableLayoutMetrics(
            rowHeight: 100,
            rowSpacing: 10,
            cardInset: 0,
            laneSpacing: 0,
            dayColumnWidth: 100,
            daySpacing: 0,
            weekSpacing: 0,
            gridHeight: 1_420,
            allowsVerticalScroll: true,
            weekStride: 0,
            containerWidth: 100,
            containerHeight: 1_420,
            horizontalPadding: 0,
            mode: .weekGrid
        )

        XCTAssertNil(position("07:59", metrics: metrics))
        XCTAssertEqual(try XCTUnwrap(position("08:00", metrics: metrics)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(position("08:22:30", metrics: metrics)), 50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(position("12:30", metrics: metrics)), 542, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(position("21:45", metrics: metrics)), 1_420, accuracy: 0.001)
        XCTAssertNil(position("21:46", metrics: metrics))
    }

    func testScheduleAndExamProjectByAbsoluteDateIntoAcademicYearPageWithoutCourses() throws {
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let academicYear = AcademicYearTimetable(
            configurations: [future],
            referenceDate: date("2026-09-08"),
            calendar: calendar
        )
        let exam = ExamArrangement(
            id: 7,
            courseID: "future-course",
            name: "Future exam",
            date: "2026-09-08",
            start: "08:00",
            end: "08:45",
            location: "Room 1"
        )
        let examStart = try XCTUnwrap(exam.startsAt)
        let schedule = CustomScheduleEvent(id: "future-event", title: "Future event", startsAt: examStart)

        let snapshot = TimetableScheduleProjectionSnapshot.make(
            countdownEvents: [schedule],
            exams: [exam],
            academicYear: academicYear,
            calendar: calendar
        )
        let page = try XCTUnwrap(academicYear.pageIndex(containing: examStart))
        let day = ((calendar.component(.weekday, from: examStart) + 5) % 7) + 1

        XCTAssertEqual(page, 1)
        XCTAssertEqual(day, 2)
        XCTAssertEqual(snapshot.countdowns(week: page, day: day).map(\.title), ["Future event"])
        let projection = try XCTUnwrap(snapshot.countdowns(week: page, day: day).first)
        XCTAssertEqual(projection.startsAt, examStart)
        XCTAssertEqual(projection.endsAt, examStart.addingTimeInterval(45 * 60))
        XCTAssertEqual(projection.startPeriod, 1)
        XCTAssertEqual(projection.endPeriod, 1)
        XCTAssertEqual(snapshot.exams(week: page, day: day).map(\.name), ["Future exam"])
    }

    func testTwoSemesterWeekOnesAreIdentifiedBySemesterIdentity() {
        let previous = configuration(id: "2025-2026-2", start: "2026-03-09")
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let timetable = AcademicYearTimetable(
            configurations: [previous, future],
            referenceDate: date("2026-09-07"),
            calendar: calendar
        )

        XCTAssertEqual(timetable.phase(for: date("2026-03-09")), .teaching(semesterID: "2025-2026-2", weekNumber: 1))
        XCTAssertEqual(timetable.phase(for: date("2026-09-07")), .teaching(semesterID: "2026-2027-1", weekNumber: 1))
    }

    func testAcademicYearBoundaryWeekUsesSemesterStartAsReferenceDate() throws {
        let semester = configuration(id: "2026-2027-1", start: "2026-01-03")
        let timetable = AcademicYearTimetable(
            configurations: [semester],
            referenceDate: date("2026-01-03"),
            calendar: calendar
        )

        let boundaryWeek = try XCTUnwrap(timetable.week(containing: date("2026-01-03")))
        XCTAssertEqual(boundaryWeek.id, date("2025-12-29"))
        XCTAssertEqual(boundaryWeek.phase, .teaching(semesterID: "2026-2027-1", weekNumber: 1))
        XCTAssertEqual(timetable.phase(for: date("2026-01-03")), .teaching(semesterID: "2026-2027-1", weekNumber: 1))
    }

    func testCalendarMenuListsOfficialWeeksDirectlyUnderSemester() throws {
        let spring = configuration(id: "2025-2026-2", start: "2026-03-09")
        let timetable = AcademicYearTimetable(
            configurations: [spring],
            referenceDate: date("2026-04-01"),
            calendar: calendar
        )
        let menu = TimetableCalendarMenuModel(
            timetable: timetable,
            configurations: [spring],
            referenceDate: date("2026-04-01"),
            calendar: calendar
        )

        let academicYear = try XCTUnwrap(menu.academicYears.first)
        XCTAssertEqual(academicYear.academicYear, "2025–2026")
        guard case let .semester(semester) = try XCTUnwrap(academicYear.stages.first) else {
            return XCTFail("Expected a teaching semester stage")
        }
        XCTAssertEqual(semester.title, "春季学期")
        XCTAssertEqual(semester.weeks.prefix(4).map(\.weekNumber), [1, 2, 3, 4])
        XCTAssertNotEqual(semester.weeks.first?.page, semester.weeks.first?.weekNumber)
    }

    func testCalendarMenuPlacesCurrentSemesterFirst() throws {
        let spring = configuration(id: "2025-2026-2", start: "2026-03-09")
        let fall = configuration(id: "2026-2027-1", start: "2026-09-07")
        let referenceDate = date("2026-09-14")
        let timetable = AcademicYearTimetable(
            configurations: [spring, fall],
            referenceDate: referenceDate,
            calendar: calendar
        )
        let menu = TimetableCalendarMenuModel(
            timetable: timetable,
            configurations: [spring, fall],
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(menu.currentSemesterID, fall.semesterID)
        let firstAcademicYear = try XCTUnwrap(menu.academicYears.first)
        guard case let .semester(firstSemester) = try XCTUnwrap(firstAcademicYear.stages.first) else {
            return XCTFail("Expected the current semester first")
        }
        XCTAssertEqual(firstSemester.semesterID, fall.semesterID)
    }

    func testTimeViewKeepsSpringInHistoryWhileFeaturingUpcomingFall() throws {
        let spring = configuration(id: "2025-2026-2", start: "2026-03-09")
        let fall = configuration(id: "2026-2027-1", start: "2026-09-07")
        let timetable = AcademicYearTimetable(
            configurations: [spring, fall],
            referenceDate: date("2026-08-22"),
            calendar: calendar
        )
        let menu = TimetableCalendarMenuModel(
            timetable: timetable,
            configurations: [spring, fall],
            referenceDate: date("2026-08-22"),
            calendar: calendar
        )

        XCTAssertTrue(menu.academicYears.flatMap(\.semesters).contains { $0.semesterID == spring.semesterID })
        XCTAssertFalse(menu.timeViewAcademicYears.flatMap(\.semesters).contains { $0.semesterID == spring.semesterID })
        XCTAssertEqual(menu.timeViewAcademicYears.flatMap(\.semesters).map(\.semesterID), [fall.semesterID])
        XCTAssertEqual(menu.historyTimeViewAcademicYears.map(\.academicYear), ["2025–2026"])
        XCTAssertEqual(
            menu.historyTimeViewAcademicYears.flatMap(\.semesters).map(\.semesterID),
            [spring.semesterID]
        )
    }

    func testTimeScopeResolverSelectsUpcomingFallDuringSummer() {
        let spring = configuration(id: "2025-2026-2", start: "2026-03-09")
        let fall = configuration(id: "2026-2027-1", start: "2026-09-07")

        XCTAssertEqual(
            TimetableTimeScopeConfigurationResolver.configuration(
                for: date("2026-08-22"),
                configurations: [spring, fall],
                calendar: calendar
            )?.semesterID,
            fall.semesterID
        )
    }

    func testRenderedWeekWindowIncludesNeighborsAndPendingJumpTarget() {
        XCTAssertEqual(
            TimetableRenderedWeekWindow.pages(currentWeek: 1, pendingWeek: nil, totalWeeks: 53),
            [1, 2]
        )
        XCTAssertEqual(
            TimetableRenderedWeekWindow.pages(currentWeek: 53, pendingWeek: nil, totalWeeks: 53),
            [52, 53]
        )
        XCTAssertEqual(
            TimetableRenderedWeekWindow.pages(currentWeek: 10, pendingWeek: 40, totalWeeks: 53),
            [9, 10, 11, 39, 40, 41]
        )
    }

    func testScheduleGeometryUsesExactTimeAcrossRowsAndBreaks() {
        let metrics = scheduleGeometryMetrics()

        let fullPeriod = TimetableScheduleBlockGeometry.make(
            startDate: time("08:00"),
            endDate: time("08:45"),
            fallbackStartPeriod: 1,
            fallbackEndPeriod: 1,
            metrics: metrics,
            minimumHeight: 18,
            calendar: calendar
        )
        XCTAssertEqual(fullPeriod.height, 96, accuracy: 0.001)
        XCTAssertEqual(fullPeriod.centerY, 50, accuracy: 0.001)

        let intoSecondPeriod = TimetableScheduleBlockGeometry.make(
            startDate: time("08:00"),
            endDate: time("09:00"),
            fallbackStartPeriod: 1,
            fallbackEndPeriod: 2,
            metrics: metrics,
            minimumHeight: 18,
            calendar: calendar
        )
        XCTAssertEqual(intoSecondPeriod.height, 128.222, accuracy: 0.01)

        let acrossBreak = TimetableScheduleBlockGeometry.make(
            startDate: time("08:40"),
            endDate: time("08:55"),
            fallbackStartPeriod: 1,
            fallbackEndPeriod: 2,
            metrics: metrics,
            minimumHeight: 18,
            calendar: calendar
        )
        XCTAssertEqual(acrossBreak.centerY, 105, accuracy: 0.01)

        let legacy = TimetableScheduleBlockGeometry.make(
            startDate: nil,
            endDate: nil,
            fallbackStartPeriod: 1,
            fallbackEndPeriod: 1,
            metrics: metrics,
            minimumHeight: 18,
            calendar: calendar
        )
        XCTAssertEqual(legacy.height, 96, accuracy: 0.001)
        XCTAssertEqual(legacy.centerY, 50, accuracy: 0.001)
    }

    func testCalendarMenuPlacesVacationDirectlyUnderItsAcademicYear() throws {
        let summer = event(
            id: "summer-2026",
            title: "暑期安排",
            start: "2026-07-27",
            end: "2026-09-06",
            category: .summerBreak
        )
        let spring = configuration(
            id: "2025-2026-2",
            start: "2026-03-09",
            calendarEvents: [summer]
        )
        let referenceDate = calendar.date(byAdding: .day, value: 7, to: try XCTUnwrap(summer.startDate))!
        let timetable = AcademicYearTimetable(
            configurations: [spring],
            semanticEvents: [summer],
            referenceDate: referenceDate,
            calendar: calendar
        )
        let menu = TimetableCalendarMenuModel(
            timetable: timetable,
            configurations: [spring],
            referenceDate: referenceDate,
            calendar: calendar
        )

        let academicYear = try XCTUnwrap(menu.academicYears.first)
        XCTAssertEqual(academicYear.academicYear, "2025–2026")
        XCTAssertEqual(academicYear.stages.count, 2)
        let vacations: [TimetableCalendarMenuVacation] = academicYear.stages.compactMap { stage in
            guard case let .vacation(vacation) = stage else { return nil }
            return vacation
        }
        let vacation = try XCTUnwrap(vacations.first)
        XCTAssertEqual(vacation.title, "暑假")
        XCTAssertEqual(vacation.page, timetable.pageIndex(containing: referenceDate))
        XCTAssertEqual(vacation.weeks.count, 6)
        XCTAssertEqual(vacation.weeks.first?.startDate, date("2026-07-27"))
        XCTAssertEqual(vacation.weeks.last?.endDate, date("2026-09-06"))
        guard case .vacation = try XCTUnwrap(academicYear.stages.first) else {
            return XCTFail("Expected summer vacation before the spring semester in history")
        }
    }

    func testVacationTargetUsesFirstIntersectingWeekEvenWhenTeachingPhaseWins() throws {
        let summer = event(
            id: "overlapping-summer-2026",
            title: "暑假",
            start: "2026-07-23",
            end: "2026-08-02",
            category: .summerBreak
        )
        let spring = configuration(
            id: "2025-2026-2",
            start: "2026-03-09",
            calendarEvents: [summer]
        )
        let timetable = AcademicYearTimetable(
            configurations: [spring],
            semanticEvents: [summer],
            referenceDate: date("2026-01-01"),
            calendar: calendar
        )
        let menu = TimetableCalendarMenuModel(
            timetable: timetable,
            configurations: [spring],
            referenceDate: date("2026-01-01"),
            calendar: calendar
        )

        let academicYear = try XCTUnwrap(menu.academicYears.first)
        let vacations: [TimetableCalendarMenuVacation] = academicYear.stages.compactMap { stage in
            guard case let .vacation(vacation) = stage else { return nil }
            return vacation
        }
        let vacation = try XCTUnwrap(vacations.first)
        let expectedPage = try XCTUnwrap(timetable.pageIndex(containing: try XCTUnwrap(summer.startDate)))
        XCTAssertEqual(vacation.page, expectedPage)
        guard case .teaching = try XCTUnwrap(timetable.week(atPageIndex: expectedPage)).phase else {
            return XCTFail("Expected the overlapping first vacation week to retain its teaching phase")
        }
    }

    func testCalendarMenuInfersUnknownSemesterSeasonFromStartMonth() {
        XCTAssertEqual(
            TimetableCalendarMenuModel.semesterSeasonTitle(
                semesterID: "custom-term",
                semesterStartDate: date("2026-09-01"),
                calendar: calendar
            ),
            "秋季学期"
        )
        XCTAssertEqual(
            TimetableCalendarMenuModel.semesterSeasonTitle(
                semesterID: "custom-term",
                semesterStartDate: date("2026-03-01"),
                calendar: calendar
            ),
            "春季学期"
        )
    }

    func testCurrentTimeIndicatorSpansAllVisibleDayColumns() {
        let metrics = TimetableLayoutMetrics(
            rowHeight: 100,
            rowSpacing: 10,
            cardInset: 0,
            laneSpacing: 0,
            dayColumnWidth: 100,
            daySpacing: 5,
            weekSpacing: 20,
            gridHeight: 1_420,
            allowsVerticalScroll: true,
            weekStride: 750,
            containerWidth: 730,
            containerHeight: 1_420,
            horizontalPadding: 0,
            mode: .weekGrid
        )

        XCTAssertEqual(TimetableCurrentTimeIndicatorGeometry.width(visibleDayCount: 5, metrics: metrics), 520)
        XCTAssertEqual(TimetableCurrentTimeIndicatorGeometry.width(visibleDayCount: 7, metrics: metrics), 730)
        XCTAssertEqual(
            TimetableCurrentTimeIndicatorGeometry.centerX(page: 3, visibleDayCount: 7, metrics: metrics),
            1_865
        )
        XCTAssertEqual(TimetableCurrentTimeIndicatorPreference.sanitizedThickness(-1), 1)
        XCTAssertEqual(TimetableCurrentTimeIndicatorPreference.sanitizedThickness(8), 6)
    }

    private func configuration(
        id: String,
        start: String,
        calendarEvents: [SchoolCalendarEvent] = []
    ) -> SemesterRuntimeConfig {
        SemesterRuntimeConfig(
            semesterID: id,
            semesterStartDateString: start,
            supportedWeeks: 20,
            graduateTimetableTermCode: "term-\(id)",
            calendarEvents: calendarEvents,
            updatedAt: nil,
            isActive: true
        )
    }

    private func event(
        id: String,
        title: String,
        start: String,
        end: String,
        category: SchoolCalendarEvent.AcademicCategory
    ) -> SchoolCalendarEvent {
        SchoolCalendarEvent(
            id: id,
            title: title,
            startDateString: start,
            endDateString: end,
            kind: .holiday,
            academicCategory: category
        )
    }

    private func date(_ string: String) -> Date {
        let components = string.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: components[0],
            month: components[1],
            day: components[2]
        ))!
    }

    private func position(_ time: String, metrics: TimetableLayoutMetrics) -> CGFloat? {
        let components = time.split(separator: ":").map { Int($0)! }
        let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 1,
            hour: components[0],
            minute: components[1],
            second: components.count > 2 ? components[2] : 0
        ))!
        return TimetableCurrentTimePosition.yPosition(for: date, metrics: metrics, calendar: calendar)
    }

    private func time(_ value: String) -> Date {
        let components = value.split(separator: ":").map { Int($0)! }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 1,
            hour: components[0],
            minute: components[1]
        ))!
    }

    private func scheduleGeometryMetrics() -> TimetableLayoutMetrics {
        TimetableLayoutMetrics(
            rowHeight: 100,
            rowSpacing: 10,
            cardInset: 2,
            laneSpacing: 0,
            dayColumnWidth: 100,
            daySpacing: 0,
            weekSpacing: 0,
            gridHeight: 1_420,
            allowsVerticalScroll: true,
            weekStride: 0,
            containerWidth: 100,
            containerHeight: 1_420,
            horizontalPadding: 0,
            mode: .weekGrid
        )
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private func day(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }
}
