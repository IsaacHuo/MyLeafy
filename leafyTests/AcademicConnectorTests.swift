import Foundation
import XCTest
@testable import Leafy

@MainActor
final class AcademicConnectorTests: XCTestCase {
    func testRestoresOnlyKnownSchoolGatewayURLs() throws {
        XCTAssertEqual(
            AcademicSchoolURL
                .original(
                    URL(
                        string: "https://vpn1.bjfu.edu.cn/web/1/http/0/newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do?xnxq01id=2026-2027-1"
                    )!
                )?
                .absoluteString,
            "http://newjwxt.bjfu.edu.cn/jsxsd/xskb/xskb_list.do?xnxq01id=2026-2027-1"
        )
        XCTAssertEqual(
            AcademicSchoolURL
                .original(
                    URL(string: "http://newjwxt.bjfu.edu.cn/web/1/http/0/newjwxt.bjfu.edu.cn/Logon.do?method=logon")!
                )?
                .path,
            "/Logon.do"
        )
        XCTAssertNil(AcademicSchoolURL.original(URL(string: "https://example.test/web/1/http/0/newjwxt.bjfu.edu.cn/")!))
        XCTAssertNil(AcademicSchoolURL.original(URL(string: "http://newjwxt.bjfu.edu.cn:8080/")!))
        XCTAssertNil(AcademicSchoolURL.original(URL(string: "https://vpn1.bjfu.edu.cn/por/logout.csp")!))
    }

    func testNativeTransportUsesOperationTokenWithoutCommunitySession() async throws {
        let client = try fixture()
        let lease = try await client.start(
            credential: SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            cookies: [:]
        )
        let request = try AcademicSchoolRequest(
            request: URLRequest(url: URL(string: "http://newjwxt.bjfu.edu.cn/verifycode.servlet")!),
            cookies: [:]
        )
        let response = try await client.execute(request, lease: lease)
        XCTAssertEqual(response.data, Data([0xff, 0xd8, 0xff]))
        XCTAssertEqual(response.url.host, "newjwxt.bjfu.edu.cn")
        XCTAssertEqual(response.cookies, ["JSESSIONID": "synthetic-cookie"])
        let closed = await client.close(lease)
        XCTAssertEqual(closed, .confirmed)
    }

    func testRejectsUntrustedOriginsAndKeepsFailureCodes() async throws {
        XCTAssertThrowsError(try AcademicConnectorClient(baseURL: URL(string: "http://api.test.invalid")!))
        let client = try fixture(host: "academic-reject.test.invalid")
        do {
            _ = try await client.start(
                credential: SchoolVPNCredential(account: "synthetic", password: "synthetic"),
                cookies: [:]
            )
            XCTFail("Expected VPN rejection")
        } catch let error as AcademicConnectorFailure {
            XCTAssertEqual(error.code, "vpn_authentication_rejected")
            XCTAssertEqual(error.status, 401)
            XCTAssertEqual(error.requestID, "synthetic-request")
        }
    }

    func testExpiredOperationCleanupDoesNotRequireTheOldTokenToRemainUsable() async throws {
        let client = try fixture(host: "academic-expired.test.invalid")
        let lease = AcademicConnectorLease(
            id: UUID(),
            token: String(repeating: "a", count: 43),
            expiresAt: .distantPast
        )
        let closed = await client.close(lease)
        XCTAssertEqual(closed, .alreadyReleased)
    }

