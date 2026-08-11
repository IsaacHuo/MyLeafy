import Foundation
import SwiftData
import UserNotifications

enum ScheduleReportMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case morningReport
    case eveningReport
    case examDigest
    case countdownDigest
    case calendarDigest
    case custom

    static let builtInCases: [ScheduleReportMode] = [
        .morningReport,
        .eveningReport,
        .examDigest,
        .countdownDigest,
        .calendarDigest
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningReport: return "今日早报"
        case .eveningReport: return "明日晚报"
        case .examDigest: return "考试提醒"
        case .countdownDigest: return "重要日期提醒"
        case .calendarDigest: return "校历节点"
        case .custom: return "自定义提醒"
        }
    }

    var subtitle: String {
        switch self {
        case .morningReport:
            return "每天查看今日课程、考试和本地日程"
        case .eveningReport:
            return "每天查看明天全部课程和时间日程"
        case .examDigest:
            return "考前 7 天至 1 天，每天提醒"
        case .countdownDigest:
            return "提前 5 天、3 天、1 天提醒"
        case .calendarDigest:
            return "今天或明天有校历、节气、假期节点时提醒"
        case .custom:
            return "在任意未来时间提醒你自己设置的事项"
        }
    }

    var systemImage: String {
        switch self {
        case .morningReport: return "sunrise.fill"
        case .eveningReport: return "moon.stars.fill"
        case .examDigest: return "pencil.and.list.clipboard"
        case .countdownDigest: return "timer"
        case .calendarDigest: return "calendar.badge.exclamationmark"
        case .custom: return "bell.and.waves.left.and.right"
        }
    }

    var defaultHour: Int {
        switch self {
        case .morningReport: return 7
        case .eveningReport: return 21
        case .examDigest: return 20
        case .countdownDigest: return 20
        case .calendarDigest: return 8
        case .custom: return 9
        }
    }

    var defaultMinute: Int {
        switch self {
        case .morningReport: return 30
        case .eveningReport: return 30
        case .examDigest, .countdownDigest, .calendarDigest: return 0
        case .custom: return 0
        }
    }
}

struct ScheduleReportModeSetting: Codable, Hashable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    init(isEnabled: Bool = false, hour: Int, minute: Int) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(mode: ScheduleReportMode, isEnabled: Bool = false) {
        self.init(isEnabled: isEnabled, hour: mode.defaultHour, minute: mode.defaultMinute)
    }
}

enum ScheduleReminderCourseScope: String, Codable, CaseIterable, Hashable {
    case singleOccurrence
    case remainingSemester

    var title: String {
        switch self {
        case .singleOccurrence: return "仅这次上课"
        case .remainingSemester: return "本学期后续全部上课"
        }
    }
}

enum ScheduleReminderSource: Codable, Hashable {
    case freeform(title: String, body: String, fireDate: Date?)
    case customSchedule(eventID: String)
    case exam(examID: Int)
    case calendar(eventID: String)
    case course(courseID: UUID, scope: ScheduleReminderCourseScope, occurrenceDate: Date?)

    var kindTitle: String {
        switch self {
        case .freeform: return "自由输入"
        case .customSchedule: return "自定日程"
        case .exam: return "教务考试"
        case .calendar: return "校历节点"
        case .course: return "课程"
        }
    }
}

enum ScheduleReminderAvailability: String, Codable, Hashable {
    case available
    case sourceUnavailable
}

struct ScheduleReminder: Codable, Hashable, Identifiable {
    static let defaultBody = "你设置的提醒时间到了。"
    static let presetLeadMinutes = [0, 10, 30, 60, 1_440, 4_320, 10_080]
    static let customLeadMinuteRange = 1...10_080

    var id: UUID
    var isEnabled: Bool
    var source: ScheduleReminderSource
    var leadMinutes: [Int]
    var availability: ScheduleReminderAvailability

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        source: ScheduleReminderSource,
        leadMinutes: [Int] = [0],
        availability: ScheduleReminderAvailability = .available
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.source = source
        self.leadMinutes = Self.normalizedLeadMinutes(leadMinutes)
        self.availability = availability
    }

    static func normalizedLeadMinutes(_ values: [Int]) -> [Int] {
        Array(Set(values.map { min(max($0, 0), customLeadMinuteRange.upperBound) })).sorted()
    }
}

