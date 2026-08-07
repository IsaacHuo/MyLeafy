import Foundation
import XCTest
@testable import Leafy

final class CalendarYearTimetableTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testYearContainsOnlyWeeksIntersectingYearAndStartsOnMonday() throws {
        let timetable = CalendarYearTimetable(year: 2026, configurations: [], calendar: calendar)
        let first = try XCTUnwrap(timetable.weeks.first)
        let last = try XCTUnwrap(timetable.weeks.last)

        XCTAssertEqual(timetable.weeks.count, 53)
        XCTAssertEqual(day(first.id), 2) // Monday in Calendar.current's Gregorian calendar.
        XCTAssertEqual(dateString(first.id), "2025-12-29")
        XCTAssertEqual(dateString(last.id), "2026-12-28")
        XCTAssertTrue(first.id < date("2026-01-01"))
        XCTAssertLessThan(date("2026-12-31"), calendar.date(byAdding: .day, value: 7, to: last.id)!)
    }

    func testCrossYearSemesterContinuesTeachingWeekNumberIntoTargetYear() {
        let semester = configuration(id: "2025-2026-1", start: "2025-09-01")
        let timetable = CalendarYearTimetable(year: 2026, configurations: [semester], calendar: calendar)

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
        let timetable = CalendarYearTimetable(
            year: 2026,
            configurations: [],
            semanticEvents: [summer],
            calendar: calendar
        )

        XCTAssertEqual(timetable.phase(for: date("2026-07-20")), .vacation(title: "暑假", category: .summerBreak))
    }

    func testFutureSemesterWithoutCoursesStillStartsAtWeekOne() {
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let timetable = CalendarYearTimetable(year: 2026, configurations: [future], calendar: calendar)

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

    func testScheduleAndExamProjectByAbsoluteDateIntoFutureCalendarYearPageWithoutCourses() throws {
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let calendarYear = CalendarYearTimetable(year: 2026, configurations: [future], calendar: calendar)
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
            calendarYear: calendarYear,
            calendar: calendar
        )
        let page = try XCTUnwrap(calendarYear.pageIndex(containing: examStart))
        let day = ((calendar.component(.weekday, from: examStart) + 5) % 7) + 1

        XCTAssertEqual(page, 37)
        XCTAssertEqual(day, 2)
        XCTAssertEqual(snapshot.countdowns(week: page, day: day).map(\.title), ["Future event"])
        XCTAssertEqual(snapshot.exams(week: page, day: day).map(\.name), ["Future exam"])
    }

    func testTwoSemesterWeekOnesAreIdentifiedBySemesterIdentity() {
        let previous = configuration(id: "2025-2026-2", start: "2026-03-09")
        let future = configuration(id: "2026-2027-1", start: "2026-09-07")
        let timetable = CalendarYearTimetable(year: 2026, configurations: [previous, future], calendar: calendar)

        XCTAssertEqual(timetable.phase(for: date("2026-03-09")), .teaching(semesterID: "2025-2026-2", weekNumber: 1))
        XCTAssertEqual(timetable.phase(for: date("2026-09-07")), .teaching(semesterID: "2026-2027-1", weekNumber: 1))
    }

    func testSpecifiedReferenceDateWinsForWeekCrossingPhaseBoundary() throws {
        let semester = configuration(id: "2026-2027-1", start: "2026-01-03")
        let withoutReference = CalendarYearTimetable(year: 2026, configurations: [semester], calendar: calendar)
        let withReference = CalendarYearTimetable(
            year: 2026,
            configurations: [semester],
            referenceDate: date("2026-01-03"),
            calendar: calendar
        )

        let weekWithoutReference = try XCTUnwrap(withoutReference.week(containing: date("2026-01-03")))
        let weekWithReference = try XCTUnwrap(withReference.week(containing: date("2026-01-03")))
        XCTAssertEqual(weekWithoutReference.id, date("2025-12-29"))
        XCTAssertEqual(weekWithoutReference.phase, .unconfigured)
        XCTAssertEqual(weekWithReference.phase, .teaching(semesterID: "2026-2027-1", weekNumber: 1))
        XCTAssertEqual(withReference.phase(for: date("2026-01-03")), .teaching(semesterID: "2026-2027-1", weekNumber: 1))
    }

    private func configuration(id: String, start: String) -> SemesterRuntimeConfig {
        SemesterRuntimeConfig(
            semesterID: id,
            semesterStartDateString: start,
            supportedWeeks: 20,
            graduateTimetableTermCode: "term-\(id)",
            calendarEvents: [],
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
