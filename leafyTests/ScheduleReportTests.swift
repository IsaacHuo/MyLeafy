import XCTest
@testable import Leafy

final class ScheduleReportTests: XCTestCase {
    private struct LegacyCountdownEvent: Codable {
        let id: String
        let title: String
        let targetDate: Date
    }

    func testSettingsDefaultToDisabledModes() {
        let settings = ScheduleReportSettings()

        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.enabledModes.isEmpty)
        XCTAssertEqual(settings.setting(for: .morningReport).hour, 7)
        XCTAssertEqual(settings.setting(for: .morningReport).minute, 30)
    }

    func testSettingsStoreUsesCampusScopedKeyAndPreservesScheduledIDs() throws {
        let defaults = try makeDefaults()
        let identity = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "Tester",
            portal: .undergraduate
        )
        CampusIdentityStore.activate(identity, defaults: defaults)

        var settings = ScheduleReportSettings(isEnabled: true)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 32, minute: -5), for: .eveningReport)
        settings.scheduledNotificationIDs = ["one", "two"]
        ScheduleReportSettingsStore.save(settings, defaults: defaults)

        let key = ScheduleReportSettingsStore.scopedStorageKey(defaults: defaults)
        let loaded = ScheduleReportSettingsStore.load(defaults: defaults)

        XCTAssertTrue(key.hasPrefix("leafy.campus."))
        XCTAssertTrue(key.hasSuffix("scheduleReport.settings.v1"))
        XCTAssertEqual(loaded.setting(for: .eveningReport).hour, 23)
        XCTAssertEqual(loaded.setting(for: .eveningReport).minute, 0)
        XCTAssertEqual(loaded.scheduledNotificationIDs, ["one", "two"])
        XCTAssertTrue(loaded.isEnabled)
    }

    func testCustomScheduleStoreMigratesLegacyCountdownsOnce() throws {
        let defaults = try makeDefaults()
        let keys = CustomScheduleStore.storageKeysForTesting()
        let targetDate = try makeDateTime("2026-03-11 12:00")
        let legacyEvents = [
            LegacyCountdownEvent(id: "cet", title: "四级报名", targetDate: targetDate)
        ]
        defaults.set(try JSONEncoder().encode(legacyEvents), forKey: keys.legacy)

        let migrated = CustomScheduleStore.load(defaults: defaults)
        let repeated = CustomScheduleStore.load(defaults: defaults)

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.id, "cet")
        XCTAssertEqual(migrated.first?.title, "四级报名")
        XCTAssertEqual(migrated.first?.startsAt, targetDate)
        XCTAssertEqual(repeated, migrated)
        XCTAssertNotNil(defaults.data(forKey: keys.current))
    }

    func testUnifiedScheduleProjectsInsideSemesterAndCountsDownOutsideSemester() {
        let inside = CustomScheduleEvent(
            title: "学期内日程",
            startsAt: SemesterConfig.startOfSemesterDate.addingTimeInterval(86_400)
        )
        let outside = CustomScheduleEvent(
            title: "学期外日程",
            startsAt: SemesterConfig.startOfSemesterDate.addingTimeInterval(
                Double(SemesterConfig.supportedWeeks * 7 + 1) * 86_400
            )
        )

        XCTAssertNotNil(inside.timetableProjection)
        XCTAssertNil(outside.timetableProjection)
    }

    func testPlannerBuildsMorningEveningAndDigestDraftsWithStableIDs() throws {
        let now = try makeDateTime("2026-03-09 06:00")
        var settings = ScheduleReportSettings(isEnabled: true)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 7, minute: 30), for: .morningReport)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 21, minute: 30), for: .eveningReport)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 20, minute: 0), for: .examDigest)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 20, minute: 0), for: .countdownDigest)

        let input = ScheduleReportInput(
            courses: [
                Course(courseName: "森林生态学", teacher: "林老师", room: "二教 101", dayOfWeek: 1, weeks: [1], duration: [1, 2]),
                Course(courseName: "计算机网络", teacher: "吴老师", room: "主楼 201", dayOfWeek: 2, weeks: [1], duration: [1, 2]),
                Course(courseName: "数据结构", teacher: "周老师", room: "主楼 202", dayOfWeek: 2, weeks: [1], duration: [3, 4])
            ],
            exams: [
                ExamArrangement(id: 1, courseID: "A", name: "高等数学期末", date: "2026-03-16", start: "09:00", end: "11:00", location: "101"),
                ExamArrangement(id: 2, courseID: "B", name: "大学英语期末", date: "2026-03-16", start: "14:00", end: "16:00", location: "102")
            ],
            countdowns: [
                CustomCountdownEvent(id: "cet", title: "四级报名", targetDate: try makeDateTime("2026-03-14 12:00")),
                CustomCountdownEvent(id: "paper", title: "论文提交", targetDate: try makeDateTime("2026-03-14 18:00"))
            ],
            cellReminders: [
                TimetableCellReminder(
                    week: 1,
                    dayOfWeek: 1,
                    period: 5,
                    title: "图书馆座位提醒",
                    startsAt: try makeDateTime("2026-03-09 13:00")
                )
            ]
        )

        let drafts = ScheduleReportPlanner.drafts(settings: settings, input: input, now: now, calendar: calendar)
        let repeatedDrafts = ScheduleReportPlanner.drafts(settings: settings, input: input, now: now, calendar: calendar)
        let morning = try XCTUnwrap(drafts.first { $0.mode == .morningReport })
        let evening = try XCTUnwrap(drafts.first { $0.mode == .eveningReport })
        let examDrafts = drafts.filter { $0.mode == .examDigest }
        let countdownDrafts = drafts.filter { $0.mode == .countdownDigest }
        let exam = try XCTUnwrap(examDrafts.first)
        let countdown = try XCTUnwrap(countdownDrafts.first)

        XCTAssertEqual(drafts.filter { $0.mode == .morningReport }.count, 7)
        XCTAssertEqual(drafts.filter { $0.mode == .eveningReport }.count, 7)
        XCTAssertTrue(morning.body.contains("今天 1 节课"))
        XCTAssertTrue(morning.body.contains("图书馆座位提醒"))
        XCTAssertTrue(evening.body.contains("明天 2 节课：计算机网络、数据结构"))
        XCTAssertFalse(evening.body.contains("第一节"))
        XCTAssertEqual(examDrafts.count, 7)
        XCTAssertTrue(exam.body.contains("高等数学期末还有 7 天"))
        XCTAssertTrue(exam.body.contains("大学英语期末还有 7 天"))
        XCTAssertEqual(countdown.title, "重要日期提醒")
        XCTAssertEqual(countdownDrafts.count, 3)
        XCTAssertTrue(countdown.body.contains("四级报名"))
        XCTAssertTrue(countdown.body.contains("论文提交"))
        XCTAssertEqual(drafts.map(\.id), repeatedDrafts.map(\.id))
    }

    func testPlannerSkipsDigestWhenThereIsNoRelevantContent() throws {
        let now = try makeDateTime("2026-03-09 06:00")
        var settings = ScheduleReportSettings(isEnabled: true)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 20, minute: 0), for: .examDigest)

        let drafts = ScheduleReportPlanner.drafts(
            settings: settings,
            input: ScheduleReportInput(courses: [], exams: [], countdowns: [], cellReminders: []),
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(drafts.isEmpty)
    }

    private var calendar: Calendar {
        Calendar.current
    }

    private func makeDateTime(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: string))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ScheduleReportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
