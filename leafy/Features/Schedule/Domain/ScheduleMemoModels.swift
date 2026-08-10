import Foundation
import SwiftData

nonisolated enum ScheduleMemoKind: String, CaseIterable, Identifiable, Sendable {
    case quickMemo
    case article
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickMemo:
            return "快速随记"
        case .article:
            return "写文"
        case .audio:
            return "录音随记"
        }
    }

    static func normalized(_ rawValue: String?) -> ScheduleMemoKind {
        guard let rawValue else { return .quickMemo }
        return ScheduleMemoKind(rawValue: rawValue) ?? .quickMemo
    }
}

@Model
final class ScheduleMemo {
    var id: UUID
    var body: String
    // These fields were added after the original memo store shipped. Keep them
    // optional so existing rows migrate without a destructive backfill.
    var kindRawValue: String?
    var title: String?
    var tagsRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var pinnedAt: Date?
    var trashedAt: Date?
    var linkedScheduleKindRawValue: String?
    var linkedScheduleID: String?

    init(
        id: UUID = UUID(),
        body: String,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinnedAt: Date? = nil,
        trashedAt: Date? = nil,
        linkedScheduleKindRawValue: String? = nil,
        linkedScheduleID: String? = nil,
        kindRawValue: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindRawValue = kindRawValue
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tagsRawValue = ScheduleMemoTagParser.encoded(tags ?? ScheduleMemoTagParser.tags(in: body))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.trashedAt = trashedAt
        self.linkedScheduleKindRawValue = linkedScheduleKindRawValue
        self.linkedScheduleID = linkedScheduleID
    }

    convenience init(
        id: UUID = UUID(),
        body: String,
        kind: ScheduleMemoKind,
        title: String? = nil,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinnedAt: Date? = nil,
        trashedAt: Date? = nil,
        linkedScheduleKindRawValue: String? = nil,
        linkedScheduleID: String? = nil
    ) {
        self.init(
            id: id,
            body: body,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinnedAt: pinnedAt,
            trashedAt: trashedAt,
            linkedScheduleKindRawValue: linkedScheduleKindRawValue,
            linkedScheduleID: linkedScheduleID,
            kindRawValue: kind.rawValue,
            title: title
        )
    }

    var tags: [String] {
        ScheduleMemoTagParser.decoded(tagsRawValue)
    }

    var kind: ScheduleMemoKind {
        get { ScheduleMemoKind.normalized(kindRawValue) }
        set { kindRawValue = newValue.rawValue }
    }

    var displayTitle: String {
        let storedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return storedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? kind.title
    }

    var linkedScheduleKind: ScheduleMemoLinkKind? {
        get { linkedScheduleKindRawValue.flatMap(ScheduleMemoLinkKind.init(rawValue:)) }
        set { linkedScheduleKindRawValue = newValue?.rawValue }
    }

    var isTrashed: Bool { trashedAt != nil }
    var isPinned: Bool { pinnedAt != nil }

    func updateBody(_ value: String, at date: Date = Date()) {
        body = value.trimmingCharacters(in: .whitespacesAndNewlines)
        tagsRawValue = ScheduleMemoTagParser.encoded(ScheduleMemoTagParser.tags(in: value))
        updatedAt = date
    }
}

@Model
final class ScheduleMemoImage {
    var id: UUID
    var memoID: UUID
    var sortOrder: Int
    var localFilename: String
    var importedAt: Date

    init(
        id: UUID = UUID(),
        memoID: UUID,
        sortOrder: Int,
        localFilename: String,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.memoID = memoID
        self.sortOrder = sortOrder
        self.localFilename = localFilename
        self.importedAt = importedAt
    }
}

@Model
final class ScheduleMemoAttachment {
    var id: UUID
    var memoID: UUID
    var sortOrder: Int
    var originalFilename: String
    var localFilename: String
    var contentTypeIdentifier: String
    var importedAt: Date

    init(
        id: UUID = UUID(),
        memoID: UUID,
        sortOrder: Int,
        originalFilename: String,
        localFilename: String,
        contentTypeIdentifier: String,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.memoID = memoID
        self.sortOrder = sortOrder
        self.originalFilename = originalFilename
        self.localFilename = localFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.importedAt = importedAt
    }
}

