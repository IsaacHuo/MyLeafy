import XCTest
@testable import Leafy

final class WidgetAgendaFormattingTests: XCTestCase {
    func testEnglishAfternoonTimesMatchThe24HourWeekAxis() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: LeafyWidgetConstants.appGroupIdentifier))
        let previous = defaults.object(forKey: LeafyWidgetConstants.appLanguagePreferenceKey)
        defaults.set("en-US", forKey: LeafyWidgetConstants.appLanguagePreferenceKey)
        defer { defaults.set(previous, forKey: LeafyWidgetConstants.appLanguagePreferenceKey) }

        XCTAssertEqual(LeafyWidgetAgendaItem.time(date(hour: 14, minute: 5)), "14:05")
        XCTAssertEqual(item(start: date(hour: 14), end: date(hour: 16)).timeText, "14:00–16:00")
    }

    func testMissingEndDoesNotInventAnEndTime() {
        XCTAssertEqual(item(start: date(hour: 19, minute: 30), end: nil).timeText, "19:30")
    }

    func testCrossMidnightLabelsKeepTheActualEnd() {
        let end = LeafyWidgetSnapshotArchive.calendar.date(byAdding: .day, value: 1, to: date(hour: 2))!
        XCTAssertEqual(item(start: date(hour: 23), end: end).timeText, "23:00–02:00")
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        LeafyWidgetSnapshotArchive.calendar.date(from: DateComponents(year: 2026, month: 10, day: 24,
                                                                      hour: hour, minute: minute))!
    }

    private func item(start: Date, end: Date?) -> LeafyWidgetAgendaItem {
        LeafyWidgetAgendaItem(id: "formatting", kind: .schedule, sourceID: "formatting", title: "Offline fixture",
                              startsAt: start, endsAt: end, locationText: "", accentIndex: 0)
    }
}
