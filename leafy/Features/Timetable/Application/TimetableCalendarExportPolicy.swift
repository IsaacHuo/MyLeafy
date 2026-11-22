import Foundation

enum TimetableCalendarExportCategory: String, CaseIterable, Identifiable {
    case courses, exams, schedules

    var id: String { rawValue }
    var title: String {
        switch self {
        case .courses: return L10n.text("课程")
        case .exams: return L10n.text("考试")
        case .schedules: return L10n.text("日程")
        }
    }

    static func courseWeek(from key: String) -> Int? {
        guard !key.hasPrefix("personalSchedule:"), !key.hasPrefix("cellReminder:"), !key.hasPrefix("exam:"),
              let marker = key.range(of: "|week:", options: .backwards), marker.lowerBound != key.startIndex,
              let week = Int(key[marker.upperBound...]), (1 ... 20).contains(week) else { return nil }
        return week
    }

    static func category(for key: String) -> Self? {
        if key.hasPrefix("personalSchedule:") { return nil }
        if key.hasPrefix("exam:"), key.count > "exam:".count { return .exams }
        if key.hasPrefix("cellReminder:"), key.count > "cellReminder:".count { return .schedules }
        return courseWeek(from: key) == nil ? nil : .courses
    }
}

struct TimetableCalendarDestination: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let isDefault: Bool
    var displayTitle: String { "\(title)（\(source)）" }
}

struct TimetableCalendarSelection {
    let categories: Set<TimetableCalendarExportCategory>
    let weeks: ClosedRange<Int>
    let interval: DateInterval
    let draftKeys: Set<String>

    func contains(key: String, startDate: Date) -> Bool {
        guard let category = TimetableCalendarExportCategory.category(for: key), categories.contains(category) else {
            return false
        }
        if let week = TimetableCalendarExportCategory.courseWeek(from: key) { return weeks.contains(week) }
        return draftKeys.contains(key) || (startDate >= interval.start && startDate < interval.end)
    }
}

struct TimetableCalendarExistingEvent {
    let identifier: String
    let url: URL?
    let startDate: Date
    let isWritable: Bool
}

struct TimetableCalendarReconciliation {
    let retainedByKey: [String: String]
    let removedIdentifiers: Set<String>

    @MainActor
    static func plan(events: [TimetableCalendarExistingEvent], selection: TimetableCalendarSelection,
                     scopeKey: String?, confirmedLegacyEventIDs: Set<String>, clearing: Bool = false) throws -> Self {
        var groups: [String: [(event: TimetableCalendarExistingEvent, isLegacy: Bool)]] = [:]
        var legacyIDs = Set<String>()
        for event in events {
            guard let key = TimetableCalendarExportBuilder.occurrenceKey(from: event.url),
                  selection.contains(key: key, startDate: event.startDate),
                  let url = event.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            let scopes = (components.queryItems ?? []).filter { $0.name == "scope" }
            // Missing scope is an old released format, never proof of ownership by the current account.
            let legacy = scopes.isEmpty
            guard legacy || (scopes.count == 1 && scopes[0].value == scopeKey && scopeKey != nil) else { continue }
            guard event.isWritable else { throw TimetableCalendarExportError.readOnlyEvents }
            if legacy { legacyIDs.insert(event.identifier) }
            groups[key, default: []].append((event, legacy))
        }
        if !legacyIDs.isSubset(of: confirmedLegacyEventIDs) {
            throw TimetableCalendarExportError.legacyEventsRequireConfirmation(legacyIDs)
        }
        var retained: [String: String] = [:]
        var removed = Set<String>()
        for (key, matches) in groups {
            // Prefer an already scoped event; stable ordering keeps retries deterministic.
            let ordered = matches.sorted {
                if $0.isLegacy != $1.isLegacy { return !$0.isLegacy }
                return $0.event.identifier < $1.event.identifier
            }
            if !clearing, selection.draftKeys.contains(key), let first = ordered.first {
                retained[key] = first.event.identifier
                removed.formUnion(ordered.dropFirst().map { $0.event.identifier })
            } else {
                removed.formUnion(ordered.map { $0.event.identifier })
            }
        }
        return Self(retainedByKey: retained, removedIdentifiers: removed)
    }
}
