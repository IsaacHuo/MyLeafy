import XCTest
import SwiftUI
@testable import Leafy

final class TimetableConflictLayoutTests: XCTestCase {
    private func item(_ id: String, _ start: Double, _ end: Double) -> TimetableConflictInterval {
        .init(id: id, start: start, end: end)
    }

    func testSingleAndAdjacentIntervalsUseFullWidth() {
        let layout = TimetableConflictLayout.make(intervals: [item("a", 0, 2), item("b", 2, 4)])
        XCTAssertTrue(layout.groups.isEmpty)
        XCTAssertEqual(layout.blocks.count, 2)
        XCTAssertTrue(layout.blocks.flatMap(\.segments).allSatisfy { $0.leading == 0 && $0.trailing == 1 })
    }

    func testNestedScheduleExpandsAfterCourseEnds() throws {
        let layout = TimetableConflictLayout.make(intervals: [item("course", 0, 2), item("schedule", 0, 4)])
        let schedule = try XCTUnwrap(layout.blocks.first { $0.id == "schedule" })
        XCTAssertEqual(schedule.segments.count, 2)
        XCTAssertEqual(schedule.segments[0].trailing - schedule.segments[0].leading, 0.5)
        XCTAssertEqual(schedule.segments[1].leading, 0)
        XCTAssertEqual(schedule.segments[1].trailing, 1)
        XCTAssertEqual(schedule.segments[0].end, schedule.segments[1].start)
    }

    func testPartialOverlapAndThreeWayChainNeverOverlapHorizontally() {
        let layout = TimetableConflictLayout.make(intervals: [
            item("a", 0, 4),
            item("b", 1, 3),
            item("c", 2, 6),
            item("d", 4, 7)
        ])
        XCTAssertTrue(layout.groups.isEmpty)
        for time in stride(from: 0.25, to: 7.0, by: 0.5) {
            let active = layout.blocks.flatMap(\.segments).filter { $0.start < time && $0.end > time }
                .sorted { $0.leading < $1.leading }
            for (left, right) in zip(active, active.dropFirst()) {
                XCTAssertLessThanOrEqual(left.trailing, right.leading) }
        }
        for block in layout.blocks {
            for (before, after) in zip(block.segments, block.segments.dropFirst()) where before.end == after.start {
                XCTAssertGreaterThan(min(before.trailing, after.trailing), max(before.leading, after.leading))
            }
        }
    }

    func testFourWayOverlapOnlyCollapsesCrowdedIntervalAndDeduplicates() throws {
        let intervals = [item("a", 0, 8), item("b", 2, 6), item("c", 3, 5), item("d", 4, 7), item("d", 4, 7)]
        let layout = TimetableConflictLayout.make(intervals: intervals)
        let group = try XCTUnwrap(layout.groups.first)
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertEqual(group.start, 4)
        XCTAssertEqual(group.end, 5)
        XCTAssertEqual(Set(group.itemIDs), Set(["a", "b", "c", "d"]))
        let a = try XCTUnwrap(layout.blocks.first { $0.id == "a" })
        XCTAssertTrue(a.segments.contains { $0.start == 0 && $0.end == 2 && $0.trailing == 1 })
        XCTAssertTrue(a.segments.contains { $0.start == 7 && $0.end == 8 && $0.leading == 0 })
        XCTAssertFalse(a.segments.contains { $0.start < 5 && $0.end > 4 })
    }

    func testFiveFullyOverlappingItemsHaveNoHiddenListLimit() throws {
        let layout = TimetableConflictLayout.make(intervals: (0 ..< 5).map { item("\($0)", 0, 2) })
        XCTAssertTrue(layout.blocks.isEmpty)
        XCTAssertEqual(try XCTUnwrap(layout.groups.first).itemIDs.count, 5)
    }

    func testRemovingOrReschedulingAnItemRecomputesLayout() {
        let original = [item("a", 0, 4), item("b", 0, 2)]
        let before = TimetableConflictLayout.make(intervals: original)
        let removed = TimetableConflictLayout.make(intervals: [original[0]])
        let moved = TimetableConflictLayout.make(intervals: [original[0], item("b", 4, 6)])
        XCTAssertNotEqual(before, removed)
        XCTAssertTrue(removed.blocks[0].segments.allSatisfy { $0.leading == 0 && $0.trailing == 1 })
        XCTAssertTrue(moved.blocks.flatMap(\.segments).allSatisfy { $0.leading == 0 && $0.trailing == 1 })
    }

    func testInputOrderDoesNotChangeLayoutAndInvalidIntervalsAreExcluded() {
        let intervals = [item("a", 0, 4), item("b", 1.5, 2.75), item("c", 2, 5)]
        XCTAssertEqual(
            TimetableConflictLayout.make(intervals: intervals),
            TimetableConflictLayout.make(intervals: Array(intervals.reversed()))
        )
        XCTAssertEqual(TimetableConflictLayout.make(intervals: [item("bad", 2, 1), item("nan", .nan, 4)]), .empty)
    }

