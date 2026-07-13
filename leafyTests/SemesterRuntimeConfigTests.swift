import XCTest
@testable import Leafy

final class SemesterRuntimeConfigTests: XCTestCase {
    func testCacheRoundTripsUsableConfig() throws {
        let suiteName = "semester-runtime-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            SemesterRuntimeConfigCache.clear(defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let config = SemesterRuntimeConfig(
            semesterID: "2026-2027-1",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 20,
            graduateTimetableTermCode: "47",
            calendarEvents: [
                SchoolCalendarEvent(id: "national-2026", title: "国庆", startDateString: "2026-10-01", endDateString: "2026-10-07", kind: .holiday)
            ],
            updatedAt: "2026-08-20T00:00:00Z",
            isActive: true
        )

        SemesterRuntimeConfigCache.save(config, defaults: defaults)

        XCTAssertEqual(SemesterRuntimeConfigCache.load(defaults: defaults), config)
    }

    func testCacheRejectsInvalidConfig() throws {
        let suiteName = "semester-runtime-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            SemesterRuntimeConfigCache.clear(defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let config = SemesterRuntimeConfig(
            semesterID: "",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 20,
            graduateTimetableTermCode: "47",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )

        SemesterRuntimeConfigCache.save(config, defaults: defaults)

        XCTAssertNil(SemesterRuntimeConfigCache.load(defaults: defaults))
    }

    func testConfigDrivesWeekCalculation() throws {
        let config = SemesterRuntimeConfig(
            semesterID: "2026-2027-1",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 20,
            graduateTimetableTermCode: "47",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )
        let target = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-09-21"))

        XCTAssertEqual(SemesterConfig.currentWeek(date: target, config: config), 3)
        XCTAssertEqual(SemesterConfig.weekAndDay(for: target, config: config).week, 3)
        XCTAssertEqual(SemesterConfig.weekAndDay(for: target, config: config).day, 1)
    }

    func testNextSemesterConfigKeepsCalendarEventsEmptyForNow() throws {
        let config = SemesterRuntimeConfig(
            semesterID: "2026-2027-1",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 20,
            graduateTimetableTermCode: "47",
            calendarEvents: [],
            updatedAt: "2026-06-05T00:00:00Z",
            isActive: true
        )
        let start = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-09-07"))

        XCTAssertTrue(config.isUsable)
        XCTAssertEqual(config.semesterID, "2026-2027-1")
        XCTAssertEqual(config.graduateTimetableTermCode, "47")
        XCTAssertEqual(SemesterConfig.supportedWeeks, 20)
        XCTAssertEqual(config.calendarEvents, [])
        XCTAssertEqual(SemesterConfig.currentWeek(date: start, config: config), 1)
    }

    func testTwentyWeekContainerDoesNotDependOnRemoteCourseHorizon() throws {
        let config = SemesterRuntimeConfig(
            semesterID: "2026-2027-1",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 19,
            graduateTimetableTermCode: "47",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )
        let weekTwentyStart = try XCTUnwrap(DateFormatters.queryDate.date(from: "2027-01-18"))

        XCTAssertEqual(SemesterConfig.currentWeek(date: weekTwentyStart, config: config), 20)
        XCTAssertEqual(SemesterConfig.weekAndDay(for: weekTwentyStart, config: config).week, 20)
    }

    func testCalendarEventDecodesSnakeCaseDates() throws {
        let json = """
        {"id":"midautumn-2026","title":"中秋","start_date":"2026-09-25","end_date":"2026-09-27","kind":"holiday"}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SchoolCalendarEvent.self, from: json)

        XCTAssertEqual(event.startDateString, "2026-09-25")
        XCTAssertEqual(event.endDateString, "2026-09-27")
        XCTAssertEqual(event.kind, .holiday)
    }

    func testNationalHolidayIsSharedAcrossBJFUAndCustomCampus() throws {
        let date = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-05-01"))

        let bjfuEvent = AcademicCalendarEvents.event(on: date, campusID: .bjfu)
        let customEvent = AcademicCalendarEvents.event(on: date, campusID: .custom)

        XCTAssertEqual(bjfuEvent?.title, "五一")
        XCTAssertEqual(bjfuEvent?.kind, .holiday)
        XCTAssertEqual(customEvent, bjfuEvent)
    }

    func testCustomCampusDoesNotExposeBJFUClosureEvents() throws {
        let date = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-04-24"))

        let bjfuEvents = AcademicCalendarEvents.events(for: date, campusID: .bjfu)
        let customEvents = AcademicCalendarEvents.events(for: date, campusID: .custom)

        XCTAssertTrue(bjfuEvents.contains { $0.title == "运动会停课" && $0.kind == .closure })
        XCTAssertFalse(customEvents.contains { $0.title == "运动会停课" })
    }

    func testSolarTermIsDisplayedButNotTreatedAsNextHoliday() throws {
        let date = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-04-20"))

        let event = AcademicCalendarEvents.event(on: date, campusID: .custom)
        let nextHoliday = AcademicCalendarEvents.nextNationalHoliday(from: date)

        XCTAssertEqual(event?.title, "谷雨")
        XCTAssertEqual(event?.kind, .solarTerm)
        XCTAssertEqual(nextHoliday?.title, "五一")
    }

    func testSolarTermsCarrySeasonForDisplayColors() {
        XCTAssertEqual(SchoolCalendarEvent(id: "spring", title: "立春", startDateString: "2026-02-04", endDateString: "2026-02-04", kind: .solarTerm).solarTermSeason, .spring)
        XCTAssertEqual(SchoolCalendarEvent(id: "summer", title: "立夏", startDateString: "2026-05-05", endDateString: "2026-05-05", kind: .solarTerm).solarTermSeason, .summer)
        XCTAssertEqual(SchoolCalendarEvent(id: "autumn", title: "立秋", startDateString: "2026-08-07", endDateString: "2026-08-07", kind: .solarTerm).solarTermSeason, .autumn)
        XCTAssertEqual(SchoolCalendarEvent(id: "winter", title: "立冬", startDateString: "2026-11-07", endDateString: "2026-11-07", kind: .solarTerm).solarTermSeason, .winter)
    }

    func testNationalCalendarEventDecodesSnakeCaseDates() throws {
        let holidayJSON = """
        {"id":"labor-2026","title":"五一","start_date":"2026-05-01","end_date":"2026-05-05","kind":"holiday"}
        """.data(using: .utf8)!
        let solarTermJSON = """
        {"id":"grain-rain-2026","title":"谷雨","date_string":"2026-04-20"}
        """.data(using: .utf8)!

        let holiday = try JSONDecoder().decode(NationalHolidayEvent.self, from: holidayJSON)
        let solarTerm = try JSONDecoder().decode(SolarTermEvent.self, from: solarTermJSON)

        XCTAssertEqual(holiday.startDateString, "2026-05-01")
        XCTAssertEqual(holiday.endDateString, "2026-05-05")
        XCTAssertEqual(holiday.kind, .holiday)
        XCTAssertEqual(solarTerm.dateString, "2026-04-20")
    }

    func testNextHolidayIgnoresCampusClosures() throws {
        let date = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-04-20"))

        let nextHoliday = AcademicCalendarEvents.nextNationalHoliday(from: date)

        XCTAssertEqual(nextHoliday?.title, "五一")
    }
}
