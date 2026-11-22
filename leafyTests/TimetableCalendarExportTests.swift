import EventKit
import XCTest
@testable import Leafy

@MainActor
final class TimetableCalendarExportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let courseKey = "semester:test|course:数学|week:2"

    private func url(_ key: String, scope: String? = "current") -> URL {
        var parts = URLComponents()
        parts.scheme = "leafy"
        parts.host = "timetable"
        parts.path = "/" + key
        if let scope { parts.queryItems = [URLQueryItem(name: "scope", value: scope)] }
        return parts.url!
    }

    private func selection(_ categories: Set<TimetableCalendarExportCategory> = [.courses],
                           keys: Set<String> = []) -> TimetableCalendarSelection {
        TimetableCalendarSelection(categories: categories, weeks: 2 ... 2,
                                   interval: DateInterval(start: start, duration: 7 * 86400), draftKeys: keys)
    }

    private func event(_ id: String, key: String? = nil, scope: String? = "current",
                       offset: TimeInterval = 60, writable: Bool = true) -> TimetableCalendarExistingEvent {
        TimetableCalendarExistingEvent(identifier: id, url: url(key ?? courseKey, scope: scope),
                                       startDate: start.addingTimeInterval(offset), isWritable: writable)
    }

    func testLegacyRequiresConfirmationBeforeAnyPlanIsReturned() throws {
        let events = [event("legacy", scope: nil), event("current")]
        XCTAssertThrowsError(try TimetableCalendarReconciliation.plan(
            events: events, selection: selection(keys: [courseKey]), scopeKey: "current", confirmedLegacyEventIDs: []
        )) { error in
            guard case TimetableCalendarExportError.legacyEventsRequireConfirmation(let ids) = error else {
                return XCTFail("Expected legacy confirmation, got \(error)")
            }
            XCTAssertEqual(ids, ["legacy"])
        }
        let plan = try TimetableCalendarReconciliation.plan(
            events: events, selection: selection(keys: [courseKey]), scopeKey: "current",
            confirmedLegacyEventIDs: ["legacy"]
        )
        XCTAssertEqual(plan.retainedByKey, [courseKey: "current"])
        XCTAssertEqual(plan.removedIdentifiers, ["legacy"])
    }

    func testAnotherLegacyEventNeedsNewConfirmation() {
        XCTAssertThrowsError(try TimetableCalendarReconciliation.plan(
            events: [event("old", scope: nil), event("new", scope: nil)], selection: selection(keys: [courseKey]),
            scopeKey: "current", confirmedLegacyEventIDs: ["old"]
        ))
    }

    func testUnselectedCategoriesWeeksAndOtherAccountsAreUntouched() throws {
        let events = [event("selected"), event("other-account", scope: "other"),
                      event("next-week", key: "course:数学|week:3"), event("exam", key: "exam:1"),
                      event("schedule", key: "cellReminder:1"), event("personal", key: "personalSchedule:1"),
                      event("unknown", key: "random")]
        let plan = try TimetableCalendarReconciliation.plan(
            events: events, selection: selection(), scopeKey: "current", confirmedLegacyEventIDs: []
        )
        XCTAssertEqual(plan.removedIdentifiers, ["selected"])
        XCTAssertTrue(plan.retainedByKey.isEmpty)
    }

    func testDuplicatesAreRemovedAndOutdatedCourseIsDeletedAfterDateMove() throws {
        let obsolete = "course:旧课|week:2"
        let events = [event("b", offset: -86400 * 60), event("a"), event("obsolete", key: obsolete)]
        let plan = try TimetableCalendarReconciliation.plan(
            events: events, selection: selection(keys: [courseKey]), scopeKey: "current", confirmedLegacyEventIDs: []
        )
        XCTAssertEqual(plan.retainedByKey, [courseKey: "a"])
        XCTAssertEqual(plan.removedIdentifiers, ["b", "obsolete"])
        let repeated = try TimetableCalendarReconciliation.plan(
            events: [event("a")], selection: selection(keys: [courseKey]), scopeKey: "current",
            confirmedLegacyEventIDs: []
        )
        XCTAssertEqual(repeated.retainedByKey, plan.retainedByKey)
        XCTAssertTrue(repeated.removedIdentifiers.isEmpty)
    }

    func testScheduleDateRangeHasExclusiveEndAndFollowsSelectedDraftIDs() throws {
        let selected = selection([.schedules, .exams], keys: ["cellReminder:moved"])
        let plan = try TimetableCalendarReconciliation.plan(
            events: [event("before", key: "exam:before", offset: -1),
                     event("inside", key: "exam:inside", offset: 0),
                     event("after", key: "exam:after", offset: 7 * 86400),
                     event("moved", key: "cellReminder:moved", offset: -86400)],
            selection: selected, scopeKey: "current", confirmedLegacyEventIDs: []
        )
        XCTAssertEqual(plan.removedIdentifiers, ["inside"])
        XCTAssertEqual(plan.retainedByKey, ["cellReminder:moved": "moved"])
    }

    func testClearFollowsMovedScheduleIDsAndDeletesRatherThanRetains() throws {
        let key = "cellReminder:moved"
        let plan = try TimetableCalendarReconciliation.plan(
            events: [event("moved", key: key, offset: -86400 * 60), event("outside", key: "exam:outside", offset: -1)],
            selection: selection([.schedules, .exams], keys: [key]), scopeKey: "current",
            confirmedLegacyEventIDs: [], clearing: true
        )
        XCTAssertTrue(plan.retainedByKey.isEmpty)
        XCTAssertEqual(plan.removedIdentifiers, ["moved"])
    }

    func testReadOnlyMatchingEventsBlockChangesButOtherAccountsDoNot() throws {
        XCTAssertThrowsError(try TimetableCalendarReconciliation.plan(
            events: [event("readonly", writable: false)], selection: selection(keys: [courseKey]),
            scopeKey: "current", confirmedLegacyEventIDs: []
        )) { error in
            guard case TimetableCalendarExportError.readOnlyEvents = error
            else { return XCTFail("Unexpected \(error)") }
        }
        let plan = try TimetableCalendarReconciliation.plan(
            events: [event("other", scope: "another", writable: false)], selection: selection(),
            scopeKey: "current", confirmedLegacyEventIDs: []
        )
        XCTAssertTrue(plan.removedIdentifiers.isEmpty)
    }

    func testURLRoundTripDecodesExactlyOnce() {
        let key = "course:名字含%20和/斜线|week:2"
        XCTAssertEqual(TimetableCalendarExportBuilder.occurrenceKey(from: url(key)), key)
        XCTAssertNil(TimetableCalendarExportBuilder.occurrenceKey(from: URL(string: "https://example.com/")))
    }

    func testBuilderFiltersCategoriesAndOmitsLocationAndNotificationMetadata() throws {
        let course = Course(courseName: "数学", teacher: "老师", room: "101", location: "教学楼",
                            dayOfWeek: 1, weeks: [2], duration: [1, 2])
        let reminder = TimetableCellReminder(week: 2, dayOfWeek: 1, period: 3, title: "自习",
                                             location: "图书馆", note: "带书", minutesBefore: 15)
        let drafts = TimetableCalendarExportBuilder.drafts(
            courses: [course], courseNotes: [], occurrenceNotes: [], cellReminders: [reminder],
            categories: [.schedules], range: .currentWeek, currentWeek: 2
        )
        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.occurrenceKey, TimetableCalendarExportBuilder.cellReminderKey(reminder))
        XCTAssertTrue(draft.location.isEmpty)
        XCTAssertFalse(draft.notes.contains("图书馆"))
        XCTAssertFalse(draft.notes.contains("本地通知"))
        XCTAssertTrue(draft.notes.contains("带书"))
        XCTAssertTrue(TimetableCalendarExportBuilder.drafts(
            courses: [course], courseNotes: [], occurrenceNotes: [], cellReminders: [reminder],
            categories: [], range: .fullSemester, currentWeek: 2
        ).isEmpty)
        XCTAssertEqual(reminder.locationText, "图书馆")
        XCTAssertEqual(reminder.minutesBefore, 15)
    }

    func testApplyingDraftMovesCalendarAndRemovesOldAlarmsAndLocation() {
        let store = EKEventStore()
        let previous = EKCalendar(for: .event, eventStore: store)
        let destination = EKCalendar(for: .event, eventStore: store)
        let event = EKEvent(eventStore: store)
        event.calendar = previous
        event.location = "旧教室"
        event.structuredLocation = EKStructuredLocation(title: "旧定位")
        let alarm = EKAlarm(relativeOffset: -900)
        alarm.structuredLocation = EKStructuredLocation(title: "离开此地")
        alarm.proximity = .leave
        event.alarms = [alarm]
        let draft = TimetableCalendarEventDraft(occurrenceKey: courseKey, title: "数学", location: "不应写入",
                                                notes: "备注", startDate: start, endDate: start.addingTimeInterval(3600),
                                                url: url(courseKey))
        TimetableCalendarExportService.apply(draft, to: event, calendar: destination)
        XCTAssertTrue(event.calendar === destination)
        XCTAssertTrue(event.alarms?.isEmpty ?? true)
        XCTAssertNil(event.location)
        XCTAssertNil(event.structuredLocation)
        XCTAssertEqual(event.notes, "备注")
    }

    func testTextExportStillIncludesOriginalLocationAndReminder() {
        let item = PersonalScheduleExportItem(key: "personalSchedule:1", title: "自习", start: start, end: nil,
                                              location: "图书馆", note: "笔记", minutesBefore: 15)
        let text = PersonalScheduleExport.text([item])
        XCTAssertTrue(text.contains("地点：图书馆"))
        XCTAssertTrue(text.contains("提醒：提前 15 分钟"))
    }
}