struct ScheduleReportSettings: Codable, Hashable {
    var isEnabled: Bool
    var modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
    var reminders: [ScheduleReminder]
    var scheduledNotificationIDs: [String]
    var scheduledCount: Int
    var waitingCount: Int

    init(
        isEnabled: Bool = false,
        modeSettings: [ScheduleReportMode: ScheduleReportModeSetting] = [:],
        reminders: [ScheduleReminder] = [],
        scheduledNotificationIDs: [String] = [],
        scheduledCount: Int = 0,
        waitingCount: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.modeSettings = Self.normalizedModeSettings(modeSettings)
        self.reminders = reminders
        self.scheduledNotificationIDs = scheduledNotificationIDs
        self.scheduledCount = max(0, scheduledCount)
        self.waitingCount = max(0, waitingCount)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case modeSettings
        case reminders
        case scheduledNotificationIDs
        case scheduledCount
        case waitingCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            modeSettings: try container.decode(
                [ScheduleReportMode: ScheduleReportModeSetting].self,
                forKey: .modeSettings
            ),
            reminders: try container.decode([ScheduleReminder].self, forKey: .reminders),
            scheduledNotificationIDs: try container.decode(
                [String].self,
                forKey: .scheduledNotificationIDs
            ),
            scheduledCount: try container.decode(Int.self, forKey: .scheduledCount),
            waitingCount: try container.decode(Int.self, forKey: .waitingCount)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(modeSettings, forKey: .modeSettings)
        try container.encode(reminders, forKey: .reminders)
        try container.encode(scheduledNotificationIDs, forKey: .scheduledNotificationIDs)
        try container.encode(scheduledCount, forKey: .scheduledCount)
        try container.encode(waitingCount, forKey: .waitingCount)
    }

    static let disabled = ScheduleReportSettings()

    func setting(for mode: ScheduleReportMode) -> ScheduleReportModeSetting {
        modeSettings[mode] ?? ScheduleReportModeSetting(mode: mode)
    }

    mutating func set(_ setting: ScheduleReportModeSetting, for mode: ScheduleReportMode) {
        modeSettings[mode] = ScheduleReportModeSetting(
            isEnabled: setting.isEnabled,
            hour: setting.hour,
            minute: setting.minute
        )
    }

    var enabledModes: [ScheduleReportMode] {
        ScheduleReportMode.builtInCases.filter { setting(for: $0).isEnabled }
    }

    mutating func deriveEnabledState(now: Date = Date()) {
        for index in reminders.indices {
            reminders[index].leadMinutes = ScheduleReminder.normalizedLeadMinutes(reminders[index].leadMinutes)
            if case .freeform(_, _, let fireDate) = reminders[index].source,
               let fireDate,
               fireDate <= now {
                reminders[index].isEnabled = false
            }
        }
        isEnabled = !enabledModes.isEmpty || reminders.contains(where: \.isEnabled)
    }

    private static func normalizedModeSettings(
        _ modeSettings: [ScheduleReportMode: ScheduleReportModeSetting]
    ) -> [ScheduleReportMode: ScheduleReportModeSetting] {
        Dictionary(
            uniqueKeysWithValues: ScheduleReportMode.builtInCases.map { mode in
                let setting = modeSettings[mode] ?? ScheduleReportModeSetting(mode: mode)
                return (
                    mode,
                    ScheduleReportModeSetting(
                        isEnabled: setting.isEnabled,
                        hour: setting.hour,
                        minute: setting.minute
                    )
                )
            }
        )
    }
}

enum ScheduleReportSettingsStore {
    private static let key = "scheduleReport.settings.v2"

    static func load(defaults: UserDefaults = .standard) -> ScheduleReportSettings {
        let currentKey = scopedKey(key, defaults: defaults)
        guard let data = defaults.data(forKey: currentKey),
              let settings = try? JSONDecoder().decode(ScheduleReportSettings.self, from: data)
        else { return .disabled }
        var normalized = ScheduleReportSettings(
            isEnabled: settings.isEnabled,
            modeSettings: settings.modeSettings,
            reminders: settings.reminders,
            scheduledNotificationIDs: settings.scheduledNotificationIDs,
            scheduledCount: settings.scheduledCount,
            waitingCount: settings.waitingCount
        )
        normalized.deriveEnabledState()
        return normalized
    }

