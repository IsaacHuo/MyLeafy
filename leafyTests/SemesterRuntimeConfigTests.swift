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
                SchoolCalendarEvent(
                    id: "national-2026",
                    title: "国庆",
                    startDateString: "2026-10-01",
                    endDateString: "2026-10-07",
                    kind: .holiday,
                    academicCategory: .publicHoliday
                )
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
        XCTAssertNil(event.academicCategory)
    }

    func testCalendarEventDecodesAcademicCategoryWithoutBreakingLegacyKind() throws {
        let json = """
        {"id":"winter-2027","title":"寒假","start_date":"2027-01-16","end_date":"2027-02-27","kind":"holiday","academic_category":"winter_break"}
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SchoolCalendarEvent.self, from: json)

        XCTAssertEqual(event.kind, .holiday)
        XCTAssertEqual(event.academicCategory, .winterBreak)
        XCTAssertTrue(event.isVacation)
        XCTAssertFalse(event.isPublicHoliday)
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
        let nextHoliday = AcademicCalendarEvents.nextHoliday(from: date)

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

        let nextHoliday = AcademicCalendarEvents.nextHoliday(from: date)

        XCTAssertEqual(nextHoliday?.title, "五一")
    }

    func testNextHolidayIncludesCampusPublicHolidayButIgnoresOtherAcademicEvents() throws {
        let referenceDate = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-12-20"))
        let events = Self.firstSemesterCalendarEvents

        let nextHoliday = AcademicCalendarEvents.nextHoliday(
            from: referenceDate,
            campusEvents: events
        )

        XCTAssertEqual(nextHoliday?.title, "元旦")
        XCTAssertEqual(nextHoliday?.academicCategory, .publicHoliday)
        XCTAssertFalse(events.first { $0.academicCategory == .importantDate }?.isPublicHoliday ?? true)
        XCTAssertFalse(events.first { $0.academicCategory == .semesterEnd }?.isPublicHoliday ?? true)
    }

    func testFirstSemesterTimeScopeUsesOfficialWinterBreakInsteadOfContainerEnd() throws {
        let referenceDate = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-12-20"))
        let displayedMonth = try XCTUnwrap(DateFormatters.queryDate.date(from: "2027-01-01"))
        let config = SemesterRuntimeConfig(
            semesterID: "2026-2027-1",
            semesterStartDateString: "2026-09-07",
            supportedWeeks: 19,
            graduateTimetableTermCode: "47",
            calendarEvents: Self.firstSemesterCalendarEvents,
            updatedAt: nil,
            isActive: true
        )

        let snapshot = TimetableTimeScopeSnapshot.make(
            currentWeek: 15,
            referenceDate: referenceDate,
            displayedMonthDate: displayedMonth,
            language: .zhHans,
            semesterConfig: config,
            campusID: .bjfu
        )

        XCTAssertEqual(snapshot.vacationTitle, "寒假")
        XCTAssertEqual(snapshot.vacationCategory, .winterBreak)
        XCTAssertEqual(snapshot.vacationStartDate, DateFormatters.queryDate.date(from: "2027-01-16"))
        XCTAssertEqual(snapshot.vacationEndDate, DateFormatters.queryDate.date(from: "2027-02-27"))
        XCTAssertEqual(snapshot.semesterEndDate, DateFormatters.queryDate.date(from: "2027-01-15"))
        XCTAssertTrue(snapshot.yearMonths.first { $0.month == 1 }?.isInSemester ?? false)
        XCTAssertTrue(snapshot.yearMonths.first { $0.month == 1 }?.isInVacation ?? false)
        XCTAssertTrue(snapshot.yearMonths.first { $0.month == 2 }?.isInVacation ?? false)
    }

    func testTimeScopeDoesNotInferVacationFromTwentyWeekContainer() throws {
        let referenceDate = try XCTUnwrap(DateFormatters.queryDate.date(from: "2026-04-01"))
        let config = SemesterRuntimeConfig(
            semesterID: "2025-2026-2",
            semesterStartDateString: "2026-03-09",
            supportedWeeks: 20,
            graduateTimetableTermCode: "46",
            calendarEvents: [],
            updatedAt: nil,
            isActive: true
        )

        let snapshot = TimetableTimeScopeSnapshot.make(
            currentWeek: 4,
            referenceDate: referenceDate,
            language: .zhHans,
            semesterConfig: config,
            campusID: .bjfu
        )

        XCTAssertNil(snapshot.vacationStartDate)
        XCTAssertNil(snapshot.semesterEndDate)
        XCTAssertEqual(snapshot.vacationTitle, "假期")
        XCTAssertEqual(snapshot.vacationCountdownText, "校历更新后显示")
        XCTAssertFalse(snapshot.yearMonths.contains { $0.isInVacation })
    }

    private static let firstSemesterCalendarEvents = [
        SchoolCalendarEvent(
            id: "bjfu-anniversary-74-2026",
            title: "建校74周年校庆日",
            startDateString: "2026-10-16",
            endDateString: "2026-10-16",
            kind: .holiday,
            academicCategory: .importantDate
        ),
        SchoolCalendarEvent(
            id: "bjfu-new-year-2027",
            title: "元旦",
            startDateString: "2027-01-01",
            endDateString: "2027-01-03",
            kind: .holiday,
            academicCategory: .publicHoliday
        ),
        SchoolCalendarEvent(
            id: "bjfu-first-semester-end-2027",
            title: "第一学期结束",
            startDateString: "2027-01-15",
            endDateString: "2027-01-15",
            kind: .holiday,
            academicCategory: .semesterEnd
        ),
        SchoolCalendarEvent(
            id: "bjfu-winter-break-2027",
            title: "寒假",
            startDateString: "2027-01-16",
            endDateString: "2027-02-27",
            kind: .holiday,
            academicCategory: .winterBreak
        ),
    ]
}
