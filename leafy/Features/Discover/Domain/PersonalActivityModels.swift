import Foundation
import SwiftData

nonisolated enum PersonalActivityChannel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case focus = "专注"
    case exercise = "运动"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .focus: return "timer"
        case .exercise: return "figure.run"
        }
    }

    var emptyTitle: String {
        switch self {
        case .focus: return "暂无专注活动"
        case .exercise: return "暂无运动活动"
        }
    }
}

nonisolated enum ActivityRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case semester = "本学期"
    case year = "近一年"

    var id: String { rawValue }
}

nonisolated struct ActivityInterval: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

nonisolated struct ActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let duration: TimeInterval
    let recordCount: Int
    let intensity: Int
    let weekIndex: Int
    let weekdayIndex: Int
    let isInRange: Bool
    let isFuture: Bool

    var id: Date { date }
}

nonisolated struct ActivityProjection: Equatable, Sendable {
    let interval: DateInterval
    let days: [ActivityDay]
    let totalDuration: TimeInterval
    let activeDayCount: Int
    let longestStreak: Int
    let currentStreak: Int
    let weekCount: Int

    static func make(
        intervals: [ActivityInterval],
        channel: PersonalActivityChannel,
        interval: DateInterval,
        now: Date = Date(),
        calendar baseCalendar: Calendar = .current
    ) -> ActivityProjection {
        var calendar = baseCalendar
        calendar.firstWeekday = 2

        let rangeStart = calendar.startOfDay(for: interval.start)
        let rawEnd = max(interval.end, rangeStart.addingTimeInterval(1))
        let rangeEndExclusive = calendar.startOfDay(for: rawEnd)
        let normalizedEndExclusive = rangeEndExclusive > rangeStart
            ? rangeEndExclusive
            : (calendar.date(byAdding: .day, value: 1, to: rangeStart) ?? rawEnd)
        let normalizedInterval = DateInterval(start: rangeStart, end: normalizedEndExclusive)

        var durationByDay: [Date: TimeInterval] = [:]
        var recordIDsByDay: [Date: Set<UUID>] = [:]

        for activity in intervals where activity.endedAt > activity.startedAt {
            var cursor = max(activity.startedAt, normalizedInterval.start)
            let clippedEnd = min(activity.endedAt, normalizedInterval.end)
            guard clippedEnd > cursor else { continue }

            while cursor < clippedEnd {
                let day = calendar.startOfDay(for: cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let segmentEnd = min(nextDay, clippedEnd)
                durationByDay[day, default: 0] += max(segmentEnd.timeIntervalSince(cursor), 0)
                recordIDsByDay[day, default: []].insert(activity.id)
                cursor = segmentEnd
            }
        }

        let leadingDays = (calendar.component(.weekday, from: rangeStart) + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: rangeStart) ?? rangeStart
        let lastRangeDay = calendar.date(byAdding: .day, value: -1, to: normalizedInterval.end) ?? rangeStart
        let trailingDays = 6 - ((calendar.component(.weekday, from: lastRangeDay) + 5) % 7)
        let gridEnd = calendar.date(byAdding: .day, value: trailingDays, to: lastRangeDay) ?? lastRangeDay
        let totalGridDays = max((calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0) + 1, 7)
        let today = calendar.startOfDay(for: now)

        let days = (0..<totalGridDays).compactMap { offset -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let duration = max(durationByDay[date, default: 0], 0)
            return ActivityDay(
                date: date,
                duration: duration,
                recordCount: recordIDsByDay[date]?.count ?? 0,
                intensity: intensity(for: duration, channel: channel),
                weekIndex: offset / 7,
                weekdayIndex: offset % 7,
                isInRange: date >= normalizedInterval.start && date < normalizedInterval.end,
                isFuture: date > today
            )
        }

        let rangeDays = days.filter(\.isInRange)
        let activeDates = Set(rangeDays.filter { $0.duration > 0 }.map(\.date))

        return ActivityProjection(
            interval: normalizedInterval,
            days: days,
            totalDuration: rangeDays.reduce(0) { $0 + $1.duration },
            activeDayCount: activeDates.count,
            longestStreak: longestStreak(in: rangeDays),
            currentStreak: currentStreak(activeDates: activeDates, today: today, interval: normalizedInterval, calendar: calendar),
            weekCount: max((totalGridDays + 6) / 7, 1)
        )
    }

    private static func intensity(for duration: TimeInterval, channel: PersonalActivityChannel) -> Int {
        let minutes = duration / 60
        guard minutes > 0 else { return 0 }

        switch channel {
        case .focus:
            if minutes < 30 { return 1 }
            if minutes < 60 { return 2 }
            if minutes < 120 { return 3 }
            return 4
        case .exercise:
            if minutes < 20 { return 1 }
            if minutes < 40 { return 2 }
            if minutes < 60 { return 3 }
            return 4
        }
    }

    private static func longestStreak(in days: [ActivityDay]) -> Int {
        var longest = 0
        var current = 0
        for day in days where day.isInRange {
            if day.duration > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func currentStreak(
        activeDates: Set<Date>,
        today: Date,
        interval: DateInterval,
        calendar: Calendar
    ) -> Int {
        guard today >= interval.start else { return 0 }
        let lastRangeDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        guard lastRangeDay >= (calendar.date(byAdding: .day, value: -1, to: today) ?? today) else {
            return 0
        }
        var cursor = min(today, lastRangeDay)
        if !activeDates.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  activeDates.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while cursor >= interval.start, activeDates.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

nonisolated enum ActivityDateRangeResolver {
    static func interval(
        for range: ActivityRange,
        now: Date = Date(),
        semesterConfig: SemesterRuntimeConfig = SemesterConfig.current,
        calendar baseCalendar: Calendar = .current
    ) -> DateInterval {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        switch range {
        case .semester:
            let start = calendar.startOfDay(for: semesterConfig.semesterStartDate)
            let semanticEnd = semesterConfig.calendarEvents
                .first { $0.academicCategory == .semesterEnd }?
                .endDate
                .map { calendar.startOfDay(for: $0) }
            let endInclusive = max(semanticEnd ?? today, start)
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: endInclusive) ?? tomorrow
            return DateInterval(start: start, end: endExclusive)
        case .year:
            let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        }
    }

    static func recentWeeks(
        _ count: Int = 4,
        now: Date = Date(),
        calendar baseCalendar: Calendar = .current
    ) -> DateInterval {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let weekdayOffset = (calendar.component(.weekday, from: today) + 5) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let start = calendar.date(byAdding: .weekOfYear, value: -(max(count, 1) - 1), to: currentWeekStart) ?? currentWeekStart
        let end = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? today
        return DateInterval(start: start, end: end)
    }
}

@Model
final class ExerciseSpace {
    var id: UUID
    var title: String
    var kindRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kindRawValue: String = ExerciseSpaceCategory.other.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kindRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }
}

@Model
final class ExerciseRecord {
    var id: UUID
    var spaceID: String
    var categoryRawValue: String
    var startedAt: Date
    var endedAt: Date
    var content: String
    var location: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        spaceID: String = "",
        categoryRawValue: String = ExerciseSpaceCategory.other.rawValue,
        startedAt: Date,
        endedAt: Date,
        content: String,
        location: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.spaceID = spaceID
        self.categoryRawValue = categoryRawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.content = content
        self.location = location
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated enum ExerciseSpaceCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case running = "跑步"
    case fitness = "健身"
    case ballSports = "球类"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .fitness: return "figure.strengthtraining.traditional"
        case .ballSports: return "sportscourt"
        case .other: return "figure.mixed.cardio"
        }
    }

    static func normalized(_ rawValue: String) -> ExerciseSpaceCategory {
        ExerciseSpaceCategory(rawValue: rawValue) ?? .other
    }
}

nonisolated enum ExerciseSpaceDestination: Hashable, Identifiable, Sendable {
    case fixed(ExerciseSpaceCategory)
    case custom(UUID)

    var id: String {
        switch self {
        case .fixed(let category): return "exercise-fixed-\(category.rawValue)"
        case .custom(let id): return "exercise-custom-\(id.uuidString)"
        }
    }

    var spaceID: String {
        switch self {
        case .fixed: return ""
        case .custom(let id): return id.uuidString
        }
    }

    var fixedCategory: ExerciseSpaceCategory? {
        if case .fixed(let category) = self { return category }
        return nil
    }
}

extension ExerciseRecord {
    var category: ExerciseSpaceCategory {
        get { ExerciseSpaceCategory.normalized(categoryRawValue) }
        set { categoryRawValue = newValue.rawValue }
    }

    func belongs(to destination: ExerciseSpaceDestination) -> Bool {
        switch destination {
        case .fixed(let category):
            return spaceID.isEmpty && self.category == category
        case .custom(let id):
            return spaceID == id.uuidString
        }
    }

    var activityInterval: ActivityInterval {
        ActivityInterval(id: id, startedAt: startedAt, endedAt: endedAt)
    }
}

@MainActor
enum ExerciseSpaceRecordMutation {
    static func delete(
        _ space: ExerciseSpace,
        records: [ExerciseRecord],
        includingRecords: Bool,
        in context: ModelContext,
        now: Date = Date()
    ) {
        for record in records where record.spaceID == space.id.uuidString {
            if includingRecords {
                context.delete(record)
            } else {
                record.spaceID = ""
                record.categoryRawValue = ExerciseSpaceCategory.other.rawValue
                record.updatedAt = now
            }
        }
        context.delete(space)
    }

    static func clear(
        _ destination: ExerciseSpaceDestination,
        records: [ExerciseRecord],
        in context: ModelContext
    ) {
        for record in records where record.belongs(to: destination) {
            context.delete(record)
        }
    }
}

extension StudyTimeRecord {
    var activityInterval: ActivityInterval {
        ActivityInterval(id: id, startedAt: startedAt, endedAt: endedAt)
    }
}

@MainActor
enum FocusActivityRecordAdapter {
    static func intervals(from records: [StudyTimeRecord]) -> [ActivityInterval] {
        records.map(\.activityInterval)
    }
}

@MainActor
enum ExerciseActivityRecordAdapter {
    static func intervals(from records: [ExerciseRecord]) -> [ActivityInterval] {
        records.map(\.activityInterval)
    }
}
