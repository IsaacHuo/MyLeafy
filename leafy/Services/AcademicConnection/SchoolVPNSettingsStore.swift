import Combine
import Foundation
import Security

nonisolated struct SchoolVPNCredential: Codable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible {
    let account: String
    let password: String

    var description: String { "SchoolVPNCredential(redacted)" }
    var debugDescription: String { description }
}

nonisolated enum SchoolVPNStorageFailure: LocalizedError {
    case keychain(OSStatus)
    case invalidRecord
    case unsupportedIdentity

    var errorDescription: String? {
        switch self {
        case .keychain, .invalidRecord:
            return "无法安全读取或保存 VPN 凭据，请重试。"
        case .unsupportedIdentity:
            return "当前入口不支持北林本科 VPN 同步。"
        }
    }
}

nonisolated protocol SchoolVPNVault: Sendable {
    func load(owner: String) throws -> SchoolVPNCredential?
    func save(_ credential: SchoolVPNCredential, owner: String) throws
    func remove(owner: String) throws
    func removeAll() throws
}

nonisolated struct KeychainSchoolVPNVault: SchoolVPNVault {
    func removeAll() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.myleafy.school-vpn"
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
        else { throw SchoolVPNStorageFailure.keychain(status) }
    }
    private func query(_ owner: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.myleafy.school-vpn",
         kSecAttrAccount as String: owner,
         kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
    }

    func load(owner: String) throws -> SchoolVPNCredential? {
        var lookup = query(owner)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let bytes = result as? Data else { throw SchoolVPNStorageFailure.keychain(status) }
        guard let credential = try? JSONDecoder().decode(SchoolVPNCredential.self, from: bytes),
              !credential.account.isEmpty, !credential.password.isEmpty
        else { throw SchoolVPNStorageFailure.invalidRecord }
        return credential
    }

    func save(_ credential: SchoolVPNCredential, owner: String) throws {
        let bytes = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query(owner) as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SchoolVPNStorageFailure.keychain(status) }
        var insertion = query(owner)
        insertion[kSecValueData as String] = bytes
        let added = SecItemAdd(insertion as CFDictionary, nil)
        guard added == errSecSuccess else { throw SchoolVPNStorageFailure.keychain(added) }
    }

    func remove(owner: String) throws {
        let status = SecItemDelete(query(owner) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
        else { throw SchoolVPNStorageFailure.keychain(status) }
    }
}

@MainActor
final class SchoolVPNSettingsStore: ObservableObject {
    static let shared = SchoolVPNSettingsStore()

    @Published private(set) var revision: UInt64 = 0
    @Published var storageWarning: String?
    private let defaults: UserDefaults
    private let vault: any SchoolVPNVault
    private var transient: [String: SchoolVPNCredential] = [:]
    private var pendingLogin: (credential: SchoolVPNCredential, remember: Bool)?
    private var pendingLoginEnabled = false

    init(defaults: UserDefaults = .standard, vault: any SchoolVPNVault = KeychainSchoolVPNVault()) {
        self.defaults = defaults
        self.vault = vault
    }

    func isEnabled(for identity: CampusIdentity?) -> Bool {
        guard let identity else { return pendingLoginEnabled }
        guard supports(identity) else { return false }
        return defaults.bool(forKey: enabledKey(identity))
    }

    func credential(for identity: CampusIdentity?) throws -> SchoolVPNCredential? {
        guard let identity else { return pendingLogin?.credential }
        guard supports(identity) else { throw SchoolVPNStorageFailure.unsupportedIdentity }
        return try transient[identity.scopeKey] ?? vault.load(owner: identity.scopeKey)
    }

    func isSaved(for identity: CampusIdentity?) throws -> Bool {
        guard let identity else { return false }
        guard supports(identity) else { return false }
        return try vault.load(owner: identity.scopeKey) != nil
    }

    func configure(_ credential: SchoolVPNCredential, remember: Bool, identity: CampusIdentity?) throws {
        let account = credential.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, account.count <= 128, !credential.password.isEmpty,
              credential.password.count <= 1024 else {
            throw AcademicConnectorFailure(
                status: 0,
                code: "vpn_credentials_required",
                message: "请填写北林 VPN 账号和密码。",
                requestID: nil
            )
        }
        let normalized = SchoolVPNCredential(account: account, password: credential.password)
        if let identity {
            guard supports(identity) else { throw SchoolVPNStorageFailure.unsupportedIdentity }
            if remember { try vault.save(normalized, owner: identity.scopeKey) }
            else { try vault.remove(owner: identity.scopeKey) }
            transient[identity.scopeKey] = remember ? nil : normalized
            defaults.set(true, forKey: enabledKey(identity))
        } else {
            // The final owner is known only after school authentication. Never save under a shared login key.
            pendingLogin = (normalized, remember)
            pendingLoginEnabled = true
        }
        revision &+= 1
        storageWarning = nil
    }

    func bindPendingLogin(to identity: CampusIdentity) throws {
        guard pendingLoginEnabled else { return }
        guard supports(identity) else { throw SchoolVPNStorageFailure.unsupportedIdentity }
        // Preserve the explicit connection choice even if secure storage needs attention.
        defaults.set(true, forKey: enabledKey(identity))
        guard let pendingLogin else {
            pendingLoginEnabled = false
            objectWillChange.send()
            return
        }
        if pendingLogin.remember { try vault.save(pendingLogin.credential, owner: identity.scopeKey) }
        else { transient[identity.scopeKey] = pendingLogin.credential }
        self.pendingLogin = nil
        pendingLoginEnabled = false
        storageWarning = nil
        // Binding an authenticated owner is not a new configuration and must not cancel that login.
        objectWillChange.send()
    }

    func finishUse(for identity: CampusIdentity?, revision expectedRevision: UInt64? = nil) {
        guard expectedRevision == nil || expectedRevision == revision else { return }
        if let identity { transient.removeValue(forKey: identity.scopeKey) }
        else { pendingLogin = nil }
        objectWillChange.send()
    }

    func rememberChoice(for identity: CampusIdentity?) throws -> Bool {
        guard let identity else { return pendingLogin?.remember ?? false }
        return try isSaved(for: identity)
    }

    func remove(for identity: CampusIdentity?) throws {
        if let identity {
            guard supports(identity) else { throw SchoolVPNStorageFailure.unsupportedIdentity }
            try vault.remove(owner: identity.scopeKey)
            transient.removeValue(forKey: identity.scopeKey)
            defaults.removeObject(forKey: enabledKey(identity))
        } else { pendingLogin = nil; pendingLoginEnabled = false }
        revision &+= 1
    }

    private func enabledKey(_ identity: CampusIdentity)
        -> String { "leafy.campus.\(identity.scopeKey).academicVPNEnabled" }
    func removeAll() throws {
        try vault.removeAll()
        transient.removeAll()
        pendingLogin = nil
        pendingLoginEnabled = false
        storageWarning = nil
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("leafy.campus.") && key.hasSuffix(".academicVPNEnabled") {
            defaults.removeObject(forKey: key)
        }
        revision &+= 1
    }
    private func supports(_ identity: CampusIdentity) -> Bool {
        identity.campusID == .bjfu && identity.portal == .undergraduate && !identity.isGuest && !identity.isCustom
    }
}
