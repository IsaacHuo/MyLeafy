import Foundation

/// Dated local occurrences, shared by the app and every widget size.
nonisolated struct LeafyWidgetAgendaItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case course, schedule }

    var id: String
    var kind: Kind
    var sourceID: String
    var title: String
    var startsAt: Date
    var endsAt: Date?
    var locationText: String
    var teacherText: String?
    var noteText: String?
    var reminderText: String?
    var accentIndex: Int

    var effectiveEnd: Date { endsAt ?? startsAt.addingTimeInterval(45 * 60) }

    var destination: URL {
        if kind == .course, let id = UUID(uuidString: sourceID) {
            return LeafyWidgetRoute.course(id: id).url
        }
        return LeafyWidgetRoute.schedules.url
    }

    func isActive(at date: Date) -> Bool { startsAt <= date && date < effectiveEnd }

    var timeText: String {
        let start = Self.time(startsAt)
        guard let endsAt else { return start }
        return "\(start)–\(Self.time(endsAt))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            .locale(LeafyWidgetLanguagePreference.current.locale))
    }
}

nonisolated struct LeafyWidgetSemester: Codable, Hashable, Sendable {
    var id: String
    var startsAt: Date
    var weekCount: Int
    var hasTimetableCache: Bool

    func week(containing date: Date, calendar: Calendar) -> Int? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startsAt),
                                           to: calendar.startOfDay(for: date)).day ?? -1
        guard days >= 0, days < weekCount * 7 else { return nil }
        return days / 7 + 1
    }
}

nonisolated struct LeafyWidgetExam: Codable, Hashable, Sendable {
    var startsAt: Date
    var endsAt: Date
    var text: String
}

nonisolated struct LeafyWidgetSnapshotArchive: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2
    var schemaVersion = currentSchemaVersion
    var generatedAt: Date
    var isAuthenticated: Bool
    var semesters: [LeafyWidgetSemester]
    var items: [LeafyWidgetAgendaItem]
    var exams: [LeafyWidgetExam]
    var defaultStartMinute: Int
    var defaultEndMinute: Int
    var syncText: String?
    var lastFailureText: String?

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    func snapshot(for dayOffset: Int, relativeTo date: Date? = nil) -> LeafyWidgetDaySnapshot {
        let reference = date ?? generatedAt
        let calendar = Self.calendar
        let day = calendar.date(byAdding: .day,
                                value: LeafyWidgetSnapshotStore.normalizedDayOffset(dayOffset),
                                to: calendar.startOfDay(for: reference)) ?? reference
        return snapshot(on: day, now: reference)
    }

    func snapshot(on day: Date, now: Date) -> LeafyWidgetDaySnapshot {
        let calendar = Self.calendar
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let events = items.filter { $0.startsAt < end && $0.effectiveEnd > start }
            .sorted { ($0.startsAt, $0.id) < ($1.startsAt, $1.id) }
        let semester = semesters.last { $0.week(containing: day, calendar: calendar) != nil }
        let week = semester?.week(containing: day, calendar: calendar)
        let status: LeafyWidgetDaySnapshot.Status
        if !isAuthenticated { status = .needsLogin }
        else if !events.isEmpty { status = .ready }
        else if let semester, !semester.hasTimetableCache { status = .needsUpdate }
        else { status = .noEvents }
        return LeafyWidgetDaySnapshot(
            date: start, status: status,
            weekText: week.map { LeafyWidgetL10n.text("第 %d 周", $0) } ?? "",
            items: isAuthenticated ? events : [],
            nextExamText: exams.first { $0.endsAt >= max(start, now) }?.text
        )
    }

    func weekDates(containing date: Date) -> [Date] {
        let calendar = Self.calendar
        let start = calendar.startOfDay(for: date)
        let weekday = (calendar.component(.weekday, from: start) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekday, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Boundaries keep active/upcoming state and calendar days correct without opening the app.
    func timelineDates(from now: Date) -> [Date] {
        let calendar = Self.calendar
        let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86400)
        var dates = Set([now, end])
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        for item in items {
            for boundary in [item.startsAt, item.effectiveEnd] where boundary > now && boundary < end {
                dates.insert(boundary)
            }
        }
        return dates.sorted()
    }
}