    static func save(_ settings: ScheduleReportSettings, defaults: UserDefaults = .standard) {
        var normalized = settings
        normalized.deriveEnabledState()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: scopedKey(key, defaults: defaults))
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: scopedKey(key, defaults: defaults))
    }

    static func scopedStorageKey(defaults: UserDefaults = .standard) -> String {
        scopedKey(key, defaults: defaults)
    }

    private static func scopedKey(_ storageKey: String, defaults: UserDefaults) -> String {
        CampusScopedDefaults.key(storageKey, defaults: defaults)
    }
}

struct ScheduleReportInput {
    var courses: [Course]
    var exams: [ExamArrangement]
    var countdowns: [CustomScheduleEvent]
    var cellReminders: [TimetableCellReminder]

    init(
        courses: [Course],
        exams: [ExamArrangement],
        countdowns: [CustomScheduleEvent],
        cellReminders: [TimetableCellReminder]
    ) {
        self.courses = courses
        self.exams = exams
        self.countdowns = countdowns
        self.cellReminders = cellReminders
    }
}

struct ScheduleReportNotificationDraft: Identifiable, Equatable {
    let id: String
    let mode: ScheduleReportMode
    let fireDate: Date
    let title: String
    let body: String
    let targetURL: URL
}

enum ScheduleReportPlanner {
    static let lookaheadDays = 7
    static let targetURL = URL(string: "leafy://schedule-reports")!