    func testUnsavedCredentialsAreConsumedWithoutSwitchingBackToDirect() throws {
        let (settings, vault, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("student-a")
        try settings.configure(
            SchoolVPNCredential(account: "vpn-a", password: "synthetic"),
            remember: false,
            identity: identity
        )
        XCTAssertTrue(settings.isEnabled(for: identity))
        XCTAssertNil(try vault.load(owner: identity.scopeKey))
        XCTAssertNotNil(try settings.credential(for: identity))
        settings.finishUse(for: identity)
        XCTAssertNil(try settings.credential(for: identity))
        XCTAssertTrue(settings.isEnabled(for: identity))
        XCTAssertFalse(settings.isEnabled(for: owner("student-b")))
    }

    func testFirstLoginCredentialsAreSavedOnlyAfterBindingToVerifiedIdentity() throws {
        let (settings, vault, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        try settings.configure(
            SchoolVPNCredential(account: "vpn-a", password: "synthetic"),
            remember: true,
            identity: nil
        )
        XCTAssertEqual(vault.count, 0)
        XCTAssertFalse(try settings.isSaved(for: nil))
        let identity = owner("student-a")
        try settings.bindPendingLogin(to: identity)
        XCTAssertEqual(vault.count, 1)
        XCTAssertNotNil(try vault.load(owner: identity.scopeKey))
        XCTAssertNil(try settings.credential(for: owner("student-b")))
        settings.finishUse(for: identity)
        XCTAssertTrue(try settings.isSaved(for: identity))
    }

    func testFailedFirstActionDoesNotSilentlyChangeVPNChoiceToDirect() throws {
        let (settings, _, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        try settings.configure(
            SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            remember: false,
            identity: nil
        )
        settings.finishUse(for: nil)
        XCTAssertNil(try settings.credential(for: nil))
        XCTAssertTrue(settings.isEnabled(for: nil))
        let identity = owner("synthetic-first-fallback")
        try settings.bindPendingLogin(to: identity)
        XCTAssertTrue(settings.isEnabled(for: identity))
        XCTAssertNil(try settings.credential(for: identity))
        XCTAssertFalse(settings.isEnabled(for: nil))
    }

    func testStorageFailurePreservesEnabledPreferenceAndReportsFailure() throws {
        let (settings, vault, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("student-a")
        try settings.configure(
            SchoolVPNCredential(account: "vpn-a", password: "synthetic"),
            remember: true,
            identity: identity
        )
        vault.shouldFail = true
        XCTAssertThrowsError(try settings.credential(for: identity))
        XCTAssertThrowsError(try settings.remove(for: identity))
        XCTAssertTrue(settings.isEnabled(for: identity))
    }

    func testFailedFirstLoginSaveKeepsVPNSelectedInsteadOfSilentlyChoosingDirect() throws {
        let (settings, vault, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        try settings.configure(
            SchoolVPNCredential(account: "vpn-a", password: "synthetic"),
            remember: true,
            identity: nil
        )
        vault.shouldFail = true
        let identity = owner("student-a")
        XCTAssertThrowsError(try settings.bindPendingLogin(to: identity))
        XCTAssertTrue(settings.isEnabled(for: identity))
        settings.finishUse(for: nil)
    }

    private func fixture(host: String = "academic.test.invalid") throws -> AcademicConnectorClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcademicTestURLProtocol.self]
        return try AcademicConnectorClient(
            baseURL: URL(string: "https://\(host)")!,
            network: URLSession(configuration: configuration)
        )
    }

    func testOneActionReusesVPNThroughReauthenticationThenReleasesIt() async throws {
        let (settings, _, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("synthetic-recovery")
        try settings.configure(
            SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            remember: false,
            identity: identity
        )
        let api = AcademicLifecycleFixture()
        let connection = SchoolAcademicConnection(
            settings: settings,
            credentialOwner: identity,
            client: { api },
            identity: { identity }
        )
        do {
            try await connection.perform(kind: .timetable) { throw SchoolNetworkError.sessionExpired }
            XCTFail("Expected session expiry")
        } catch SchoolNetworkError.sessionExpired {}
        XCTAssertTrue(connection.isConnected)
        try connection.prepareRecovery(.timetable)
        try await connection.perform(kind: nil, retainingForLogin: true) {}
        try await connection.perform(kind: nil) {}
        XCTAssertNotNil(try settings.credential(for: identity))
        try await connection.perform(kind: .timetable) {}
        let counts = await api.counts()
        XCTAssertEqual(counts.starts, 1)
        XCTAssertEqual(counts.closes, 1)
        XCTAssertFalse(connection.isConnected)
        XCTAssertNil(try settings.credential(for: identity))
        XCTAssertTrue(settings.isEnabled(for: identity))
    }

    func testFailedActionReleasesVPNAndSurfacesUnconfirmedLogout() async throws {
        let (settings, _, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("synthetic-failure")
        try settings.configure(
            SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            remember: true,
            identity: identity
        )
        let api = AcademicLifecycleFixture(closeResult: .unconfirmed("合成退出未确认"))
        let connection = SchoolAcademicConnection(
            settings: settings,
            credentialOwner: identity,
            client: { api },
            identity: { identity }
        )
        do {
            try await connection.perform(kind: .timetable) { throw URLError(.badServerResponse) }
            XCTFail("Expected failure")
        } catch {}
        let counts = await api.counts()
        XCTAssertEqual(counts.closes, 1)
        XCTAssertEqual(connection.cleanupWarning, "合成退出未确认")
        XCTAssertFalse(connection.isConnected)
    }

    func testCancellationReleasesLeaseThatArrivesAfterCancellation() async throws {
        let (settings, _, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("synthetic-cancel")
        try settings.configure(
            SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            remember: true,
            identity: identity
        )
        let api = AcademicLifecycleFixture(paused: true)
        let connection = SchoolAcademicConnection(
            settings: settings,
            credentialOwner: identity,
            client: { api },
            identity: { identity }
        )
        let task = Task {
            try await connection.perform(kind: .timetable) { XCTFail("Cancelled action must not query school") } }
        await api.waitForStart()
        connection.cancel()
        task.cancel()
        await api.resumeStart()
        _ = await task.result
        await connection.finish()
        let counts = await api.counts()
        XCTAssertEqual(counts.starts, 1)
        XCTAssertEqual(counts.closes, 1)
        XCTAssertFalse(connection.isConnected)
    }

    func testVPNTimetableValidatesExistingSchoolSessionBeforeRequestingLogin() async throws {
        let (settings, _, defaults, suite) = fixtureSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = owner("synthetic-session")
        try settings.configure(
            SchoolVPNCredential(account: "synthetic", password: "synthetic"),
            remember: true,
            identity: identity
        )
        let api = AcademicLifecycleFixture(schoolPages: true)
        let connection = SchoolAcademicConnection(settings: settings, credentialOwner: identity, client: { api })
        let manager = SchoolNetworkManager(connectionMode: .serverVPN, academicConnection: connection)
        connection.manager = manager
        let flagKey = CampusScopedDefaults.key("serverVPN.isLoggedIn")
        let oldFlag = UserDefaults.standard.object(forKey: flagKey)
        let landingKey = CampusScopedDefaults.key("serverVPN.lastLandingURL")
        let oldLanding = UserDefaults.standard.object(forKey: landingKey)
        defer {
            UserDefaults.standard.set(oldFlag, forKey: flagKey)
            UserDefaults.standard.set(oldLanding, forKey: landingKey)
        }
        manager.isLoggedIn = false
        manager.persistedCookieValues = ["JSESSIONID": "synthetic-existing-session"]
        XCTAssertNil(SchoolReauthentication.preflightRequest(
            networkManager: manager,
            context: .timetable(portal: .undergraduate)
        ))
        let document = try await manager.fetchTimetable()
        XCTAssertTrue(document.html.contains("kbtable"))
        let requests = await api.requestPaths()
        XCTAssertEqual(requests, ["/jsxsd/framework/xsMain.jsp", "/jsxsd/xskb/xskb_list.do"])
        let counts = await api.counts()
        XCTAssertEqual(counts.starts, 1)
        XCTAssertEqual(counts.closes, 1)
        XCTAssertTrue(manager.isLoggedIn)
    }

    private func owner(_ account: String) -> CampusIdentity {
        CampusIdentity(campusID: .bjfu, eduID: account, displayName: "合成学生", portal: .undergraduate)
    }

    private func fixtureSettings() -> (SchoolVPNSettingsStore, AcademicTestVPNVault, UserDefaults, String) {
        let suite = "academic-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let vault = AcademicTestVPNVault()
        return (SchoolVPNSettingsStore(defaults: defaults, vault: vault), vault, defaults, suite)
    }
}

private actor AcademicLifecycleFixture: AcademicConnectorServicing {
    private var starts = 0
    private var closes = 0
    private let paused: Bool
    private let schoolPages: Bool
    private var paths: [String] = []
    private let closeResult: AcademicConnectorCloseResult
    private var pendingStart: CheckedContinuation<Void, Never>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(paused: Bool = false, closeResult: AcademicConnectorCloseResult = .confirmed, schoolPages: Bool = false) {
        self.paused = paused
        self.closeResult = closeResult
        self.schoolPages = schoolPages
    }
    func start(credential: SchoolVPNCredential, cookies: [String: String]) async throws -> AcademicConnectorLease {
        starts += 1
        if paused {
            await withCheckedContinuation {
                pendingStart = $0; for waiter in waiting { waiter.resume() }; waiting.removeAll() }
        }
        return AcademicConnectorLease(
            id: UUID(),
            token: String(repeating: "a", count: 43),
            expiresAt: Date().addingTimeInterval(300)
        )
    }
    func execute(_ request: AcademicSchoolRequest,
                 lease: AcademicConnectorLease) async throws -> AcademicSchoolResponse {
        guard schoolPages else { throw URLError(.unsupportedURL) }
        paths.append(request.path)
        let page = request.path.contains("xsMain.jsp") ? "<html>退出系统</html>" : "<table id=\"kbtable\"></table>"
        return AcademicSchoolResponse(
            data: Data(page.utf8),
            url: URL(string: "http://newjwxt.bjfu.edu.cn\(request.path)")!,
            status: 200,
            contentType: "text/html",
            cookies: request.cookies
        )
    }
    func close(_ lease: AcademicConnectorLease) async -> AcademicConnectorCloseResult { closes += 1; return closeResult
    }
    func counts() -> (starts: Int, closes: Int) { (starts, closes) }
    func requestPaths() -> [String] { paths }
    func waitForStart() async { if pendingStart != nil { return }; await withCheckedContinuation { waiting.append($0) }
    }
    func resumeStart() { pendingStart?.resume(); pendingStart = nil }
}

private nonisolated final class AcademicTestVPNVault: SchoolVPNVault, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: SchoolVPNCredential] = [:]
    private var failure = false
    var shouldFail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failure }
        set { lock.lock(); defer { lock.unlock() }; failure = newValue }
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return records.count }
    func load(owner: String) throws -> SchoolVPNCredential? {
        lock.lock(); defer { lock.unlock() }
        if failure { throw SchoolVPNStorageFailure.keychain(-1) }
        return records[owner]
    }
    func save(_ credential: SchoolVPNCredential, owner: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failure { throw SchoolVPNStorageFailure.keychain(-1) }
        records[owner] = credential
    }
    func remove(owner: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failure { throw SchoolVPNStorageFailure.keychain(-1) }
        records.removeValue(forKey: owner)
    }
}

private nonisolated final class AcademicTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?
        .hasSuffix("test.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = String(repeating: "a", count: 43)
        let status: Int
        let payload: [String: Any]
        if request.url!.host == "academic-reject.test.invalid" || request.url!.host == "academic-expired.test.invalid" {
            status = request.url!.host == "academic-reject.test.invalid" ? 401 : 410
            payload = [
                "errorEnvelope": ["code": "vpn_authentication_rejected", "message": "合成错误", "retryable": false],
                "request_id": "synthetic-request"
            ]
        } else if request.httpMethod == "DELETE" {
            status = 204
            payload = [:]
        } else if request.url!.path.hasSuffix("/requests") {
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" else {
                client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
            }
            status = 200
            payload = [
                "status": 200,
                "url": "http://newjwxt.bjfu.edu.cn/verifycode.servlet",
                "contentType": "image/jpeg",
                "bodyBase64": Data([0xff, 0xd8, 0xff]).base64EncodedString(),
                "cookies": ["JSESSIONID": "synthetic-cookie"]
            ]
        } else {
            guard request.value(forHTTPHeaderField: "Authorization") == nil else {
                client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
            }
            status = 201
            payload = ["operationID": "7ED49EB9-0761-4192-8805-86DB2173679C", "operationToken": token,
                       "expiresAt": "2026-11-10T00:05:00.000Z", "idleTimeoutSeconds": 120]
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status != 204 { client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
