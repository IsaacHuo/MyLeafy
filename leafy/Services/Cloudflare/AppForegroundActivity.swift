import Foundation
import OSLog

nonisolated struct ForegroundActivityEvent: Codable, Sendable, Equatable {
    let id: UUID
    let occurredAt: String
    let platform: String
    let appVersion: String

    static func make(now: Date = Date(), version: String) -> Self {
        Self(id: UUID(), occurredAt: ISO8601DateFormatter().string(from: now), platform: "ios", appVersion: version)
    }
}
nonisolated struct ForegroundActivityQueue: Codable, Sendable {
    var profileID: UUID?
    var events: [ForegroundActivityEvent] = []

    mutating func prune(now: Date) {
        let formatter = ISO8601DateFormatter()
        events.removeAll { event in
            guard let date = formatter.date(from: event.occurredAt) else { return true }
            return date < now.addingTimeInterval(-7 * 86_400) || date > now.addingTimeInterval(300)
        }
    }
    mutating func bind(to profile: UUID) {
        if let profileID, profileID != profile { events.removeAll() }
        profileID = profile
    }
    mutating func acknowledge(_ ids: [UUID]) {
        let accepted = Set(ids)
        events.removeAll { accepted.contains($0.id) }
    }
}

nonisolated struct ForegroundActivityBatch: Encodable, Sendable { let profileID: UUID; let events: [ForegroundActivityEvent] }
nonisolated struct ForegroundActivityReceipt: Decodable, Sendable { let accepted: [UUID] }

/// The root view's cancellable foreground task owns this loop. Guest and tests never create a client.
@MainActor enum AppForegroundActivity {
    private static let logger = Logger(subsystem: "com.isaachuo.leafy", category: "AppActivity")
    static func permits(identity: CampusIdentity?, isDemo: Bool) -> Bool {
        identity != nil && identity?.isGuest == false && !isDemo
    }
    static func run(identity: CampusIdentity) async {
        guard permits(identity: identity, isDemo: ReviewDemoMode.isEnabled), !AppRuntimeEnvironment.isRunningUnitTests else { return }
        let key = "leafy.foreground-activity.\(identity.scopeKey)"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        while !Task.isCancelled && ActiveCampusContext.identity?.scopeKey == identity.scopeKey {
            do {
                var queue = try load(key: key)
                queue.prune(now: Date())
                let event = ForegroundActivityEvent.make(version: version)
                queue.events.append(event)
                try save(queue, key: key)
                await CommunitySessionManager.shared.bootstrapCommunityUser()
                try Task.checkCancellation()
                guard ActiveCampusContext.identity?.scopeKey == identity.scopeKey else { return }
                guard let profile = CommunitySessionManager.shared.profile, profile.eduID.caseInsensitiveCompare(identity.eduID) == .orderedSame else {
                    throw MyLeafyBackendError(status: 0, code: "activity_profile_unavailable", message: "活动身份尚未准备完成", requestID: nil)
                }
                queue.bind(to: profile.id)
                // A recreated account must never inherit the former profile's activity.
                if !queue.events.contains(where: { $0.id == event.id }) { queue.events.append(event) }
                try save(queue, key: key)
                let backend = try MyLeafyBackendEnvironment.client()
                while !queue.events.isEmpty {
                    try Task.checkCancellation()
                    guard ActiveCampusContext.identity?.scopeKey == identity.scopeKey else { return }
                    let receipt: ForegroundActivityReceipt = try await backend.request("/v1/activity", body: ForegroundActivityBatch(profileID: profile.id, events: Array(queue.events.prefix(100))))
                    try Task.checkCancellation()
                    guard !receipt.accepted.isEmpty else { throw MyLeafyBackendError(status: 0, code: "invalid_activity_receipt", message: "活动回执为空", requestID: nil) }
                    let before = queue.events.count
                    queue.acknowledge(receipt.accepted)
                    guard queue.events.count < before else { throw MyLeafyBackendError(status: 0, code: "invalid_activity_receipt", message: "活动回执不属于当前批次", requestID: nil) }
                    try save(queue, key: key)
                }
            } catch is CancellationError { return }
            catch { logger.error("Foreground activity retained for retry: \(error.localizedDescription, privacy: .public)") }
            do { try await Task.sleep(for: .seconds(300)) }
            catch { return }
        }
    }
    private static func load(key: String) throws -> ForegroundActivityQueue {
        guard let data = UserDefaults.standard.data(forKey: key) else { return ForegroundActivityQueue() }
        return try JSONDecoder().decode(ForegroundActivityQueue.self, from: data)
    }
    private static func save(_ queue: ForegroundActivityQueue, key: String) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(queue), forKey: key)
    }
}
