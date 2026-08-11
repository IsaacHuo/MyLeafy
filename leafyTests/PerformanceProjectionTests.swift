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
    func testRatingCatalogWorkspaceLoadsEachSectionOnceOnDemand() {
        let workspace = RatingCatalogWorkspace()

        XCTAssertTrue(workspace.teachers.beginInitialLoad())
        XCTAssertFalse(workspace.teachers.beginInitialLoad())
        XCTAssertFalse(workspace.courses.hasStartedInitialLoad)
        XCTAssertFalse(workspace.dishes.hasStartedInitialLoad)

        XCTAssertTrue(workspace.courses.beginInitialLoad())
        XCTAssertTrue(workspace.teachers.hasStartedInitialLoad)
        XCTAssertTrue(workspace.courses.hasStartedInitialLoad)
        XCTAssertFalse(workspace.dishes.hasStartedInitialLoad)
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

    func testCompactTimestampFormatterKeepsExistingFeedFormat() throws {
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 9, minute: 5)))

        XCTAssertEqual(CommunityCompactTimestampFormatter.string(from: date), "7/22 09:05")
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
