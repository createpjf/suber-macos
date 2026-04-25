import Foundation
import Security

// ┌───────────── IMAPAccount — config + Keychain credential storage ───────────┐
// │                                                                            │
// │  The user's IMAP setup. Two parts:                                         │
// │                                                                            │
// │   Public config (in AppSettings.autopilot.imapAccount, syncs via iCloud):  │
// │     - provider: Gmail / iCloud / Outlook / Yahoo / Fastmail / Generic      │
// │     - email: the account's address (also serves as the IMAP login user     │
// │       for all major providers)                                             │
// │     - host: imap.gmail.com etc. (preset or user-entered for generic)       │
// │     - port: usually 993                                                    │
// │                                                                            │
// │   Secret credential (in Keychain, NEVER syncs):                            │
// │     - App Password — service "com.suber.imap", account = email             │
// │                                                                            │
// │  Why split:                                                                │
// │    iCloud KVS is unencrypted-in-transit-but-encrypted-at-rest, fine for    │
// │    settings but Apple's own docs say "do not store passwords in user       │
// │    defaults." Keychain is the macOS-canonical password store. Splitting    │
// │    means the user's config travels with them across Macs, but each Mac     │
// │    needs its own App Password entry in Keychain.                           │
// │                                                                            │
// │  D8 privacy: app passwords NEVER leave the local Keychain. The IMAP        │
// │  client reads them at scan time and discards immediately. They aren't      │
// │  copied to logs, environment variables, or persisted anywhere else.        │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// User-facing IMAP config. The credential lives separately in Keychain.
struct IMAPAccount: Codable, Equatable, Identifiable {
    var id: String { email }    // email is the natural key

    var provider: IMAPProvider
    var email: String
    var host: String
    var port: UInt16
    /// Display label shown in Settings. Defaults to provider name + email.
    var displayName: String

    init(provider: IMAPProvider, email: String, host: String? = nil, port: UInt16? = nil, displayName: String? = nil) {
        self.provider = provider
        self.email = email
        self.host = host ?? provider.defaultHost ?? ""
        self.port = port ?? provider.defaultPort
        self.displayName = displayName ?? "\(provider.displayName) · \(email)"
    }
}

// MARK: - Keychain credential storage

/// Static helpers around `Security.framework`'s SecKeychain APIs scoped to
/// "com.suber.imap" service. Keys: app password keyed by email address.
enum IMAPCredentialStore {

    private static let service = "com.suber.imap"

    /// Save (or update) the App Password for the given email.
    @discardableResult
    static func save(password: String, for email: String) -> Bool {
        let data = Data(password.utf8)

        // Try update first (cheap if the entry exists).
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // No existing entry → add.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecValueData as String: data,
            // Allow background access (Watchdog scans run via NSBackgroundActivityScheduler
            // even when Suber isn't frontmost). kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            // means: readable after first unlock, not synced via iCloud Keychain.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Retrieve the App Password. Returns nil if missing or Keychain access denied.
    static func load(email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }

    /// Remove the credential. Idempotent; returns true even if no entry existed.
    @discardableResult
    static func delete(email: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// True iff a credential exists for the given email.
    static func has(email: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