@Model
final class ScheduleMemoAudio {
    var id: UUID
    var memoID: UUID
    var localFilename: String
    var duration: TimeInterval
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        memoID: UUID,
        localFilename: String,
        duration: TimeInterval,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.memoID = memoID
        self.localFilename = localFilename
        self.duration = duration
        self.recordedAt = recordedAt
    }
}

nonisolated enum ScheduleMemoLinkKind: String, Sendable {
    case timetableReminder
    case importantDate
}

nonisolated enum ScheduleMemoSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case recentlyUpdated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "创建时间（从新到旧）"
        case .oldest: return "创建时间（从旧到新）"
        case .recentlyUpdated: return "最近更新"
        }
    }
}

nonisolated enum ScheduleMemoPhotoSelection {
    static func removing<Item: Equatable>(_ item: Item, from items: [Item]) -> [Item] {
        items.filter { $0 != item }
    }

    static func merging<Item>(
        pickerItems: [Item],
        capturedItems: [Item],
        maximumCount: Int
    ) -> [Item] {
        Array((pickerItems + capturedItems).prefix(max(maximumCount, 0)))
    }
}

nonisolated struct ScheduleMemoPhotoSelectionTransaction<Item> {
    private(set) var committed: [Item]
    var pending: [Item]

    init(committed: [Item]) {
        self.committed = committed
        self.pending = committed
    }

    mutating func commit() -> [Item] {
        committed = pending
        return committed
    }

    mutating func cancel() -> [Item] {
        pending = committed
        return committed
    }

    var fullPickerSelection: [Item] {
        pending
    }
}

nonisolated struct ScheduleMemoSearchRecord: Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let tags: [String]
    let attachmentNames: [String]
    let createdAt: Date
    let updatedAt: Date
    let pinnedAt: Date?
    let isTrashed: Bool
    let imageCount: Int
    let isLinked: Bool

    init(
        id: UUID,
        title: String = "",
        body: String,
        tags: [String],
        attachmentNames: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        pinnedAt: Date?,
        isTrashed: Bool,
        imageCount: Int,
        isLinked: Bool
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.attachmentNames = attachmentNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.isTrashed = isTrashed
        self.imageCount = imageCount
        self.isLinked = isLinked
    }
}

nonisolated enum ScheduleMemoSearchEngine {
    static func results(
        in records: [ScheduleMemoSearchRecord],
        query: String,
        tag: String? = nil,
        requiresImages: Bool = false,
        requiresLink: Bool = false,
        sort: ScheduleMemoSort = .newest
    ) -> [ScheduleMemoSearchRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            guard !record.isTrashed else { return false }
            if let tag,
               !record.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) {
                return false
            }
            if requiresImages && record.imageCount == 0 { return false }
            if requiresLink && !record.isLinked { return false }
            return normalizedQuery.isEmpty
                || record.title.localizedCaseInsensitiveContains(normalizedQuery)
                || record.body.localizedCaseInsensitiveContains(normalizedQuery)
                || record.tags.contains(where: { $0.localizedCaseInsensitiveContains(normalizedQuery) })
                || record.attachmentNames.contains(where: { $0.localizedCaseInsensitiveContains(normalizedQuery) })
        }
        .sorted { lhs, rhs in
            if (lhs.pinnedAt != nil) != (rhs.pinnedAt != nil) { return lhs.pinnedAt != nil }
            switch sort {
            case .newest: return lhs.createdAt > rhs.createdAt
            case .oldest: return lhs.createdAt < rhs.createdAt
            case .recentlyUpdated: return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}

nonisolated enum ScheduleMemoTagParser {
    private static let pattern = #"#([\p{L}\p{N}_-]+(?:/[\p{L}\p{N}_-]+)*)"#

    static func tags(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var result: [String] = []

        for match in expression.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let tagRange = Range(match.range(at: 1), in: text)
            else { continue }
            let tag = String(text[tagRange])
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted {
                result.append(tag)
            }
        }
        return result
    }

    static func encoded(_ tags: [String]) -> String {
        tags.joined(separator: "\n")
    }

    static func decoded(_ value: String) -> [String] {
        value.split(separator: "\n").map(String.init)
    }
}

nonisolated struct ScheduleMemoActivityDay: Identifiable, Equatable, Sendable {
    let date: Date
    let count: Int

    var id: Date { date }
}

nonisolated struct ScheduleMemoMonthStatistics: Identifiable, Equatable, Sendable {
    let month: Int
    let memoCount: Int
    let recordingDayCount: Int

    var id: Int { month }
}

