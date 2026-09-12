import Foundation
import XCTest
@testable import leafy

final class CloudflareBackendClientTests: XCTestCase {
    func testRejectsNonOriginAndInsecureURLs() throws {
        for value in ["http://api.example.com", "https://api.example.com/path", "https://user:pass@api.example.com", "https://api.example.com?token=secret"] {
            XCTAssertThrowsError(try MyLeafyBackendClient(baseURL: URL(string: value)!, storage: BackendMemorySessions()))
        }
    }

    func testSignedBearerSessionIsSavedAndUsedInsteadOfJSONToken() async throws {
        let store = BackendMemorySessions()
        let userID = UUID()
        let network = backendNetwork { request in
            if request.url?.path == "/v1/auth/sign-in/anonymous" {
                return (200, ["set-auth-token":"signed-token"], Data("{\"token\":\"unsigned-token\",\"user\":{\"id\":\"\(userID)\",\"isAnonymous\":true}}".utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer signed-token")
            return (200, [:], Data("{\"ok\":true}".utf8))
        }
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: network, storage: store)
        try await client.establishSession()
        let reply: BackendReply = try await client.get("/v1/profile")
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(try store.load()?.token, "signed-token")
        XCTAssertEqual(try store.load()?.userID, userID)
    }

    func testMissingSignedTokenDoesNotPersistUnsignedSession() async throws {
        let store = BackendMemorySessions()
        let network = backendNetwork { _ in (200, [:], Data("{\"token\":\"unsigned\",\"user\":{\"id\":\"\(UUID())\"}}".utf8)) }
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: network, storage: store)
        do { try await client.establishSession(); XCTFail("Unsigned session accepted") }
        catch let error as MyLeafyBackendError { XCTAssertEqual(error.code, "missing_signed_session") }
        XCTAssertNil(try store.load())
    }

    func testPublicRuntimeRequestDoesNotCreateSession() async throws {
        let store = BackendMemorySessions()
        let network = backendNetwork { request in
            XCTAssertEqual(request.url?.path, "/v1/runtime/semester")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, [:], Data("{\"ok\":true}".utf8))
        }
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: network, storage: store)
        let _: BackendReply = try await client.get("/v1/runtime/semester", authenticated: false)
        XCTAssertNil(try store.load())
    }

    func testAPIErrorPreservesEnvelopeAndRequestID() async throws {
        let store = BackendMemorySessions(session: MyLeafyBackendSession(token: "signed", userID: UUID(), isAnonymous: true))
        let network = backendNetwork { _ in (503, ["X-Request-ID":"request-123"], Data("{\"errorEnvelope\":{\"code\":\"maintenance\",\"message\":\"Read only\"}}".utf8)) }
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: network, storage: store)
        do { let _: BackendReply = try await client.get("/v1/profile"); XCTFail("Error was swallowed") }
        catch let error as MyLeafyBackendError {
            XCTAssertEqual(error.status, 503); XCTAssertEqual(error.code, "maintenance"); XCTAssertEqual(error.requestID, "request-123")
        }
        XCTAssertNotNil(try store.load())
    }

    func testUnauthorizedResponseClearsOnlyRejectedSession() async throws {
        let store = BackendMemorySessions(session: MyLeafyBackendSession(token: "expired", userID: UUID(), isAnonymous: true))
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: backendNetwork { _ in (401, [:], Data("{\"code\":\"unauthenticated\",\"message\":\"Sign in\"}".utf8)) }, storage: store)
        do { let _: BackendReply = try await client.get("/v1/profile"); XCTFail("Expired session accepted") }
        catch let error as MyLeafyBackendError { XCTAssertEqual(error.status, 401) }
        XCTAssertNil(try store.load())
    }

    func testConcurrentSessionEstablishmentCreatesOneIdentity() async throws {
        let counter = BackendRequestCounter()
        let store = BackendMemorySessions()
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: backendNetwork { _ in
            counter.increment()
            return (200, ["set-auth-token":"signed"], Data("{\"user\":{\"id\":\"\(UUID())\",\"isAnonymous\":true}}".utf8))
        }, storage: store)
        async let first: Void = client.establishSession()
        async let second: Void = client.establishSession()
        _ = try await (first, second)
        XCTAssertEqual(counter.value, 1)
    }

    func testAuthenticatedReadWithoutSessionDoesNotContactNetwork() async throws {
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, network: backendNetwork { _ in
            XCTFail("A sessionless client contacted the server")
            return (200, [:], Data())
        }, storage: BackendMemorySessions())
        do { let _: BackendReply = try await client.get("/v1/profile"); XCTFail("Sessionless read accepted") }
        catch let error as MyLeafyBackendError { XCTAssertEqual(error.status, 401) }
    }

    func testUploadRequestUsesServerContractWithoutLegacyStoragePath() async throws {
        let store = BackendMemorySessions(session: MyLeafyBackendSession(token: "signed", userID: UUID(), isAnonymous: true))
        let client = try MyLeafyBackendClient(baseURL: URL(string: "https://api.example.com")!, storage: store)
        let id = UUID(), post = UUID()
        let request = try await client.uploadRequest(kind: "attachment", uploadID: id, postID: post, name: "课程 笔记.md", contentType: "text/markdown")
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/v1/files/upload")
        XCTAssertEqual(components.queryItems?.first { $0.name == "upload_id" }?.value, id.uuidString.lowercased())
        XCTAssertEqual(components.queryItems?.first { $0.name == "name" }?.value, "课程 笔记.md")
        XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
    }
}

private nonisolated struct BackendReply: Decodable, Sendable { let ok: Bool }
private nonisolated final class BackendMemorySessions: MyLeafyBackendSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MyLeafyBackendSession?
    init(session: MyLeafyBackendSession? = nil) { self.session = session }
    func load() throws -> MyLeafyBackendSession? { lock.lock(); defer { lock.unlock() }; return session }
    func save(_ session: MyLeafyBackendSession) throws { lock.lock(); defer { lock.unlock() }; self.session = session }
    func remove() throws { lock.lock(); defer { lock.unlock() }; session = nil }
}
private nonisolated final class BackendMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String:String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
private nonisolated func backendNetwork(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, [String:String], Data)) -> URLSession {
    BackendMockProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BackendMockProtocol.self]
    return URLSession(configuration: config)
}

private nonisolated final class BackendRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}
