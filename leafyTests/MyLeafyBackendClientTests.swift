import Foundation
import XCTest
@testable import leafy

@MainActor
final class MyLeafyBackendClientTests: XCTestCase {
    func testRejectsNonHTTPSOrigin() {
        XCTAssertThrowsError(try MyLeafyBackendClient(baseURL: URL(string: "http://api.test.invalid")!, storage: BackendTestSessionStore()))
    }

    func testSignedSessionHeaderIsPersistedAndUsedForRequests() async throws {
        let (client, store) = try fixture()
        try await client.anonymousSession()
        let result: BackendEcho = try await client.get("/v1/echo")
        XCTAssertEqual(result.authorization, "Bearer signed-session.test")
        XCTAssertEqual(try store.load()?.token, "signed-session.test")
        try await client.signOut(localOnly: true)
        XCTAssertNil(try store.load())
    }

    func testMaintenanceErrorPreservesSessionAndRequestID() async throws {
        let (client, store) = try fixture()
        try await client.anonymousSession()
        do {
            let _: BackendEcho = try await client.get("/v1/maintenance")
            XCTFail("Expected maintenance rejection")
        } catch let error as MyLeafyBackendError {
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.code, "maintenance")
            XCTAssertEqual(error.requestID, "request-for-test")
        }
        XCTAssertNotNil(try store.load())
    }

    private func fixture() throws -> (MyLeafyBackendClient, BackendTestSessionStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        let store = BackendTestSessionStore()
        return (try MyLeafyBackendClient(baseURL: URL(string: "https://api.test.invalid")!, network: URLSession(configuration: configuration), storage: store), store)
    }
}

private nonisolated struct BackendEcho: Decodable, Sendable { let authorization: String }

private nonisolated final class BackendTestSessionStore: MyLeafyBackendSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MyLeafyBackendSession?
    func load() throws -> MyLeafyBackendSession? { lock.lock(); defer { lock.unlock() }; return session }
    func save(_ session: MyLeafyBackendSession) throws { lock.lock(); defer { lock.unlock() }; self.session = session }
    func remove() throws { lock.lock(); defer { lock.unlock() }; session = nil }
}

private nonisolated final class BackendTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status: Int
        var headers = ["Content-Type": "application/json"]
        let payload: [String: Any]
        switch request.url!.path {
        case "/v1/auth/sign-in/anonymous":
            status = 200
            headers["set-auth-token"] = "signed-session.test"
            payload = ["token": "unsigned-token-must-not-be-used", "user": ["id": "BA74D3B9-C806-4FCA-8BFC-1E5B60DD8D10", "isAnonymous": true]]
        case "/v1/maintenance":
            status = 503
            headers["X-Request-ID"] = "request-for-test"
            payload = ["errorEnvelope": ["code": "maintenance", "message": "服务维护中，请稍后重试。", "retryable": true]]
        default:
            status = 200
            payload = ["authorization": request.value(forHTTPHeaderField: "Authorization") ?? ""]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
