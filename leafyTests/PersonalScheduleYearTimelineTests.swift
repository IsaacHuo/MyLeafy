import Foundation
import XCTest
@testable import Leafy

final class PersonalScheduleYearTimelineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testNaturalYearContainsOnlySelectedYearAndUsesMondayWeeks() throws {
        let timeline = PersonalScheduleYearTimeline(year: 2026, calendar: calendar)
        let firstWeek = try XCTUnwrap(timeline.weeks.first)
        let lastWeek = try XCTUnwrap(timeline.weeks.last)

        XCTAssertEqual(string(firstWeek), "2025-12-29")
        XCTAssertEqual(string(lastWeek), "2026-12-28")
        XCTAssertTrue(timeline.contains(date("2026-01-01"), calendar: calendar))
        XCTAssertTrue(timeline.contains(date("2026-12-31"), calendar: calendar))
        XCTAssertFalse(timeline.contains(date("2027-01-01"), calendar: calendar))
    }

    func testPageMappingSupportsFutureYearsWithoutFixedRange() throws {
        let timeline = PersonalScheduleYearTimeline(year: 2029, calendar: calendar)
        let target = date("2029-07-18")
        let page = try XCTUnwrap(timeline.pageIndex(containing: target, calendar: calendar))
        let reconstructed = try XCTUnwrap(
            timeline.date(page: page, dayOfWeek: 3, calendar: calendar)
        )

        XCTAssertEqual(string(reconstructed), "2029-07-18")
        XCTAssertNil(timeline.pageIndex(containing: date("2028-12-31"), calendar: calendar))
    }

    func testLeapAndNonLeapYearsBothCoverTheirLastDay() {
        XCTAssertTrue(
            PersonalScheduleYearTimeline(year: 2028, calendar: calendar)
                .contains(date("2028-12-31"), calendar: calendar)
        )
        XCTAssertTrue(
            PersonalScheduleYearTimeline(year: 2029, calendar: calendar)
                .contains(date("2029-12-31"), calendar: calendar)
        )
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    private func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
