import CoreGraphics
import Foundation
import UIKit
import Vision

nonisolated struct CaptchaResult: Equatable, Sendable {
    let text: String
    let confidence: Float
}

nonisolated protocol CaptchaRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> CaptchaResult
}

nonisolated struct VisionCaptchaRecognizer: CaptchaRecognizing {
    func recognize(_ image: CGImage) async throws -> CaptchaResult {
        let sendableImage = SendableCGImage(image)

        return try await Task.detached(priority: .userInitiated) {
            var recognitionError: Error?
            var observations: [VNRecognizedTextObservation] = []
            let request = VNRecognizeTextRequest { request, error in
                recognitionError = error
                observations = request.results as? [VNRecognizedTextObservation] ?? []
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: sendableImage.image, orientation: .up)
            try handler.perform([request])
            if let recognitionError {
                throw recognitionError
            }

            let candidates = observations.compactMap { observation -> (String, Float, CGFloat)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return (candidate.string, candidate.confidence, observation.boundingBox.minX)
            }
            .sorted { $0.2 < $1.2 }

            guard !candidates.isEmpty else {
                throw CaptchaRecognitionError.noText
            }

            return CaptchaResult(
                text: candidates.map(\.0).joined(),
                confidence: candidates.map(\.1).min() ?? 0
            )
        }.value
    }
}

private nonisolated final class SendableCGImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

nonisolated enum CaptchaRecognitionError: LocalizedError {
    case noText

    var errorDescription: String? {
        switch self {
        case .noText:
            return "未识别到验证码字符"
        }
    }
}

nonisolated enum UndergraduateCaptchaPolicy {
    static let minimumConfidence: Float = 0.90

    static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .uppercased()
    }

    static func automaticCandidate(from result: CaptchaResult) -> String? {
        guard result.confidence >= minimumConfidence else { return nil }
        let normalizedText = normalized(result.text)
        guard normalizedText.range(of: #"^[A-Z0-9]{4}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalizedText
    }
}

@MainActor
protocol SchoolAuthenticationClient: AnyObject {
    var campusDescriptor: CampusDescriptor { get }
    var authenticatedEduID: String? { get }

    func fetchCaptcha(for portal: SchoolPortal) async throws -> (key: String, image: UIImage)
    func performLogin(
        account: String,
        password: String,
        captcha: String,
        key: String,
        portal: SchoolPortal
    ) async throws -> Bool
}

extension SchoolNetworkManager: SchoolAuthenticationClient {}

nonisolated protocol SchoolLoginCredentialProviding: Sendable {
    func load(campusID: CampusID, portal: SchoolPortal) -> SchoolLoginCredential?
}

nonisolated struct KeychainSchoolLoginCredentialProvider: SchoolLoginCredentialProviding {
    func load(campusID: CampusID, portal: SchoolPortal) -> SchoolLoginCredential? {
        SchoolLoginCredentialStore.load(campusID: campusID, portal: portal)
    }
}

struct SchoolCaptchaChallenge {
    let portal: SchoolPortal
    let key: String
    let image: UIImage
    let credential: SchoolLoginCredential?
}

enum SchoolAuthenticationRecoveryResult {
    case authenticated
    case requiresManual(SchoolCaptchaChallenge, message: String?)
}

@MainActor
struct SchoolAuthenticationService {
    private let client: any SchoolAuthenticationClient
    private let recognizer: any CaptchaRecognizing
    private let credentialProvider: any SchoolLoginCredentialProviding

    init(
        client: any SchoolAuthenticationClient,
        recognizer: any CaptchaRecognizing = VisionCaptchaRecognizer(),
        credentialProvider: any SchoolLoginCredentialProviding = KeychainSchoolLoginCredentialProvider()
    ) {
        self.client = client
        self.recognizer = recognizer
        self.credentialProvider = credentialProvider
    }

    func recover(
        portal: SchoolPortal,
        allowsAutomaticAttempt: Bool
    ) async throws -> SchoolAuthenticationRecoveryResult {
        let challenge = try await fetchManualChallenge(portal: portal)

        guard allowsAutomaticAttempt,
              portal == .undergraduate,
              let credential = challenge.credential else {
            return .requiresManual(challenge, message: nil)
        }

        let recognition: CaptchaResult
        do {
            guard let cgImage = challenge.image.cgImage else {
                return .requiresManual(challenge, message: nil)
            }
            recognition = try await recognizer.recognize(cgImage)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .requiresManual(challenge, message: nil)
        }

        guard let captcha = UndergraduateCaptchaPolicy.automaticCandidate(from: recognition) else {
            return .requiresManual(challenge, message: nil)
        }

        do {
            let didLogin = try await client.performLogin(
                account: credential.account,
                password: credential.password,
                captcha: captcha,
                key: challenge.key,
                portal: portal
            )
            guard didLogin else {
                return try await freshManualChallenge(
                    portal: portal,
                    message: "需要重新验证，请输入新的验证码。"
                )
            }
            return .authenticated
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case SchoolNetworkError.campusNetworkRequired = error {
                throw error
            }
            return try await freshManualChallenge(
                portal: portal,
                message: "需要重新验证，请输入新的验证码。"
            )
        }
    }

    func fetchManualChallenge(portal: SchoolPortal) async throws -> SchoolCaptchaChallenge {
        let captcha = try await client.fetchCaptcha(for: portal)
        return SchoolCaptchaChallenge(
            portal: portal,
            key: captcha.key,
            image: captcha.image,
            credential: matchingCredential(portal: portal)
        )
    }

    func submitManual(
        challenge: SchoolCaptchaChallenge,
        account: String,
        password: String,
        captcha: String
    ) async throws -> Bool {
        try await client.performLogin(
            account: account,
            password: password,
            captcha: captcha,
            key: challenge.key,
            portal: challenge.portal
        )
    }

    private func freshManualChallenge(
        portal: SchoolPortal,
        message: String
    ) async throws -> SchoolAuthenticationRecoveryResult {
        let challenge = try await fetchManualChallenge(portal: portal)
        return .requiresManual(challenge, message: message)
    }

    private func matchingCredential(portal: SchoolPortal) -> SchoolLoginCredential? {
        guard let credential = credentialProvider.load(
            campusID: client.campusDescriptor.id,
            portal: portal
        ) else {
            return nil
        }

        let authenticatedAccount = client.authenticatedEduID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard authenticatedAccount?.isEmpty == false,
              credential.account == authenticatedAccount else {
            return nil
        }
        return credential
    }
}
