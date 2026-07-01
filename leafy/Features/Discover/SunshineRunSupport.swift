import Foundation
import UserNotifications

struct SunshineRunRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var periodStartWeek: Int
    var periodEndWeek: Int

    init(
        id: UUID = UUID(),
        date: Date,
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        calendar: Calendar = .current
    ) {
        self.id = id
        let normalizedDate = calendar.startOfDay(for: date)
        self.date = normalizedDate
        if let period = SunshineRunPlanner.period(
            for: normalizedDate,
            semesterStart: semesterStart,
            totalWeeks: totalWeeks,
            excludedWeeks: excludedWeeks,
            calendar: calendar
        ) {
            self.periodStartWeek = period.startWeek
            self.periodEndWeek = period.endWeek
        } else {
            let schedule = SunshineRunPlanner.clampedPeriodWeeks(for: normalizedDate, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, calendar: calendar)
            self.periodStartWeek = schedule.startWeek
            self.periodEndWeek = schedule.endWeek
        }
    }
}

struct SunshineRunReminderSettings: Codable, Hashable {
    var isEnabled: Bool
    var selectedWeekdays: [Int]
    var hour: Int
    var minute: Int
    var scheduledNotificationIDs: [String]

    init(
        isEnabled: Bool = false,
        selectedWeekdays: [Int] = [2, 4],
        hour: Int = 20,
        minute: Int = 0,
        scheduledNotificationIDs: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.selectedWeekdays = Self.normalizedWeekdays(selectedWeekdays)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.scheduledNotificationIDs = scheduledNotificationIDs
    }

    static func normalizedWeekdays(_ weekdays: [Int]) -> [Int] {
        Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
    }

    var normalizedSelectedWeekdays: [Int] {
        Self.normalizedWeekdays(selectedWeekdays)
    }
}

struct SunshineRunPeriod: Identifiable, Hashable {
    let index: Int
    let startWeek: Int
    let endWeek: Int
    let startDate: Date
    let endDate: Date
    let activeWeeks: [Int]

    var id: Int { index }
    var title: String {
        guard let firstWeek = activeWeeks.first, let lastWeek = activeWeeks.last else {
            return "第 \(startWeek)-\(endWeek) 周"
        }
        if activeWeeks.count == 1 {
            return "第 \(firstWeek) 周"
        }
        if activeWeeks == Array(firstWeek...lastWeek) {
            return "第 \(firstWeek)-\(lastWeek) 周"
        }
        return "第 \(activeWeeks.map(String.init).joined(separator: "、")) 周"
    }

    var hasSkippedWeeks: Bool {
        activeWeeks.count != endWeek - startWeek + 1
    }

    init(
        index: Int,
        startWeek: Int,
        endWeek: Int,
        startDate: Date,
        endDate: Date,
        activeWeeks: [Int]? = nil
    ) {
        self.index = index
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.startDate = startDate
        self.endDate = endDate
        self.activeWeeks = activeWeeks ?? Array(startWeek...endWeek)
    }

    func containsWeek(_ week: Int) -> Bool {
        activeWeeks.contains(week)
    }
}

struct SunshineRunPeriodProgress: Identifiable, Hashable {
    let period: SunshineRunPeriod
    let records: [SunshineRunRecord]
    let periodTarget: Int

    var id: Int { period.id }
    var count: Int { records.count }
    var remainingCount: Int { max(periodTarget - count, 0) }
    var isCompleted: Bool { count >= periodTarget }

    init(period: SunshineRunPeriod, records: [SunshineRunRecord], periodTarget: Int = SunshineRunPlanner.periodTarget) {
        self.period = period
        self.records = records
        self.periodTarget = max(periodTarget, 1)
    }
}

struct SunshineRunProgressSummary: Hashable {
    let totalCount: Int
    let cappedTotalCount: Int
    let remainingForFullScore: Int
    let isFullScoreReached: Bool
}

