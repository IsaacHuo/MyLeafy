import Foundation
import Supabase

nonisolated enum CampusEmailAliasLoginError: LocalizedError, Equatable {
    case invalidEmail
    case unsupportedCampus
    case notBound
    case backendUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .unsupportedCampus:
            return "邮箱别名登录目前仅支持北京林业大学入口。"
        case .notBound:
            return Self.notBoundMessage
        case .backendUnavailable(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "邮箱别名服务暂时不可用，请稍后再试。" : trimmed
        }
    }

    static let notBoundMessage = "没有找到这个邮箱对应的北林学号；请先用学号登录并绑定邮箱。"
}

nonisolated struct CampusEmailAliasLoginService: Sendable {
    private let communityService: CommunityService

    init(communityService: CommunityService = .shared) {
        self.communityService = communityService
    }

    func resolveEduID(email: String, campusID: CampusID = .bjfu) async throws -> String {
        let normalizedEmail = Self.normalizedEmail(email)
        guard Self.isValidEmail(normalizedEmail) else {
            throw CampusEmailAliasLoginError.invalidEmail
        }
        guard campusID == .bjfu else {
            throw CampusEmailAliasLoginError.unsupportedCampus
        }

        try await communityService.ensureAnonymousSession()
        let client = try LeafySupabase.shared.requireClient()
        let config = try LeafySupabase.shared.requireConfig()
        let session = try await client.auth.session
        client.functions.setAuth(token: session.accessToken)

        do {
            let response: CampusEmailAliasLookupResponse = try await client.functions.invoke(
                config.emailLookupFunctionName,
                options: FunctionInvokeOptions(
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    body: CampusEmailAliasLookupRequest(
                        email: normalizedEmail,
                        campusID: campusID.rawValue
                    )
                )
            )
            let eduID = response.eduID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !eduID.isEmpty else {
                throw CampusEmailAliasLoginError.backendUnavailable("邮箱别名服务返回空学号，请稍后再试。")
            }
            return eduID
        } catch let error as FunctionsError {
            throw Self.mapFunctionsError(error)
        }
    }

    static func isEmailIdentifier(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
    }

    static func normalizedEmail(_ value: String) -> String {
        CommunityEmailBinding.normalizedEmail(value)
    }

    static func isValidEmail(_ value: String) -> Bool {
        CommunityEmailBinding.isValidEmail(normalizedEmail(value))
    }

    static func mapFunctionsErrorForTesting(_ error: FunctionsError) -> Error {
        mapFunctionsError(error)
    }

    private static func mapFunctionsError(_ error: FunctionsError) -> Error {
        let envelope = SupabaseBackendClient.shared.mapFunctionsError(
            error,
            fallbackMessage: "邮箱别名服务暂时不可用，请稍后再试。"
        )
        return mapBackendErrorEnvelope(envelope)
    }

    private static func mapBackendErrorEnvelope(_ envelope: BackendErrorEnvelope) -> Error {
        switch envelope.code {
        case "bad_request":
            return CampusEmailAliasLoginError.invalidEmail
        case "not_found":
            return CampusEmailAliasLoginError.notBound
        default:
            return CampusEmailAliasLoginError.backendUnavailable(envelope.message)
        }
    }
}

private nonisolated struct CampusEmailAliasLookupRequest: Encodable, Sendable {
    let email: String
    let campusID: String

    enum CodingKeys: String, CodingKey {
        case email
        case campusID = "campus_id"
    }
}

private nonisolated struct CampusEmailAliasLookupResponse: Decodable, Sendable {
    let eduID: String

    enum CodingKeys: String, CodingKey {
        case eduID = "edu_id"
    }
}
