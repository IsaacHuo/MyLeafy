import XCTest
@testable import Leafy

final class SunshineRunPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPeriodsStartFromFirstWeekInTwoWeekGroups() throws {
        let start = try makeDate("2026-03-09")
        let periods = SunshineRunPlanner.periods(semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar)

        XCTAssertEqual(periods.count, 10)
        XCTAssertEqual(periods.map { "\($0.startWeek)-\($0.endWeek)" }, [
            "1-2", "3-4", "5-6", "7-8", "9-10",
            "11-12", "13-14", "15-16", "17-18", "19-20"
        ])
    }

    func testPeriodsSkipExcludedHolidayWeeks() throws {
        let start = try makeDate("2026-03-09")
        let periods = SunshineRunPlanner.periods(semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar)

        XCTAssertEqual(periods.count, 10)
        XCTAssertEqual(periods.map { $0.activeWeeks }, [
            [1, 2], [3, 4], [5, 6], [7, 9], [10, 11],
            [12, 13], [14, 15], [16, 17], [18, 19], [20]
        ])
        XCTAssertEqual(periods[3].title, "第 7、9 周")
        XCTAssertTrue(periods[3].hasSkippedWeeks)
    }

    func testDateMapsToExpectedTwoWeekPeriod() throws {
        let start = try makeDate("2026-03-09")
        let weekOne = try XCTUnwrap(SunshineRunPlanner.period(for: try makeDate("2026-03-09"), semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar))
        let weekTwo = try XCTUnwrap(SunshineRunPlanner.period(for: try makeDate("2026-03-22"), semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar))
        let weekThree = try XCTUnwrap(SunshineRunPlanner.period(for: try makeDate("2026-03-23"), semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar))

        XCTAssertEqual(weekOne.startWeek, 1)
        XCTAssertEqual(weekTwo.startWeek, 1)
        XCTAssertEqual(weekThree.startWeek, 3)
    }

    func testExcludedHolidayWeekDoesNotAcceptRecords() throws {
        let start = try makeDate("2026-03-09")
        let weekSeven = try XCTUnwrap(SunshineRunPlanner.period(for: try makeDate("2026-04-20"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar))
        let weekEight = SunshineRunPlanner.period(for: try makeDate("2026-04-27"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar)
        let weekNine = try XCTUnwrap(SunshineRunPlanner.period(for: try makeDate("2026-05-04"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar))

        XCTAssertEqual(weekSeven.activeWeeks, [7, 9])
        XCTAssertNil(weekEight)
        XCTAssertEqual(weekNine.startWeek, weekSeven.startWeek)
        XCTAssertTrue(SunshineRunPlanner.isExcludedDate(try makeDate("2026-04-27"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar))
    }

    func testDailyRecordsDeduplicateAndGroupByPeriod() throws {
        let start = try makeDate("2026-03-09")
        let records = [
            SunshineRunRecord(date: try makeDate("2026-03-10"), semesterStart: start, calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-03-10"), semesterStart: start, calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-03-24"), semesterStart: start, calendar: calendar)
        ]

        let summary = SunshineRunPlanner.progressSummary(records: records, semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar)
        let progresses = SunshineRunPlanner.periodProgresses(records: records, semesterStart: start, totalWeeks: 20, excludedWeeks: [], calendar: calendar)

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(progresses[0].count, 1)
        XCTAssertEqual(progresses[1].count, 1)
    }

    func testFullScoreProgressIsCappedAtThirtyFour() throws {
        let start = try makeDate("2026-03-09")
        let records = try (0..<36).map { offset in
            SunshineRunRecord(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start)),
                semesterStart: start,
                calendar: calendar
            )
        }

        let summary = SunshineRunPlanner.progressSummary(records: records, excludedWeeks: [], calendar: calendar)

        XCTAssertEqual(summary.totalCount, 36)
        XCTAssertEqual(summary.cappedTotalCount, 34)
        XCTAssertTrue(summary.isFullScoreReached)
        XCTAssertEqual(summary.remainingForFullScore, 0)
    }

    func testCustomRuleSettingsChangePeriodAndTargets() throws {
        let start = try makeDate("2026-03-09")
        let rules = SunshineRunRuleSettings(totalTarget: 12, weeksPerPeriod: 3, periodTarget: 2, skipsExcludedWeeks: false)
        let records = [
            SunshineRunRecord(date: try makeDate("2026-03-10"), semesterStart: start, calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-03-17"), semesterStart: start, calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-03-24"), semesterStart: start, calendar: calendar)
        ]

        let periods = SunshineRunPlanner.periods(
            semesterStart: start,
            totalWeeks: 9,
            excludedWeeks: rules.excludedWeeks,
            weeksPerPeriod: rules.weeksPerPeriod,
            calendar: calendar
        )
        let progresses = SunshineRunPlanner.periodProgresses(
            records: records,
            semesterStart: start,
            totalWeeks: 9,
            excludedWeeks: rules.excludedWeeks,
            weeksPerPeriod: rules.weeksPerPeriod,
            periodTarget: rules.periodTarget,
            calendar: calendar
        )
        let summary = SunshineRunPlanner.progressSummary(
            records: records,
            semesterStart: start,
            totalWeeks: 9,
            excludedWeeks: rules.excludedWeeks,
            weeksPerPeriod: rules.weeksPerPeriod,
            totalTarget: rules.totalTarget,
            calendar: calendar
        )

        XCTAssertEqual(periods.map { "\($0.startWeek)-\($0.endWeek)" }, ["1-3", "4-6", "7-9"])
        XCTAssertEqual(progresses[0].periodTarget, 2)
        XCTAssertTrue(progresses[0].isCompleted)
        XCTAssertEqual(summary.cappedTotalCount, 3)
        XCTAssertEqual(summary.remainingForFullScore, 9)
    }

    func testRuleSettingsDeriveExcludedWeeksFromNationalHolidays() throws {
        let start = try makeDate("2026-03-09")
        let rules = SunshineRunRuleSettings()

        XCTAssertTrue(rules.excludedWeeks.contains(8))
        XCTAssertTrue(rules.excludedWeeks.contains(15))
        XCTAssertTrue(SunshineRunPlanner.isExcludedDate(try makeDate("2026-05-01"), semesterStart: start, totalWeeks: 20, excludedWeeks: rules.excludedWeeks, calendar: calendar))
        XCTAssertFalse(SunshineRunPlanner.isExcludedDate(try makeDate("2026-04-24"), semesterStart: start, totalWeeks: 20, excludedWeeks: rules.excludedWeeks, calendar: calendar))
    }

    func testRuleSettingsCanDisableNationalHolidaySkippedWeeks() throws {
        let rules = SunshineRunRuleSettings(skipsExcludedWeeks: false)

        XCTAssertTrue(rules.excludedWeeks.isEmpty)
    }

    func testProgressSummaryIgnoresExcludedHolidayWeekRecords() throws {
        let start = try makeDate("2026-03-09")
        let records = [
            SunshineRunRecord(date: try makeDate("2026-04-20"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-04-27"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar),
            SunshineRunRecord(date: try makeDate("2026-05-04"), semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar)
        ]

        let summary = SunshineRunPlanner.progressSummary(records: records, semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar)
        let progresses = SunshineRunPlanner.periodProgresses(records: records, semesterStart: start, totalWeeks: 20, excludedWeeks: [8], calendar: calendar)

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(progresses[3].count, 2)
    }

    func testNotificationPlanStaysEmptyWhenDisabled() throws {
        let start = try makeDate("2026-03-09")
        let settings = SunshineRunReminderSettings(isEnabled: false, selectedWeekdays: [2, 4], hour: 20, minute: 0)
        let plan = SunshineRunPlanner.notificationPlan(
            settings: settings,
            records: [],
            now: try makeDateTime("2026-03-09 08:00"),
            semesterStart: start,
            totalWeeks: 20,
            calendar: calendar
        )

        XCTAssertTrue(plan.isEmpty)
    }

    func testNotificationPlanUsesSelectedWeekdaysAndTime() throws {
        let start = try makeDate("2026-03-09")
        let settings = SunshineRunReminderSettings(isEnabled: true, selectedWeekdays: [2, 4], hour: 20, minute: 0)
        let plan = SunshineRunPlanner.notificationPlan(
            settings: settings,
            records: [],
            now: try makeDateTime("2026-03-09 08:00"),
            semesterStart: start,
            totalWeeks: 20,
            calendar: calendar,
            limit: 4
        )

        XCTAssertEqual(plan.map { displayDateTime($0.fireDate) }, [
            "2026-03-10 20:00",
            "2026-03-12 20:00",
            "2026-03-17 20:00",
            "2026-03-19 20:00"
        ])
        XCTAssertEqual(plan.first?.periodTitle, "第 1-2 周")
        XCTAssertEqual(plan.first?.remainingCount, 4)
    }

    func testNotificationPlanSkipsExcludedHolidayWeeks() throws {
        let start = try makeDate("2026-03-09")
        let settings = SunshineRunReminderSettings(isEnabled: true, selectedWeekdays: [1], hour: 20, minute: 0)
        let plan = SunshineRunPlanner.notificationPlan(
            settings: settings,
            records: [],
            now: try makeDateTime("2026-04-20 08:00"),
            semesterStart: start,
            totalWeeks: 20,
            excludedWeeks: [8],
            calendar: calendar,
            limit: 3
        )

        XCTAssertEqual(plan.map { displayDateTime($0.fireDate) }, [
            "2026-04-20 20:00",
            "2026-05-04 20:00",
            "2026-05-11 20:00"
        ])
        XCTAssertEqual(plan[1].periodTitle, "第 7、9 周")
    }

    func testNotificationPlanStopsAfterFullScore() throws {
        let start = try makeDate("2026-03-09")
        let records = try (0..<34).map { offset in
            SunshineRunRecord(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start)),
                semesterStart: start,
                calendar: calendar
            )
        }
        let settings = SunshineRunReminderSettings(isEnabled: true, selectedWeekdays: [2, 4], hour: 20, minute: 0)
        let plan = SunshineRunPlanner.notificationPlan(
            settings: settings,
            records: records,
            now: try makeDateTime("2026-03-09 08:00"),
            semesterStart: start,
            totalWeeks: 20,
            excludedWeeks: [],
            calendar: calendar
        )

        XCTAssertTrue(plan.isEmpty)
    }

    private func makeDate(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return try XCTUnwrap(formatter.date(from: string))
    }

    private func makeDateTime(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: string))
    }

    private func displayDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
