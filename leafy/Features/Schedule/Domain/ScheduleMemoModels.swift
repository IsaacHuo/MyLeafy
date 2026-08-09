import Foundation
import SwiftData

nonisolated enum ScheduleMemoKind: String, CaseIterable, Identifiable, Sendable {
    case quickMemo
    case article

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickMemo:
            return "快速随记"
        case .article:
            return "写文"
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

struct ScheduleMemoStatistics: Equatable {
    let memoCount: Int
    let tagCount: Int
    let recordingDayCount: Int
    let activityDays: [ScheduleMemoActivityDay]

    static func make(
        memos: [ScheduleMemo],
        now: Date = Date(),
        calendar: Calendar = .current,
        weekCount: Int = 12
    ) -> ScheduleMemoStatistics {
        let active = memos.filter { !$0.isTrashed }
        let uniqueTags = Set(active.flatMap(\.tags).map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        let counts = Dictionary(grouping: active) { calendar.startOfDay(for: $0.createdAt) }
            .mapValues { $0.count }
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let firstDay = calendar.date(byAdding: .day, value: -(max(weekCount, 1) - 1) * 7, to: currentMonday) ?? currentMonday
        let totalDays = max(weekCount, 1) * 7
        let activityDays = (0..<totalDays).compactMap { offset -> ScheduleMemoActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return ScheduleMemoActivityDay(date: date, count: counts[date, default: 0])
        }

        return ScheduleMemoStatistics(
            memoCount: active.count,
            tagCount: uniqueTags.count,
            recordingDayCount: counts.count,
            activityDays: activityDays
        )
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
