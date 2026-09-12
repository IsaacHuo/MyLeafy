import Foundation
import Security

nonisolated struct MyLeafyBackendSession: Codable, Sendable {
    let token: String
    let userID: UUID
    let isAnonymous: Bool
}

nonisolated struct MyLeafyBackendError: LocalizedError, Sendable {
    let status: Int
    let code: String
    let message: String
    let requestID: String?

    var errorDescription: String? { message }
}

nonisolated protocol MyLeafyBackendSessionStoring: Sendable {
    func load() throws -> MyLeafyBackendSession?
    func save(_ session: MyLeafyBackendSession) throws
    func remove() throws
}

nonisolated struct MyLeafyBackendKeychainStore: MyLeafyBackendSessionStoring {
    let origin: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.myleafy.cloudflare-session",
         kSecAttrAccount as String: origin,
         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    }

    func load() throws -> MyLeafyBackendSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw storageError(status) }
        return try JSONDecoder().decode(MyLeafyBackendSession.self, from: data)
    }

    func save(_ session: MyLeafyBackendSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw storageError(status) }
        var insertion = query
        insertion[kSecValueData as String] = data
        let inserted = SecItemAdd(insertion as CFDictionary, nil)
        guard inserted == errSecSuccess else { throw storageError(inserted) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError(status) }
    }

    private func storageError(_ status: OSStatus) -> MyLeafyBackendError {
        MyLeafyBackendError(status: 0, code: "session_storage_\(status)", message: "无法安全保存登录状态，请稍后重试。", requestID: nil)
    }
}

