import XCTest
import UIKit
@testable import Leafy

final class SchoolAuthenticationRecoveryTests: XCTestCase {
    func testUndergraduateCaptchaPolicyNormalizesAndAcceptsReliableCode() {
        XCTAssertEqual(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(text: " a7\nk3 ", confidence: 0.96)
            ),
            "A7K3"
        )
    }

    func testUndergraduateCaptchaPolicyRejectsLowConfidenceAndInvalidFormats() {
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(text: "A7K3", confidence: 0.899)
            )
        )
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(text: "A?K3", confidence: 0.99)
            )
        )
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(text: "A7K", confidence: 0.99)
            )
        )
    }

    @MainActor
    func testReliableUndergraduateCaptchaAuthenticatesAutomaticallyOnce() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.96))
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)

        guard case .authenticated = result else {
            return XCTFail("Expected automatic authentication")
        }
        XCTAssertEqual(client.fetchCount, 1)
        XCTAssertEqual(client.loginCaptchas, ["A7K3"])
        XCTAssertEqual(recognizer.callCount, 1)
    }

    @MainActor
    func testLowConfidenceUsesSameChallengeWithoutSubmittingLogin() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.5))
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)

        guard case .requiresManual(let challenge, _) = result else {
            return XCTFail("Expected manual verification")
        }
        XCTAssertEqual(challenge.key, "key-1")
        XCTAssertEqual(client.fetchCount, 1)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
        XCTAssertEqual(recognizer.callCount, 1)
    }

    @MainActor
    func testMissingCredentialSkipsRecognitionAndUsesManualFallback() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.99))
        let service = makeService(client: client, recognizer: recognizer, credential: nil)

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)

        guard case .requiresManual = result else {
            return XCTFail("Expected manual verification")
        }
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
    }

    @MainActor
    func testGraduateRecoveryNeverRunsRecognition() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "1234", confidence: 0.99))
        let service = makeService(client: client, recognizer: recognizer, credential: credential(portal: .graduate))

        let result = try await service.recover(portal: .graduate, allowsAutomaticAttempt: true)

        guard case .requiresManual = result else {
            return XCTFail("Expected graduate manual verification")
        }
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
    }

    @MainActor
    func testConsumedAutomaticBudgetSkipsRecognition() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.99))
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: false)

        guard case .requiresManual = result else {
            return XCTFail("Expected manual verification")
        }
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
    }

    @MainActor
    func testRejectedAutomaticLoginFetchesFreshManualChallengeWithoutSecondRecognition() async throws {
        let client = FakeSchoolAuthenticationClient()
        client.loginResult = false
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.99))
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)

        guard case .requiresManual(let challenge, _) = result else {
            return XCTFail("Expected fresh manual verification")
        }
        XCTAssertEqual(challenge.key, "key-2")
        XCTAssertEqual(client.fetchCount, 2)
        XCTAssertEqual(client.loginCaptchas, ["A7K3"])
        XCTAssertEqual(recognizer.callCount, 1)
    }

    @MainActor
    func testNetworkFailureDoesNotAttemptRecognitionOrLogin() async {
        let client = FakeSchoolAuthenticationClient()
        client.fetchError = SchoolNetworkError.campusNetworkRequired
        let recognizer = FakeCaptchaRecognizer(result: CaptchaResult(text: "A7K3", confidence: 0.99))
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        do {
            _ = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)
            XCTFail("Expected network error")
        } catch {
            XCTAssertTrue(error is SchoolNetworkError)
        }
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
    }

    @MainActor
    private func makeService(
        client: FakeSchoolAuthenticationClient,
        recognizer: FakeCaptchaRecognizer,
        credential: SchoolLoginCredential?
    ) -> SchoolAuthenticationService {
        SchoolAuthenticationService(
            client: client,
            recognizer: recognizer,
            credentialProvider: FakeCredentialProvider(credential: credential)
        )
    }

    private func credential(portal: SchoolPortal = .undergraduate) -> SchoolLoginCredential {
        SchoolLoginCredential(
            campusID: .bjfu,
            portal: portal,
            account: "20260001",
            password: "secret",
            savedAt: Date()
        )
    }
}

private nonisolated struct FakeCredentialProvider: SchoolLoginCredentialProviding {
    let credential: SchoolLoginCredential?

    func load(campusID: CampusID, portal: SchoolPortal) -> SchoolLoginCredential? {
        guard credential?.campusID == campusID, credential?.portal == portal else { return nil }
        return credential
    }
}

private nonisolated final class FakeCaptchaRecognizer: CaptchaRecognizing, @unchecked Sendable {
    let result: CaptchaResult
    private(set) var callCount = 0

    init(result: CaptchaResult) {
        self.result = result
    }

    func recognize(_ image: CGImage) async throws -> CaptchaResult {
        callCount += 1
        return result
    }
}

@MainActor
private final class FakeSchoolAuthenticationClient: SchoolAuthenticationClient {
    let campusDescriptor = CampusDescriptor.bjfu
    let authenticatedEduID: String? = "20260001"

    var fetchCount = 0
    var loginCaptchas: [String] = []
    var loginResult = true
    var fetchError: Error?

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage) {
        if let fetchError {
            throw fetchError
        }
        fetchCount += 1
        return ("key-\(fetchCount)", makeImage())
    }

    func performLogin(
        account: String,
        password: String,
        captcha: String,
        key: String,
        portal: SchoolPortal
    ) async throws -> Bool {
        loginCaptchas.append(captcha)
        return loginResult
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
