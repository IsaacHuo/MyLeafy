import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

nonisolated struct CaptchaResult: Equatable, Sendable {
    let text: String
    let confidence: Float
    let supportingVariantCount: Int

    init(
        text: String,
        confidence: Float,
        supportingVariantCount: Int = 1
    ) {
        self.text = text
        self.confidence = confidence
        self.supportingVariantCount = supportingVariantCount
    }
}

nonisolated protocol CaptchaRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> CaptchaResult
}

nonisolated protocol CaptchaImagePreprocessing: Sendable {
    func variants(for image: CGImage) throws -> [CGImage]
}

nonisolated final class CoreImageCaptchaPreprocessor: CaptchaImagePreprocessing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func variants(for image: CGImage) throws -> [CGImage] {
        let source = CIImage(cgImage: image)
        let scaled = try renderScaled(source)
        let enhanced = try renderEnhanced(source)
        return [image, scaled, enhanced]
    }

    private func renderScaled(_ source: CIImage) throws -> CGImage {
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = source
        filter.scale = 4
        filter.aspectRatio = 1
        guard let output = filter.outputImage,
              let image = context.createCGImage(output, from: output.extent.integral) else {
            throw CaptchaRecognitionError.preprocessingFailed
        }
        return image
    }

    private func renderEnhanced(_ source: CIImage) throws -> CGImage {
        let scaleFilter = CIFilter.lanczosScaleTransform()
        scaleFilter.inputImage = source
        scaleFilter.scale = 4
        scaleFilter.aspectRatio = 1
        guard let scaled = scaleFilter.outputImage else {
            throw CaptchaRecognitionError.preprocessingFailed
        }

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = scaled
        colorFilter.saturation = 0
        colorFilter.contrast = 1.4
        colorFilter.brightness = 0.02
        guard let output = colorFilter.outputImage,
              let image = context.createCGImage(output, from: output.extent.integral) else {
            throw CaptchaRecognitionError.preprocessingFailed
        }
        return image
    }
}

nonisolated struct VisionCaptchaRecognizer: CaptchaRecognizing {
    private let preprocessor: any CaptchaImagePreprocessing

    init(
        preprocessor: any CaptchaImagePreprocessing = CoreImageCaptchaPreprocessor()
    ) {
        self.preprocessor = preprocessor
    }

    func recognize(_ image: CGImage) async throws -> CaptchaResult {
        let sendableImage = SendableCGImage(image)
        let preprocessor = self.preprocessor

        return try await Task.detached(priority: .userInitiated) {
            let variants = try preprocessor.variants(for: sendableImage.image)
            var results: [CaptchaResult] = []

            for variant in variants {
                try Task.checkCancellation()
                do {
                    results.append(try recognizeSingleImage(variant))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
            }

            return try CaptchaConsensus.aggregate(results)
        }.value
    }

    private nonisolated func recognizeSingleImage(_ image: CGImage) throws -> CaptchaResult {
        var recognitionError: Error?
        var observations: [VNRecognizedTextObservation] = []
        let request = VNRecognizeTextRequest { request, error in
            recognitionError = error
            observations = request.results as? [VNRecognizedTextObservation] ?? []
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
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
    }
}

nonisolated enum CaptchaConsensus {
    static func aggregate(_ results: [CaptchaResult]) throws -> CaptchaResult {
        guard !results.isEmpty else {
            throw CaptchaRecognitionError.noText
        }

        let groups = Dictionary(grouping: results) {
            UndergraduateCaptchaPolicy.normalized($0.text)
        }
        let summaries = groups.map { text, matches in
            CaptchaResult(
                text: text,
                confidence: matches.map(\.confidence).min() ?? 0,
                supportingVariantCount: matches.count
            )
        }
        .sorted {
            if $0.supportingVariantCount != $1.supportingVariantCount {
                return $0.supportingVariantCount > $1.supportingVariantCount
            }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.text < $1.text
        }

        guard let result = summaries.first else {
            throw CaptchaRecognitionError.noText
        }
        return result
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
    case preprocessingFailed

    var errorDescription: String? {
        switch self {
        case .noText:
            return "未识别到验证码字符"
        case .preprocessingFailed:
            return "验证码图像处理失败"
        }
    }
}

nonisolated enum UndergraduateCaptchaPolicy {
    static let minimumConfidence: Float = 0.85
    static let minimumSupportingVariantCount = 2

    static func normalized(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    static func automaticCandidate(from result: CaptchaResult) -> String? {
        guard result.confidence >= minimumConfidence else { return nil }
        guard result.supportingVariantCount >= minimumSupportingVariantCount else { return nil }
        let normalizedText = normalized(result.text)
        guard normalizedText.range(of: #"^[a-z0-9]{4}$"#, options: .regularExpression) != nil else {
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
    case networkUnavailable
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
        allowsAutomaticAttempt: Bool,
        progressReporter: AcademicOperationProgressReporter? = nil
    ) async throws -> SchoolAuthenticationRecoveryResult {
        progressReporter?(.begin(.connectingAcademicSystem))
        let challenge: SchoolCaptchaChallenge
        do {
            challenge = try await fetchManualChallenge(portal: portal)
        } catch {
            if case SchoolNetworkError.campusNetworkRequired = error {
                return .networkUnavailable
            }
            throw error
        }

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
            progressReporter?(.begin(.recognizingCaptcha))
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
            progressReporter?(.begin(.authenticating))
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
                return .networkUnavailable
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
        do {
            let challenge = try await fetchManualChallenge(portal: portal)
            return .requiresManual(challenge, message: message)
        } catch {
            if case SchoolNetworkError.campusNetworkRequired = error {
                return .networkUnavailable
            }
            throw error
        }
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
