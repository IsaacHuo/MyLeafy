import Foundation

nonisolated struct UserTimetableSettings: Codable, Equatable, Sendable {
    var academicYear: Int
    var term: Int
    var firstMonday: Date
    var periods: [TimetablePeriodSchedule.Slot]

    private enum CodingKeys: String, CodingKey { case academicYear, term, firstMonday, periods }
    init(academicYear: Int, term: Int, firstMonday: Date, periods: [TimetablePeriodSchedule.Slot]) {
        self.academicYear = academicYear; self.term = term; self.firstMonday = firstMonday; self.periods = periods
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        academicYear = try values.decode(Int.self, forKey: .academicYear)
        term = try values.decode(Int.self, forKey: .term)
        periods = try values.decode([TimetablePeriodSchedule.Slot].self, forKey: .periods)
        let dateString = try values.decode(String.self, forKey: .firstMonday)
        guard let date = Self.civilDate(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .firstMonday,
                in: values,
                debugDescription: "Invalid first Monday"
            )
        }
        firstMonday = date
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(academicYear, forKey: .academicYear); try values.encode(term, forKey: .term)
        try values.encode(periods, forKey: .periods)
        try values.encode(firstMondayString, forKey: .firstMonday)
    }

    var firstMondayString: String {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: firstMonday)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func civilDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: string), formatter.string(from: date) == string else { return nil }
        return date
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    static func monday(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    var semesterID: String { "\(academicYear)-\(academicYear + 1)-\(term)" }
    var summary: String { L10n.text("%d–%d 学年 · 第 %d 学期", academicYear, academicYear + 1, term) }
    var isValid: Bool {
        (1900 ... 2200).contains(academicYear) && (1 ... 2).contains(term)
            && firstMonday == Self.monday(containing: firstMonday)
            && (1 ... 24).contains(periods.count)
            && periods.enumerated().allSatisfy { index, slot in
                guard slot.period == index + 1, (0 ..< 24).contains(slot.startHour),
                      (0 ..< 24).contains(slot.endHour), (0 ..< 60).contains(slot.startMinute),
                      (0 ..< 60).contains(slot.endMinute) else { return false }
                let start = slot.startHour * 60 + slot.startMinute
                let end = slot.endHour * 60 + slot.endMinute
                return start < end
                    && (index == 0 || periods[index - 1].endHour * 60 + periods[index - 1].endMinute <= start)
            }
    }

    func runtimeConfig(base: SemesterRuntimeConfig) -> SemesterRuntimeConfig {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: firstMonday)
        let dateString = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        return SemesterRuntimeConfig(semesterID: semesterID,
                                     semesterStartDateString: dateString, supportedWeeks: 20,
                                     graduateTimetableTermCode: base.graduateTimetableTermCode,
                                     calendarEvents: base.calendarEvents, updatedAt: nil, isActive: true)
    }
}

nonisolated enum UserTimetableSettingsStore {
    static let key = "timetable.userSettings.v1"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (String, Data, UserTimetableSettings)?
    static func load(defaults: UserDefaults = .standard) -> UserTimetableSettings {
        let scoped = CampusScopedDefaults.key(key, defaults: defaults)
        let cacheKey = scoped + "|" + UserTimetableSettings.calendar.timeZone.identifier
        if let data = defaults.data(forKey: scoped) {
            if let value = lock
                .withLock({ cached.flatMap { $0.0 == cacheKey && $0.1 == data ? $0.2 : nil } }) { return value }
            if let value = try? JSONDecoder().decode(UserTimetableSettings.self, from: data), value.isValid {
                lock.withLock { cached = (cacheKey, data, value) }
                return value
            }
        }
        let base = SemesterRuntimeConfigCache.load(defaults: defaults) ?? .builtIn
        let year = Int(base.semesterID.split(separator: "-").first ?? "") ?? 2026
        return UserTimetableSettings(academicYear: year,
                                     term: Int(base.semesterID.split(separator: "-").last ?? "") ?? 1,
                                     firstMonday: UserTimetableSettings.monday(containing: base.semesterStartDate),
                                     periods: TimetablePeriodSchedule.defaultSlots)
    }
    static func freezeIfNeeded(defaults: UserDefaults = .standard) throws {
        let scoped = CampusScopedDefaults.key(key, defaults: defaults)
        if defaults.data(forKey: scoped) == nil {
            defaults.set(try JSONEncoder().encode(load(defaults: defaults)), forKey: scoped)
        }
    }
    static func save(_ settings: UserTimetableSettings, defaults: UserDefaults = .standard) throws {
        guard settings.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: CampusScopedDefaults.key(key, defaults: defaults))
        defaults.set(Date(), forKey: CampusScopedDefaults.key(key + ".editedAt", defaults: defaults))
        NotificationCenter.default.post(name: .semesterRuntimeConfigDidChange, object: nil)
    }
}

nonisolated enum TimetableClock {
    static func formatter(_ source: DateFormatter) -> DateFormatter {
        let formatter = source.copy() as! DateFormatter
        formatter.calendar = UserTimetableSettings.calendar
        formatter.timeZone = UserTimetableSettings.calendar.timeZone
        return formatter
    }
}
