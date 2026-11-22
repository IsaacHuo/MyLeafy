import Foundation

nonisolated struct TimetablePendingUpdates: OptionSet {
    let rawValue: Int
    static let data = Self(rawValue: 1 << 0)
    static let schedule = Self(rawValue: 1 << 1)
    static let timeline = Self(rawValue: 1 << 2)
    static let widget = Self(rawValue: 1 << 3)
    static let reports = Self(rawValue: 1 << 4)
}

/// Transient invalidations only; all data remains owned by the existing snapshots and stores.
nonisolated struct TimetableUpdateBuffer {
    private(set) var pending: TimetablePendingUpdates = []
    mutating func request(_ updates: TimetablePendingUpdates) { pending.formUnion(updates) }

    mutating func takeReady(isInteracting: Bool, hasInteractiveLayout: Bool) -> TimetablePendingUpdates {
        guard !isInteracting else { return [] }
        var ready = pending
        if !hasInteractiveLayout { ready.subtract([.widget, .reports]) }
        pending.subtract(ready)
        return ready
    }
}