nonisolated struct ScheduleMemoFrequency: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

nonisolated enum ScheduleMemoTimePeriod: String, CaseIterable, Identifiable, Sendable {
    case earlyMorning
    case morning
    case afternoon
    case evening
    case lateNight

    var id: String { rawValue }
}

nonisolated struct ScheduleMemoTimePeriodFrequency: Identifiable, Equatable, Sendable {
    let period: ScheduleMemoTimePeriod
    let count: Int

    var id: ScheduleMemoTimePeriod { period }
}

struct ScheduleMemoStatistics: Equatable {
    let memoCount: Int
    let tagCount: Int
    let recordingDayCount: Int
    let activityDays: [ScheduleMemoActivityDay]
    let currentStreak: Int
    let longestStreak: Int
    let selectedYear: Int
    let selectedYearMonths: [ScheduleMemoMonthStatistics]
    let recent30Days: [ScheduleMemoActivityDay]
    let recent30DayMemoCount: Int
    let previous30DayMemoCount: Int
    let recent30DayRecordingDayCount: Int
    let previous30DayRecordingDayCount: Int
    let weekdayDistribution: [Int] // Monday through Sunday.
    let timePeriodDistribution: [ScheduleMemoTimePeriodFrequency]
    let topTags: [ScheduleMemoFrequency]
    let firstRecordingDate: Date?
    let peakDate: Date?
    let peakMemoCount: Int
    let recordingMonthCount: Int

    static func make(
        memos: [ScheduleMemo],
        now: Date = Date(),
        calendar: Calendar = .current,
        weekCount: Int = 12
    ) -> ScheduleMemoStatistics {
        snapshot(memos: memos, selectedYear: calendar.component(.year, from: now), now: now, calendar: calendar, weekCount: weekCount)
    }

    static func snapshot(
        memos: [ScheduleMemo],
        selectedYear: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        weekCount: Int = 12
    ) -> ScheduleMemoStatistics {
        let active = memos.filter { !$0.isTrashed }
        let today = calendar.startOfDay(for: now)
        let counts = Dictionary(grouping: active) { calendar.startOfDay(for: $0.createdAt) }
            .mapValues { $0.count }
        let days = Set(counts.keys)
        let uniqueTags = Set(active.flatMap(\.tags).map(Self.tagKey))

        let weekdayCounts = active.reduce(into: Array(repeating: 0, count: 7)) { result, memo in
            let sundayBased = calendar.component(.weekday, from: memo.createdAt)
            result[(sundayBased + 5) % 7] += 1
        }
        let periods = ScheduleMemoTimePeriod.allCases.map { period in
            ScheduleMemoTimePeriodFrequency(period: period, count: active.filter { Self.period(for: calendar.component(.hour, from: $0.createdAt)) == period }.count)
        }
        var tagCounts: [String: (display: String, count: Int)] = [:]
        for tag in active.flatMap(\.tags) {
            let key = Self.tagKey(tag)
            tagCounts[key, default: (tag, 0)].count += 1
        }
        let topTags = tagCounts.values.sorted { lhs, rhs in
            lhs.count != rhs.count ? lhs.count > rhs.count : Self.tagKey(lhs.display) < Self.tagKey(rhs.display)
        }.prefix(5).map { ScheduleMemoFrequency(name: $0.display, count: $0.count) }

        let currentStreak = Self.streak(from: days, endingAt: today, calendar: calendar)
        let longestStreak = Self.longestStreak(from: days, calendar: calendar)
        let recent30Days = Self.dayRange(endingAt: today, count: 30, counts: counts, calendar: calendar)
        let previous30Days = Self.dayRange(endingAt: calendar.date(byAdding: .day, value: -30, to: today) ?? today, count: 30, counts: counts, calendar: calendar)
        let yearMonths = (1...12).map { month in
            let monthMemos = active.filter {
                let components = calendar.dateComponents([.year, .month], from: $0.createdAt)
                return components.year == selectedYear && components.month == month
            }
            return ScheduleMemoMonthStatistics(month: month, memoCount: monthMemos.count, recordingDayCount: Set(monthMemos.map { calendar.startOfDay(for: $0.createdAt) }).count)
        }
        let sortedDays = days.sorted()
        let peak = counts.sorted { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key }.first
        let months = Set(active.compactMap { memo -> Int? in
            let components = calendar.dateComponents([.year, .month], from: memo.createdAt)
            guard let year = components.year, let month = components.month else { return nil }
            return year * 100 + month
        })

        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        let firstDay = calendar.date(byAdding: .day, value: -(max(weekCount, 1) - 1) * 7, to: monday) ?? monday
        let activityDays = Self.dayRange(startingAt: firstDay, count: max(weekCount, 1) * 7, counts: counts, calendar: calendar)
        return ScheduleMemoStatistics(
            memoCount: active.count, tagCount: uniqueTags.count, recordingDayCount: counts.count,
            activityDays: activityDays, currentStreak: currentStreak, longestStreak: longestStreak,
            selectedYear: selectedYear, selectedYearMonths: yearMonths, recent30Days: recent30Days,
            recent30DayMemoCount: recent30Days.reduce(0) { $0 + $1.count }, previous30DayMemoCount: previous30Days.reduce(0) { $0 + $1.count },
            recent30DayRecordingDayCount: recent30Days.filter { $0.count > 0 }.count, previous30DayRecordingDayCount: previous30Days.filter { $0.count > 0 }.count,
            weekdayDistribution: weekdayCounts, timePeriodDistribution: periods, topTags: Array(topTags),
            firstRecordingDate: sortedDays.first, peakDate: peak?.key, peakMemoCount: peak?.value ?? 0, recordingMonthCount: months.count
        )
    }

