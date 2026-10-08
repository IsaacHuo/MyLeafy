import Foundation

@MainActor
struct CampusOperationScope: Sendable {
    private let identityKey = ActiveCampusContext.identity?.scopeKey
    private let portal = ActiveCampusContext.networkManager.currentPortal
    private let generation = ActiveCampusContext.networkManager.sessionGeneration

    var isCurrent: Bool {
        identityKey == ActiveCampusContext.identity?.scopeKey
            && portal == ActiveCampusContext.networkManager.currentPortal
            && generation == ActiveCampusContext.networkManager.sessionGeneration
    }

    func check() throws {
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
    }

    func wasCancelled(_ error: Error) -> Bool {
        !isCurrent || Task.isCancelled || error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }
}