    static func drafts(
        settings: ScheduleReportSettings,
        input: ScheduleReportInput,
        weather: TimetableWeatherSnapshot? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScheduleReportNotificationDraft] {
        var normalizedSettings = settings
        normalizedSettings.deriveEnabledState(now: now)
        normalizedSettings = resolvingReminderSources(
            in: normalizedSettings,
            input: input,
            now: now,
            calendar: calendar
        )
        guard normalizedSettings.isEnabled else { return [] }

        let today = calendar.startOfDay(for: now)
        let modes = normalizedSettings.enabledModes
        var scheduledDrafts = modes.flatMap { mode in
            drafts(
                mode: mode,
                setting: normalizedSettings.setting(for: mode),
                input: input,
                weather: weather,
                now: now,
                startDay: today,
                calendar: calendar
            )
        }
        scheduledDrafts.append(contentsOf: reminderDrafts(
            normalizedSettings.reminders,
            input: input,
            now: now,
            calendar: calendar
        ))
        return scheduledDrafts.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.id < rhs.id
        }
    }

    static func summary(
        for mode: ScheduleReportMode,
        input: ScheduleReportInput,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        switch mode {
        case .morningReport:
            return reportBody(for: calendar.startOfDay(for: referenceDate), input: input, label: "今天", calendar: calendar)
        case .eveningReport:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
            return reportBody(for: tomorrow, input: input, label: "明天", includesAllCourses: true, calendar: calendar)
        case .examDigest:
            return upcomingExamSummary(input.exams, from: referenceDate, days: lookaheadDays, calendar: calendar)
                ?? "未来 7 天暂无考试安排。"
        case .countdownDigest:
            return upcomingImportantDateSummary(input.countdowns, from: referenceDate, days: lookaheadDays, calendar: calendar)
                ?? "未来 7 天暂无重要日期。"
        case .calendarDigest:
            return calendarDigestSummary(from: referenceDate, calendar: calendar)
                ?? "今天和明天暂无校历节点。"
        case .custom:
            return "你设置的自定义提醒。"
        }
    }

    private static func drafts(
        mode: ScheduleReportMode,
        setting: ScheduleReportModeSetting,
        input: ScheduleReportInput,
        weather: TimetableWeatherSnapshot?,
        now: Date,
        startDay: Date,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        guard setting.isEnabled else { return [] }

        switch mode {
        case .morningReport:
            return (0..<lookaheadDays).compactMap { dayOffset in
                let reportDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
                guard let fireDate = fireDate(on: reportDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return draft(
                    mode: mode,
                    fireDate: fireDate,
                    title: "今日早报",
                    body: reportBody(
                        for: reportDay,
                        input: input,
                        label: "今天",
                        weather: weather,
                        calendar: calendar
                    ),
                    calendar: calendar
                )
            }
        case .eveningReport:
            return (0..<lookaheadDays).compactMap { dayOffset in
                let fireDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
                let reportDay = calendar.date(byAdding: .day, value: 1, to: fireDay) ?? fireDay
                guard let fireDate = fireDate(on: fireDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return draft(
                    mode: mode,
                    fireDate: fireDate,
                    title: "明日晚报",
                    body: reportBody(
                        for: reportDay,
                        input: input,
                        label: "明天",
                        includesAllCourses: true,
                        weather: weather,
                        calendar: calendar
                    ),
                    calendar: calendar
                )
            }
        case .examDigest:
            return examReminderDrafts(
                exams: input.exams,
                setting: setting,
                now: now,
                calendar: calendar
            )
        case .countdownDigest:
            return importantDateReminderDrafts(
                events: input.countdowns,
                setting: setting,
                now: now,
                calendar: calendar
            )
        case .calendarDigest:
            return singleDraftIfNeeded(
                mode: mode,
                setting: setting,
                startDay: startDay,
                now: now,
                title: "校历节点",
                body: calendarDigestSummary(from: now, calendar: calendar),
                calendar: calendar
            )
        case .custom:
            return []
        }
    }

    static func resolvingReminderSources(
        in settings: ScheduleReportSettings,
        input: ScheduleReportInput,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleReportSettings {
        var resolved = settings
        for index in resolved.reminders.indices {
            let hasSource = !resolvedOccurrences(
                for: resolved.reminders[index],
                input: input,
                now: now,
                calendar: calendar,
                includesPastOccurrences: true
            ).isEmpty
            resolved.reminders[index].availability = hasSource ? .available : .sourceUnavailable
            if !hasSource {
                resolved.reminders[index].isEnabled = false
            }
        }
        resolved.deriveEnabledState(now: now)
        return resolved
    }

    private struct ResolvedReminderOccurrence {
        let sourceDate: Date
        let title: String
        let body: String
    }

    private static func reminderDrafts(
        _ reminders: [ScheduleReminder],
        input: ScheduleReportInput,
        now: Date,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        let windowEnd = calendar.date(byAdding: .day, value: lookaheadDays, to: now)
            ?? now.addingTimeInterval(Double(lookaheadDays) * 86_400)

        return reminders
            .filter { $0.isEnabled && $0.availability == .available }
            .flatMap { reminder -> [ScheduleReportNotificationDraft] in
                let occurrences = resolvedOccurrences(
                    for: reminder,
                    input: input,
                    now: now,
                    calendar: calendar
                )
                return occurrences.flatMap { occurrence in
                    reminder.leadMinutes.compactMap { leadMinutes in
                        let fireDate = occurrence.sourceDate.addingTimeInterval(-Double(leadMinutes) * 60)
                        guard fireDate > now, fireDate <= windowEnd else { return nil }
                        return ScheduleReportNotificationDraft(
                            id: reminderNotificationID(
                                reminderID: reminder.id,
                                sourceDate: occurrence.sourceDate,
                                leadMinutes: leadMinutes
                            ),
                            mode: .custom,
                            fireDate: fireDate,
                            title: occurrence.title,
                            body: occurrence.body,
                            targetURL: targetURL
                        )
                    }
                }
            }
    }

    private static func resolvedOccurrences(
        for reminder: ScheduleReminder,
        input: ScheduleReportInput,
        now: Date,
        calendar: Calendar,
        includesPastOccurrences: Bool = false
    ) -> [ResolvedReminderOccurrence] {
        switch reminder.source {
        case .freeform(let title, let body, let fireDate):
            guard let fireDate else { return [] }
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return [] }
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                ResolvedReminderOccurrence(
                    sourceDate: fireDate,
                    title: trimmedTitle,
                    body: trimmedBody.isEmpty ? ScheduleReminder.defaultBody : trimmedBody
                )
            ]

        case .customSchedule(let eventID):
            guard let event = input.countdowns.first(where: { $0.id == eventID }) else { return [] }
            return [
                ResolvedReminderOccurrence(
                    sourceDate: event.startsAt,
                    title: event.title,
                    body: [event.location, event.note]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                        .nonEmptyOrDefault("自定日程即将开始。")
                )
            ]

        case .exam(let examID):
            guard let exam = input.exams.first(where: { $0.id == examID }),
                  let startsAt = exam.startsAt else { return [] }
            return [
                ResolvedReminderOccurrence(
                    sourceDate: startsAt,
                    title: exam.name,
                    body: "\(exam.date) \(exam.start) · \(exam.location)"
                )
            ]

        case .calendar(let eventID):
            guard let event = AcademicCalendarEvents.displayEvents().first(where: { $0.id == eventID }),
                  let startsAt = event.startDate else { return [] }
            return [
                ResolvedReminderOccurrence(
                    sourceDate: startsAt,
                    title: event.title,
                    body: "校历节点即将开始。"
                )
            ]

        case .course(let courseID, let scope, let occurrenceDate):
            guard let course = input.courses.first(where: { $0.id == courseID }) else { return [] }
            let allOccurrences = course.weeks.compactMap { week -> ResolvedReminderOccurrence? in
                guard let startsAt = TimetablePeriodSchedule.startDate(for: course, week: week) else {
                    return nil
                }
                return ResolvedReminderOccurrence(
                    sourceDate: startsAt,
                    title: course.courseName,
                    body: [course.teacher, course.room]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                        .nonEmptyOrDefault("课程即将开始。")
                )
            }
            switch scope {
            case .singleOccurrence:
                guard let occurrenceDate else { return [] }
                return allOccurrences.filter {
                    abs($0.sourceDate.timeIntervalSince(occurrenceDate)) < 60
                }
            case .remainingSemester:
                return allOccurrences.filter {
                    includesPastOccurrences || $0.sourceDate >= now
                }
            }
        }
    }

    private static func reminderNotificationID(
        reminderID: UUID,
        sourceDate: Date,
        leadMinutes: Int
    ) -> String {
        let occurrenceMinute = Int(sourceDate.timeIntervalSince1970 / 60)
        return "leafy.scheduleReminder.\(reminderID.uuidString.lowercased()).\(occurrenceMinute).\(leadMinutes)"
    }

    private static func singleDraftIfNeeded(
        mode: ScheduleReportMode,
        setting: ScheduleReportModeSetting,
        startDay: Date,
        now: Date,
        title: String,
        body: String?,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        guard let body,
              let fireDate = nextFireDate(startingAt: startDay, setting: setting, now: now, calendar: calendar)
        else {
            return []
        }
        return [
            draft(mode: mode, fireDate: fireDate, title: title, body: body, calendar: calendar)
        ]
    }

    private struct ExamReminderOccurrence {
        let fireDate: Date
        let exam: ExamArrangement
        let daysBefore: Int
    }

    private struct ImportantDateReminderOccurrence {
        let fireDate: Date
        let event: CustomScheduleEvent
        let daysBefore: Int
    }

    private static func examReminderDrafts(
        exams: [ExamArrangement],
        setting: ScheduleReportModeSetting,
        now: Date,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        let occurrences = exams.flatMap { exam -> [ExamReminderOccurrence] in
            guard let examDate = exam.startsAt else { return [] }
            return (1...7).compactMap { daysBefore in
                guard let fireDay = calendar.date(
                    byAdding: .day,
                    value: -daysBefore,
                    to: calendar.startOfDay(for: examDate)
                ),
                      let fireDate = fireDate(on: fireDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return ExamReminderOccurrence(fireDate: fireDate, exam: exam, daysBefore: daysBefore)
            }
        }

        return Dictionary(grouping: occurrences, by: \.fireDate)
            .map { fireDate, grouped in
                let body = grouped
                    .sorted { ($0.exam.startsAt ?? .distantFuture) < ($1.exam.startsAt ?? .distantFuture) }
                    .map { "\($0.exam.name)还有 \($0.daysBefore) 天（\($0.exam.date) \($0.exam.start)）" }
                    .joined(separator: "；")
                return draft(
                    mode: .examDigest,
                    fireDate: fireDate,
                    title: "考试提醒",
                    body: body,
                    calendar: calendar
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private static func importantDateReminderDrafts(
        events: [CustomScheduleEvent],
        setting: ScheduleReportModeSetting,
        now: Date,
        calendar: Calendar
    ) -> [ScheduleReportNotificationDraft] {
        let occurrences = events.flatMap { event -> [ImportantDateReminderOccurrence] in
            [5, 3, 1].compactMap { daysBefore in
                guard let fireDay = calendar.date(
                    byAdding: .day,
                    value: -daysBefore,
                    to: calendar.startOfDay(for: event.startsAt)
                ),
                      let fireDate = fireDate(on: fireDay, setting: setting, calendar: calendar),
                      fireDate > now else { return nil }
                return ImportantDateReminderOccurrence(
                    fireDate: fireDate,
                    event: event,
                    daysBefore: daysBefore
                )
            }
        }

        return Dictionary(grouping: occurrences, by: \.fireDate)
            .map { fireDate, grouped in
                let body = grouped
                    .sorted { $0.event.startsAt < $1.event.startsAt }
                    .map {
                        "\($0.event.title)还有 \($0.daysBefore) 天（\(DateFormatters.headerWithTime.string(from: $0.event.startsAt))）"
                    }
                    .joined(separator: "；")
                return draft(
                    mode: .countdownDigest,
                    fireDate: fireDate,
                    title: "重要日期提醒",
                    body: body,
                    calendar: calendar
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private static func draft(
        mode: ScheduleReportMode,
        fireDate: Date,
        title: String,
        body: String,
        calendar: Calendar
    ) -> ScheduleReportNotificationDraft {
        ScheduleReportNotificationDraft(
            id: notificationID(mode: mode, fireDate: fireDate, calendar: calendar),
            mode: mode,
            fireDate: fireDate,
            title: title,
            body: body,
            targetURL: targetURL
        )
    }

    private static func reportBody(
        for date: Date,
        input: ScheduleReportInput,
        label: String,
        includesAllCourses: Bool = false,
        weather: TimetableWeatherSnapshot? = nil,
        calendar: Calendar
    ) -> String {
        let courses = courses(on: date, from: input.courses)
        let exams = exams(on: date, from: input.exams, calendar: calendar)
        let reminders = cellReminders(on: date, from: input.cellReminders, calendar: calendar)
        let events = AcademicCalendarEvents.events(for: date, calendar: calendar)
        var parts: [String] = []

        if courses.isEmpty {
            parts.append("\(label)没有课程")
        } else if includesAllCourses {
            let names = courses.map(\.courseName).joined(separator: "、")
            parts.append("\(label) \(courses.count) 节课：\(names)")
        } else if let first = courses.first {
            parts.append("\(label) \(courses.count) 节课，第一节 \(first.courseName)")
        }

        if !exams.isEmpty {
            let names = exams.prefix(2).map(\.name).joined(separator: "、")
            parts.append("\(exams.count) 场考试：\(names)")
        }

        if !reminders.isEmpty {
            let titles = reminders.prefix(2).map(\.title).joined(separator: "、")
            parts.append("\(reminders.count) 个本地日程：\(titles)")
        }

        if !events.isEmpty {
            parts.append(events.map(\.title).joined(separator: "、"))
        }

        if let weather,
           let supplement = ScheduleReportWeatherSupplementBuilder.supplement(
               snapshot: weather,
               for: date,
               calendar: calendar
           ) {
            parts.append(supplement)
        }

        return parts.joined(separator: "；")
    }

    private static func upcomingExamSummary(
        _ exams: [ExamArrangement],
        from date: Date,
        days: Int,
        calendar: Calendar
    ) -> String? {
        let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let upcoming = exams
            .filter { exam in
                guard let start = exam.startsAt else { return false }
                return start >= date && start <= end
            }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
        guard !upcoming.isEmpty else { return nil }

        let first = upcoming[0]
        return "未来 7 天有 \(upcoming.count) 场考试，最近：\(first.name) \(first.date) \(first.start)。"
    }

    private static func upcomingImportantDateSummary(
        _ countdowns: [CustomScheduleEvent],
        from date: Date,
        days: Int,
        calendar: Calendar
    ) -> String? {
        let end = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let upcoming = countdowns
            .filter { $0.startsAt >= date && $0.startsAt <= end }
            .sorted { $0.startsAt < $1.startsAt }
        guard let first = upcoming.first else { return nil }

        return "未来 7 天有 \(upcoming.count) 个重要日期，最近：\(first.title)。"
    }

    private static func calendarDigestSummary(from date: Date, calendar: Calendar) -> String? {
        let today = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let todayEvents = AcademicCalendarEvents.events(for: today, calendar: calendar)
        let tomorrowEvents = AcademicCalendarEvents.events(for: tomorrow, calendar: calendar)
        var parts: [String] = []

        if !todayEvents.isEmpty {
            parts.append("今天：" + todayEvents.map(\.title).joined(separator: "、"))
        }
        if !tomorrowEvents.isEmpty {
            parts.append("明天：" + tomorrowEvents.map(\.title).joined(separator: "、"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private static func courses(on date: Date, from courses: [Course]) -> [Course] {
        let config = SemesterConfig.current
        let schedule = SemesterConfig.weekAndDay(for: date, config: config)
        return courses
            .filter {
                $0.sourceSemesterID == config.semesterID
                    && $0.dayOfWeek == schedule.day
                    && $0.weeks.contains(schedule.week)
            }
            .sortedByStartPeriod()
    }

    private static func exams(
        on date: Date,
        from exams: [ExamArrangement],
        calendar: Calendar
    ) -> [ExamArrangement] {
        exams
            .filter { exam in
                guard let start = exam.startsAt else { return false }
                return calendar.isDate(start, inSameDayAs: date)
            }
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }

    private static func cellReminders(
        on date: Date,
        from reminders: [TimetableCellReminder],
        calendar: Calendar
    ) -> [TimetableCellReminder] {
        reminders
            .filter { reminder in
                guard let start = reminder.resolvedStartDate else { return false }
                return calendar.isDate(start, inSameDayAs: date)
            }
            .sorted { lhs, rhs in
                (lhs.resolvedStartDate ?? .distantFuture) < (rhs.resolvedStartDate ?? .distantFuture)
            }
    }

    private static func nextFireDate(
        startingAt startDay: Date,
        setting: ScheduleReportModeSetting,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        for dayOffset in 0..<lookaheadDays {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: startDay) ?? startDay
            guard let fireDate = fireDate(on: day, setting: setting, calendar: calendar),
                  fireDate > now else { continue }
            return fireDate
        }
        return nil
    }

    private static func fireDate(
        on day: Date,
        setting: ScheduleReportModeSetting,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            bySettingHour: setting.hour,
            minute: setting.minute,
            second: 0,
            of: day
        )
    }

    private static func notificationID(
        mode: ScheduleReportMode,
        fireDate: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let stamp = [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        ]
        .map { String(format: "%02d", $0) }
        .joined()
        return "leafy.scheduleReport.\(mode.rawValue).\(stamp)"
    }
}

enum ScheduleReportWeatherSupplementBuilder {
    static func supplement(
        snapshot: TimetableWeatherSnapshot?,
        for date: Date,
        calendar: Calendar = .current
    ) -> String? {
        guard let snapshot else { return nil }
        let hours = snapshot.hourlyForecast
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
        guard !hours.isEmpty else { return nil }

        let minimum = Int((hours.map(\.temperature).min() ?? snapshot.temperature).rounded())
        let maximum = Int((hours.map(\.temperature).max() ?? snapshot.temperature).rounded())
        let representative = hours.first(where: { calendar.component(.hour, from: $0.date) >= 8 })
            ?? hours.first!
        let advice: String
        if hours.contains(where: { $0.precipitationChance >= 0.35 || $0.symbolName.contains("rain") || $0.symbolName.contains("snow") }) {
            advice = "出门建议带伞，并留意路面湿滑"
        } else if minimum <= 8 {
            advice = "早晚偏凉，建议加一层衣物"
        } else if maximum >= 30 || hours.contains(where: { $0.uvIndex >= 7 }) {
            advice = "注意防晒并及时补水"
        } else {
            advice = "出门前可再留意天气变化"
        }
        return "天气：\(minimum)～\(maximum)℃ \(representative.condition)；\(advice)"
    }
}

enum ScheduleReportNotificationCapacityPlanner {
    static let systemLimit = 64

    static func selectedDrafts(
        from drafts: [ScheduleReportNotificationDraft],
        otherPendingCount: Int,
        systemLimit: Int = ScheduleReportNotificationCapacityPlanner.systemLimit
    ) -> [ScheduleReportNotificationDraft] {
        let availableSlots = max(0, systemLimit - max(0, otherPendingCount))
        return Array(
            drafts
                .sorted {
                    if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
                    return $0.id < $1.id
                }
                .prefix(availableSlots)
        )
    }
}

@MainActor
enum ScheduleReportNotificationManager {
    static func updateNotifications(
        settings: ScheduleReportSettings,
        input: ScheduleReportInput,
        weather: TimetableWeatherSnapshot? = nil,
        now: Date = Date()
    ) async throws -> ScheduleReportSettings {
        var updatedSettings = ScheduleReportPlanner.resolvingReminderSources(
            in: settings,
            input: input,
            now: now
        )
        updatedSettings.scheduledNotificationIDs = []
        updatedSettings.scheduledCount = 0
        updatedSettings.waitingCount = 0

        let drafts = ScheduleReportPlanner.drafts(
            settings: updatedSettings,
            input: input,
            weather: weather,
            now: now
        )
        guard updatedSettings.isEnabled, !drafts.isEmpty else {
            cancelScheduledNotifications(settings: settings)
            return updatedSettings
        }

        let center = try await authorizedNotificationCenter()
        let pendingRequests = await center.pendingNotificationRequests()
        let previousIDs = Set(settings.scheduledNotificationIDs)
        let otherPendingCount = pendingRequests.filter {
            !previousIDs.contains($0.identifier)
                && !$0.identifier.hasPrefix("leafy.scheduleReport.")
                && !$0.identifier.hasPrefix("leafy.scheduleReminder.")
        }.count
        let selectedDrafts = ScheduleReportNotificationCapacityPlanner.selectedDrafts(
            from: drafts,
            otherPendingCount: otherPendingCount
        )
        updatedSettings.scheduledCount = selectedDrafts.count
        updatedSettings.waitingCount = max(0, drafts.count - selectedDrafts.count)

        cancelScheduledNotifications(settings: settings)
        do {
            for draft in selectedDrafts {
                try Task.checkCancellation()
                let content = UNMutableNotificationContent()
                content.title = draft.title
                content.body = draft.body
                content.sound = .default
                content.userInfo = ["url": draft.targetURL.absoluteString]

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: draft.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: draft.id, content: content, trigger: trigger)
                try await center.add(request)
                updatedSettings.scheduledNotificationIDs.append(draft.id)
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: selectedDrafts.map(\.id))
            throw error
        }

        return updatedSettings
    }

    static func cancelScheduledNotifications(settings: ScheduleReportSettings) {
        guard !settings.scheduledNotificationIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: settings.scheduledNotificationIDs)
    }

    static func clearScheduledNotifications(defaults: UserDefaults = .standard) {
        let settings = ScheduleReportSettingsStore.load(defaults: defaults)
        cancelScheduledNotifications(settings: settings)
        var clearedSettings = settings
        clearedSettings.scheduledNotificationIDs = []
        ScheduleReportSettingsStore.save(clearedSettings, defaults: defaults)
    }

    static func refreshIfEnabled(
        modelContext: ModelContext,
        weather: TimetableWeatherSnapshot? = nil,
        defaults: UserDefaults = .standard
    ) async throws {
        let settings = ScheduleReportSettingsStore.load(defaults: defaults)
        guard settings.isEnabled else { return }

        let input = ScheduleReportDataSource.input(modelContext: modelContext)
        let updatedSettings = try await updateNotifications(
            settings: settings,
            input: input,
            weather: weather
        )
        ScheduleReportSettingsStore.save(updatedSettings, defaults: defaults)
    }

    private static func authorizedNotificationCenter() async throws -> UNUserNotificationCenter {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { throw TimetableNotificationError.permissionDenied }
        } else if settings.authorizationStatus == .denied {
            throw TimetableNotificationError.permissionDenied
        }

        return center
    }
}

@MainActor
enum ScheduleReportDataSource {
    static func input(modelContext: ModelContext) -> ScheduleReportInput {
        ScheduleReportInput(
            courses: fetch(Course.self, in: modelContext)
                .filter { $0.sourceSemesterID == SemesterConfig.currentSemesterID },
            exams: SchoolDataCache.loadExamSchedule(),
            countdowns: CustomScheduleStore.load(),
            cellReminders: fetch(TimetableCellReminder.self, in: modelContext)
        )
    }

    private static func fetch<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}

private extension String {
    func nonEmptyOrDefault(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
