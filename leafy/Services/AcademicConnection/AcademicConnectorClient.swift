import Foundation

nonisolated enum SchoolConnectionMode: String, Codable, Sendable {
    case serverVPN
    case campusDirect
}

nonisolated enum SchoolConnectionRoute {
    @TaskLocal static var modeOverride: SchoolConnectionMode?
}

nonisolated struct AcademicConnectorFailure: LocalizedError, Equatable, Sendable {
    let status: Int
    let code: String
    let message: String
    let requestID: String?

    var errorDescription: String? { message }

    static let invalidResponse = Self(
        status: 0, code: "academic_response_invalid",
        message: "教务连接服务返回了无法识别的结果，请重试或改用校园网直连。", requestID: nil
    )
}

nonisolated struct AcademicConnectorLease: Sendable {
    let id: UUID
    let token: String
    let expiresAt: Date
}

nonisolated struct AcademicSchoolRequest: Encodable, Sendable {
    let method: String
    let path: String
    let bodyBase64: String?
    let referer: String?
    let cookies: [String: String]

    init(request: URLRequest, cookies: [String: String]) throws {
        guard let original = request.url,
              let url = AcademicSchoolURL.original(original),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw AcademicConnectorFailure.invalidResponse }
        let method = request.httpMethod ?? "GET"
        guard method == "GET" || method == "POST", request.httpBodyStream == nil else {
            throw AcademicConnectorFailure.invalidResponse
        }
        self.method = method
        path = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        bodyBase64 = request.httpBody?.base64EncodedString()
        if let raw = request.value(forHTTPHeaderField: "Referer"), let value = URL(string: raw),
           let original = AcademicSchoolURL.original(value) {
            referer = original.absoluteString
        } else {
            referer = nil
        }
        self.cookies = cookies
    }
}

nonisolated enum AcademicSchoolURL {
    private static let gatewayPrefix = "/web/1/http/0/newjwxt.bjfu.edu.cn"

    /// Restore only the school's known WebVPN prefix; never widen the allowed school origin.
    static func original(_ url: URL) -> URL? {
        guard url.user == nil, url.password == nil, url.fragment == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let direct = url.scheme == "http" && url.host?.lowercased() == "newjwxt.bjfu.edu.cn"
            && (url.port == nil || url.port == 80)
        let gateway = url.scheme == "https" && url.host?.lowercased() == "vpn1.bjfu.edu.cn"
            && (url.port == nil || url.port == 443)
        let wrapped = components.percentEncodedPath.hasPrefix(gatewayPrefix + "/")
        guard direct || (gateway && wrapped) else { return nil }
        if wrapped {
            components.percentEncodedPath = String(components.percentEncodedPath.dropFirst(gatewayPrefix.count)) }
        components.scheme = "http"
        components.host = "newjwxt.bjfu.edu.cn"
        components.port = nil
        return components.url
    }
}

nonisolated struct AcademicSchoolResponse: Sendable {
    let data: Data
    let url: URL
    let status: Int
    let contentType: String
    let cookies: [String: String]

    var response: HTTPURLResponse? {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )
    }
}

nonisolated enum AcademicConnectorCloseResult: Equatable, Sendable {
    case confirmed
    case alreadyReleased
    case unconfirmed(String)
}

nonisolated protocol AcademicConnectorServicing: Sendable {
    func start(credential: SchoolVPNCredential, cookies: [String: String]) async throws -> AcademicConnectorLease
    func execute(_ request: AcademicSchoolRequest, lease: AcademicConnectorLease) async throws -> AcademicSchoolResponse
    func close(_ lease: AcademicConnectorLease) async -> AcademicConnectorCloseResult
}

nonisolated private final class AcademicConnectorRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // These fixed JSON endpoints never redirect. Do not forward credentials or tokens elsewhere.
        completionHandler(nil)
    }
}