nonisolated struct LeafyWidgetDaySnapshot: Hashable, Sendable {
    enum Status: String, Sendable { case ready, noEvents, needsLogin, needsUpdate }
    var date: Date
    var status: Status
    var weekText: String
    var items: [LeafyWidgetAgendaItem]
    var nextExamText: String?

    func remainingItems(at now: Date) -> [LeafyWidgetAgendaItem] {
        items.filter { $0.effectiveEnd > now }.sorted {
            let leftActive = $0.isActive(at: now)
            let rightActive = $1.isActive(at: now)
            if leftActive != rightActive { return leftActive }
            return ($0.startsAt, $0.id) < ($1.startsAt, $1.id)
        }
    }
}

/// A cross-midnight event is clipped to each day while retaining its real start/end labels.
nonisolated struct LeafyWidgetDaySegment: Identifiable, Hashable, Sendable {
    var item: LeafyWidgetAgendaItem
    var startMinute: Double
    var endMinute: Double
    var id: String { item.id }

    static func make(item: LeafyWidgetAgendaItem, day: Date) -> Self {
        let calendar = LeafyWidgetSnapshotArchive.calendar
        let midnight = calendar.startOfDay(for: day)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        func minute(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        }
        return Self(item: item,
                    startMinute: item.startsAt <= midnight ? 0 : minute(item.startsAt),
                    endMinute: item.effectiveEnd >= tomorrow ? 1440 : minute(item.effectiveEnd))
    }
}

/// At most two lanes. Dense overlap groups keep one lane plus an explicit details link.
nonisolated struct LeafyWidgetWeekBlock: Identifiable, Sendable {
    var id: String
    var segment: LeafyWidgetDaySegment
    var lane: Int
    var laneCount: Int
    var hiddenCount: Int
    var startMinute: Double
    var endMinute: Double

    static func layout(_ segments: [LeafyWidgetDaySegment], minimumMinutes: Double) -> [Self] {
        let sorted = segments.sorted {
            ($0.startMinute, $0.item.kind == .course ? 0 : 1, $0.id)
                < ($1.startMinute, $1.item.kind == .course ? 0 : 1, $1.id)
        }
        var groups: [[LeafyWidgetDaySegment]] = []
        var groupEnd = -Double.infinity
        for segment in sorted {
            if segment.startMinute >= groupEnd { groups.append([]) }
            groups[groups.count - 1].append(segment)
            groupEnd = max(groupEnd, max(segment.endMinute, segment.startMinute + minimumMinutes))
        }
        return groups.flatMap { group -> [Self] in
            var laneEnds: [Double] = []
            let assigned = group.map { segment -> (LeafyWidgetDaySegment, Int) in
                let lane = laneEnds.firstIndex { $0 <= segment.startMinute } ?? laneEnds.count
                let end = max(segment.endMinute, segment.startMinute + minimumMinutes)
                if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
                return (segment, lane)
            }
            let dense = laneEnds.count > 2
            let visible = dense ? assigned.filter { $0.1 == 0 } : assigned
            var blocks = visible.map { segment, lane in
                Self(id: segment.id, segment: segment, lane: lane,
                     laneCount: min(laneEnds.count, 2), hiddenCount: 0,
                     startMinute: segment.startMinute,
                     endMinute: max(segment.endMinute, segment.startMinute + minimumMinutes))
            }
            if dense, let first = group.first {
                blocks.append(Self(id: "more-\(first.id)", segment: first, lane: 1, laneCount: 2,
                                   hiddenCount: assigned.count - visible.count,
                                   startMinute: first.startMinute,
                                   endMinute: group.map { max($0.endMinute, $0.startMinute + minimumMinutes) }.max() ?? first.endMinute))
            }
            return blocks
        }
    }
}
