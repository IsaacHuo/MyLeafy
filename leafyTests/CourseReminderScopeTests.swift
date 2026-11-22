import Foundation
import SwiftData
import XCTest
@testable import Leafy

@MainActor
final class CourseReminderScopeTests: XCTestCase {
    private func course(teacher: String = "教师甲", weeks: [Int] = [1, 2, 3, 4]) -> Course {
        Course(courseName: "范围测试课", teacher: teacher, classInfo: "一班", room: "101", location: "二教",
               dayOfWeek: 2, weeks: weeks, duration: [1, 2])
    }
    private func container() throws -> ModelContainer {
        let schema = Schema([Course.self, CourseNote.self, CourseOccurrenceNote.self,
                             CourseReminderSetting.self, TimetableCellReminder.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                cloudKitDatabase: .none)]
        )
    }
    private func record(_ course: Course) -> ParsedCourseRecord {
        ParsedCourseRecord(courseName: course.courseName, teacher: course.teacher, classInfo: course.classInfo,
                           room: course.room, location: course.location, dayOfWeek: course.dayOfWeek,
                           weeks: course.weeks, duration: course.duration)
    }

    func testOccurrenceOverrideAndExplicitOffKeepOtherWeeksOnDefault() throws {
        let course = course()
        let all = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 15)
        let off = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 0, week: 2)
        let once = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 5, week: 3)
        let settings = [all, off, once]
        XCTAssertEqual(
            CourseReminderResolver.effective(courseKey: course.stableCourseKey, week: 1, settings: settings)?
                .minutesBefore,
            15
        )
        XCTAssertEqual(
            CourseReminderResolver.effective(courseKey: course.stableCourseKey, week: 2, settings: settings)?
                .minutesBefore,
            0
        )
        XCTAssertEqual(
            CourseReminderResolver.effective(courseKey: course.stableCourseKey, week: 3, settings: settings)?
                .minutesBefore,
            5
        )
        let plan = try TimetableReminderRefreshPlan(oldIdentifiers: [], courses: [course], settings: settings)
        XCTAssertEqual(plan.schedules.first { $0.minutesBefore == 15 }?.course.weeks, [1, 4])
        XCTAssertEqual(plan.schedules.first { $0.minutesBefore == 5 }?.course.weeks, [3])
        XCTAssertFalse(plan.schedules.flatMap { $0.course.weeks }.contains(2))
    }

    func testOnlyOccurrenceSettingDoesNotCreateOtherWeekReminders() throws {
        let course = course()
        let setting = CourseReminderSetting(
            courseKey: course.stableCourseKey,
            minutesBefore: 10,
            anchorPeriod: 2,
            week: 3
        )
        let plan = try TimetableReminderRefreshPlan(oldIdentifiers: [], courses: [course], settings: [setting])
        XCTAssertEqual(plan.schedules.count, 1)
        XCTAssertEqual(plan.schedules.first?.course.weeks, [3])
        XCTAssertEqual(plan.schedules.first?.anchorPeriod, 2)
        XCTAssertNil(CourseReminderResolver.effective(courseKey: course.stableCourseKey, week: 4, settings: [setting]))
    }

    func testChangingDefaultPreservesOccurrenceSettingsAndTheirOffValue() throws {
        let container = try container(), context = container.mainContext
        let course = course(); context.insert(course); try context.save()
        try TimetableLocalEdits.setReminder(
            courseKey: course.stableCourseKey,
            minutesBefore: 15,
            anchorPeriod: 1,
            in: context
        )
        try TimetableLocalEdits.setReminder(
            courseKey: course.stableCourseKey,
            minutesBefore: 0,
            anchorPeriod: 2,
            week: 2,
            in: context
        )
        try TimetableLocalEdits.setReminder(
            courseKey: course.stableCourseKey,
            minutesBefore: 30,
            anchorPeriod: 1,
            in: context
        )
        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(settings.count, 2)
        XCTAssertEqual(
            CourseReminderResolver.record(courseKey: course.stableCourseKey, week: nil, settings: settings)?
                .minutesBefore,
            30
        )
        XCTAssertEqual(
            CourseReminderResolver.record(courseKey: course.stableCourseKey, week: 2, settings: settings)?
                .minutesBefore,
            0
        )
        XCTAssertNotEqual(settings[0].scopeKey, settings[1].scopeKey)
    }

    func testFailedSaveRestoresSelectedOverrideAndLeavesDefaultUntouched() throws {
        let container = try container(), context = container.mainContext
        let course = course(); context.insert(course); try context.save()
        try TimetableLocalEdits.setReminder(
            courseKey: course.stableCourseKey,
            minutesBefore: 15,
            anchorPeriod: 1,
            in: context
        )
        try TimetableLocalEdits.setReminder(
            courseKey: course.stableCourseKey,
            minutesBefore: 5,
            anchorPeriod: 2,
            week: 2,
            in: context
        )
        XCTAssertThrowsError(try TimetableLocalEdits.setReminder(courseKey: course.stableCourseKey, minutesBefore: 60,
                                                                 anchorPeriod: 1, week: 2, in: context,
                                                                 save: { _ in throw CocoaError(.fileWriteUnknown) }))
        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(
            CourseReminderResolver.record(courseKey: course.stableCourseKey, week: nil, settings: settings)?
                .minutesBefore,
            15
        )
        let once = try XCTUnwrap(CourseReminderResolver.record(
            courseKey: course.stableCourseKey,
            week: 2,
            settings: settings
        ))
        XCTAssertEqual(once.minutesBefore, 5)
        XCTAssertEqual(once.anchorPeriod, 2)
        XCTAssertEqual(once.week, 2)
    }

    func testConflictsAreCheckedWithinScopeRatherThanAcrossDifferentWeeks() throws {
        let course = course()
        let first = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 5, week: 2)
        let otherWeek = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 30, week: 3)
        XCTAssertNoThrow(try TimetableReminderRefreshPlan(
            oldIdentifiers: [],
            courses: [course],
            settings: [first, otherWeek]
        ))
        let conflicting = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 10, week: 2)
        XCTAssertThrowsError(try TimetableReminderRefreshPlan(
            oldIdentifiers: [],
            courses: [course],
            settings: [first, conflicting]
        ))
    }

    func testRefreshTeacherSplitKeepsDefaultAndMovesOnlyMatchingOccurrenceOverride() throws {
        let container = try container(), context = container.mainContext
        let old = course(); context.insert(old)
        context.insert(CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 15))
        let once = CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 0, week: 3)
        context.insert(once); try context.save()
        let result = try TimetableRefreshUseCase().persist(records: [record(course(weeks: [1, 2])),
                                                                     record(course(teacher: "教师乙", weeks: [3, 4]))],
                                                           existingCourses: [old], modelContext: context)
        let second = try XCTUnwrap(result.courses.first { $0.teacher == "教师乙" })
        XCTAssertEqual(once.courseKey, second.stableCourseKey)
        XCTAssertEqual(once.week, 3)
        XCTAssertFalse(once.isUnassociated)
        let settings = try context.fetch(FetchDescriptor<CourseReminderSetting>())
        XCTAssertEqual(settings.filter { $0.week == nil }.count, 2)
        XCTAssertEqual(settings.filter { $0.week == 3 }.count, 1)
        XCTAssertEqual(result.reminders.schedules.first { $0.course.teacher == "教师乙" }?.course.weeks, [4])
    }

    func testRemovedOccurrenceIsPreservedUnassociatedAndNotScheduled() throws {
        let container = try container(), context = container.mainContext
        let old = course(), once = CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 10, week: 4)
        context.insert(old); context.insert(once); try context.save()
        let result = try TimetableRefreshUseCase().persist(records: [record(course(weeks: [1, 2]))],
                                                           existingCourses: [old], modelContext: context)
        XCTAssertTrue(once.isUnassociated)
        XCTAssertEqual(once.week, 4)
        XCTAssertEqual(once.minutesBefore, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseReminderSetting>()).count, 1)
        XCTAssertTrue(result.reminders.schedules.isEmpty)
    }

    func testLegacyIdentityMigrationKeepsBothScopesWithoutFalseConflict() throws {
        let container = try container(), context = container.mainContext
        let course = course(); context.insert(course)
        let all = CourseReminderSetting(courseKey: course.previousStableCourseKey, minutesBefore: 15)
        let once = CourseReminderSetting(courseKey: course.previousStableCourseKey, minutesBefore: 5, week: 2)
        context.insert(all); context.insert(once); try context.save()
        XCTAssertTrue(try ICloudLocalData.markUnlinkedEdits(in: context))
        XCTAssertEqual(all.courseKey, course.stableCourseKey)
        XCTAssertEqual(once.courseKey, course.stableCourseKey)
        XCTAssertNil(all.week)
        XCTAssertEqual(once.week, 2)
        XCTAssertFalse(all.isUnassociated)
        XCTAssertFalse(once.isUnassociated)
    }

    func testLegacyCloudPayloadDefaultsToWholeCourseAndOverrideRoundTrips() throws {
        let course = course()
        let all = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 15)
        let data = try JSONEncoder().encode(SyncedCourseReminderSetting(all))
        XCTAssertNil((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["week"])
        XCTAssertNil(try JSONDecoder().decode(SyncedCourseReminderSetting.self, from: data).make().week)
        let once = CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 0, anchorPeriod: 2, week: 3)
        let encoded = try JSONEncoder().encode(SyncedCourseReminderSetting(once))
        let restored = try JSONDecoder().decode(SyncedCourseReminderSetting.self, from: encoded).make()
        XCTAssertEqual(restored.week, 3)
        XCTAssertEqual(restored.minutesBefore, 0)
        XCTAssertEqual(restored.anchorPeriod, 2)
        XCTAssertEqual(restored.id, once.id)
    }

    func testWidgetUsesOccurrenceOverrideForEachWeek() throws {
        let course = course()
        let settings = [CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 15),
                        CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 0, week: 2)]
        for (week, hasReminder) in [(1, true), (2, false)] {
            let date = try XCTUnwrap(TimetablePeriodSchedule.startDate(for: course, week: week))
            let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(courses: [course], reminders: settings,
                                                                           isAuthenticated: true, date: date)
            let snapshot = try XCTUnwrap(archive.snapshot(for: 0))
            let item = try XCTUnwrap(snapshot.items.first { $0.kind == .course && $0.title == course.courseName })
            XCTAssertEqual(item.reminderText != nil, hasReminder)
        }
    }

    func testRebuildSchedulesEachEffectiveWeekOnce() async throws {
        let course = course()
        let plan = try TimetableReminderRefreshPlan(oldIdentifiers: ["old"], courses: [course], settings: [
            CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 15),
            CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 5, week: 2),
            CourseReminderSetting(courseKey: course.stableCourseKey, minutesBefore: 0, week: 3)
        ])
        let scheduler = ScopeRecordingScheduler()
        let warning = await plan.restore(using: scheduler)
        XCTAssertNil(warning)
        XCTAssertEqual(scheduler.cancelled, ["old"])
        XCTAssertEqual(scheduler.weeks, [1, 4, 2])
        XCTAssertEqual(Set(scheduler.weeks).count, scheduler.weeks.count)
    }

    func testAutomaticStoreUpgradePreservesExistingWholeCourseReminder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReminderUpgrade-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite"), id = UUID()
        try autoreleasepool {
            let schema = Schema([BeforeOccurrenceReminder.CourseReminderSetting.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
            )
            container.mainContext.insert(BeforeOccurrenceReminder.CourseReminderSetting(
                id: id,
                courseKey: "existing-course",
                minutesBefore: 15
            ))
            try container.mainContext.save()
        }
        let schema = Schema([CourseReminderSetting.self])
        let migrated = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        )
        let setting = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<CourseReminderSetting>()).first)
        XCTAssertEqual(setting.id, id)
        XCTAssertEqual(setting.courseKey, "existing-course")
        XCTAssertEqual(setting.minutesBefore, 15)
        XCTAssertNil(setting.week)
    }
}

@MainActor
private final class ScopeRecordingScheduler: TimetableCourseReminderScheduling {
    var cancelled: [String] = []
    var weeks: [Int] = []
    func cancel(identifiers: [String]) { cancelled = identifiers }
    func schedule(course: Course, minutesBefore: Int, anchorPeriod: Int?) async throws { weeks += course.weeks }
}

private enum BeforeOccurrenceReminder {
    @Model
    final class CourseReminderSetting {
        var isUnassociated: Bool = false
        var sourceCourseTitle: String = ""
        var id: UUID
        var courseKey: String
        var minutesBefore: Int
        var anchorPeriod: Int?
        var updatedAt: Date
        init(id: UUID, courseKey: String, minutesBefore: Int) {
            self.id = id; self.courseKey = courseKey; self.minutesBefore = minutesBefore; updatedAt = Date()
        }
    }
}
