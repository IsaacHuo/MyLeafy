import Foundation
import OSLog

enum CommunityAccessRequirement: Sendable {
    case communityEntry
    case postCreation
    case commentCreation
    case profileInteraction
    case rating
}

enum CommunityAccessResult: Equatable, Sendable {
    case allowed
    case requiresProfileCompletion
    case requiresTermsAcceptance
    case failed(String)
}

@MainActor
protocol CommunitySessionManaging: AnyObject {
    var currentUserID: UUID? { get }
    var bootstrapError: String? { get }
    var requiresProfileCompletion: Bool { get }
    var communityAccessStatus: CommunityAccessStatus { get }
    var hasApprovedCommunityAccess: Bool { get }

    func restoreProfileIfPossible() async
    func bootstrapCommunityUser(force: Bool) async
}

nonisolated protocol CommunityTermsChecking: Sendable {
    func hasAcceptedCurrentTerms() async throws -> Bool
}

@MainActor
struct CommunityAccessGate {
    private let sessionManager: any CommunitySessionManaging
    private let termsChecker: any CommunityTermsChecking

    init(sessionManager: any CommunitySessionManaging, termsChecker: any CommunityTermsChecking) {
        self.sessionManager = sessionManager
        self.termsChecker = termsChecker
    }

    init(termsChecker: any CommunityTermsChecking = LiveCommunityRepository()) {
        self.init(sessionManager: CommunitySessionManager.shared, termsChecker: termsChecker)
    }

    func evaluate(
        _ requirement: CommunityAccessRequirement,
        forceBootstrap: Bool = false
    ) async -> CommunityAccessResult {
        CommunityDiagnostics.log.info("Community access gate evaluating \(String(describing: requirement), privacy: .public) forceBootstrap=\(forceBootstrap, privacy: .public)")
        await sessionManager.restoreProfileIfPossible()
        await sessionManager.bootstrapCommunityUser(force: forceBootstrap)

        let isBuiltInBJFUCommunity = ActiveCampusContext.descriptor.id == .bjfu
            && ActiveCampusContext.identity?.isCustom != true
        if let bootstrapError = sessionManager.bootstrapError,
           !(isBuiltInBJFUCommunity && sessionManager.currentUserID != nil) {
            CommunityDiagnostics.log.error("Community access gate failed after bootstrap: \(bootstrapError, privacy: .public)")
            return .failed(bootstrapError)
        }

        guard sessionManager.currentUserID != nil else {
            CommunityDiagnostics.log.error("Community access gate failed: missing authenticated user")
            return .failed(CommunityServiceError.missingAuthenticatedUser.localizedDescription)
        }

        let requiresSchoolCommunityApproval = ActiveCampusContext.identity?.isCustom == true
        guard !requiresSchoolCommunityApproval || sessionManager.hasApprovedCommunityAccess else {
            CommunityDiagnostics.log.error("Community access gate failed: school community unavailable")
            return .failed(communityUnavailableMessage)
        }

        switch requirement {
        case .rating:
            return .allowed
        case .profileInteraction:
            return sessionManager.requiresProfileCompletion ? .requiresProfileCompletion : .allowed
        case .communityEntry:
            return await termsResult()
        case .postCreation, .commentCreation:
            guard !sessionManager.requiresProfileCompletion else {
                return .requiresProfileCompletion
            }
            return await termsResult()
        }
    }

    private func termsResult() async -> CommunityAccessResult {
        do {
            let accepted = try await termsChecker.hasAcceptedCurrentTerms()
            CommunityDiagnostics.log.info("Community access gate terms result accepted=\(accepted, privacy: .public)")
            return accepted ? .allowed : .requiresTermsAcceptance
        } catch {
            CommunityDiagnostics.log.error("Community access gate terms check failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private var communityUnavailableMessage: String {
        switch sessionManager.communityAccessStatus {
        case .pending:
            return "学校申请正在审核中，社区功能暂未开放。"
        case .rejected:
            return "您申请的学校不通过，您现在是处于通用的模式下，社区功能暂不开放。"
        case .approved:
            return "社区身份正在同步，请稍后重试。"
        case .general:
            return "当前为通用模式，社区功能暂不开放。请先在社区页提交学校申请。"
        }
    }
}

extension CommunitySessionManager: CommunitySessionManaging {}