struct SunshineRunNotificationPlanItem: Identifiable, Hashable {
    let id: String
    let fireDate: Date
    let periodTitle: String
    let remainingCount: Int
}

struct SunshineRunRuleSettings: Codable, Hashable {
    var totalTarget: Int
    var weeksPerPeriod: Int
    var periodTarget: Int
    var skipsExcludedWeeks: Bool

    init(
        totalTarget: Int = SunshineRunPlanner.fullScoreTarget,
        weeksPerPeriod: Int = 2,
        periodTarget: Int = SunshineRunPlanner.periodTarget,
        skipsExcludedWeeks: Bool = true
    ) {
        self.totalTarget = min(max(totalTarget, 1), 200)
        self.weeksPerPeriod = min(max(weeksPerPeriod, 1), 8)
        self.periodTarget = min(max(periodTarget, 1), 30)
        self.skipsExcludedWeeks = skipsExcludedWeeks
    }

    static let bjfuDefault = SunshineRunRuleSettings()

    var excludedWeeks: Set<Int> {
        skipsExcludedWeeks ? SemesterConfig.sunshineRunExcludedWeeks : []
    }
}

enum SunshineRunPlanner {
    static let fullScoreTarget = 34
    static let periodTarget = 4

    static func periods(
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        calendar: Calendar = .current
    ) -> [SunshineRunPeriod] {
        guard totalWeeks > 0 else { return [] }
        let startDate = calendar.startOfDay(for: semesterStart)
        let eligibleWeeks = activeWeeks(totalWeeks: totalWeeks, excludedWeeks: excludedWeeks)
        let safeWeeksPerPeriod = max(weeksPerPeriod, 1)
        return stride(from: 0, to: eligibleWeeks.count, by: safeWeeksPerPeriod).enumerated().map { offset, startIndex in
            let periodWeeks = Array(eligibleWeeks[startIndex..<min(startIndex + safeWeeksPerPeriod, eligibleWeeks.count)])
            let startWeek = periodWeeks[0]
            let endWeek = periodWeeks[periodWeeks.count - 1]
            let periodStart = calendar.date(byAdding: .day, value: (startWeek - 1) * 7, to: startDate) ?? startDate
            let periodEnd = calendar.date(byAdding: .day, value: endWeek * 7 - 1, to: startDate) ?? periodStart
            return SunshineRunPeriod(
                index: offset + 1,
                startWeek: startWeek,
                endWeek: endWeek,
                startDate: periodStart,
                endDate: periodEnd,
                activeWeeks: periodWeeks
            )
        }
    }

    static func period(
        for date: Date,
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        calendar: Calendar = .current
    ) -> SunshineRunPeriod? {
        guard let week = weekNumber(for: date, semesterStart: semesterStart, totalWeeks: totalWeeks, calendar: calendar) else {
            return nil
        }
        return period(containingWeek: week, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar)
    }

    static func period(
        containingWeek week: Int,
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        calendar: Calendar = .current
    ) -> SunshineRunPeriod? {
        guard totalWeeks > 0 else { return nil }
        let clampedWeek = min(max(week, 1), totalWeeks)
        guard !normalizedExcludedWeeks(excludedWeeks, totalWeeks: totalWeeks).contains(clampedWeek) else {
            return nil
        }
        return periods(semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar)
            .first { $0.containsWeek(clampedWeek) }
    }

    static func currentPeriod(
        now: Date = Date(),
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        calendar: Calendar = .current
    ) -> SunshineRunPeriod? {
        if let period = period(for: now, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar) {
            return period
        }

        let week = clampedWeek(for: now, semesterStart: semesterStart, totalWeeks: totalWeeks, calendar: calendar)
        let allPeriods = periods(semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar)
        return allPeriods.first { $0.startWeek <= week && week <= $0.endWeek }
            ?? allPeriods.first { $0.startWeek > week }
            ?? allPeriods.last
    }

