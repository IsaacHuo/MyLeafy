import XCTest
import UIKit
@testable import Leafy

final class SchoolAuthenticationRecoveryTests: XCTestCase {
    func testSessionRecoveryPolicySkipsFirstLoginAndValidSession() {
        XCTAssertFalse(
            SchoolSessionRecoveryPolicy.shouldBeginRecovery(
                hasCachedIdentity: false,
                isLoggedIn: false
            )
        )
        XCTAssertFalse(
            SchoolSessionRecoveryPolicy.shouldBeginRecovery(
                hasCachedIdentity: true,
                isLoggedIn: true
            )
        )
        XCTAssertTrue(
            SchoolSessionRecoveryPolicy.shouldBeginRecovery(
                hasCachedIdentity: true,
                isLoggedIn: false
            )
        )
    }

    func testUndergraduateCaptchaPolicyNormalizesAndAcceptsReliableCode() {
        XCTAssertEqual(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(
                    text: " a7\nk3 ",
                    confidence: 0.86,
                    supportingVariantCount: 3
                )
            ),
            "a7k3"
        )
    }

    func testUndergraduateCaptchaPolicyRejectsLowConfidenceAndInvalidFormats() {
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(
                    text: "a7k3",
                    confidence: 0.849,
                    supportingVariantCount: 3
                )
            )
        )
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(
                    text: "a7k3",
                    confidence: 0.99,
                    supportingVariantCount: 1
                )
            )
        )
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(
                    text: "a?k3",
                    confidence: 0.99,
                    supportingVariantCount: 3
                )
            )
        )
        XCTAssertNil(
            UndergraduateCaptchaPolicy.automaticCandidate(
                from: CaptchaResult(
                    text: "a7k",
                    confidence: 0.99,
                    supportingVariantCount: 3
                )
            )
        )
    }

    func testCaptchaConsensusUsesMatchingVariantsAndMinimumConfidence() throws {
        let result = try CaptchaConsensus.aggregate([
            CaptchaResult(text: "a7k3", confidence: 0.94),
            CaptchaResult(text: " a7 k3 ", confidence: 0.87),
            CaptchaResult(text: "a7x3", confidence: 0.99)
        ])

        XCTAssertEqual(result.text, "a7k3")
        XCTAssertEqual(result.confidence, 0.87)
        XCTAssertEqual(result.supportingVariantCount, 2)
        XCTAssertEqual(UndergraduateCaptchaPolicy.automaticCandidate(from: result), "a7k3")
    }

    func testCaptchaConsensusRejectsThreeConflictingVariants() throws {
        let result = try CaptchaConsensus.aggregate([
            CaptchaResult(text: "a7k3", confidence: 0.99),
            CaptchaResult(text: "a7x3", confidence: 0.98),
            CaptchaResult(text: "a7y3", confidence: 0.97)
        ])

        XCTAssertEqual(result.supportingVariantCount, 1)
        XCTAssertNil(UndergraduateCaptchaPolicy.automaticCandidate(from: result))
    }

    @MainActor
    func testReliableUndergraduateCaptchaAuthenticatesAutomaticallyOnce() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.90, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())
        let recorder = AuthenticationProgressRecorder()

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            progressReporter: { recorder.events.append($0) },
            policy: testPolicy
        )

        guard case .authenticated = result else {
            return XCTFail("Expected automatic authentication")
        }
        XCTAssertEqual(client.fetchCount, 1)
        XCTAssertEqual(client.loginCaptchas, ["a7k3"])
        XCTAssertEqual(recognizer.callCount, 1)
        XCTAssertEqual(recorder.events, [
            .begin(.connectingAcademicSystem),
            .beginAttempt(.recognizingCaptcha, current: 1, total: 3),
            .beginAttempt(.authenticating, current: 1, total: 3)
        ])
    }

    @MainActor
    func testThreeUnreliableRecognitionsUseThirdChallengeWithoutSubmittingLogin() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.5, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            policy: testPolicy
        )

        guard case .requiresManual(let challenge, _) = result else {
            return XCTFail("Expected manual verification")
        }
        XCTAssertEqual(challenge.key, "key-3")
        XCTAssertEqual(client.fetchCount, 3)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
        XCTAssertEqual(recognizer.callCount, 3)
    }

    @MainActor
    func testMissingCredentialSkipsRecognitionAndUsesManualFallback() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.99, supportingVariantCount: 3)
        )
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
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "1234", confidence: 0.99, supportingVariantCount: 3)
        )
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
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.99, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: false)

        guard case .requiresManual = result else {
            return XCTFail("Expected manual verification")
        }
        XCTAssertEqual(recognizer.callCount, 0)
        XCTAssertTrue(client.loginCaptchas.isEmpty)
    }

    @MainActor
    func testThreeRejectedLoginsFetchFreshFourthManualChallenge() async throws {
        let client = FakeSchoolAuthenticationClient()
        client.loginResult = false
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.99, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            policy: testPolicy
        )

        guard case .requiresManual(let challenge, _) = result else {
            return XCTFail("Expected fresh manual verification")
        }
        XCTAssertEqual(challenge.key, "key-4")
        XCTAssertEqual(client.fetchCount, 4)
        XCTAssertEqual(client.loginCaptchas, ["a7k3", "a7k3", "a7k3"])
        XCTAssertEqual(recognizer.callCount, 3)
    }

    @MainActor
    func testSecondRoundSucceedsAfterFirstRecognitionIsUnreliable() async throws {
        let client = FakeSchoolAuthenticationClient()
        let recognizer = FakeCaptchaRecognizer(results: [
            CaptchaResult(text: "a7k3", confidence: 0.4, supportingVariantCount: 1),
            CaptchaResult(text: "c113", confidence: 0.99, supportingVariantCount: 2)
        ])
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            policy: testPolicy
        )

        guard case .authenticated = result else {
            return XCTFail("Expected second-round authentication")
        }
        XCTAssertEqual(client.fetchCount, 2)
        XCTAssertEqual(recognizer.callCount, 2)
        XCTAssertEqual(client.loginCaptchas, ["c113"])
    }

    @MainActor
    func testThirdRoundSucceedsAfterTwoCaptchaRejections() async throws {
        let client = FakeSchoolAuthenticationClient()
        client.loginOutcomes = [
            .failure(SchoolNetworkError.loginFailed("验证码错误")),
            .failure(SchoolNetworkError.loginFailed("随机码错误")),
            .success(true)
        ]
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "22nv", confidence: 0.99, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            policy: testPolicy
        )

        guard case .authenticated = result else {
            return XCTFail("Expected third-round authentication")
        }
        XCTAssertEqual(client.fetchCount, 3)
        XCTAssertEqual(recognizer.callCount, 3)
        XCTAssertEqual(client.loginCaptchas, ["22nv", "22nv", "22nv"])
    }

    @MainActor
    func testCredentialFailureStopsAutomaticRetriesAndRevealsCredentials() async throws {
        let client = FakeSchoolAuthenticationClient()
        client.loginOutcomes = [
            .failure(SchoolNetworkError.loginFailed("账号或密码错误"))
        ]
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "c113", confidence: 0.99, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        let result = try await service.recover(
            portal: .undergraduate,
            allowsAutomaticAttempt: true,
            policy: testPolicy
        )

        guard case .requiresManual(let challenge, _) = result else {
            return XCTFail("Expected manual credentials")
        }
        XCTAssertNil(challenge.credential)
        XCTAssertTrue(challenge.prefersCredentialEntry)
        XCTAssertEqual(client.fetchCount, 2)
        XCTAssertEqual(client.loginCaptchas.count, 1)
        XCTAssertEqual(recognizer.callCount, 1)
    }

    @MainActor
    func testNetworkFailureDoesNotAttemptRecognitionOrLogin() async {
        let client = FakeSchoolAuthenticationClient()
        client.fetchError = SchoolNetworkError.campusNetworkRequired
        let recognizer = FakeCaptchaRecognizer(
            result: CaptchaResult(text: "a7k3", confidence: 0.99, supportingVariantCount: 3)
        )
        let service = makeService(client: client, recognizer: recognizer, credential: credential())

        do {
            let result = try await service.recover(portal: .undergraduate, allowsAutomaticAttempt: true)
            guard case .networkUnavailable = result else {
                return XCTFail("Expected network-unavailable recovery result")
            }
        } catch {
            XCTFail("Expected a recovery result, got \(error)")
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

    private var testPolicy: CaptchaRecoveryPolicy {
        CaptchaRecoveryPolicy(maximumAttempts: 3, retryDelay: .zero)
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

@MainActor
private final class AuthenticationProgressRecorder {
    var events: [AcademicOperationProgressEvent] = []
}

private nonisolated struct FakeCredentialProvider: SchoolLoginCredentialProviding {
    let credential: SchoolLoginCredential?

    func load(campusID: CampusID, portal: SchoolPortal) -> SchoolLoginCredential? {
        guard credential?.campusID == campusID, credential?.portal == portal else { return nil }
        return credential
    }
}

private nonisolated final class FakeCaptchaRecognizer: CaptchaRecognizing, @unchecked Sendable {
    private var results: [CaptchaResult]
    private(set) var callCount = 0

    init(result: CaptchaResult) {
        results = [result]
    }

    init(results: [CaptchaResult]) {
        self.results = results
    }

    func recognize(_ image: CGImage) async throws -> CaptchaResult {
        callCount += 1
        if results.count > 1 {
            return results.removeFirst()
        }
        guard let result = results.first else {
            throw CaptchaRecognitionError.noText
        }
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
    var loginOutcomes: [Result<Bool, Error>] = []
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
        if !loginOutcomes.isEmpty {
            return try loginOutcomes.removeFirst().get()
        }
        return loginResult
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
