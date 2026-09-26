import Foundation





nonisolated struct BackendErrorEnvelope: Decodable, LocalizedError, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    let details: String?

    var errorDescription: String? {
        message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case retryable
        case details
    }

    init(code: String, message: String, retryable: Bool, details: String? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        retryable = try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false
        details = (try? container.decodeIfPresent(String.self, forKey: .details)) ?? nil
    }
}

nonisolated struct BackendErrorPayload: Decodable, Sendable {
    let error: String?
    let errorEnvelope: BackendErrorEnvelope?
}
