import XCTest
@testable import Leafy

@MainActor
final class ClockScheduleProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private var semesterStart: Date {
        calendar.startOfDay(for: SemesterConfig.startOfSemesterDate)
    }

    func testCourseUsesRealSlotTimesWithoutFillingLunch() throws {
        let date = try day(offset: 0)
        let course = Course(
            courseName: "午间课程",
            teacher: "老师",
            room: "101",
            dayOfWeek: 1,
            weeks: [1],
            duration: [5, 6]
        )

        let events = ClockScheduleProjection.events(
            on: date,
            courses: [course],
            reminders: [],
            customEvents: [],
            calendar: calendar
        )

        XCTAssertEqual(events.count, 3, "period 5 crosses noon and period 6 stays after lunch")
        XCTAssertEqual(events.map { calendar.component(.hour, from: $0.startsAt) }, [11, 12, 13])
        XCTAssertEqual(events.map { calendar.component(.minute, from: $0.startsAt) }, [30, 0, 30])
        XCTAssertEqual(events.filter { $0.period == 5 }.map(\.dayPart), [.am, .pm])
        XCTAssertTrue(events.allSatisfy { $0.source == .course })
    }

    func testCourseFiltersBySemesterWeekAndWeekday() throws {
        let monday = try day(offset: 0)
        let wrongWeek = Course(
            courseName: "下周课程",
            teacher: "老师",
            room: "101",
            dayOfWeek: 1,
            weeks: [2],
            duration: [1]
        )
        let wrongDay = Course(
            courseName: "周二课程",
            teacher: "老师",
            room: "102",
            dayOfWeek: 2,
            weeks: [1],
            duration: [1]
        )

        XCTAssertTrue(
            ClockScheduleProjection.events(
                on: monday,
                courses: [wrongWeek, wrongDay],
                reminders: [],
                customEvents: [],
                calendar: calendar
            ).isEmpty
        )
    }

    func testProjectionCropsNaturalDayAndSplitsAtNoon() throws {
        let date = try day(offset: 0)
        let previousDate = try day(offset: -1)
        let nextDate = try day(offset: 1)
        let beforeMidnight = CustomScheduleEvent(
            id: "before-midnight",
            title: "跨午夜前半段",
            startsAt: calendar.date(bySettingHour: 23, minute: 30, second: 0, of: previousDate)!,
            endsAt: calendar.date(bySettingHour: 0, minute: 30, second: 0, of: date)!
        )
        let afterMidnight = CustomScheduleEvent(
            id: "after-midnight",
            title: "跨午夜后半段",
            startsAt: calendar.date(bySettingHour: 23, minute: 30, second: 0, of: date)!,
            endsAt: calendar.date(bySettingHour: 0, minute: 30, second: 0, of: nextDate)!
        )
        let noonEvent = CustomScheduleEvent(
            id: "cross-noon",
            title: "跨午",
            startsAt: calendar.date(bySettingHour: 11, minute: 59, second: 0, of: date)!,
            endsAt: calendar.date(bySettingHour: 12, minute: 1, second: 0, of: date)!
        )

        let currentEvents = ClockScheduleProjection.events(
            on: date,
            courses: [],
            reminders: [],
            customEvents: [beforeMidnight, afterMidnight, noonEvent],
            calendar: calendar
        )

        let before = try XCTUnwrap(currentEvents.first { $0.sourceID == beforeMidnight.id })
        XCTAssertEqual(before.startsAt, date)
        XCTAssertEqual(calendar.component(.minute, from: before.endsAt!), 30)

        let after = try XCTUnwrap(currentEvents.first { $0.sourceID == afterMidnight.id })
        XCTAssertEqual(calendar.component(.hour, from: after.startsAt), 23)
        XCTAssertEqual(after.endsAt, calendar.date(byAdding: .day, value: 1, to: date))

        let noonPieces = currentEvents.filter { $0.sourceID == noonEvent.id }
        XCTAssertEqual(noonPieces.count, 2)
        XCTAssertEqual(noonPieces.map(\.dayPart), [.am, .pm])
        XCTAssertEqual(calendar.component(.minute, from: noonPieces[0].endsAt!), 0)
        XCTAssertEqual(calendar.component(.minute, from: noonPieces[1].startsAt), 0)
    }

    func testPointEventsAndTimeEdgesRemainVisible() throws {
        let date = try day(offset: 0)
        let edgeEvents = [
            CustomScheduleEvent(id: "zero", title: "零点", startsAt: calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date)!),
            CustomScheduleEvent(id: "before-noon", title: "午前边界", startsAt: calendar.date(bySettingHour: 11, minute: 59, second: 0, of: date)!),
            CustomScheduleEvent(id: "noon", title: "正午", startsAt: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!),
            CustomScheduleEvent(id: "last-minute", title: "末分钟", startsAt: calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)!)
        ]

        let events = ClockScheduleProjection.events(
            on: date,
            courses: [],
            reminders: [],
            customEvents: edgeEvents,
            calendar: calendar
        )

        XCTAssertEqual(events.count, 4)
        XCTAssertTrue(events.allSatisfy(\.isPoint))
        XCTAssertEqual(events.first { $0.sourceID == "zero" }?.dayPart, .am)
        XCTAssertEqual(events.first { $0.sourceID == "noon" }?.dayPart, .pm)
        XCTAssertEqual(calendar.component(.minute, from: events.first { $0.sourceID == "last-minute" }!.startsAt), 59)
    }

    func testTwelveHourDialMapsAMAndPMToTheSameReadableFace() throws {
        let date = try day(offset: 0)
        let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date)!
        let beforeNoon = calendar.date(bySettingHour: 11, minute: 59, second: 0, of: date)!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let beforeMidnight = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)!

        XCTAssertEqual(ClockScheduleDialGeometry.minutes(on: midnight, in: .am, calendar: calendar), 0)
        XCTAssertEqual(ClockScheduleDialGeometry.minutes(on: beforeNoon, in: .am, calendar: calendar), 719)
        XCTAssertEqual(ClockScheduleDialGeometry.minutes(on: noon, in: .pm, calendar: calendar), 0)
        XCTAssertEqual(ClockScheduleDialGeometry.minutes(on: beforeMidnight, in: .pm, calendar: calendar), 719)
    }

    func testReminderUsesResolvedDatesAndPreservesStableSourceID() throws {
        let date = try day(offset: 0)
        let start = calendar.date(bySettingHour: 11, minute: 59, second: 0, of: date)!
        let end = calendar.date(bySettingHour: 12, minute: 1, second: 0, of: date)!
        let reminder = TimetableCellReminder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            week: 1,
            dayOfWeek: 1,
            period: 3,
            title: "提醒",
            startsAt: start,
            endsAt: end
        )

        let events = ClockScheduleProjection.events(
            on: date,
            courses: [],
            reminders: [reminder],
            customEvents: [],
            calendar: calendar
        )

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.source == .reminder && $0.sourceID == reminder.id.uuidString })
        XCTAssertEqual(events.map(\.dayPart), [.am, .pm])
    }

    func testOverlapLanesAreStableAndDeterministic() throws {
        let date = try day(offset: 0)
        let first = CustomScheduleEvent(
            id: "first",
            title: "第一项",
            startsAt: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!,
            endsAt: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: date)!
        )
        let second = CustomScheduleEvent(
            id: "second",
            title: "第二项",
            startsAt: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date)!,
            endsAt: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)!
        )

        let firstProjection = ClockScheduleProjection.events(
            on: date,
            courses: [],
            reminders: [],
            customEvents: [second, first],
            calendar: calendar
        )
        let secondProjection = ClockScheduleProjection.events(
            on: date,
            courses: [],
            reminders: [],
            customEvents: [first, second],
            calendar: calendar
        )

        let firstLanes = Dictionary(uniqueKeysWithValues: firstProjection.map { ($0.sourceID, $0.lane) })
        let secondLanes = Dictionary(uniqueKeysWithValues: secondProjection.map { ($0.sourceID, $0.lane) })
        XCTAssertEqual(firstLanes, secondLanes)
        XCTAssertEqual(firstLanes["first"], 0)
        XCTAssertEqual(firstLanes["second"], 1)
        XCTAssertEqual(Set(firstProjection.map(\.laneCount)), [2])
    }

    private func day(offset: Int) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: semesterStart))
    }
}