actor AcademicConnectorClient: AcademicConnectorServicing {
    private let baseURL: URL
    private let network: URLSession
    private let injectedNetwork: Bool

    init(baseURL: URL, network: URLSession? = nil) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, baseURL.path.isEmpty || baseURL.path == "/"
        else { throw AcademicConnectorFailure.invalidResponse }
        self.baseURL = baseURL
        injectedNetwork = network != nil
        if let network {
            self.network = network
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            self.network = URLSession(
                configuration: configuration,
                delegate: AcademicConnectorRedirectGuard(),
                delegateQueue: nil
            )
        }
    }

    func start(credential: SchoolVPNCredential, cookies: [String: String]) async throws -> AcademicConnectorLease {
        let payload = AcademicConnectorStartPayload(
            campus: "bjfu", portal: "undergraduate", vpnAccount: credential.account,
            vpnPassword: credential.password, cookies: cookies
        )
        let bytes = try await send(
            path: "v1/academic/operations",
            method: "POST",
            body: JSONEncoder().encode(payload),
            token: nil
        )
        guard let decoded = try? JSONDecoder().decode(AcademicConnectorStartedPayload.self, from: bytes),
              let id = UUID(uuidString: decoded.operationID),
              decoded.operationToken.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              (1 ... 300).contains(decoded.idleTimeoutSeconds)
        else { throw AcademicConnectorFailure.invalidResponse }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let expires = format.date(from: decoded.expiresAt) else { throw AcademicConnectorFailure.invalidResponse }
        return AcademicConnectorLease(id: id, token: decoded.operationToken, expiresAt: expires)
    }

    func execute(_ request: AcademicSchoolRequest,
                 lease: AcademicConnectorLease) async throws -> AcademicSchoolResponse {
        let bytes = try await send(
            path: "v1/academic/operations/\(lease.id.uuidString.lowercased())/requests", method: "POST",
            body: JSONEncoder().encode(request), token: lease.token
        )
        guard let decoded = try? JSONDecoder().decode(AcademicConnectorResponsePayload.self, from: bytes),
              let rawURL = URL(string: decoded.url), let url = AcademicSchoolURL.original(rawURL),
              url == rawURL, (100 ... 599).contains(decoded.status),
              let data = Data(base64Encoded: decoded.bodyBase64), data.count <= 2 * 1024 * 1024,
              decoded.cookies.count <= 64, !decoded.cookies.keys.contains(where: { $0.lowercased() == "twfid" }),
              decoded.contentType.count <= 256
        else { throw AcademicConnectorFailure.invalidResponse }
        return AcademicSchoolResponse(
            data: data, url: url, status: decoded.status, contentType: decoded.contentType, cookies: decoded.cookies
        )
    }

    func close(_ lease: AcademicConnectorLease) async -> AcademicConnectorCloseResult {
        // Cancellation of a view task must not cancel the cleanup request itself.
        await Task.detached { [self] () async -> AcademicConnectorCloseResult in
            do {
                _ = try await send(
                    path: "v1/academic/operations/\(lease.id.uuidString.lowercased())",
                    method: "DELETE",
                    body: nil,
                    token: lease.token
                )
                return .confirmed
            } catch let error as AcademicConnectorFailure where error.status == 404 || error.status == 410 {
                return .alreadyReleased
            } catch {
                return .unconfirmed("本次 VPN 退出未确认，连接会在超时后结束。")
            }
        }.value
    }

    private func send(path: String, method: String, body: Data?, token: String?) async throws -> Data {
        guard injectedNetwork || !AppRuntimeEnvironment.isRunningUnitTests else {
            throw AcademicConnectorFailure(
                status: 0,
                code: "test_network_prohibited",
                message: "单测必须注入隔离的教务连接器。",
                requestID: nil
            )
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if method == "DELETE" { request.timeoutInterval = 8 }
        let bytes: Data
        let response: URLResponse
        do { (bytes, response) = try await network.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw AcademicConnectorFailure(
                status: 0,
                code: "academic_service_unavailable",
                message: "暂时无法连接 MyLeafy 教务服务，请重试或改用校园网直连。",
                requestID: nil
            )
        }
        guard let http = response as? HTTPURLResponse, bytes.count <= 4 * 1024 * 1024 else {
            throw AcademicConnectorFailure.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(AcademicConnectorErrorPayload.self, from: bytes)
            guard let failure = decoded?.errorEnvelope, failure.code.count <= 80, failure.message.count <= 1024 else {
                throw AcademicConnectorFailure.invalidResponse
            }
            throw AcademicConnectorFailure(
                status: http.statusCode,
                code: failure.code,
                message: failure.message,
                requestID: decoded?.request_id
            )
        }
        return bytes
    }
}

nonisolated private struct AcademicConnectorStartPayload: Encodable {
    let campus: String
    let portal: String
    let vpnAccount: String
    let vpnPassword: String
    let cookies: [String: String]
}

nonisolated private struct AcademicConnectorStartedPayload: Decodable {
    let operationID: String
    let operationToken: String
    let expiresAt: String
    let idleTimeoutSeconds: Int
}

nonisolated private struct AcademicConnectorResponsePayload: Decodable {
    let status: Int
    let url: String
    let contentType: String
    let bodyBase64: String
    let cookies: [String: String]
}

nonisolated private struct AcademicConnectorErrorPayload: Decodable {
    let errorEnvelope: Envelope
    let request_id: String?
    nonisolated struct Envelope: Decodable {
        let code: String
        let message: String
    }
}