    nonisolated private static func tagKey(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func period(for hour: Int) -> ScheduleMemoTimePeriod {
        switch hour { case 5...8: return .earlyMorning; case 9...11: return .morning; case 12...17: return .afternoon; case 18...23: return .evening; default: return .lateNight }
    }

    private static func dayRange(endingAt end: Date, count: Int, counts: [Date: Int], calendar: Calendar) -> [ScheduleMemoActivityDay] {
        let start = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: end) ?? end
        return dayRange(startingAt: start, count: count, counts: counts, calendar: calendar)
    }

    private static func dayRange(startingAt start: Date, count: Int, counts: [Date: Int], calendar: Calendar) -> [ScheduleMemoActivityDay] {
        guard count > 0 else { return [] }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ScheduleMemoActivityDay(date: date, count: counts[date, default: 0])
        }
    }

    private static func streak(from days: Set<Date>, endingAt end: Date, calendar: Calendar) -> Int {
        var cursor = days.contains(end) ? end : (calendar.date(byAdding: .day, value: -1, to: end) ?? end)
        var result = 0
        while days.contains(cursor) { result += 1; guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }; cursor = previous }
        return result
    }

    private static func longestStreak(from days: Set<Date>, calendar: Calendar) -> Int {
        let sortedDays = days.sorted()
        guard let first = sortedDays.first else { return 0 }

        var longest = 1
        var current = 1
        var previous = first
        for day in sortedDays.dropFirst() {
            if calendar.date(byAdding: .day, value: 1, to: previous) == day {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
            previous = day
        }
        return longest
    }
}

enum ScheduleMemoReviewEngine {
    static func selection(
        from memos: [ScheduleMemo],
        now: Date = Date(),
        page: Int = 0,
        limit: Int = 5,
        calendar: Calendar = .current
    ) -> [ScheduleMemo] {
        guard limit > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let eligible = memos.filter {
            !$0.isTrashed && calendar.startOfDay(for: $0.createdAt) < today
        }
        let anniversary = eligible.filter {
            let created = calendar.dateComponents([.month, .day], from: $0.createdAt)
            let current = calendar.dateComponents([.month, .day], from: now)
            return created.month == current.month && created.day == current.day
        }
        let anniversaryIDs = Set(anniversary.map(\.id))
        let remaining = eligible.filter { !anniversaryIDs.contains($0.id) }
        let seed = dayKey(today, calendar: calendar)
        let orderedAnniversary = deterministicOrder(anniversary, seed: seed)
        let orderedRemaining = deterministicOrder(remaining, seed: seed)
        let pool = orderedAnniversary + orderedRemaining
        guard !pool.isEmpty else { return [] }

        let start = (max(page, 0) * limit) % pool.count
        return (0..<min(limit, pool.count)).map { pool[(start + $0) % pool.count] }
    }

    private static func deterministicOrder(_ memos: [ScheduleMemo], seed: String) -> [ScheduleMemo] {
        memos.sorted {
            stableHash("\(seed)|\($0.id.uuidString)") < stableHash("\(seed)|\($1.id.uuidString)")
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
