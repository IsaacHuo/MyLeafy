import Observation
import SwiftUI

/// Coordinates a single visible-grid snapshot with the existing live timetable container.
@MainActor
@Observable
final class TimetableReturnTransition {
    static let duration: TimeInterval = 0.14
    private(set) var requestID: UUID?
    private(set) var readyID: UUID?
    var isActive: Bool { requestID != nil }
    @ObservationIgnored var prepare: ((Int) -> Bool)?
    @ObservationIgnored var cancelPresentation: (() -> Void)?

    func perform(direction: Int, reducesMotion: Bool, update: () -> Void) {
        guard !isActive else { return }
        guard !reducesMotion, direction != 0 else { update(); return }
        requestID = UUID()
        readyID = nil
        guard prepare?(direction) == true else {
            finish()
            update()
            return
        }
        update()
    }

    func contentReady() { readyID = requestID }

    func cancel() {
        cancelPresentation?()
        finish()
    }

    func finish() {
        requestID = nil
        readyID = nil
    }
}
