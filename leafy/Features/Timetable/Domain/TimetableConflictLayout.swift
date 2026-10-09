import Foundation

/// Screen-independent intervals. Adjacent intervals do not conflict.
nonisolated struct TimetableConflictInterval: Identifiable, Equatable {
    let id: String
    let start: Double
    let end: Double
}

nonisolated struct TimetableConflictSegment: Equatable {
    var start: Double
    var end: Double
    let leading: Double
    let trailing: Double
}

nonisolated struct TimetableConflictBlock: Identifiable, Equatable {
    let id: String
    var segments: [TimetableConflictSegment]
}

nonisolated struct TimetableConflictGroup: Identifiable, Equatable {
    var start: Double
    var end: Double
    let itemIDs: [String]
    var id: String { "\(start)-\(itemIDs.joined(separator: ","))" }
}

nonisolated struct TimetableConflictLayout: Equatable {
    let blocks: [TimetableConflictBlock]
    let groups: [TimetableConflictGroup]

    static let empty = Self(blocks: [], groups: [])

    static func make(intervals: [TimetableConflictInterval]) -> Self {
        var seen = Set<String>()
        let items = intervals.filter { $0.end > $0.start && $0.start.isFinite && $0.end.isFinite }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end > $1.end }
                return $0.id < $1.id
            }
            .filter { seen.insert($0.id).inserted }
        guard !items.isEmpty else { return .empty }
        var blocks: [TimetableConflictBlock] = []
        var groups: [TimetableConflictGroup] = []
        var cluster: [TimetableConflictInterval] = []
        var clusterEnd = -Double.infinity
        func flush() {
            guard !cluster.isEmpty else { return }
            let result = layoutCluster(cluster)
            blocks.append(contentsOf: result.blocks)
            groups.append(contentsOf: result.groups)
            cluster.removeAll(keepingCapacity: true)
        }
        for item in items {
            if item.start >= clusterEnd { flush() }
            if cluster.isEmpty { clusterEnd = item.end } else { clusterEnd = max(clusterEnd, item.end) }
            cluster.append(item)
        }
        flush()
        return Self(blocks: blocks, groups: groups)
    }

    private static func layoutCluster(_ items: [TimetableConflictInterval]) -> Self {
        var endings: [Double] = []
        var lanes: [String: Int] = [:]
        for item in items {
            let lane = endings.firstIndex(where: { $0 <= item.start }) ?? endings.count
            if lane == endings.count { endings.append(item.end) } else { endings[lane] = item.end }
            lanes[item.id] = lane
        }
        let boundaries = Array(Set(items.flatMap { [$0.start, $0.end] })).sorted()
        var segments: [String: [TimetableConflictSegment]] = [:]
        var groups: [TimetableConflictGroup] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let active = items.filter { $0.start < end && $0.end > start }
                .sorted { lanes[$0.id, default: 0] < lanes[$1.id, default: 0] }
            if active.count >= 4 {
                let ids = active.map(\.id).sorted()
                if let last = groups.last, last.end == start, last.itemIDs == ids {
                    groups[groups.count - 1].end = end
                } else {
                    groups.append(.init(start: start, end: end, itemIDs: ids))
                }
                continue
            }
            let centers = active.map { (Double(lanes[$0.id, default: 0]) + 0.5) / Double(endings.count) }
            for (index, item) in active.enumerated() {
                let leading = index == 0 ? 0 : (centers[index - 1] + centers[index]) / 2
                let trailing = index == active.count - 1 ? 1 : (centers[index] + centers[index + 1]) / 2
                let segment = TimetableConflictSegment(start: start, end: end, leading: leading, trailing: trailing)
                var existing = segments[item.id, default: []]
                if let last = existing.last, last.end == start, last.leading == leading, last.trailing == trailing {
                    existing[existing.count - 1].end = end
                } else { existing.append(segment) }
                segments[item.id] = existing
            }
        }
        return Self(
            blocks: items.compactMap { item in
                guard let value = segments[item.id], !value.isEmpty else { return nil }
                return .init(id: item.id, segments: value)
            },
            groups: groups
        )
    }
}