/// URLSession transport for the versioned Workers API. Construction performs no
/// network request; guest mode can keep using local stores without creating it.
actor MyLeafyBackendClient {
    nonisolated let baseURL: URL
    private let network: URLSession
    private let storage: any MyLeafyBackendSessionStoring
    private var establishingSession: Task<Void, Error>?
    private var currentSession: MyLeafyBackendSession?

    init(baseURL: URL, network: URLSession? = nil, storage: (any MyLeafyBackendSessionStoring)? = nil) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, baseURL.path.isEmpty || baseURL.path == "/" else {
            throw MyLeafyBackendError(status: 0, code: "invalid_api_origin", message: "后台地址配置无效。", requestID: nil)
        }
        self.baseURL = baseURL
        if let network {
            self.network = network
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.network = URLSession(configuration: configuration)
        }
        let resolvedStorage = storage ?? MyLeafyBackendKeychainStore(origin: baseURL.absoluteString)
        self.storage = resolvedStorage
        self.currentSession = try resolvedStorage.load()
    }

    func requireBearerToken() throws -> String {
        guard let currentSession else { throw MyLeafyBackendError(status: 401, code: "unauthenticated", message: "请重新登录。", requestID: nil) }
        return currentSession.token
    }

    var authUserID: UUID? { currentSession?.userID }

    func establishSession(legacyToken: String? = nil, legacyAnonymous: Bool = true) async throws {
        if currentSession != nil { return }
        if let establishingSession { return try await establishingSession.value }
        let task = Task {
            if let legacyToken { _ = try await exchangeLegacySession(accessToken: legacyToken, isAnonymous: legacyAnonymous) }
            else { try await anonymousSession() }
        }
        establishingSession = task
        defer { establishingSession = nil }
        try await task.value
    }

    func anonymousSession() async throws {
        if currentSession != nil { return }
        let (_, response, data) = try await send(path: "/v1/auth/sign-in/anonymous", method: "POST", body: Data("{}".utf8), authenticated: false)
        try captureSession(response: response, data: data)
    }

    func signIn(email: String, password: String) async throws -> UUID {
        let data = try JSONEncoder().encode(EmailPassword(email: email, password: password))
        let (_, response, payload) = try await send(path: "/v1/auth/sign-in/email", method: "POST", body: data, authenticated: false)
        try captureSession(response: response, data: payload)
        return currentSession!.userID
    }

    func signUp(email: String, password: String) async throws {
        struct Input: Encodable { let email: String; let password: String; let name: String }
        _ = try await send(path: "/v1/auth/sign-up/email", method: "POST", body: JSONEncoder().encode(Input(email: email, password: password, name: email)), authenticated: false)
    }

    func resendVerification(email: String) async throws {
        struct Input: Encodable { let email: String; let type = "email-verification" }
        _ = try await send(path: "/v1/auth/email-otp/send-verification-otp", method: "POST", body: JSONEncoder().encode(Input(email: email)), authenticated: false)
    }

    func verifyRegistration(email: String, otp: String) async throws -> UUID {
        struct Input: Encodable { let email: String; let otp: String }
        let (_, response, payload) = try await send(path: "/v1/auth/email-otp/verify-email", method: "POST", body: JSONEncoder().encode(Input(email: email, otp: otp)), authenticated: false)
        try captureSession(response: response, data: payload)
        return currentSession!.userID
    }

    func exchangeLegacySession(accessToken: String, isAnonymous: Bool) async throws -> UUID {
        struct Input: Encodable, Sendable { let access_token: String }
        struct Output: Decodable, Sendable { let token: String; let user_id: UUID }
        let payload = try JSONEncoder().encode(Input(access_token: accessToken))
        let (_, _, data) = try await send(path: "/v1/session/exchange", method: "POST", body: payload, authenticated: false)
        let output = try JSONDecoder().decode(Output.self, from: data)
        let session = MyLeafyBackendSession(token: output.token, userID: output.user_id, isAnonymous: isAnonymous)
        try storage.save(session)
        currentSession = session
        return session.userID
    }

    func signOut(localOnly: Bool = false) async throws {
        if !localOnly, currentSession != nil {
            _ = try await send(path: "/v1/auth/sign-out", method: "POST", body: Data("{}".utf8), authenticated: true)
        }
        try storage.remove()
        currentSession = nil
    }

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> Response {
        let (_, _, data) = try await send(path: path, query: query, method: "GET", authenticated: authenticated)
        return try Self.decoder().decode(Response.self, from: data)
    }

    func request<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        _ path: String, method: String = "POST", body: Body
    ) async throws -> Response {
        let (_, _, data) = try await send(path: path, method: method, body: JSONEncoder().encode(body), authenticated: true)
        return try Self.decoder().decode(Response.self, from: data)
    }

    func perform<Body: Encodable & Sendable>(_ path: String, method: String = "POST", body: Body) async throws {
        _ = try await send(path: path, method: method, body: JSONEncoder().encode(body), authenticated: true)
    }

    func uploadRequest(kind: String, uploadID: UUID, postID: UUID?, name: String, contentType: String) throws -> URLRequest {
        guard let session = currentSession else { throw MyLeafyBackendError(status: 401, code: "unauthenticated", message: "请重新登录。", requestID: nil) }
        var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        url.path = "/v1/files/upload"
        url.queryItems = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "upload_id", value: uploadID.uuidString.lowercased()), URLQueryItem(name: "name", value: name)]
        if let postID { url.queryItems?.append(URLQueryItem(name: "post_id", value: postID.uuidString.lowercased())) }
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    nonisolated func changeEvents(scope: String) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let socket = try await self.events(scope: scope)
                    socket.resume()
                    defer { socket.cancel(with: .goingAway, reason: nil) }
                    try await withTaskCancellationHandler {
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            let data: Data
                            switch message {
                            case .data(let bytes): data = bytes
                            case .string(let string): data = Data(string.utf8)
                            @unknown default: continue
                            }
                            struct Event: Decodable { let type: String }
                            if try JSONDecoder().decode(Event.self, from: data).type == "changed" { continuation.yield(()) }
                        }
                    } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
                    continuation.finish()
                } catch {
                    if Task.isCancelled { continuation.finish() } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func upload<Response: Decodable & Sendable>(data: Data, contentType: String, query: [URLQueryItem]) async throws -> Response {
        let (_, _, response) = try await send(path: "/v1/files/upload", query: query, method: "POST", body: data, contentType: contentType, authenticated: true)
        return try Self.decoder().decode(Response.self, from: response)
    }

    func download(bucket: String, path: String) async throws -> Data {
        let (_, _, data) = try await send(path: "/v1/files/read", query: [URLQueryItem(name: "bucket", value: bucket), URLQueryItem(name: "path", value: path)], method: "GET", authenticated: true)
        return data
    }

    func events(scope: String) throws -> URLSessionWebSocketTask {
        guard scope == "feed" || scope == "notifications", let session = currentSession else {
            throw MyLeafyBackendError(status: 401, code: "unauthenticated", message: "请重新登录。", requestID: nil)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/v1/events/\(scope)"
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        return network.webSocketTask(with: request)
    }

    private func send(path: String, query: [URLQueryItem] = [], method: String, body: Data? = nil,
                      contentType: String = "application/json", authenticated: Bool) async throws -> (Int, HTTPURLResponse, Data) {
        guard path.hasPrefix("/v1/") else {
            throw MyLeafyBackendError(status: 0, code: "invalid_api_path", message: "后台请求路径无效。", requestID: nil)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session = currentSession else {
                throw MyLeafyBackendError(status: 401, code: "unauthenticated", message: "请重新登录。", requestID: nil)
            }
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            if authenticated && response.statusCode == 401 && request.value(forHTTPHeaderField: "Authorization") == currentSession.map({ "Bearer \($0.token)" }) {
                try storage.remove()
                currentSession = nil
            }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw MyLeafyBackendError(status: response.statusCode, code: failure?.errorEnvelope?.code ?? failure?.code ?? "http_\(response.statusCode)",
                                     message: failure?.errorEnvelope?.message ?? failure?.error ?? failure?.message ?? "后台请求失败，请稍后重试。",
                                     requestID: response.value(forHTTPHeaderField: "X-Request-ID"))
        }
        return (response.statusCode, response, data)
    }

    private func captureSession(response: HTTPURLResponse, data: Data) throws {
        try Task.checkCancellation()
        let result = try JSONDecoder().decode(AuthenticationResult.self, from: data)
        // Better Auth's bearer plugin returns a signed token in this header. Its
        // unsigned JSON token must never be used as the Authorization credential.
        guard let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw MyLeafyBackendError(status: 0, code: "missing_signed_session", message: "登录状态未建立，请重试。", requestID: nil)
        }
        let session = MyLeafyBackendSession(token: token, userID: result.user.id, isAnonymous: result.user.isAnonymous ?? false)
        try storage.save(session)
        currentSession = session
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { input in
            let value = try input.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: input.codingPath, debugDescription: "Invalid API timestamp"))
        }
        return decoder
    }

    private struct EmailPassword: Encodable { let email: String; let password: String }
    private struct AuthenticationResult: Decodable { let user: User }
    private struct User: Decodable { let id: UUID; let isAnonymous: Bool? }
    private struct Failure: Decodable {
        let error: String?; let code: String?; let message: String?; let errorEnvelope: Envelope?
        struct Envelope: Decodable { let code: String; let message: String }
    }
}
