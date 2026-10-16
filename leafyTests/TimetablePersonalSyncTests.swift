import XCTest
import SwiftData
@testable import Leafy

@MainActor
final class TimetablePersonalSyncTests: XCTestCase {
    private var retainedContainer: ModelContainer?
    private func context() throws -> ModelContext {
        let schema = Schema([Course.self, Grade.self, CourseNote.self, CourseOccurrenceNote.self,
            CourseReminderSetting.self, TimetableCellReminder.self, ScheduleMemo.self,
            ScheduleMemoImage.self, ScheduleMemoAttachment.self, ScheduleMemoAudio.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        retainedContainer = container
        return container.mainContext
    }
    private func record(day: Int = 1, room: String = "101", teacher: String = "林老师") -> ParsedCourseRecord {
        ParsedCourseRecord(courseName: "数据结构", teacher: teacher, classInfo: "一班", room: room,
            location: "二教", dayOfWeek: day, weeks: [1, 2, 3], duration: [1, 2])
    }
    func testLatestReplacementKeepsPersonalDataWhenTeacherPlaceAndDayChange() throws {
        let context = try context()
        let old = record().makeCourse(semesterID: "old")
        let note = CourseNote(courseKey: old.stableCourseKey, text: "带实验报告")
        let occurrence = CourseOccurrenceNote(courseKey: old.stableCourseKey, occurrenceKey: old.occurrenceKey(week: 2), week: 2, dayOfWeek: 1, text: "交作业")
        let setting = CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 15)
        let schedule = TimetableCellReminder(week: 2, dayOfWeek: 3, period: 5, title: "个人安排", startsAt: Date(timeIntervalSince1970: 100))
        context.insert(old); context.insert(note); context.insert(occurrence); context.insert(setting); context.insert(schedule)
        try context.save()
        _ = try TimetableRefreshUseCase().persist(records: [record(day: 4, room: "306", teacher: "新老师")], existingCourses: [old], modelContext: context, semesterID: "new")
        let replacement = try XCTUnwrap(context.fetch(FetchDescriptor<Course>()).first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
        XCTAssertEqual(replacement.teacher, "新老师")
        XCTAssertEqual(note.text, "带实验报告")
        XCTAssertEqual(note.courseKey, replacement.stableCourseKey)
        XCTAssertEqual(occurrence.courseKey, replacement.stableCourseKey)
        XCTAssertEqual(occurrence.dayOfWeek, 4)
        XCTAssertFalse(setting.isUnassociated)
        XCTAssertEqual(setting.minutesBefore, 15)
        XCTAssertEqual(schedule.startsAt, Date(timeIntervalSince1970: 100))
    }
    func testRemovedCourseKeepsNotesAndPausesReminder() throws {
        let context = try context()
        let old = record().makeCourse(semesterID: "old")
        let note = CourseNote(courseKey: old.stableCourseKey, text: "不能删除")
        let setting = CourseReminderSetting(courseKey: old.stableCourseKey, minutesBefore: 20)
        context.insert(old); context.insert(note); context.insert(setting); try context.save()
        let saved = try TimetableRefreshUseCase().persist(records: [], existingCourses: [old], modelContext: context, allowsEmpty: true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 0)
        XCTAssertEqual(note.text, "不能删除")
        XCTAssertTrue(note.isUnassociated)
        XCTAssertTrue(setting.isUnassociated)
        XCTAssertTrue(saved.reminders.schedules.isEmpty)
    }
    func testEmptyRequiresConfirmationAndDoesNotMutateData() throws {
        let context = try context()
        let course = record().makeCourse(semesterID: "source")
        context.insert(course); try context.save()
        XCTAssertThrowsError(try TimetableRefreshUseCase().persist(records: [], existingCourses: [course], modelContext: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 1)
    }
    func testAmbiguousNewArrangementsKeepOccurrenceForManualRelinking() throws {
        let context = try context()
        let old = record().makeCourse(semesterID: "old")
        let note = CourseOccurrenceNote(courseKey: old.stableCourseKey, occurrenceKey: old.occurrenceKey(week: 2), week: 2, dayOfWeek: 1, text: "保留")
        context.insert(old); context.insert(note); try context.save()
        _ = try TimetableRefreshUseCase().persist(records: [record(teacher: "甲"), record(teacher: "乙")], existingCourses: [old], modelContext: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Course>()).count, 2)
        XCTAssertTrue(note.isUnassociated)
        XCTAssertEqual(note.text, "保留")
    }
    func testSettingsStayTwentyWeeksAcrossYearBoundary() throws {
        let base = SemesterRuntimeConfig.builtIn
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-30T04:00:00Z"))
        let config = UserTimetableSettings(academicYear: 2026, term: 2,
            firstMonday: UserTimetableSettings.monday(containing: date), periods: TimetablePeriodSchedule.defaultSlots)
        XCTAssertTrue(config.isValid)
        let timetable = AcademicYearTimetable(container: config.runtimeConfig(base: base))
        XCTAssertEqual(timetable.weeks.count, 20)
        XCTAssertEqual(timetable.pageIndex(containing: timetable.startDate), 1)
        XCTAssertNil(timetable.pageIndex(containing: timetable.endDate))
        XCTAssertEqual(UserTimetableSettings.calendar.component(.weekday, from: config.firstMonday), 2)
    }
    func testSettingsRejectOverlappingAndReversedPeriods() {
        var settings = UserTimetableSettingsStore.load()
        settings.periods[1] = .init(period: 2, startHour: 8, startMinute: 30, endHour: 9, endMinute: 0)
        XCTAssertFalse(settings.isValid)
        settings.periods = [.init(period: 1, startHour: 10, startMinute: 0, endHour: 9, endMinute: 0)]
        XCTAssertFalse(settings.isValid)
    }
    func testUserDateIsUnaffectedByNewRemoteConfig() throws {
        let name = "settings-sync-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UserTimetableSettingsStore.load(defaults: defaults)
        try UserTimetableSettingsStore.save(settings, defaults: defaults)
        SemesterRuntimeConfigCache.save(.previousSpring, defaults: defaults)
        XCTAssertEqual(UserTimetableSettingsStore.load(defaults: defaults), settings)
    }
    func testCloudTimetableFieldsPreserveConcurrentChangesToOtherFields() throws {
        let defaults = UserDefaults.standard
        let key = CampusScopedDefaults.key(UserTimetableSettingsStore.key)
        let editedKey = CampusScopedDefaults.key(UserTimetableSettingsStore.key + ".editedAt")
        let previous = defaults.data(forKey: key), previousDate = defaults.object(forKey: editedKey)
        defer { defaults.set(previous, forKey: key); defaults.set(previousDate, forKey: editedKey) }
        var base = UserTimetableSettingsStore.load()
        base.academicYear = 2026; base.term = 1
        base.periods = Array(TimetablePeriodSchedule.defaultSlots.prefix(12))
        try UserTimetableSettingsStore.save(base)
        let context = try context()
        func apply<T: Encodable>(_ field: String, _ payload: T) throws {
            try ICloudLocalData.apply(ICloudSyncValue(key: "settings/timetable/" + field,
                payload: ICloudLocalData.encode(payload), modifiedAt: Date()), context: context)
        }
        try apply("academicYear", 2028)
        XCTAssertEqual(UserTimetableSettingsStore.load().firstMonday, base.firstMonday)
        try apply("firstMonday", "2026-10-05")
        var merged = UserTimetableSettingsStore.load()
        XCTAssertEqual(merged.academicYear, 2028)
        XCTAssertEqual(merged.term, 1)
        XCTAssertEqual(merged.periods, base.periods)
        XCTAssertEqual(merged.firstMondayString, "2026-10-05")
        try apply("periods", TimetablePeriodSchedule.defaultSlots)
        try apply("term", 2)
        merged = UserTimetableSettingsStore.load()
        XCTAssertEqual(merged.firstMondayString, "2026-10-05")
        XCTAssertEqual(merged.academicYear, 2028)
        XCTAssertEqual(merged.term, 2)
        XCTAssertEqual(merged.periods, TimetablePeriodSchedule.defaultSlots)
        XCTAssertThrowsError(try apply("firstMonday", "2026-10-06"))
        XCTAssertEqual(UserTimetableSettingsStore.load(), merged)
    }
    func testTermDiscoveryUsesNumericOrderAndIgnoresBlankOptions() throws {
        let html = "<select name='termcode'><option value=''>请选择</option><option value='9'>旧</option><option value='10'>新</option><option value='10'>重复</option></select>"
        XCTAssertEqual(try SchoolNetworkManager.shared.timetableTermOptions(in: html, selector: "select[name=termcode] option"), ["10", "9"])
    }
    func testTXTExportsPastAndFutureWithoutInventingEnd() throws {
        let past = CustomScheduleEvent(id: "past", title: "过去的日程", startsAt: Date(timeIntervalSince1970: 100), note: "第一行\n第二行")
        let future = CustomScheduleEvent(id: "future", title: "未来的日程", startsAt: Date(timeIntervalSince1970: 4_000_000_000), minutesBefore: 15)
        let items = try PersonalScheduleExport.items(reminders: [], events: [future, past])
        XCTAssertEqual(items.map(\.key), ["personalSchedule:past", "personalSchedule:future"])
        let text = PersonalScheduleExport.text(items)
        XCTAssertTrue(text.contains("第一行\n第二行"))
        XCTAssertTrue(text.contains("提前 15 分钟"))
        XCTAssertFalse(text.contains("结束："))
        XCTAssertEqual(String(data: Data(text.utf8), encoding: .utf8), text)
    }
    func testAbsolutePersonalScheduleWithoutEndDoesNotInheritSemesterEndTime() {
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        let reminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 1,
            title: "个人日程", startsAt: date, endsAt: nil)
        XCTAssertEqual(reminder.resolvedStartDate, date)
        XCTAssertNil(reminder.resolvedEndDate)
    }
    func testCellCalendarKeyMatchesTimetableExporter() throws {
        let reminder = TimetableCellReminder(week: 1, dayOfWeek: 1, period: 1, title: "格子日程")
        let item = try XCTUnwrap(PersonalScheduleExport.items(reminders: [reminder], events: []).first)
        let drafts = TimetableCalendarExportBuilder.drafts(courses: [], courseNotes: [], occurrenceNotes: [], cellReminders: [reminder], range: .fullSemester, currentWeek: 1)
        XCTAssertEqual(item.key, drafts.first?.occurrenceKey)
        XCTAssertEqual(TimetableCalendarExportBuilder.url(for: item.key), drafts.first?.url)
    }
    func testDeletedRecordWinsOverOfflineEditAndRoundTrips() throws {
        let edit = ICloudSyncValue(key: "ScheduleMemo/a", payload: Data("edit".utf8), modifiedAt: Date(timeIntervalSince1970: 200))
        var deleted = edit; deleted.deleted = true; deleted.modifiedAt = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(ICloudSyncValue.winner(local: edit, remote: deleted).deleted)
        var journal = ICloudSyncJournal(); journal.records[edit.key] = deleted
        journal.capture([edit])
        XCTAssertTrue(try XCTUnwrap(journal.records[edit.key]).deleted)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try journal.save(to: url)
        XCTAssertEqual(try ICloudSyncJournal.load(from: url).records, journal.records)
    }
    func testJournalDetectsOfflineDeleteAndRetainsQueueAfterRestart() throws {
        let value = ICloudSyncValue(key: "CourseNote/a", payload: Data("note".utf8), modifiedAt: Date())
        var journal = ICloudSyncJournal(); journal.capture([value]); journal.pending = []
        journal.capture([])
        XCTAssertTrue(try XCTUnwrap(journal.records[value.key]).deleted)
        XCTAssertTrue(journal.pending.contains(value.key))
        let data = try JSONEncoder().encode(journal)
        let restored = try JSONDecoder().decode(ICloudSyncJournal.self, from: data)
        XCTAssertEqual(restored.pending, journal.pending)
    }
    func testJournalCorruptionThrowsWithoutOverwritingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("corrupt but preserved".utf8)
        try original.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ICloudSyncJournal.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testLocalCaptureIsIdempotentAndUsesSchoolFetchDate() {
        let value = ICloudSyncValue(key: "school/courses", payload: Data("courses".utf8), modifiedAt: Date(timeIntervalSince1970: 10))
        var journal = ICloudSyncJournal(); journal.capture([value], now: Date(timeIntervalSince1970: 50))
        let first = journal.records[value.key]
        journal.pending = []; journal.capture([value], now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(journal.records[value.key], first)
        XCTAssertEqual(first?.modifiedAt, value.modifiedAt)
        XCTAssertTrue(journal.pending.isEmpty)
    }
    func testCommittedSchoolRefreshCannotLoseToOldCloudWhileMetadataUpdateIsDelayed() {
        let old = ICloudSyncValue(key: "school/courses", payload: Data("old".utf8), modifiedAt: Date(timeIntervalSince1970: 1))
        var journal = ICloudSyncJournal()
        journal.capture([old])
        var incoming = old
        incoming.payload = Data("new committed courses".utf8)
        journal.capture([incoming], now: Date(timeIntervalSince1970: 10))
        let committed = journal.records[old.key]!
        XCTAssertEqual(ICloudSyncValue.winner(local: committed, remote: old).payload, incoming.payload)
    }
    func testInitialUnknownPreferenceUsesCloudInsteadOfNewDeviceDefault() {
        var cloud = ICloudSyncValue(key: "preference/theme", payload: Data("blue".utf8), modifiedAt: .distantPast)
        var local = ICloudSyncValue(key: cloud.key, payload: Data("default green".utf8), modifiedAt: .distantPast)
        cloud.revision = "A"; local.revision = "Z"
        XCTAssertEqual(ICloudSyncValue.winner(local: local, remote: cloud).payload, cloud.payload)
    }
    func testManualGradesAndExamsFromDifferentDevicesMergeWithoutLosingLocalRows() throws {
        let previous = CampusIdentityStore.currentIdentity()
        CampusIdentityStore.activate(CampusIdentity(campusID: .guest, eduID: "sync-test-" + UUID().uuidString, displayName: nil, portal: .undergraduate, kind: .guest))
        let examKey = CampusScopedDefaults.key("schoolCache.examSchedule")
        let dateKey = CampusScopedDefaults.key("schoolCache.lastExamScheduleSyncAt")
        defer {
            UserDefaults.standard.removeObject(forKey: examKey)
            UserDefaults.standard.removeObject(forKey: dateKey)
            if let previous { CampusIdentityStore.activate(previous) } else { CampusIdentityStore.clear() }
        }
        let context = try context()
        let localGrade = Grade(term: "一", courseName: "本机课程", credit: "2", score: "90", type: "必修")
        context.insert(localGrade); try context.save()
        let remoteGrade = Grade(term: "一", courseName: "另一台设备的课程", credit: "3", score: "95", type: "必修")
        let grade = ICloudSyncValue(key: "Grade/" + remoteGrade.id.uuidString.lowercased(), payload: try ICloudLocalData.encode(SyncedGrade(remoteGrade)), modifiedAt: Date())
        try ICloudLocalData.apply(grade, context: context); try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Grade>()).count, 2)
        let localExamID = UUID(), remoteExamID = UUID()
        let localExam = ExamArrangement(id: 1, courseID: "A", name: "本机考试", date: "2026-12-01", start: "08:00", end: "10:00", location: "101", syncID: localExamID)
        let remoteExam = ExamArrangement(id: 1, courseID: "B", name: "另一台设备的考试", date: "2026-12-02", start: "08:00", end: "10:00", location: "202", syncID: remoteExamID)
        SchoolDataCache.saveExamSchedule([localExam], notifies: false)
        let exam = ICloudSyncValue(key: "ManualExam/" + remoteExamID.uuidString.lowercased(), payload: try ICloudLocalData.encode(remoteExam), modifiedAt: Date())
        try ICloudLocalData.apply(exam, context: context)
        let merged = SchoolDataCache.loadExamSchedule()
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.map(\.id)).count, 2)
        XCTAssertEqual(merged.first { $0.syncID == localExamID }?.id, 1)
        XCTAssertEqual(Set(merged.compactMap(\.syncID)), [localExamID, remoteExamID])
    }
    func testAssetPathsRejectTraversal() {
        for path in ["../Leafy.store", "images/../secret", "images/..", "unknown/name", "images/abc\\def"] {
            XCTAssertThrowsError(try ICloudLocalData.fileURL(path))
        }
    }
    func testTextConflictCopyKeepsBothBodies() throws {
        let context = try context()
        let memo = ScheduleMemo(body: "原始内容")
        context.insert(memo); try context.save()
        let value = ICloudSyncValue(key: "ScheduleMemo/" + memo.id.uuidString.lowercased(), payload: try ICloudLocalData.encode(SyncedScheduleMemo(memo)), modifiedAt: Date())
        _ = try ICloudLocalData.conflictCopy(value, context: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleMemo>()).map(\.body).sorted(), ["原始内容", "原始内容"])
        // Replaying a received batch does not create another conflict copy.
        _ = try ICloudLocalData.conflictCopy(value, context: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleMemo>()).count, 2)
    }
}
