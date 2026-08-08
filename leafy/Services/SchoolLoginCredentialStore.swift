import Foundation
import OSLog
import Security

nonisolated struct SchoolLoginCredential: Codable, Equatable, Sendable {
    let campusID: CampusID
    let portal: SchoolPortal
    let account: String
    let password: String
    let savedAt: Date
}

nonisolated enum SchoolLoginCredentialStore {
    private static let service = "com.myleafy.school-login"
    private static let logger = Logger(subsystem: "com.myleafy.leafy", category: "SchoolLoginCredentials")

    static func load(campusID: CampusID, portal: SchoolPortal) -> SchoolLoginCredential? {
        var query = baseQuery(campusID: campusID, portal: portal)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("School login credential read failed status=\(status, privacy: .public)")
            }
            return nil
        }

        do {
            let credential = try JSONDecoder().decode(SchoolLoginCredential.self, from: data)
            guard credential.campusID == campusID, credential.portal == portal else {
                logger.error("School login credential scope mismatch")
                return nil
            }
            return credential
        } catch {
            logger.error("School login credential decode failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func loadMostRecent(campusID: CampusID) -> SchoolLoginCredential? {
        SchoolPortal.allCases
            .compactMap { load(campusID: campusID, portal: $0) }
            .max(by: { $0.savedAt < $1.savedAt })
    }

    @discardableResult
    static func save(
        account: String,
        password: String,
        campusID: CampusID,
        portal: SchoolPortal
    ) -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty, !password.isEmpty else { return false }

        do {
            let credential = SchoolLoginCredential(
                campusID: campusID,
                portal: portal,
                account: trimmedAccount,
                password: password,
                savedAt: Date()
            )
            let data = try JSONEncoder().encode(credential)
            let updateStatus = SecItemUpdate(
                baseQuery(campusID: campusID, portal: portal) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if updateStatus == errSecSuccess { return true }
            guard updateStatus == errSecItemNotFound else {
                logger.error("School login credential update failed status=\(updateStatus, privacy: .public)")
                return false
            }

            var query = baseQuery(campusID: campusID, portal: portal)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("School login credential add failed status=\(addStatus, privacy: .public)")
                return false
            }
            return true
        } catch {
            logger.error("School login credential encode failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("School login credential deletion failed status=\(status, privacy: .public)")
            throw SchoolLoginCredentialStoreError.deletionFailed(status)
        }
    }

    private static func baseQuery(campusID: CampusID, portal: SchoolPortal) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(campusID.rawValue):\(portal.rawValue)"
        ]
    }
}

private nonisolated enum SchoolLoginCredentialStoreError: LocalizedError {
    case deletionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deletionFailed(let status):
            return "教务登录凭据删除失败（Keychain 状态 \(status)）"
        }
    }
}
