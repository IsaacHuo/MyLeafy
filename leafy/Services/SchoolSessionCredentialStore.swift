import Foundation
import OSLog
import Security

nonisolated enum SchoolSessionCredentialStore {
    private static let service = "com.myleafy.school-session"
    private static let logger = Logger(subsystem: "com.myleafy.leafy", category: "SchoolCredentials")

    static func load(identity: CampusIdentity?, portal: SchoolPortal) -> [String: String] {
        guard let account = account(identity: identity, portal: portal) else { return [:] }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("School cookie read failed status=\(status, privacy: .public)")
            }
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            logger.error("School cookie decode failed error=\(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    @discardableResult
    static func save(
        _ cookies: [String: String],
        identity: CampusIdentity?,
        portal: SchoolPortal
    ) -> Bool {
        guard let account = account(identity: identity, portal: portal) else { return false }
        if cookies.isEmpty {
            return delete(identity: identity, portal: portal)
        }

        do {
            let data = try JSONEncoder().encode(cookies)
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            if updateStatus == errSecSuccess { return true }
            guard updateStatus == errSecItemNotFound else {
                logger.error("School cookie update failed status=\(updateStatus, privacy: .public)")
                return false
            }

            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("School cookie add failed status=\(addStatus, privacy: .public)")
                return false
            }
            return true
        } catch {
            logger.error("School cookie encode failed error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    static func delete(identity: CampusIdentity?, portal: SchoolPortal) -> Bool {
        guard let account = account(identity: identity, portal: portal) else { return true }
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("School cookie delete failed status=\(status, privacy: .public)")
            return false
        }
        return true
    }

    static func migrateLegacyCookiesIfNeeded(
        defaults: UserDefaults,
        defaultsKey: String,
        identity: CampusIdentity?,
        portal: SchoolPortal
    ) -> [String: String] {
        let stored = load(identity: identity, portal: portal)
        guard stored.isEmpty,
              let legacy = defaults.dictionary(forKey: defaultsKey) as? [String: String],
              !legacy.isEmpty else {
            if !stored.isEmpty {
                defaults.removeObject(forKey: defaultsKey)
            }
            return stored
        }

        guard save(legacy, identity: identity, portal: portal) else {
            logger.error("Legacy school cookies remain in defaults because Keychain migration failed")
            return legacy
        }
        defaults.removeObject(forKey: defaultsKey)
        return legacy
    }

    private static func account(identity: CampusIdentity?, portal: SchoolPortal) -> String? {
        guard let identity else { return nil }
        return "\(identity.scopeKey):\(portal.rawValue)"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}
