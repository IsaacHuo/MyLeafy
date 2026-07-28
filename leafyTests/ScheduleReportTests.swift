import XCTest
@testable import Leafy

final class ScheduleReportTests: XCTestCase {
    private struct LegacyScheduleReportSettings: Codable {
        let isEnabled: Bool
        let modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
        let scheduledNotificationIDs: [String]
    }

    private struct LegacyScheduleReportSettingsWithReminder: Codable {
        let isEnabled: Bool
        let modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
        let customReminder: ScheduleReportCustomSetting
        let scheduledNotificationIDs: [String]
    }

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
        XCTAssertTrue(key.hasSuffix("scheduleReport.settings.v2"))
        XCTAssertEqual(loaded.setting(for: .eveningReport).hour, 23)
        XCTAssertEqual(loaded.setting(for: .eveningReport).minute, 0)
        XCTAssertEqual(loaded.scheduledNotificationIDs, ["one", "two"])
        XCTAssertTrue(loaded.isEnabled)
    }

    func testLegacySettingsDecodeWithoutCustomReminder() throws {
        let legacy = LegacyScheduleReportSettings(
            isEnabled: true,
            modeSettings: [
                .morningReport: ScheduleReportModeSetting(isEnabled: true, hour: 8, minute: 15)
            ],
            scheduledNotificationIDs: ["legacy"]
        )

        let decoded = try JSONDecoder().decode(
            ScheduleReportSettings.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertFalse(decoded.customReminder.isConfigured)
        XCTAssertFalse(decoded.customReminder.isEnabled)
        XCTAssertEqual(decoded.setting(for: .morningReport).hour, 8)
        XCTAssertEqual(decoded.scheduledNotificationIDs, ["legacy"])
    }

    func testV1StoreMigratesSingleReminderIntoV2List() throws {
        let defaults = try makeDefaults()
        let fireDate = try makeDateTime("2026-03-10 09:30")
        let legacy = LegacyScheduleReportSettingsWithReminder(
            isEnabled: true,
            modeSettings: [:],
            customReminder: ScheduleReportCustomSetting(
                isEnabled: true,
                title: "提交材料",
                body: "带上盖章版",
                fireDate: fireDate
            ),
            scheduledNotificationIDs: ["legacy-id"]
        )
        let legacyKey = ScheduleReportSettingsStore.scopedStorageKey(defaults: defaults)
            .replacingOccurrences(of: ".v2", with: ".v1")
        defaults.set(try JSONEncoder().encode(legacy), forKey: legacyKey)

        let migrated = ScheduleReportSettingsStore.load(defaults: defaults)

        XCTAssertEqual(migrated.reminders.count, 1)
        XCTAssertEqual(migrated.customReminder.title, "提交材料")
        XCTAssertEqual(migrated.customReminder.body, "带上盖章版")
        XCTAssertEqual(migrated.customReminder.fireDate, fireDate)
        XCTAssertEqual(migrated.reminders.first?.leadMinutes, [0])
        XCTAssertNotNil(defaults.data(forKey: ScheduleReportSettingsStore.scopedStorageKey(defaults: defaults)))
    }

    func testCustomReminderBuildsOneDraftWithDefaultBody() throws {
        let now = try makeDateTime("2026-03-09 06:00")
        let fireDate = try makeDateTime("2026-03-10 14:25")
        var settings = ScheduleReportSettings(
            customReminder: ScheduleReportCustomSetting(
                isEnabled: true,
                title: "  提交报名材料  ",
                body: "   ",
                fireDate: fireDate
            )
        )
        settings.deriveEnabledState(now: now)

        let drafts = ScheduleReportPlanner.drafts(
            settings: settings,
            input: ScheduleReportInput(courses: [], exams: [], countdowns: [], cellReminders: []),
            now: now,
            calendar: calendar
        )

        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(draft.mode, .custom)
        XCTAssertEqual(draft.title, "提交报名材料")
        XCTAssertEqual(draft.body, ScheduleReportCustomSetting.defaultBody)
        XCTAssertEqual(draft.fireDate, fireDate)
    }

    func testExpiredCustomReminderDisablesWithoutClearingContent() throws {
        let now = try makeDateTime("2026-03-10 12:00")
        let fireDate = try makeDateTime("2026-03-10 11:00")
        var settings = ScheduleReportSettings(
            customReminder: ScheduleReportCustomSetting(
                isEnabled: true,
                title: "查看报名结果",
                body: "记得截图",
                fireDate: fireDate
            )
        )

        settings.deriveEnabledState(now: now)

        XCTAssertFalse(settings.customReminder.isEnabled)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.customReminder.title, "查看报名结果")
        XCTAssertEqual(settings.customReminder.body, "记得截图")
        XCTAssertEqual(settings.customReminder.fireDate, fireDate)
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

    func testReminderSupportsMultipleUniqueLeadTimesWithStableIDs() throws {
        let now = try makeDateTime("2026-03-09 08:00")
        let occurrence = try makeDateTime("2026-03-10 10:00")
        let reminderID = UUID(uuidString: "11111111-2222-3333-8444-555555555555")!
        let settings = ScheduleReportSettings(
            reminders: [
                ScheduleReminder(
                    id: reminderID,
                    source: .freeform(title: "答辩", body: "", fireDate: occurrence),
                    leadMinutes: [60, 0, 60, 10]
                )
            ]
        )
        let input = ScheduleReportInput(courses: [], exams: [], countdowns: [], cellReminders: [])

        let first = ScheduleReportPlanner.drafts(settings: settings, input: input, now: now, calendar: calendar)
        let second = ScheduleReportPlanner.drafts(settings: settings, input: input, now: now, calendar: calendar)

        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.fireDate)), Set([
            occurrence,
            occurrence.addingTimeInterval(-10 * 60),
            occurrence.addingTimeInterval(-60 * 60),
        ]))
    }

    func testMissingSourceIsDisabledWithoutDeletingConfiguration() {
        let reminder = ScheduleReminder(
            id: UUID(),
            isEnabled: true,
            source: .customSchedule(eventID: "removed-event"),
            leadMinutes: [0, 60]
        )
        let settings = ScheduleReportSettings(reminders: [reminder])

        let resolved = ScheduleReportPlanner.resolvingReminderSources(
            in: settings,
            input: ScheduleReportInput(courses: [], exams: [], countdowns: [], cellReminders: [])
        )

        XCTAssertEqual(resolved.reminders.count, 1)
        XCTAssertFalse(resolved.reminders[0].isEnabled)
        XCTAssertEqual(resolved.reminders[0].availability, .sourceUnavailable)
        XCTAssertEqual(resolved.reminders[0].source, reminder.source)
        XCTAssertEqual(resolved.reminders[0].leadMinutes, [0, 60])
    }

    func testCourseReminderCanTargetOneOccurrenceOrRemainingSemester() throws {
        let now = SemesterConfig.startOfSemesterDate.addingTimeInterval(-60)
        let courseID = UUID()
        let course = Course(
            id: courseID,
            courseName: "森林生态",
            teacher: "林老师",
            room: "二教 203",
            dayOfWeek: 1,
            weeks: [1, 2],
            duration: [1, 2]
        )
        let firstOccurrence = try XCTUnwrap(TimetablePeriodSchedule.startDate(for: course, week: 1))
        let input = ScheduleReportInput(courses: [course], exams: [], countdowns: [], cellReminders: [])
        let single = ScheduleReportSettings(reminders: [
            ScheduleReminder(
                source: .course(
                    courseID: courseID,
                    scope: .singleOccurrence,
                    occurrenceDate: firstOccurrence
                )
            )
        ])
        let remaining = ScheduleReportSettings(reminders: [
            ScheduleReminder(
                source: .course(
                    courseID: courseID,
                    scope: .remainingSemester,
                    occurrenceDate: nil
                )
            )
        ])

        XCTAssertEqual(
            ScheduleReportPlanner.drafts(settings: single, input: input, now: now, calendar: calendar).count,
            1
        )
        XCTAssertEqual(
            ScheduleReportPlanner.drafts(settings: remaining, input: input, now: now, calendar: calendar).count,
            1,
            "滚动窗口只调度未来 7 天内的课程；后一周由后续刷新补入"
        )
    }

    func testReportWeatherIsAppendedOnlyWhenForecastExistsForTargetDay() throws {
        let now = try makeDateTime("2026-03-09 06:00")
        var settings = ScheduleReportSettings(isEnabled: true)
        settings.set(ScheduleReportModeSetting(isEnabled: true, hour: 7, minute: 30), for: .morningReport)
        let input = ScheduleReportInput(courses: [], exams: [], countdowns: [], cellReminders: [])
        let weather = TimetableWeatherSnapshot(
            temperature: 20,
            condition: "多云",
            symbolName: "cloud",
            observedAt: now,
            hourlyForecast: [
                TimetableHourlyWeather(
                    date: try makeDateTime("2026-03-09 09:00"),
                    temperature: 22,
                    condition: "多云",
                    symbolName: "cloud",
                    precipitationChance: 0,
                    uvIndex: 2,
                    isDaylight: true
                )
            ],
            attribution: .appleWeather
        )

        let withWeather = ScheduleReportPlanner.drafts(
            settings: settings,
            input: input,
            weather: weather,
            now: now,
            calendar: calendar
        )
        let withoutWeather = ScheduleReportPlanner.drafts(
            settings: settings,
            input: input,
            weather: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(withWeather.first?.body.contains("天气：") == true)
        XCTAssertFalse(withoutWeather.first?.body.contains("天气") == true)
        XCTAssertFalse(withoutWeather.first?.body.contains("不可用") == true)
    }

    func testNotificationCapacityReservesOtherPendingSlotsAndKeepsEarliestDrafts() throws {
        let base = try makeDateTime("2026-03-09 08:00")
        let drafts = (0..<10).reversed().map { offset in
            ScheduleReportNotificationDraft(
                id: "draft-\(offset)",
                mode: .custom,
                fireDate: base.addingTimeInterval(Double(offset) * 60),
                title: "提醒",
                body: "正文",
                targetURL: ScheduleReportPlanner.targetURL
            )
        }

        let selected = ScheduleReportNotificationCapacityPlanner.selectedDrafts(
            from: drafts,
            otherPendingCount: 61
        )

        XCTAssertEqual(selected.map(\.id), ["draft-0", "draft-1", "draft-2"])
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
