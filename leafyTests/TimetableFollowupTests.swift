import SwiftData
import SwiftUI
import XCTest
@testable import Leafy

@MainActor
final class TimetableFollowupTests: XCTestCase {
    private func course(room: String = "501", classInfo: String = "一班",
                        weeks: [Int] = [2, 5, 6, 7, 8, 9, 10, 11, 12]) -> Course {
        Course(courseName: "随机过程B", teacher: "教师甲", classInfo: classInfo, room: room, location: "二教",
               dayOfWeek: 2, weeks: weeks, duration: [6, 7])
    }
    private func container() throws -> ModelContainer {
        let schema = Schema([Course.self, CourseNote.self, CourseOccurrenceNote.self,
                             CourseReminderSetting.self, TimetableCellReminder.self])
        return try ModelContainer(for: schema,
                                  configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                                      cloudKitDatabase: .none)])
    }

    func testArrangementIdentitySeparatesRoomAndClassWithoutChangingReleasedAliases() {
        let first = course(), second = course(room: "108"), anotherClass = course(classInfo: "二班")
        XCTAssertEqual(first.previousStableCourseKey, second.previousStableCourseKey)
        XCTAssertNotEqual(first.stableCourseKey, second.stableCourseKey)
        XCTAssertNotEqual(first.stableCourseKey, anotherClass.stableCourseKey)
        XCTAssertNotEqual(first.occurrenceKey(week: 11), second.occurrenceKey(week: 11))
        XCTAssertTrue(TimetableNotificationManager.courseReminderIdentifiers(for: first)
            .contains(TimetableNotificationManager.notificationID(courseKey: first.previousStableCourseKey, week: 11)))
    }

    func testPersistOverlappingArrangementsDisplaysBothAndExportsSeparateEvents() throws {
        let container = try container(), context = container.mainContext
        let records = [course(), course(room: "108", weeks: [11, 12])].map {
            ParsedCourseRecord(courseName: $0.courseName, teacher: $0.teacher, classInfo: $0.classInfo,
                               room: $0.room, location: $0.location, dayOfWeek: $0.dayOfWeek,
                               weeks: $0.weeks, duration: $0.duration)
        }
        let result = try TimetableRefreshUseCase().persist(records: records, existingCourses: [], modelContext: context)
        let input = TimetableRenderInput(
            courses: result.courses,
            notes: [],
            occurrenceNotes: [],
            cellReminders: [],
            hidesWeekends: false
        )
        let snapshot = TimetableGridSnapshotCache().snapshot(input: input, totalWeeks: 20)
        XCTAssertEqual(snapshot.layouts(day: 2, week: 10).count, 1)
        let layouts = snapshot.layouts(day: 2, week: 11)
        XCTAssertEqual(layouts.count, 2)
        XCTAssertEqual(Set(layouts.map(\.laneIndex)), [0, 1])
        XCTAssertTrue(layouts.allSatisfy { $0.laneCount == 2 })
        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: result.courses,
            courseNotes: [],
            occurrenceNotes: [],
            range: .currentWeek,
            currentWeek: 11
        )
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(Set(drafts.map(\.url)).count, 2)
        let date = try XCTUnwrap(TimetablePeriodSchedule.startDate(for: result.courses[0], week: 11))
        let archive = LeafyWidgetSnapshotBuilder.makeArchiveForTesting(
            courses: result.courses,
            isAuthenticated: true,
            date: date
        )
        let widget = try XCTUnwrap(archive.snapshot(for: 0))
        let widgetCourses = widget.items.filter { $0.title == "随机过程B" }
        XCTAssertEqual(widgetCourses.count, 2)
        XCTAssertEqual(Set(widgetCourses.map(\.locationText)), ["二教 501", "二教 108"])
        XCTAssertEqual(
            Set(result.courses
                .map { TimetableNotificationManager.notificationID(courseKey: $0.stableCourseKey, week: 11) }).count,
            2
        )
    }

    func testUniqueReleasedNotesAndRemindersMigrateIdempotently() throws {
        let container = try container(), context = container.mainContext
        let course = course(), timestamp = Date(timeIntervalSince1970: 100)
        let note = CourseNote(courseKey: course.previousStableCourseKey, text: "带教材", updatedAt: timestamp)
        let occurrence = CourseOccurrenceNote(courseKey: course.previousStableCourseKey,
                                              occurrenceKey: CourseOccurrenceNote.occurrenceKey(
                                                  courseKey: course.previousStableCourseKey,
                                                  week: 11
                                              ),
                                              week: 11, dayOfWeek: 2, text: "交作业", updatedAt: timestamp)
        let reminder = CourseReminderSetting(
            courseKey: course.previousStableCourseKey,
            minutesBefore: 15,
            updatedAt: timestamp
        )
        context.insert(course); context.insert(note); context.insert(occurrence); context.insert(reminder)
        try context.save()
        XCTAssertNotNil(try TimetableArrangementIdentityMigration.run(context: context))
        XCTAssertEqual(note.courseKey, course.stableCourseKey)
        XCTAssertEqual(occurrence.occurrenceKey, course.occurrenceKey(week: 11))
        XCTAssertEqual(reminder.courseKey, course.stableCourseKey)
        XCTAssertEqual(note.updatedAt, timestamp)
        XCTAssertFalse(note.isUnassociated)
        XCTAssertNil(try TimetableArrangementIdentityMigration.run(context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseNote>()).count, 1)
    }

    func testAmbiguousReleasedRecordsRemainAndWeekUniqueOccurrenceStillMigrates() throws {
        let container = try container(), context = container.mainContext
        let first = course(), second = course(room: "108", weeks: [11, 12])
        let oldKey = first.previousStableCourseKey
        let note = CourseNote(courseKey: oldKey, text: "保留内容")
        let reminder = CourseReminderSetting(courseKey: oldKey, minutesBefore: 20)
        let unique = CourseOccurrenceNote(
            courseKey: oldKey,
            occurrenceKey: oldKey + "|week:2",
            week: 2,
            dayOfWeek: 2,
            text: "唯一课次"
        )
        let ambiguous = CourseOccurrenceNote(
            courseKey: oldKey,
            occurrenceKey: oldKey + "|week:11",
            week: 11,
            dayOfWeek: 2,
            text: "重叠课次"
        )
        context.insert(first); context.insert(second); context.insert(note); context.insert(reminder)
        context.insert(unique); context.insert(ambiguous); try context.save()
        let plan = try XCTUnwrap(TimetableArrangementIdentityMigration.run(context: context))
        XCTAssertTrue(note.isUnassociated)
        XCTAssertEqual(note.text, "保留内容")
        XCTAssertTrue(reminder.isUnassociated)
        XCTAssertTrue(plan.schedules.isEmpty)
        XCTAssertFalse(unique.isUnassociated)
        XCTAssertEqual(unique.occurrenceKey, first.occurrenceKey(week: 2))
        XCTAssertTrue(ambiguous.isUnassociated)
        XCTAssertEqual(ambiguous.text, "重叠课次")
    }

    func testMigrationSaveFailureRestoresOriginalAssociations() throws {
        let container = try container(), context = container.mainContext
        let course = course(), oldKey = course.previousStableCourseKey
        let note = CourseNote(courseKey: oldKey, text: "不可丢失")
        let setting = CourseReminderSetting(courseKey: oldKey, minutesBefore: 10)
        context.insert(course); context.insert(note); context.insert(setting); try context.save()
        XCTAssertThrowsError(try TimetableArrangementIdentityMigration.run(context: context) { _ in
            throw CocoaError(.fileWriteUnknown) })
        XCTAssertEqual(note.courseKey, oldKey)
        XCTAssertEqual(setting.courseKey, oldKey)
        XCTAssertEqual(note.text, "不可丢失")
        XCTAssertFalse(note.isUnassociated)
    }

    func testOldKeyReceivedFromICloudIsNormalizedBeforeUnlinkedCheck() throws {
        let container = try container(), context = container.mainContext
        let course = course(), note = CourseNote(courseKey: course.previousStableCourseKey, text: "旧设备备注")
        context.insert(course); context.insert(note); try context.save()
        XCTAssertTrue(try ICloudLocalData.markUnlinkedEdits(in: context))
        XCTAssertEqual(note.courseKey, course.stableCourseKey)
        XCTAssertFalse(note.isUnassociated)
        XCTAssertFalse(try ICloudLocalData.markUnlinkedEdits(in: context))
    }

    func testPeriodTimesListEveryPeriodAndItsOwnTime() {
        let course = course(); course.duration = [6, 7, 8, 9]
        let lines = course.periodTimesText.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4)
        for (index, period) in [6, 7, 8, 9].enumerated() {
            let slot = TimetablePeriodSchedule.slot(for: period)!
            XCTAssertEqual(lines[index], "\(period): \(slot.startText)–\(slot.endText)")
        }
        course.duration = [9, 6, 8, 6]
        let separated = course.periodTimesText.components(separatedBy: "\n")
        XCTAssertEqual(separated.count, 3)
        XCTAssertTrue(separated[0].hasPrefix("6: "))
        XCTAssertTrue(separated[1].hasPrefix("8: "))
        XCTAssertTrue(separated[2].hasPrefix("9: "))
    }

    func testConfigurationAndDataUpdatesWaitForDragAndCoalesce() {
        var buffer = TimetableUpdateBuffer()
        buffer.request([.timeline, .widget])
        buffer.request([.timeline, .data, .schedule, .reports])
        XCTAssertTrue(buffer.takeReady(isInteracting: true, hasInteractiveLayout: true).isEmpty)
        XCTAssertEqual(buffer.pending, [.timeline, .data, .schedule, .widget, .reports])
        XCTAssertEqual(buffer.takeReady(isInteracting: false, hasInteractiveLayout: true),
                       [.timeline, .data, .schedule, .widget, .reports])
        XCTAssertTrue(buffer.pending.isEmpty)
        XCTAssertTrue(buffer.takeReady(isInteracting: false, hasInteractiveLayout: true).isEmpty)
    }

    func testFirstFramePreparesDataBeforeWidgetAndNotificationMaintenance() {
        var buffer = TimetableUpdateBuffer()
        buffer.request([.data, .widget, .reports])
        XCTAssertEqual(buffer.takeReady(isInteracting: false, hasInteractiveLayout: false), [.data])
        XCTAssertEqual(buffer.pending, [.widget, .reports])
        XCTAssertEqual(buffer.takeReady(isInteracting: false, hasInteractiveLayout: true), [.widget, .reports])
    }

    func testInitialAndSubpixelLayoutsDoNotCancelFirstDrag() {
        XCTAssertFalse(TimetableScrollGeometry.shouldRebaseViewport(from: .zero, to: CGSize(width: 390, height: 600)))
        XCTAssertFalse(TimetableScrollGeometry.shouldRebaseViewport(
            from: CGSize(width: 390, height: 600),
            to: CGSize(width: 390.1, height: 600.1)
        ))
        XCTAssertTrue(TimetableScrollGeometry.shouldRebaseViewport(
            from: CGSize(width: 390, height: 600),
            to: CGSize(width: 760, height: 600)
        ))
    }

    func testReturnCoalescesRequestsAndCancellationReleasesPresentation() {
        let transition = TimetableReturnTransition()
        var updates = 0, cancellations = 0
        transition.prepare = { XCTAssertEqual($0, -1); return true }
        transition.cancelPresentation = { cancellations += 1 }
        transition.perform(direction: -1, reducesMotion: false) { updates += 1 }
        let request = transition.requestID
        transition.contentReady()
        XCTAssertEqual(transition.readyID, request)
        transition.perform(direction: 1, reducesMotion: false) { updates += 1 }
        XCTAssertEqual(updates, 1)
        transition.cancel()
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(transition.isActive)
        XCTAssertNil(transition.readyID)
        XCTAssertEqual(TimetableReturnTransition.duration, 0.14)
    }

    func testReducedMotionAndUnavailableSnapshotsReturnWithoutWaiting() {
        let transition = TimetableReturnTransition()
        var updates = 0
        transition.prepare = { _ in XCTFail("Reduced motion must not capture a snapshot"); return false }
        transition.perform(direction: 1, reducesMotion: true) { updates += 1 }
        XCTAssertFalse(transition.isActive)
        transition.prepare = { _ in false }
        transition.perform(direction: 1, reducesMotion: false) { updates += 1 }
        XCTAssertEqual(updates, 2)
        XCTAssertFalse(transition.isActive)
    }

    func testReturnAfterInterruptedResizeAllowsImmediatePaging() {
        let start = SemesterConfig.startOfSemesterDate
        let end = start.addingTimeInterval(139 * 86400)
        let controller = TimetableContinuousViewportController(weekStartDate: start, centerDate: start,
                                                               rangeStart: start, rangeEnd: end)
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.updatePaging(translation: -100)
        controller.resizeViewport()
        XCTAssertFalse(controller.beginPaging(viewportWidth: 390))
        controller.returnToToday(start)
        XCTAssertTrue(controller.beginPaging(viewportWidth: 390))
        controller.cancelPaging(reducesMotion: true)
        XCTAssertEqual(controller.phase, .idle)
    }
}