    static func normalizedRecords(_ records: [SunshineRunRecord], calendar: Calendar = .current) -> [SunshineRunRecord] {
        let recordsByDay = records.reduce(into: [Date: SunshineRunRecord]()) { partialResult, record in
            let day = calendar.startOfDay(for: record.date)
            if partialResult[day] == nil {
                var normalizedRecord = record
                normalizedRecord.date = day
                partialResult[day] = normalizedRecord
            }
        }
        return recordsByDay.values.sorted { $0.date < $1.date }
    }

    static func containsRecord(on date: Date, in records: [SunshineRunRecord], calendar: Calendar = .current) -> Bool {
        let targetDay = calendar.startOfDay(for: date)
        return records.contains { calendar.startOfDay(for: $0.date) == targetDay }
    }

    static func periodProgresses(
        records: [SunshineRunRecord],
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        periodTarget: Int = SunshineRunPlanner.periodTarget,
        calendar: Calendar = .current
    ) -> [SunshineRunPeriodProgress] {
        let normalizedRecords = normalizedRecords(records, calendar: calendar)
        return periods(semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar).map { runPeriod in
            let periodRecords = normalizedRecords.filter { record in
                guard let recordPeriod = period(for: record.date, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar) else {
                    return false
                }
                return recordPeriod.startWeek == runPeriod.startWeek
            }
            return SunshineRunPeriodProgress(period: runPeriod, records: periodRecords, periodTarget: periodTarget)
        }
    }

    static func progressSummary(
        records: [SunshineRunRecord],
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        totalTarget: Int = SunshineRunPlanner.fullScoreTarget,
        calendar: Calendar = .current
    ) -> SunshineRunProgressSummary {
        let totalCount = normalizedRecords(records, calendar: calendar)
            .filter { period(for: $0.date, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar) != nil }
            .count
        let safeTotalTarget = max(totalTarget, 1)
        let cappedTotalCount = min(totalCount, safeTotalTarget)
        return SunshineRunProgressSummary(
            totalCount: totalCount,
            cappedTotalCount: cappedTotalCount,
            remainingForFullScore: max(safeTotalTarget - cappedTotalCount, 0),
            isFullScoreReached: cappedTotalCount >= safeTotalTarget
        )
    }

