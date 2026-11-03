import XCTest
import UIKit
@testable import Leafy

@MainActor
final class SchoolLoginReliabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewDemoMode.disable()
        ActiveCampusContext.networkManager.clearSession()
    }

    override func tearDown() {
        ActiveCampusContext.networkManager.clearSession()
        try? SchoolLoginCredentialStore.deleteAll()
        super.tearDown()
    }

    func testSharedLoginMessageFixtures() throws {
        let cases = try JSONSerialization.jsonObject(with: fixture("login_messages.json")) as! [[String: Any]]
        for item in cases {
            XCTAssertEqual(
                SchoolNetworkManager.shared.extractLoginMessage(from: item["html"] as! String),
                item["expected"] as? String,
                item["name"] as! String
            )
        }
    }

    func testSchoolJavaScriptEncodingAndFormRoundtrip() throws {
        let input = try JSONSerialization.jsonObject(with: fixture("login_encoding.json")) as! [String: Any]
        let key = input["key"] as! String
        let cases = input["cases"] as! [[String: String]]
        XCTAssertEqual(cases.count, 1235)
        let manager = SchoolNetworkManager.shared
        for item in cases {
            let encoded = try manager.encodeKey(key: key, account: item["account"]!, password: item["password"]!)
            XCTAssertEqual(Array(encoded.utf16), Array(item["encoded"]!.utf16))
            let body = manager.formURLEncodedBody(queryItems: [URLQueryItem(name: "encoded", value: encoded)])
            XCTAssertEqual(formValues(body)["encoded"], encoded)
        }
    }

    func testDefaultSchoolTransportStillProhibitsLiveRequests() async {
        let manager = SchoolNetworkManager()
        do {
            _ = try await manager.data(for: URLRequest(url: URL(string: manager.baseURL)!))
            XCTFail("Default transport must not contact the real school in tests")
        } catch { XCTAssertEqual((error as? URLError)?.code, .unsupportedURL) }
    }

    func testInvalidKeysNeverSubmitLogin() async throws {
        for key in ["no", "", "<html>error</html>", "ABC#", "#123", "ABC#12x", "ABC#１２３", "ABC#1#2"] {
            let stub = SchoolLoginStub()
            stub.key = key
            let manager = makeManager(stub)
            do {
                _ = try await login(manager)
                XCTFail("Invalid challenge must stop before login")
            } catch { XCTAssertNotNil(error as? SchoolNetworkError) }
            XCTAssertEqual(stub.requests.count, 1)
            XCTAssertFalse(manager.isLoggedIn)
        }
    }

    func testNonSuccessKeyHTTPStatusNeverSubmitsLogin() async throws {
        let stub = SchoolLoginStub()
        stub.keyStatus = 503
        let manager = makeManager(stub)
        do { _ = try await login(manager); XCTFail("HTTP failure must stop login") } catch {}
        XCTAssertEqual(stub.requests.count, 1)
        XCTAssertFalse(manager.isLoggedIn)
    }

    func testAnnouncementDoesNotBlockVerifiedSessionAndPasswordIsPreserved() async throws {
        let stub = SchoolLoginStub()
        stub.loginHTML = try messageFixture("announcement")
        let manager = makeManager(stub)
        let challenge = try await manager.fetchCaptcha(for: .undergraduate)
        let succeeded = try await manager.performLogin(
            account: "2099000001",
            password: " Ab9+%&#=Z7 ",
            captcha: "a1b2",
            key: challenge.key
        )
        XCTAssertTrue(succeeded)
        XCTAssertTrue(manager.isLoggedIn)
        XCTAssertEqual(manager.authenticatedEduID, "2099000001")
        XCTAssertEqual(
            stub.requests.map { $0.url!.path },
            ["/Logon.do", "/verifycode.servlet", "/Logon.do", "/Logon.do", "/jsxsd/framework/xsMain.jsp"]
        )
        let post = try XCTUnwrap(stub.requests.first { $0.url?.query == "method=logon" })
        let fields = formValues(try XCTUnwrap(post.httpBody))
        XCTAssertEqual(
            fields["encoded"],
            try manager.encodeKey(key: stub.key, account: "2099000001", password: " Ab9+%&#=Z7 ")
        )
        XCTAssertEqual(fields["RANDOMCODE"], "a1b2")
        XCTAssertTrue(stub.requests.dropFirst()
            .allSatisfy { $0.value(forHTTPHeaderField: "Cookie")?.contains("JSESSIONID=login-test") == true })
        XCTAssertEqual(
            SchoolLoginCredentialStore.load(campusID: .bjfu, portal: .undergraduate)?.password,
            " Ab9+%&#=Z7 "
        )
    }

    func testActualErrorsRemainFailuresEvenIfVerificationWouldSucceed() async throws {
        for name in ["credentials", "captcha_after_validation", "locked"] {
            let stub = SchoolLoginStub()
            stub.loginHTML = try messageFixture(name)
            let manager = makeManager(stub)
            do { _ = try await login(manager); XCTFail("Real rejection cannot be overridden") }
            catch { XCTAssertTrue(error is SchoolNetworkError) }
            XCTAssertFalse(manager.isLoggedIn)
            XCTAssertFalse(stub.requests.contains { $0.url?.path.contains("xsMain.jsp") == true })
            XCTAssertNil(SchoolLoginCredentialStore.load(campusID: .bjfu, portal: .undergraduate))
        }
    }

    func testNoticeAndUnknownVerificationPageCannotEstablishIdentity() async throws {
        let stub = SchoolLoginStub()
        stub.loginHTML = try messageFixture("announcement")
        stub.verificationHTML = "<html>学校维护中</html>"
        let manager = makeManager(stub)
        do { _ = try await login(manager); XCTFail("Unknown page is not authentication evidence") } catch {}
        XCTAssertFalse(manager.isLoggedIn)
        XCTAssertNil(manager.authenticatedEduID)
    }

    func testEmptyLoginResponseCanSucceedOnlyWithVerifiedSession() async throws {
        let stub = SchoolLoginStub()
        stub.loginHTML = ""
        let manager = makeManager(stub)
        let succeeded = try await login(manager)
        XCTAssertTrue(succeeded)
        XCTAssertTrue(manager.isLoggedIn)
        XCTAssertEqual(stub.requests.filter { $0.url?.path.contains("xsMain.jsp") == true }.count, 1)
    }

    func testEmptyLoginAndHTTPFailureCannotEstablishIdentity() async throws {
        for status in [200, 503] {
            let stub = SchoolLoginStub()
            stub.loginHTML = ""
            stub.verificationHTML = "<html>学校维护中</html>"
            stub.loginStatus = status
            let manager = makeManager(stub)
            do { _ = try await login(manager); XCTFail("Invalid response cannot establish identity") } catch {}
            XCTAssertFalse(manager.isLoggedIn)
        }
    }

    func testVerificationNetworkFailureIsReportedWithoutResubmittingPassword() async throws {
        let stub = SchoolLoginStub()
        stub.verificationError = URLError(.timedOut)
        let manager = makeManager(stub)
        do { _ = try await login(manager); XCTFail("Verification failure must be visible") }
        catch { XCTAssertEqual(SchoolLoginFailureClassifier.classify(error), .networkUnavailable) }
        XCTAssertEqual(stub.requests.filter { $0.url?.query == "method=logon" }.count, 1)
        XCTAssertFalse(manager.isLoggedIn)
    }

    func testCaptchaAndLoginAreMutuallyExclusive() async throws {
        let stub = SchoolLoginStub()
        stub.holdsKey = true
        let manager = makeManager(stub)
        let captchaTask = Task { try await manager.fetchCaptcha(for: .undergraduate) }
        await stub.waitForHeldRequest()
        do { _ = try await login(manager); XCTFail("Login cannot race captcha") } catch {}
        XCTAssertEqual(stub.requests.count, 1)
        manager.cancelAuthenticationOperation()
        stub.resumeHeldRequest()
        do { _ = try await captchaTask.value; XCTFail("Old captcha must be cancelled") } catch {}
        XCTAssertTrue(manager.persistedCookieValues.isEmpty)
    }

    func testLoginBlocksRefreshAndRepeatedSubmission() async throws {
        let stub = SchoolLoginStub()
        stub.holdsKey = true
        let manager = makeManager(stub)
        let task = Task { try await login(manager) }
        await stub.waitForHeldRequest()
        do { _ = try await manager.fetchCaptcha(); XCTFail("Captcha cannot clear login cookies") } catch {}
        do { _ = try await login(manager); XCTFail("Duplicate login must be blocked") } catch {}
        XCTAssertEqual(stub.requests.count, 1)
        manager.cancelAuthenticationOperation()
        stub.resumeHeldRequest()
        do { _ = try await task.value; XCTFail("Cancelled login cannot succeed") } catch {}
        XCTAssertFalse(manager.isLoggedIn)
    }

    func testOldResponseAndCleanupCannotOverwriteReplacementAttempt() async throws {
        let stub = SchoolLoginStub()
        stub.holdsKey = true
        let manager = makeManager(stub)
        let oldTask = Task { try await login(manager) }
        await stub.waitForHeldRequest()
        manager.cancelAuthenticationOperation()
        // Returning to another portal and back also invalidates the old task.
        manager.currentPortal = .graduate
        manager.currentPortal = .undergraduate
        let replacement = Task { try await login(manager) }
        await stub.waitForHeldRequest(count: 2)
        let replacementID = manager.authenticationOperationID
        stub.resumeHeldRequest(index: 0)
        do { _ = try await oldTask.value; XCTFail("Old request must not complete") } catch {}
        XCTAssertEqual(manager.authenticationOperationID, replacementID)
        XCTAssertTrue(manager.persistedCookieValues.isEmpty)
        manager.cancelAuthenticationOperation()
        stub.resumeHeldRequest(index: 1)
        _ = try? await replacement.value
    }

    func testInvalidKeyIsTerminalRatherThanCaptchaRejection() {
        XCTAssertEqual(
            SchoolLoginFailureClassifier.classify(SchoolNetworkError.loginUnavailable("学校登录密钥无效，请刷新验证码后重试。")),
            .terminal("学校登录密钥无效，请刷新验证码后重试。")
        )
    }

    private func makeManager(_ stub: SchoolLoginStub) -> SchoolNetworkManager {
        let manager = SchoolNetworkManager(requestLoader: { try await stub.load($0) })
        manager.currentPortal = .undergraduate
        manager.isLoggedIn = false
        manager.authenticatedEduID = nil
        manager.persistedCookieValues = [:]
        return manager
    }

    private func login(_ manager: SchoolNetworkManager) async throws -> Bool {
        try await manager.performLogin(account: "2099000001", password: "Ab9+%&#=Z7", captcha: "a1b2", key: "unused")
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/jwxt/fixtures/" + name))
    }

    private func messageFixture(_ name: String) throws -> String {
        let items = try JSONSerialization.jsonObject(with: fixture("login_messages.json")) as! [[String: Any]]
        return try XCTUnwrap(items.first { $0["name"] as? String == name }?["html"] as? String)
    }

    private func formValues(_ data: Data) -> [String: String] {
        String(decoding: data, as: UTF8.self).split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            result[String(parts[0])] = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
    }
}

