import Foundation

/// Coalesces committed local changes before collecting records for CloudKit.
@MainActor
final class ICloudSyncWorkScheduler {
    private var task: Task<Void, Never>?
    private var operation: (@MainActor () -> Void)?

    func schedule(after delay: Duration, operation: @escaping @MainActor () -> Void) {
        cancel()
        self.operation = operation
        task = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        let pending = operation
        cancel()
        pending?()
    }

    func cancel() {
        task?.cancel()
        task = nil
        operation = nil
    }
}

nonisolated enum ICloudSyncScheduling {
    static let localChangeDelay: Duration = .seconds(5)

    /// System-managed transfers use CloudKit's retry policy. This applies only
    /// to bootstrap and unfinished local download/merge recovery.
    static func recoveryDelay(failures: Int, retryAfter: TimeInterval = 0) -> TimeInterval {
        max(min(300 * pow(2, Double(min(max(failures - 1, 0), 3))), 1_800), retryAfter)
    }
}