    static func notificationPlan(
        settings: SunshineRunReminderSettings,
        records: [SunshineRunRecord],
        now: Date = Date(),
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        periodTarget: Int = SunshineRunPlanner.periodTarget,
        totalTarget: Int = SunshineRunPlanner.fullScoreTarget,
        calendar: Calendar = .current,
        limit: Int = 64
    ) -> [SunshineRunNotificationPlanItem] {
        guard settings.isEnabled,
              !settings.normalizedSelectedWeekdays.isEmpty,
              limit > 0,
              !progressSummary(records: records, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, totalTarget: totalTarget, calendar: calendar).isFullScoreReached
        else { return [] }

        let normalizedWeekdays = Set(settings.normalizedSelectedWeekdays)
        let progressByStartWeek = Dictionary(
            uniqueKeysWithValues: periodProgresses(records: records, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, periodTarget: periodTarget, calendar: calendar)
                .map { ($0.period.startWeek, $0) }
        )
        let startDate = calendar.startOfDay(for: max(now, semesterStart))
        let semesterEnd = calendar.date(byAdding: .day, value: totalWeeks * 7 - 1, to: calendar.startOfDay(for: semesterStart)) ?? startDate

        var items: [SunshineRunNotificationPlanItem] = []
        var currentDay = startDate
        while currentDay <= semesterEnd, items.count < limit {
            let leafyWeekday = leafyWeekday(for: currentDay, calendar: calendar)
            if normalizedWeekdays.contains(leafyWeekday),
               let fireDate = date(on: currentDay, hour: settings.hour, minute: settings.minute, calendar: calendar),
               fireDate > now,
               let period = period(for: currentDay, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar),
               let progress = progressByStartWeek[period.startWeek],
               progress.remainingCount > 0 {
                items.append(
                    SunshineRunNotificationPlanItem(
                        id: notificationID(for: fireDate, period: period, calendar: calendar),
                        fireDate: fireDate,
                        periodTitle: period.title,
                        remainingCount: progress.remainingCount
                    )
                )
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }
        return items
    }

    static func clampedPeriodWeeks(
        for date: Date,
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        weeksPerPeriod: Int = 2,
        calendar: Calendar = .current
    ) -> (startWeek: Int, endWeek: Int) {
        if let period = currentPeriod(now: date, semesterStart: semesterStart, totalWeeks: totalWeeks, excludedWeeks: excludedWeeks, weeksPerPeriod: weeksPerPeriod, calendar: calendar) {
            return (period.startWeek, period.endWeek)
        }

        let week = clampedWeek(for: date, semesterStart: semesterStart, totalWeeks: totalWeeks, calendar: calendar)
        let safeWeeksPerPeriod = max(weeksPerPeriod, 1)
        let startWeek = ((week - 1) / safeWeeksPerPeriod) * safeWeeksPerPeriod + 1
        return (startWeek, min(startWeek + safeWeeksPerPeriod - 1, totalWeeks))
    }

    static func isExcludedDate(
        _ date: Date,
        semesterStart: Date = SemesterConfig.startOfSemesterDate,
        totalWeeks: Int = SemesterConfig.supportedWeeks,
        excludedWeeks: Set<Int> = SemesterConfig.sunshineRunExcludedWeeks,
        calendar: Calendar = .current
    ) -> Bool {
        guard let week = weekNumber(for: date, semesterStart: semesterStart, totalWeeks: totalWeeks, calendar: calendar) else {
            return false
        }
        return normalizedExcludedWeeks(excludedWeeks, totalWeeks: totalWeeks).contains(week)
    }

    private static func activeWeeks(totalWeeks: Int, excludedWeeks: Set<Int>) -> [Int] {
        guard totalWeeks > 0 else { return [] }
        let excludedWeeks = normalizedExcludedWeeks(excludedWeeks, totalWeeks: totalWeeks)
        return (1...totalWeeks).filter { !excludedWeeks.contains($0) }
    }

    private static func normalizedExcludedWeeks(_ excludedWeeks: Set<Int>, totalWeeks: Int) -> Set<Int> {
        guard totalWeeks > 0 else { return [] }
        return Set(excludedWeeks.filter { (1...totalWeeks).contains($0) })
    }

    private static func weekNumber(
        for date: Date,
        semesterStart: Date,
        totalWeeks: Int,
        calendar: Calendar
    ) -> Int? {
        guard totalWeeks > 0 else { return nil }
        let startDate = calendar.startOfDay(for: semesterStart)
        let targetDate = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        guard dayOffset >= 0, dayOffset < totalWeeks * 7 else { return nil }
        return dayOffset / 7 + 1
    }

    private static func clampedWeek(
        for date: Date,
        semesterStart: Date,
        totalWeeks: Int,
        calendar: Calendar
    ) -> Int {
        guard totalWeeks > 0 else { return 1 }
        let startDate = calendar.startOfDay(for: semesterStart)
        let targetDate = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: startDate, to: targetDate).day ?? 0
        return min(max(dayOffset / 7 + 1, 1), totalWeeks)
    }

    private static func leafyWeekday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return ((weekday + 5) % 7) + 1
    }

    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private static func notificationID(for fireDate: Date, period: SunshineRunPeriod, calendar: Calendar) -> String {
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
        return "leafy.sunshineRun.\(period.startWeek)-\(period.endWeek).\(stamp)"
    }
}

enum SunshineRunStore {
    private static let recordsKey = "sunshineRun.records"
    private static let reminderSettingsKey = "sunshineRun.reminderSettings"
    private static let ruleSettingsKey = "sunshineRun.ruleSettings"