@MainActor
private final class SchoolLoginStub {
    var key = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#12345678901234567890"
    var keyStatus = 200
    var loginStatus = 200
    var loginHTML = "<html>退出系统</html>"
    var verificationHTML = "<html>学生课表 退出系统</html>"
    var verificationError: Error?
    var holdsKey = false
    var requests: [URLRequest] = []
    private var held: [CheckedContinuation<(Data, URLResponse), Error>?] = []

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = request.url!
        if url.query?.contains("flag=sess") == true {
            if holdsKey { return try await withCheckedThrowingContinuation { held.append($0) } }
            return response(request, data: Data(key.utf8), status: keyStatus)
        }
        if url.path == "/verifycode.servlet" {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            return response(request, data: image.pngData()!)
        }
        if url.query == "method=logon" { return response(request, data: Data(loginHTML.utf8), status: loginStatus) }
        if let verificationError { throw verificationError }
        return response(request, data: Data(verificationHTML.utf8))
    }

    func waitForHeldRequest(count: Int = 1) async {
        for _ in 0 ..< 1000 {
            if held.count >= count { return }
            await Task.yield()
        }
        XCTFail("Expected request to suspend")
    }

    func resumeHeldRequest(index: Int = 0) {
        guard held.indices.contains(index), let continuation = held[index] else { return }
        held[index] = nil
        let request = requests.filter { $0.url?.query?.contains("flag=sess") == true }[index]
        continuation.resume(returning: response(request, data: Data(key.utf8)))
    }

    private func response(_ request: URLRequest, data: Data, status: Int = 200) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                               headerFields: ["Set-Cookie": "JSESSIONID=login-test; Path=/"])!)
    }
}
