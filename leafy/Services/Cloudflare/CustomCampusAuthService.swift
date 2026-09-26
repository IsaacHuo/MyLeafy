import Foundation

enum CustomCampusAuthError: LocalizedError {
    case invalidEmail
    case passwordTooShort
    case invalidCode
    case expiredCode
    case emailNotConfirmed(String)
    case invalidCredentials
    case emailRateLimited
    case emailProviderDisabled
    case signupDisabled
    case userAlreadyExists
    case weakPassword(String)
    case codeSendFailed
    case callbackLinkInvalid
    case callbackNeedsOriginalDevice
    case missingSession

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "请输入有效的邮箱地址。"
        case .passwordTooShort:
            return "密码至少需要 8 位。"
        case .invalidCode:
            return "验证码不正确，请核对邮件中的数字后重试。"
        case .expiredCode:
            return "验证码已失效，请重新发送验证码。"
        case .emailNotConfirmed(let email):
            return "\(email) 尚未完成邮箱验证。请切换到注册，重新发送验证码并完成验证。"
        case .invalidCredentials:
            return "邮箱或密码不正确。如果是第一次使用，请先注册并完成邮箱验证码。"
        case .emailRateLimited:
            return "验证码发送太频繁，请稍后再试。"
        case .emailProviderDisabled:
            return "邮箱登录暂不可用，请稍后重试。"
        case .signupDisabled:
            return "邮箱注册暂不可用，请稍后重试。"
        case .userAlreadyExists:
            return "这个邮箱已经注册。请切换到登录；如果还没完成验证，可以在注册页重新发送验证码。"
        case .weakPassword(let message):
            return "密码强度不足：\(message)"
        case .codeSendFailed:
            return "验证码邮件发送失败，请稍后重试。"
        case .callbackLinkInvalid:
            return "这个邮箱验证链接已失效或已经使用过。请回到 App 输入验证码，或使用邮箱和密码登录。"
        case .callbackNeedsOriginalDevice:
            return "这个验证链接需要在发起注册的设备上完成。请回到 App 输入验证码，或使用邮箱和密码登录。"
        case .missingSession:
            return "登录会话未建立，请稍后重试。"
        }
    }
}

struct CustomCampusAuthSession: Equatable, Sendable {
    let authUserID: UUID
    let email: String

    var campusIdentity: CampusIdentity {
        CampusIdentity(
            campusID: .custom,
            eduID: authUserID.uuidString,
            displayName: email,
            portal: .undergraduate,
            kind: .customSupabase
        )
    }
}

struct CustomCampusAuthService: Sendable {
    private let clientProvider: @Sendable () throws -> MyLeafyBackendClient
    init(clientProvider: @escaping @Sendable () throws -> MyLeafyBackendClient = { try MyLeafyBackendEnvironment.client() }) {
        self.clientProvider = clientProvider
    }
    func signIn(email: String, password: String) async throws -> CustomCampusAuthSession {
        let credentials = try validatedCredentials(email: email, password: password)
        do {
            let id = try await clientProvider().signIn(email: credentials.email, password: credentials.password)
            return CustomCampusAuthSession(authUserID: id, email: credentials.email)
        } catch { throw Self.mapAuthError(error, email: credentials.email) }
    }
    func startSignUp(email: String, password: String) async throws {
        let credentials = try validatedCredentials(email: email, password: password)
        do { try await clientProvider().signUp(email: credentials.email, password: credentials.password) }
        catch { throw Self.mapAuthError(error, email: credentials.email) }
    }
    func resendSignUpCode(email: String) async throws {
        let email = try validatedEmail(email)
        do { try await clientProvider().resendVerification(email: email) }
        catch { throw Self.mapAuthError(error, email: email) }
    }
    func verifySignUpCode(email: String, code: String) async throws -> CustomCampusAuthSession {
        let email = try validatedEmail(email), code = try validatedCode(code)
        do {
            let id = try await clientProvider().verifyRegistration(email: email, otp: code)
            return CustomCampusAuthSession(authUserID: id, email: email)
        } catch { throw Self.mapAuthError(error, email: email) }
    }
    func restoreSession(from url: URL) async throws -> CustomCampusAuthSession? {
        guard CustomCampusAuthCallback.isCallback(url) else { return nil }
        throw CustomCampusAuthError.callbackLinkInvalid
    }
    private func validatedEmail(_ email: String) throws -> String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidEmail(trimmedEmail) else {
            throw CustomCampusAuthError.invalidEmail
        }
        return trimmedEmail
    }

    private func validatedCredentials(email: String, password: String) throws -> (email: String, password: String) {
        let trimmedEmail = try validatedEmail(email)
        guard password.count >= 8 else {
            throw CustomCampusAuthError.passwordTooShort
        }
        return (trimmedEmail, password)
    }

    private func validatedCode(_ code: String) throws -> String {
        let trimmedCode = Self.normalizedCode(code)
        guard trimmedCode.count == 8, trimmedCode.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw CustomCampusAuthError.invalidCode
        }
        return trimmedCode
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func normalizedCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }

    static func normalizeCodeForTesting(_ code: String) -> String {
        normalizedCode(code)
    }

    static func mapAuthErrorForTesting(_ error: Error, email: String = "user@example.com") -> Error {
        mapAuthError(error, email: email)
    }

    static func mapCallbackErrorForTesting(_ error: Error) -> Error {
        CustomCampusAuthError.callbackLinkInvalid
    }

    private static func mapAuthError(_ error: Error, email: String) -> Error {
        guard let error = error as? MyLeafyBackendError else { return error }
        switch error.code.uppercased() {
        case "EMAIL_NOT_VERIFIED": return CustomCampusAuthError.emailNotConfirmed(email)
        case "INVALID_EMAIL_OR_PASSWORD": return CustomCampusAuthError.invalidCredentials
        case "OTP_EXPIRED": return CustomCampusAuthError.expiredCode
        case "INVALID_OTP": return CustomCampusAuthError.invalidCode
        case "TOO_MANY_REQUESTS", "TOO_MANY_ATTEMPTS": return CustomCampusAuthError.emailRateLimited
        case "USER_ALREADY_EXISTS", "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL": return CustomCampusAuthError.userAlreadyExists
        case "EMAIL_DELIVERY_FAILED", "EMAIL_UNAVAILABLE": return CustomCampusAuthError.codeSendFailed
        default: return error.status == 429 ? CustomCampusAuthError.emailRateLimited : error
        }
    }
}

nonisolated enum CustomCampusAuthCallback {
    static func isCallback(_ url: URL) -> Bool {
        url.scheme == "leafy" && url.host == "auth" && url.path == "/callback"
    }
}

@MainActor
extension SchoolNetworkManager {
    func persistCustomCampusAuthSession(_ session: CustomCampusAuthSession) {
        let identity = session.campusIdentity
        CampusIdentityStore.activate(identity)
        currentPortal = .undergraduate
        authenticatedEduID = identity.eduID
        authenticatedDisplayName = session.email
        isLoggedIn = true
    }
}