    static func loadRecords() -> [SunshineRunRecord] {
        migrateLegacyValues()
        guard let data = UserDefaults.standard.data(forKey: scoped(recordsKey)) else { return [] }
        let records = (try? JSONDecoder().decode([SunshineRunRecord].self, from: data)) ?? []
        return SunshineRunPlanner.normalizedRecords(records)
    }

    static func saveRecords(_ records: [SunshineRunRecord]) {
        let normalizedRecords = SunshineRunPlanner.normalizedRecords(records)
        guard let data = try? JSONEncoder().encode(normalizedRecords) else { return }
        UserDefaults.standard.set(data, forKey: scoped(recordsKey))
    }

    static func loadReminderSettings() -> SunshineRunReminderSettings {
        migrateLegacyValues()
        guard let data = UserDefaults.standard.data(forKey: scoped(reminderSettingsKey)),
              let settings = try? JSONDecoder().decode(SunshineRunReminderSettings.self, from: data)
        else { return SunshineRunReminderSettings() }
        return SunshineRunReminderSettings(
            isEnabled: settings.isEnabled,
            selectedWeekdays: settings.selectedWeekdays,
            hour: settings.hour,
            minute: settings.minute,
            scheduledNotificationIDs: settings.scheduledNotificationIDs
        )
    }

    static func saveReminderSettings(_ settings: SunshineRunReminderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: scoped(reminderSettingsKey))
    }

    static func loadRuleSettings() -> SunshineRunRuleSettings {
        migrateLegacyValues()
        guard let data = UserDefaults.standard.data(forKey: scoped(ruleSettingsKey)),
              let settings = try? JSONDecoder().decode(SunshineRunRuleSettings.self, from: data)
        else { return .bjfuDefault }
        return SunshineRunRuleSettings(
            totalTarget: settings.totalTarget,
            weeksPerPeriod: settings.weeksPerPeriod,
            periodTarget: settings.periodTarget,
            skipsExcludedWeeks: settings.skipsExcludedWeeks
        )
    }

    static func saveRuleSettings(_ settings: SunshineRunRuleSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: scoped(ruleSettingsKey))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: scoped(recordsKey))
        UserDefaults.standard.removeObject(forKey: scoped(reminderSettingsKey))
        UserDefaults.standard.removeObject(forKey: scoped(ruleSettingsKey))
    }

    private static func scoped(_ key: String) -> String {
        CampusScopedDefaults.key(key)
    }

    private static func migrateLegacyValues() {
        CampusScopedDefaults.migrateLegacyValuesIfNeeded(
            keys: [recordsKey, reminderSettingsKey, ruleSettingsKey],
            migrationID: "sunshineRun"
        )
    }
}

@MainActor
enum SunshineRunNotificationManager {
    static func updateNotifications(
        settings: SunshineRunReminderSettings,
        records: [SunshineRunRecord],
        rules: SunshineRunRuleSettings,
        now: Date = Date()
    ) async throws -> SunshineRunReminderSettings {
        cancelScheduledNotifications(settings: settings)

        var updatedSettings = settings
        updatedSettings.scheduledNotificationIDs = []

        let planItems = SunshineRunPlanner.notificationPlan(
            settings: settings,
            records: records,
            now: now,
            excludedWeeks: rules.excludedWeeks,
            weeksPerPeriod: rules.weeksPerPeriod,
            periodTarget: rules.periodTarget,
            totalTarget: rules.totalTarget
        )
        guard settings.isEnabled, !planItems.isEmpty else {
            return updatedSettings
        }

        let center = try await authorizedNotificationCenter()
        for item in planItems {
            let content = UNMutableNotificationContent()
            content.title = "阳光长跑提醒"
            content.body = "\(item.periodTitle)这一组还差 \(item.remainingCount) 次。"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try await center.add(request)
            updatedSettings.scheduledNotificationIDs.append(item.id)
        }

        return updatedSettings
    }

    static func cancelScheduledNotifications(settings: SunshineRunReminderSettings) {
        guard !settings.scheduledNotificationIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: settings.scheduledNotificationIDs)
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
