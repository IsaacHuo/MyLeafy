import Foundation
import OSLog
import SwiftData

enum SchoolDataPrefetchTrigger: Equatable {
    case login
    case foreground
}

enum SchoolDataPrefetchSkipReason: Equatable {
    case alreadyRunning
    case unsupportedCampus
    case customCampus
    case missingIdentity
    case notLoggedIn
    case nonUndergraduatePortal
    case successCooldown
    case failureCooldown
}

enum SchoolDataPrefetchStartResult: Equatable {
    case started
    case skipped(SchoolDataPrefetchSkipReason)
}

@MainActor
final class SchoolDataPrefetchCoordinator {
    typealias SyncOperation = @MainActor (ModelContext, AppLanguagePreference) async -> SchoolDataSyncOutcome

    static let shared = SchoolDataPrefetchCoordinator()

    private static let lastSuccessKey = "schoolDataPrefetch.lastSuccessAt"
    private static let lastFailureKey = "schoolDataPrefetch.lastFailureAt"
    private static let successCooldown: TimeInterval = 30 * 60
    private static let failureCooldown: TimeInterval = 2 * 60

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.isaachuo.leafy", category: "SchoolDataPrefetch")
    private var activeTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.now = now
    }

    @discardableResult
    func prefetchIfNeeded(
        modelContext: ModelContext,
        language: AppLanguagePreference,
        trigger: SchoolDataPrefetchTrigger,
        syncOperation: @escaping SyncOperation = { modelContext, language in
            await SchoolDataSyncService.syncAll(modelContext: modelContext, language: language)
        }
    ) -> SchoolDataPrefetchStartResult {
        guard activeTask == nil else {
            return .skipped(.alreadyRunning)
        }

        if ActiveCampusContext.identity?.isCustom == true {
            return .skipped(.customCampus)
        }

        guard ActiveCampusContext.descriptor.id == .bjfu else {
            return .skipped(.unsupportedCampus)
        }

        let networkManager = ActiveCampusContext.networkManager
        guard networkManager.hasCachedIdentity else {
            return .skipped(.missingIdentity)
        }
        guard networkManager.isLoggedIn else {
            return .skipped(.notLoggedIn)
        }
        guard networkManager.currentPortal == .undergraduate else {
            return .skipped(.nonUndergraduatePortal)
        }

        let startedAt = now()
        if trigger != .login {
            if let lastSuccessAt, startedAt.timeIntervalSince(lastSuccessAt) < Self.successCooldown {
                return .skipped(.successCooldown)
            }
            if let lastFailureAt, startedAt.timeIntervalSince(lastFailureAt) < Self.failureCooldown {
                return .skipped(.failureCooldown)
            }
        }

        activeTask = Task { @MainActor in
            logger.info("Academic prefetch started trigger=\(String(describing: trigger), privacy: .public)")
            let outcome = await syncOperation(modelContext, language)
            guard !Task.isCancelled else { return }

            switch outcome {
            case .success:
                lastSuccessAt = now()
                logger.info("Academic prefetch completed")
            case .needsLogin:
                lastFailureAt = now()
                logger.info("Academic prefetch skipped because login is required")
            case .needsReauthentication:
                lastFailureAt = now()
                logger.info("Academic prefetch requires reauthentication")
            }
            activeTask = nil
        }

        return .started
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    private var lastSuccessAt: Date? {
        get { userDefaults.object(forKey: scoped(Self.lastSuccessKey)) as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: scoped(Self.lastSuccessKey))
            } else {
                userDefaults.removeObject(forKey: scoped(Self.lastSuccessKey))
            }
        }
    }

    private var lastFailureAt: Date? {
        get { userDefaults.object(forKey: scoped(Self.lastFailureKey)) as? Date }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: scoped(Self.lastFailureKey))
            } else {
                userDefaults.removeObject(forKey: scoped(Self.lastFailureKey))
            }
        }
    }

    private func scoped(_ key: String) -> String {
        CampusScopedDefaults.key(key, defaults: userDefaults)
    }
}
