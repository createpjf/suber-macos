import Foundation

// ┌───────────── AppGroupStore — file-based app-group storage ────────────────┐
// │                                                                            │
// │  Backstory (v1.6.2). v1.6.0 + v1.6.1 used                                  │
// │  `UserDefaults(suiteName: "group.com.suber.app")` for everything           │
// │  shared between Suber.app and SuberWidget.appex. Worked fine through       │
// │  macOS 14 / 15. Then macOS 26.4 (Tahoe) tightened cfprefsd:                │
// │                                                                            │
// │    [User Defaults] Couldn't read values in CFPrefsPlistSource              │
// │    (Domain: group.com.suber.app, User: kCFPreferencesAnyUser, ...):        │
// │    Using kCFPreferencesAnyUser with a container is only allowed for        │
// │    System Containers, detaching from cfprefsd                              │
// │                                                                            │
// │  When cfprefsd detaches, UserDefaults silently falls back to a path        │
// │  that macOS classifies as "cross-app data access" → fires                  │
// │  `kTCCServiceSystemPolicyAppData` prompt: "Suber would like to access      │
// │  data from other apps." User UI gets stuck because the popover sits        │
// │  on top of the system prompt.                                              │
// │                                                                            │
// │  Apple's recommended path on modern macOS is FILESYSTEM-based              │
// │  sharing via `FileManager.containerURL(forSecurityApplicationGroupId...)`. │
// │  This API bypasses cfprefsd entirely — no User=kCFPreferencesAnyUser       │
// │  ambiguity, no TCC trigger.                                                │
// │                                                                            │
// │  Storage layout:                                                           │
// │    <container>/Library/Preferences/Suber/{key}.json                        │
// │                                                                            │
// │  AppGroupStore is a thin wrapper. Same Data-in/Data-out shape as           │
// │  UserDefaults so call-site migration is mechanical.                        │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum AppGroupStore {
    static let groupIdentifier = "group.com.suber.app"

    /// Resolves to e.g. `/Users/x/Library/Group Containers/group.com.suber.app/`.
    /// Returns nil only when the entitlement is missing or the container
    /// hasn't been created yet — both are unrecoverable, callers should fall
    /// through and treat the read as "no data".
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    /// `<container>/Library/Preferences/Suber/`. Library/Preferences is the
    /// canonical home for app-defined preferences and gets backed up by
    /// Time Machine.
    private static var preferencesDirectory: URL? {
        guard let base = containerURL else { return nil }
        let dir = base
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("Suber", isDirectory: true)
        // Lazy-create on first write/read; cheap on subsequent calls.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for key: String) -> URL? {
        // Sanitize: keys are Suber-internal and won't contain path separators,
        // but defense-in-depth replaces "/" just in case.
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return preferencesDirectory?.appendingPathComponent("\(safe).json")
    }

    // MARK: - Public Data API

    /// Load raw bytes for `key`. Returns nil when no value has been stored.
    static func data(forKey key: String) -> Data? {
        guard let url = fileURL(for: key),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Persist raw bytes for `key`. Atomic write — partial files never
    /// observed by the widget reader during refresh.
    @discardableResult
    static func set(_ data: Data, forKey key: String) -> Bool {
        guard let url = fileURL(for: key) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            NSLog("Suber AppGroupStore: write failed for \(key): \(error)")
            return false
        }
    }

    @discardableResult
    static func removeObject(forKey key: String) -> Bool {
        guard let url = fileURL(for: key) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    // MARK: - TimeInterval helper for v1.6.0 migration

    /// MailWatchdog persisted `lastScanDate` as a TimeInterval. Provide a
    /// matching helper so call sites read like the old UserDefaults API.
    static func double(forKey key: String) -> Double {
        guard let data = data(forKey: key) else { return 0 }
        return (try? JSONDecoder().decode(Double.self, from: data)) ?? 0
    }

    static func set(_ value: Double, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}
