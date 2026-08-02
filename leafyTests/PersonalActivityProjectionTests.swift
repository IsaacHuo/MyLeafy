import Foundation
import SwiftData
import XCTest
@testable import Leafy

final class PersonalActivityProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func testProjectionSplitsCrossMidnightIntervalAcrossDays() throws {
        let start = try date(2026, 3, 2, 23, 30)
        let end = try date(2026, 3, 3, 0, 30)
        let range = DateInterval(start: try date(2026, 3, 2), end: try date(2026, 3, 4))

        let projection = ActivityProjection.make(
            intervals: [ActivityInterval(startedAt: start, endedAt: end)],
            channel: .focus,
            interval: range,
            now: try date(2026, 3, 3, 12),
            calendar: calendar
        )

        let monday = try XCTUnwrap(projection.days.first { calendar.isDate($0.date, inSameDayAs: start) })
        let tuesday = try XCTUnwrap(projection.days.first { calendar.isDate($0.date, inSameDayAs: end) })
        XCTAssertEqual(monday.duration, 30 * 60, accuracy: 0.1)
        XCTAssertEqual(tuesday.duration, 30 * 60, accuracy: 0.1)
        XCTAssertEqual(projection.totalDuration, 60 * 60, accuracy: 0.1)
        XCTAssertEqual(projection.activeDayCount, 2)
    }

    func testEmptyProjectionAlignsGridToMonday() throws {
        let range = DateInterval(start: try date(2026, 3, 4), end: try date(2026, 3, 6))
        let projection = ActivityProjection.make(
            intervals: [],
            channel: .focus,
            interval: range,
            now: try date(2026, 3, 5),
            calendar: calendar
        )

        let firstDay = try XCTUnwrap(projection.days.first)
        XCTAssertEqual(calendar.component(.weekday, from: firstDay.date), 2)
        XCTAssertEqual(firstDay.weekdayIndex, 0)
        XCTAssertEqual(projection.totalDuration, 0)
        XCTAssertEqual(projection.activeDayCount, 0)
    }

    func testFocusAndExerciseUseIndependentIntensityThresholds() throws {
        let start = try date(2026, 3, 2, 8)
        let range = DateInterval(start: try date(2026, 3, 2), end: try date(2026, 3, 3))
        let duration = 25.0 * 60
        let interval = ActivityInterval(startedAt: start, endedAt: start.addingTimeInterval(duration))

        let focus = ActivityProjection.make(
            intervals: [interval],
            channel: .focus,
            interval: range,
            now: start,
            calendar: calendar
        )
        let exercise = ActivityProjection.make(
            intervals: [interval],
            channel: .exercise,
            interval: range,
            now: start,
            calendar: calendar
        )

        XCTAssertEqual(focus.days.first(where: \.isInRange)?.intensity, 1)
        XCTAssertEqual(exercise.days.first(where: \.isInRange)?.intensity, 2)
    }

    func testChannelIntensityBoundaries() throws {
        let start = try date(2026, 3, 2, 8)
        let range = DateInterval(start: try date(2026, 3, 2), end: try date(2026, 3, 3))
        let focusCases = [(1, 1), (29, 1), (30, 2), (59, 2), (60, 3), (119, 3), (120, 4)]
        let exerciseCases = [(1, 1), (19, 1), (20, 2), (39, 2), (40, 3), (59, 3), (60, 4)]

        for (minutes, expected) in focusCases {
            let projection = ActivityProjection.make(
                intervals: [ActivityInterval(startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)))],
                channel: .focus,
                interval: range,
                now: start,
                calendar: calendar
            )
            XCTAssertEqual(projection.days.first(where: \.isInRange)?.intensity, expected, "专注 \(minutes) 分钟")
        }

        for (minutes, expected) in exerciseCases {
            let projection = ActivityProjection.make(
                intervals: [ActivityInterval(startedAt: start, endedAt: start.addingTimeInterval(Double(minutes * 60)))],
                channel: .exercise,
                interval: range,
                now: start,
                calendar: calendar
            )
            XCTAssertEqual(projection.days.first(where: \.isInRange)?.intensity, expected, "运动 \(minutes) 分钟")
        }
    }

    func testCurrentStreakMayEndYesterday() throws {
        let today = try date(2026, 3, 6, 9)
        let range = DateInterval(start: try date(2026, 3, 2), end: try date(2026, 3, 7))
        let intervals = try [2, 3, 4, 5].map { day -> ActivityInterval in
            let start = try date(2026, 3, day, 8)
            return ActivityInterval(startedAt: start, endedAt: start.addingTimeInterval(30 * 60))
        }

        let projection = ActivityProjection.make(
            intervals: intervals,
            channel: .exercise,
            interval: range,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(projection.currentStreak, 4)
        XCTAssertEqual(projection.longestStreak, 4)
    }

    func testNegativeAndOutOfRangeIntervalsDoNotContribute() throws {
        let range = DateInterval(start: try date(2026, 3, 2), end: try date(2026, 3, 4))
        let invalid = ActivityInterval(
            startedAt: try date(2026, 3, 3, 10),
            endedAt: try date(2026, 3, 3, 9)
        )
        let outside = ActivityInterval(
            startedAt: try date(2026, 2, 1, 8),
            endedAt: try date(2026, 2, 1, 9)
        )

        let projection = ActivityProjection.make(
            intervals: [invalid, outside],
            channel: .focus,
            interval: range,
            now: try date(2026, 3, 3),
            calendar: calendar
        )

        XCTAssertEqual(projection.totalDuration, 0)
        XCTAssertEqual(projection.activeDayCount, 0)
        XCTAssertEqual(projection.longestStreak, 0)
        XCTAssertEqual(projection.currentStreak, 0)
    }

    func testCurrentStreakIsZeroWhenRangeEndedBeforeYesterday() throws {
        let start = try date(2026, 2, 1, 8)
        let projection = ActivityProjection.make(
            intervals: [ActivityInterval(startedAt: start, endedAt: start.addingTimeInterval(30 * 60))],
            channel: .exercise,
            interval: DateInterval(start: try date(2026, 2, 1), end: try date(2026, 2, 2)),
            now: try date(2026, 3, 6),
            calendar: calendar
        )

        XCTAssertEqual(projection.longestStreak, 1)
        XCTAssertEqual(projection.currentStreak, 0)
    }

    func testSemesterRangeUsesSemanticSemesterEndEvent() throws {
        let config = SemesterRuntimeConfig(
            semesterID: "2025-2026-2",
            semesterStartDateString: "2026-02-23",
            supportedWeeks: 20,
            graduateTimetableTermCode: "45",
            calendarEvents: [
                SchoolCalendarEvent(
                    id: "semester-end",
                    title: "学期结束",
                    startDateString: "2026-07-10",
                    endDateString: "2026-07-10",
                    kind: .holiday,
                    academicCategory: .semesterEnd
                )
            ],
            updatedAt: nil,
            isActive: true
        )

        let interval = ActivityDateRangeResolver.interval(
            for: .semester,
            now: try date(2026, 6, 1),
            semesterConfig: config,
            calendar: calendar
        )

        XCTAssertEqual(interval.start, calendar.startOfDay(for: config.semesterStartDate))
        let semanticEnd = try XCTUnwrap(config.calendarEvents.first?.endDate)
        XCTAssertEqual(
            interval.end,
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: semanticEnd))
        )
    }

    @MainActor
    func testExerciseRecordBelongsToFixedAndCustomSpaces() {
        let customID = UUID()
        let fixed = ExerciseRecord(
            categoryRawValue: ExerciseSpaceCategory.running.rawValue,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "跑步",
            location: "操场"
        )
        let custom = ExerciseRecord(
            spaceID: customID.uuidString,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "羽毛球",
            location: "体育馆"
        )

        XCTAssertTrue(fixed.belongs(to: .fixed(.running)))
        XCTAssertFalse(fixed.belongs(to: .fixed(.fitness)))
        XCTAssertTrue(custom.belongs(to: .custom(customID)))
        XCTAssertFalse(custom.belongs(to: .fixed(.other)))
    }

    @MainActor
    func testArchivedExerciseSpaceRetainsItsDestinationAndRecords() {
        let space = ExerciseSpace(title: "校队训练", isArchived: true)
        let record = ExerciseRecord(
            spaceID: space.id.uuidString,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "训练",
            location: "球场"
        )

        XCTAssertTrue(space.isArchived)
        XCTAssertTrue(record.belongs(to: .custom(space.id)))
    }

    @MainActor
    func testDeletingCustomSpaceCanMoveRecordsToOther() throws {
        let container = try exerciseContainer()
        let context = container.mainContext
        let space = ExerciseSpace(title: "羽毛球")
        let record = ExerciseRecord(
            spaceID: space.id.uuidString,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "训练",
            location: "体育馆"
        )
        context.insert(space)
        context.insert(record)

        ExerciseSpaceRecordMutation.delete(
            space,
            records: [record],
            includingRecords: false,
            in: context,
            now: try date(2026, 3, 6)
        )
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSpace>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseRecord>()), 1)
        XCTAssertEqual(record.spaceID, "")
        XCTAssertEqual(record.category, .other)
    }

    @MainActor
    func testDeletingCustomSpaceCanDeleteItsRecords() throws {
        let container = try exerciseContainer()
        let context = container.mainContext
        let space = ExerciseSpace(title: "力量训练")
        let record = ExerciseRecord(
            spaceID: space.id.uuidString,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "训练",
            location: "健身房"
        )
        context.insert(space)
        context.insert(record)

        ExerciseSpaceRecordMutation.delete(
            space,
            records: [record],
            includingRecords: true,
            in: context
        )
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSpace>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseRecord>()), 0)
    }

    @MainActor
    func testClearingFixedSpaceDoesNotDeleteOtherRecords() throws {
        let container = try exerciseContainer()
        let context = container.mainContext
        let running = ExerciseRecord(
            categoryRawValue: ExerciseSpaceCategory.running.rawValue,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "跑步",
            location: "操场"
        )
        let fitness = ExerciseRecord(
            categoryRawValue: ExerciseSpaceCategory.fitness.rawValue,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "力量",
            location: "健身房"
        )
        context.insert(running)
        context.insert(fitness)

        ExerciseSpaceRecordMutation.clear(.fixed(.running), records: [running, fitness], in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ExerciseRecord>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.category, .fitness)
    }

    @MainActor
    func testAddingExerciseModelsPreservesExistingStudyTimeStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalActivityMigrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Leafy.store")
        let recordID = UUID()

        do {
            let legacySchema = Schema([StudyTimeRecord.self])
            let legacyConfiguration = ModelConfiguration(
                "PersonalActivityMigration",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            legacyContainer.mainContext.insert(StudyTimeRecord(
                id: recordID,
                startedAt: try date(2026, 3, 6, 8),
                endedAt: try date(2026, 3, 6, 9),
                content: "复习",
                location: "图书馆"
            ))
            try legacyContainer.mainContext.save()
        }

        let expandedSchema = Schema([StudyTimeRecord.self, ExerciseSpace.self, ExerciseRecord.self])
        let expandedConfiguration = ModelConfiguration(
            "PersonalActivityMigration",
            schema: expandedSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let expandedContainer = try ModelContainer(
            for: expandedSchema,
            configurations: [expandedConfiguration]
        )

        let preservedRecords = try expandedContainer.mainContext.fetch(FetchDescriptor<StudyTimeRecord>())
        XCTAssertEqual(preservedRecords.map(\.id), [recordID])
        XCTAssertEqual(try expandedContainer.mainContext.fetchCount(FetchDescriptor<ExerciseSpace>()), 0)
        XCTAssertEqual(try expandedContainer.mainContext.fetchCount(FetchDescriptor<ExerciseRecord>()), 0)
    }

    @MainActor
    func testLocalAccountCleanupDeletesExerciseSpacesAndRecords() throws {
        let setup = AppModelContainerFactory.make()
        let context = setup.container.mainContext
        let space = ExerciseSpace(title: "夜跑")
        let record = ExerciseRecord(
            spaceID: space.id.uuidString,
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            content: "跑步",
            location: "操场"
        )
        context.insert(space)
        context.insert(record)
        try context.save()

        try AppSessionResetter.deleteAllModels(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSpace>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseRecord>()), 0)
    }

    @MainActor
    private func exerciseContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ExerciseSpace.self,
            ExerciseRecord.self,
            configurations: configuration
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }
}