    func testShapeHitRegionExcludesNotchAndNeighbor() {
        let rects = [CGRect(x: 50, y: 0, width: 50, height: 100), CGRect(x: 0, y: 100, width: 100, height: 100)]
        let path = TimetableConflictShape(rects: rects).path(in: CGRect(x: 0, y: 0, width: 100, height: 200))
        XCTAssertTrue(path.contains(CGPoint(x: 75, y: 50)))
        XCTAssertTrue(path.contains(CGPoint(x: 25, y: 150)))
        XCTAssertFalse(path.contains(CGPoint(x: 25, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 101, y: 150)))
    }

    func testTextUsesWidestRegionWithEnoughHeightAndEarliestTie() throws {
        let rects = [CGRect(x: 50, y: 0, width: 50, height: 100), CGRect(x: 0, y: 100, width: 100, height: 100)]
        XCTAssertEqual(try XCTUnwrap(TimetableConflictGeometry.textRegion(in: rects, minimumHeight: 28)), rects[1])
        let shortWide = [CGRect(x: 0, y: 0, width: 100, height: 5), CGRect(x: 50, y: 5, width: 50, height: 100)]
        XCTAssertEqual(try XCTUnwrap(TimetableConflictGeometry.textRegion(in: shortWide, minimumHeight: 28)).width, 50)
    }
}

@MainActor
final class TimetableConflictCacheTests: XCTestCase {
    private func metadata(
        date: Date,
        countdowns: [TimetableCountdownProjection] = [],
        exams: [TimetableExamProjection] = []
    ) -> TimetableDayMetadata {
        .init(
            week: 1,
            day: 1,
            date: date,
            isToday: false,
            dayTitle: "周一",
            numericDateText: "01-05",
            chineseDateText: "1 月 5 日",
            event: nil,
            countdowns: countdowns,
            exams: exams,
            projectionSignature: .init(countdowns: countdowns, exams: exams)
        )
    }

    func testCacheInvalidatesOnNotesSchedulesAndCoursesAndUsesCurrentDate() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let course = Course(
            courseName: "课程",
            teacher: "教师",
            room: "101",
            location: "教学楼",
            dayOfWeek: 1,
            weeks: [1],
            duration: [1, 2]
        )
        func snapshot(notes: [CourseNote] = [], courses: [Course]? = nil) -> TimetableGridSnapshot {
            .make(
                courses: courses ?? [course],
                notes: notes,
                occurrenceNotes: [],
                cellReminders: [],
                hidesWeekends: false,
                totalWeeks: 1
            )
        }
        let cache = TimetableConflictDayCache()
        let initial = cache.content(metadata: metadata(date: day), snapshot: snapshot(), totalClasses: 13)
        XCTAssertEqual(initial.items.count, 1)
        let note = CourseNote(courseKey: course.stableCourseKey, text: "完整的备注内容")
        let noted = cache.content(metadata: metadata(date: day), snapshot: snapshot(notes: [note]), totalClasses: 13)
        XCTAssertEqual(noted.items.values.first?.note, note.text)
        let start = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 20, second: 0, of: day))
        let end = try XCTUnwrap(calendar.date(bySettingHour: 11, minute: 25, second: 0, of: day))
        let schedule = TimetableCountdownProjection(
            eventID: "schedule",
            title: "日程",
            startsAt: start,
            endsAt: end,
            week: 1,
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 4
        )
        let scheduled = cache.content(
            metadata: metadata(date: day, countdowns: [schedule]),
            snapshot: snapshot(),
            totalClasses: 13
        )
        XCTAssertEqual(scheduled.items.count, 2)
        XCTAssertEqual(
            scheduled.items.values.first { $0.agenda.title == "日程" }?.interval.start,
            start.timeIntervalSinceReferenceDate
        )
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: day))
        let moved = cache.content(metadata: metadata(date: nextDay), snapshot: snapshot(), totalClasses: 13)
        XCTAssertEqual(
            try XCTUnwrap(moved.items.values.first).interval
                .start - (try XCTUnwrap(initial.items.values.first).interval.start),
            7 * 86400,
            accuracy: 1
        )
        XCTAssertEqual(moved.items.values.first?.agenda.date, nextDay)
        let empty = cache.content(metadata: metadata(date: nextDay), snapshot: snapshot(courses: []), totalClasses: 13)
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testExamsParticipateAndChangingTheirDurationInvalidatesCache() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let start = try XCTUnwrap(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day))
        func exam(end: Date) -> TimetableExamProjection {
            .init(
                examID: 1,
                name: "考试",
                startsAt: start,
                endsAt: end,
                startText: "08:00",
                location: "101",
                week: 1,
                dayOfWeek: 1,
                period: 1
            )
        }
        let snapshot = TimetableGridSnapshot.make(
            courses: [],
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false,
            totalWeeks: 1
        )
        let cache = TimetableConflictDayCache()
        let initial = cache.content(
            metadata: metadata(date: day, exams: [exam(end: start.addingTimeInterval(45 * 60))]),
            snapshot: snapshot,
            totalClasses: 13
        )
        let changed = cache.content(
            metadata: metadata(date: day, exams: [exam(end: start.addingTimeInterval(90 * 60))]),
            snapshot: snapshot,
            totalClasses: 13
        )
        XCTAssertNotEqual(initial.layout, changed.layout)
        XCTAssertEqual(changed.items.values.first?.typeText, "考试")
    }
}
