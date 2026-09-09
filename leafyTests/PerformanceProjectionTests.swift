import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Supabase
import SwiftData
@testable import Leafy

final class PerformanceProjectionTests: XCTestCase {
    @MainActor
    func testRatingCatalogRetainsDataAndOnlyCompletesCurrentSuccessfulRequest() {
        let workspace = RatingCatalogWorkspace()
        let first = workspace.teachers.load.begin()
        workspace.teachers.search = "测试"
        XCTAssertFalse(workspace.teachers.load.hasLoaded)
        workspace.teachers.load.cancel()
        workspace.teachers.load.complete(first)
        XCTAssertFalse(workspace.teachers.load.hasLoaded)
        let second = workspace.teachers.load.begin()
        XCTAssertFalse(workspace.teachers.load.isCurrent(first))
        workspace.teachers.load.complete(second)
        XCTAssertTrue(workspace.teachers.load.hasLoaded)
        XCTAssertEqual(workspace.teachers.search, "测试")
        XCTAssertFalse(workspace.courses.load.hasLoaded)
        XCTAssertFalse(workspace.dishes.load.hasLoaded)
    }

    func testMasonryProjectionPreservesAlternatingOrder() {
        let columns = CommunityMasonryColumns(items: Array(0..<7))

        XCTAssertEqual(columns.left, [0, 2, 4, 6])
        XCTAssertEqual(columns.right, [1, 3, 5])
    }

    func testProfileDraftBoxOccupiesFirstMasonrySlot() {
        let columns = CommunityMasonryColumns(
            items: ["draft-box", "post-0", "post-1", "post-2"]
        )

        XCTAssertEqual(columns.left, ["draft-box", "post-1"])
        XCTAssertEqual(columns.right, ["post-0", "post-2"])
    }

    func testCompactTimestampFormatterUsesRequestedLocale() throws {
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 9, minute: 5)))

        let chinese = CommunityCompactTimestampFormatter.string(
            from: date,
            locale: Locale(identifier: "zh-Hans")
        )
        let english = CommunityCompactTimestampFormatter.string(
            from: date,
            locale: Locale(identifier: "en-US")
        )

        XCTAssertEqual(chinese, "7/22 09:05")
        XCTAssertTrue(english.contains("7/22"))
        // Compact timestamps intentionally omit AM/PM.
        XCTAssertTrue(english.contains("9:05"))
        XCTAssertNotEqual(chinese, english)
    }

    func testMasonryFavoriteAccessibilityTextIsLocalizedForEachState() {
        XCTAssertEqual(L10n.text("收藏", language: .enUS), "Favorite")
        XCTAssertEqual(L10n.text("取消收藏", language: .enUS), "Cancel collection")
        XCTAssertEqual(L10n.text("未选择", language: .enUS), "Not selected")
        XCTAssertEqual(L10n.text("已选择", language: .enUS), "Selected")
    }

    @MainActor
    func testTimetableCacheAcceptsOnePrebuiltRenderInput() {
        let course = Course(
            courseName: "A",
            teacher: "T",
            room: "101",
            location: "",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1]
        )
        let input = TimetableRenderInput(
            courses: [course],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false
        )
        let cache = TimetableGridSnapshotCache()

        let first = cache.snapshot(input: input, totalWeeks: 2)
        let second = cache.snapshot(input: input, totalWeeks: 2)

        XCTAssertEqual(cache.buildCount, 1)
        XCTAssertEqual(first.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
        XCTAssertEqual(second.layouts(day: 1, week: 1).map(\.course.courseName), ["A"])
    }
}
