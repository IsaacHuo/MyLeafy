import Foundation
import Security

nonisolated enum LegacyCampusAIDataCleanup {
    private static let keychainService = "com.myleafy.campus-ai"

    static func deleteKeychainData() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LegacyCampusAIDataCleanupError.unexpectedStatus(status)
        }
    }
}

private enum LegacyCampusAIDataCleanupError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "历史 AI Keychain 数据清理失败（\(status)）。"
        }
    }
}
