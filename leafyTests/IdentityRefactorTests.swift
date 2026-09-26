import XCTest
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import SwiftData
@testable import Leafy

extension PerformanceRefactorTests {
    func testSchoolReauthenticationRecognizesSessionFailuresOnly() {
        XCTAssertTrue(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.sessionExpired))
        XCTAssertTrue(SchoolReauthentication.requiresReauthentication(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.campusNetworkRequired))
        XCTAssertFalse(SchoolReauthentication.requiresReauthentication(SchoolNetworkError.featureUnavailable("未开放")))

        XCTAssertTrue(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.sessionExpired))
        XCTAssertFalse(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.campusNetworkRequired))
        XCTAssertFalse(SchoolReauthentication.shouldPromptForUserInitiatedAccess(SchoolNetworkError.featureUnavailable("未开放")))
    }

    @MainActor
    func testSchoolSessionPreflightUsesLocalStateWithoutNetworkRequest() {
        let manager = SchoolNetworkManager.shared
        manager.clearSession()

        let result = SchoolReauthentication.preflightRequest(
            networkManager: manager,
            context: .schoolDataSync
        )

        XCTAssertNil(result)
    }

    @MainActor
    func testGraduateLoginFormEncodingEscapesPlusInEncryptedPassword() throws {
        let payload = #"{"UserId":"123","Password":"a+b/c==","VeriCode":"0000","url":"","city":""}"#
        let body = SchoolNetworkManager.shared.formURLEncodedBody(queryItems: [
            URLQueryItem(name: "json", value: payload)
        ])
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("a%2Bb/c%3D%3D"))
        XCTAssertFalse(bodyString.contains("a+b/c"))
    }

    @MainActor
    func testGraduateLoginResponseAcceptsSuccessfulRedirect() throws {
        let redirect = try SchoolNetworkManager.shared.parseGraduateLoginRedirect(
            from: #"{"jg":"1","url":"student/default"}"#
        )

        XCTAssertEqual(redirect, "student/default")
    }

    @MainActor
    func testGraduateLoginResponseUsesServerFailureMessage() {
        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(
                from: #"{"jg":"0","msg":"验证码错误"}"#
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "验证码错误")
        }
    }

    @MainActor
    func testGraduateLoginResponseRejectsEmptyOrInvalidBodies() {
        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(from: "")
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("研究生系统登录响应无法解密"))
        }

        XCTAssertThrowsError(
            try SchoolNetworkManager.shared.parseGraduateLoginRedirect(from: "not json")
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("研究生系统登录响应格式异常"))
        }
    }

    func testCampusIdentityScopeKeySeparatesSchoolPortalAndCustomSupabase() {
        let undergraduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .undergraduate
        )
        let graduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .graduate
        )
        let custom = CampusIdentity(
            campusID: .custom,
            eduID: "00000000-0000-0000-0000-000000000001",
            displayName: "user@example.com",
            portal: .undergraduate,
            kind: .customSupabase
        )
        let guest = CampusIdentity(
            campusID: .guest,
            eduID: "local-guest",
            displayName: "本地用户",
            portal: .undergraduate,
            kind: .guest
        )

        XCTAssertNotEqual(undergraduate.scopeKey, graduate.scopeKey)
        XCTAssertNotEqual(undergraduate.scopeKey, custom.scopeKey)
        XCTAssertNotEqual(graduate.scopeKey, custom.scopeKey)
        XCTAssertNotEqual(custom.scopeKey, guest.scopeKey)
    }

    func testGuestIdentityIsCustomAndIsolated() {
        let guest = CampusIdentity(
            campusID: .guest,
            eduID: "local-guest",
            displayName: "本地用户",
            portal: .undergraduate,
            kind: .guest
        )

        XCTAssertEqual(guest.campusID, .guest)
        XCTAssertEqual(guest.kind, .guest)
        XCTAssertTrue(guest.isGuest)
        XCTAssertTrue(guest.isCustom)

        let custom = CampusIdentity(
            campusID: .custom,
            eduID: "00000000-0000-0000-0000-000000000001",
            displayName: "user@example.com",
            portal: .undergraduate,
            kind: .customSupabase
        )
        XCTAssertFalse(custom.isGuest)
        XCTAssertNotEqual(guest.scopeKey, custom.scopeKey)

        let guestDescriptor = CampusDescriptor.guest
        XCTAssertFalse(guestDescriptor.supports(.community))
        XCTAssertFalse(guestDescriptor.supports(.authentication))
        XCTAssertTrue(guestDescriptor.supports(.timetable))
        XCTAssertTrue(guestDescriptor.supports(.grades))
        XCTAssertTrue(guestDescriptor.supports(.exams))
    }

    func testCampusIdentityActivationOnlyNotifiesWhenScopeChanges() throws {
        let suiteName = "campus-identity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            CampusIdentityStore.clear(defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
        }

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .campusIdentityDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        let initial = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .undergraduate
        )
        CampusIdentityStore.activate(initial, defaults: defaults)
        XCTAssertEqual(notificationCount, 1)

        let renamed = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "新名字",
            portal: .undergraduate
        )
        CampusIdentityStore.activate(renamed, defaults: defaults)
        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(CampusIdentityStore.currentIdentity(defaults: defaults)?.displayName, "新名字")

        let graduate = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "新名字",
            portal: .graduate
        )
        CampusIdentityStore.activate(graduate, defaults: defaults)
        XCTAssertEqual(notificationCount, 2)

        let differentAccount = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260002",
            displayName: "另一位同学",
            portal: .graduate
        )
        CampusIdentityStore.activate(differentAccount, defaults: defaults)
        XCTAssertEqual(notificationCount, 3)
    }

    func testCampusIdentityStoreIgnoresPayloadWithoutCurrentScopeFields() throws {
        let suiteName = "campus-identity-current-format-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let obsoletePayload = try XCTUnwrap(
            #"{"campusID":"bjfu","eduID":"20260001","displayName":"同学"}"#.data(using: .utf8)
        )
        defaults.set(obsoletePayload, forKey: "leafy.activeCampusIdentity.v1")
        defaults.set(obsoletePayload, forKey: "leafy.activeCampusIdentity")

        XCTAssertNil(CampusIdentityStore.currentIdentity(defaults: defaults))
    }

    func testCampusStoreScopeUsesOnlyIdentityDirectory() throws {
        let identity = CampusIdentity(
            campusID: .bjfu,
            eduID: "20260001",
            displayName: "同学",
            portal: .undergraduate
        )
        let scopedURL = try XCTUnwrap(CampusStoreScope.scopedStoreURL(for: identity))

        XCTAssertTrue(scopedURL.path.contains("/CampusStores/\(identity.scopeKey)/"))
        XCTAssertEqual(scopedURL.lastPathComponent, "Leafy.store")
        XCTAssertNotEqual(
            scopedURL,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Leafy.store")
        )
    }

    func testCustomCampusAuthCallbackOnlyAcceptsAuthCallbackURL() {
        XCTAssertTrue(CustomCampusAuthCallback.isCallback(URL(string: "leafy://auth/callback?code=abc")!))
        XCTAssertFalse(CustomCampusAuthCallback.isCallback(URL(string: "leafy://community-post?id=00000000-0000-0000-0000-000000000001")!))
        XCTAssertFalse(CustomCampusAuthCallback.isCallback(URL(string: "https://myleafy.space/auth/callback?code=abc")!))
    }

    func testCustomCampusAuthSessionBuildsCustomCampusIdentity() {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let session = CustomCampusAuthSession(authUserID: userID, email: "user@example.com")
        let identity = session.campusIdentity

        XCTAssertEqual(identity.campusID, .custom)
        XCTAssertEqual(identity.eduID, userID.uuidString)
        XCTAssertEqual(identity.displayName, "user@example.com")
        XCTAssertEqual(identity.kind, .customSupabase)
        XCTAssertTrue(identity.isCustom)
    }

    func testCustomCampusAuthNormalizesEmailOTPCode() {
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting(" 123 456 "), "123456")
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting("12-34-56"), "123456")
        XCTAssertEqual(CustomCampusAuthService.normalizeCodeForTesting("12 34 56 78"), "12345678")
    }

    func testCustomCampusAuthMapsRecoverableBackendErrors() {
        let cases: [(String, CustomCampusAuthError)] = [
            ("INVALID_EMAIL_OR_PASSWORD", .invalidCredentials),
            ("EMAIL_NOT_VERIFIED", .emailNotConfirmed("user@example.com")),
            ("OTP_EXPIRED", .expiredCode),
            ("TOO_MANY_REQUESTS", .emailRateLimited),
            ("USER_ALREADY_EXISTS", .userAlreadyExists),
        ]
        for (code, expected) in cases {
            let error = MyLeafyBackendError(status: 400, code: code, message: "Server message", requestID: "test")
            XCTAssertEqual(CustomCampusAuthService.mapAuthErrorForTesting(error).localizedDescription, expected.localizedDescription)
        }
    }

    func testOldEmailCallbackRequiresFreshLogin() async {
        do {
            _ = try await CustomCampusAuthService().restoreSession(from: URL(string: "leafy://auth/callback?code=expired")!)
            XCTFail("Old sessions must not be exchanged")
        } catch {
            XCTAssertEqual(error.localizedDescription, CustomCampusAuthError.callbackLinkInvalid.localizedDescription)
        }
    }
}
