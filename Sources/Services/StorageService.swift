import Foundation

final class StorageService {
    static let shared = StorageService()

    // v1.6.2: Migrated off `UserDefaults(suiteName: "group.com.suber.app")`
    // because macOS 26.4 (Tahoe) tightened cfprefsd to reject app-group
    // suites with `kCFPreferencesAnyUser`. The fallback path triggered a
    // user-facing `kTCCServiceSystemPolicyAppData` ("data from other apps")
    // prompt at launch. AppGroupStore wraps `FileManager.containerURL`
    // which bypasses cfprefsd entirely.
    private let subscriptionsKey = "suber-subscriptions"
    private let settingsKey = "suber-settings"
    private let changesKey = "suber-changes"  // v1.6: SubscriptionChange log

    // MARK: - H5 (eng re-review) prune policy
    //
    // Prune on WRITE, not on read. Prevents iCloud KVS blowout when a user
    // with a noisy inbox goes weeks without opening the Changes Window.
    //
    // HARD CAP at 200 most-recent entries. Anything beyond gets dropped,
    // regardless of age. Storage-safety first: KVS budget is 1MB total, and
    // 200 entries × ~500 bytes/entry = ~100KB leaves room for subs + settings.
    //
    // The 14-day UNREAD window is a separate policy — it lives in
    // SubscriptionStore.unreadChangeCount (badge count), NOT here.
    // Historical entries that are acknowledged still appear in the Changes
    // Window for review; they just don't count toward the badge.
    static let changeLogMaxEntries = 200

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Cached date formatters for decoding

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Decoder that handles multiple date formats from Chrome extension exports:
    /// - ISO 8601 with fractional seconds: "2026-02-06T08:10:11.226Z"
    /// - ISO 8601 without fractional: "2026-02-06T08:10:11Z"
    /// - Date-only: "2026-01-31"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            // Try ISO 8601 with fractional seconds (Chrome's createdAt/updatedAt)
            if let date = StorageService.isoFractionalFormatter.date(from: str) { return date }

            // Try standard ISO 8601 (Swift's default export)
            if let date = StorageService.isoFormatter.date(from: str) { return date }

            // Try date-only "yyyy-MM-dd" (Chrome's startDate)
            if let date = StorageService.dateOnlyFormatter.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    private init() {}

    // MARK: - Subscriptions

    func loadSubscriptions() -> [Subscription] {
        guard let data = AppGroupStore.data(forKey: subscriptionsKey) else { return [] }
        return (try? decoder.decode([Subscription].self, from: data)) ?? []
    }

    func saveSubscriptions(_ subs: [Subscription]) {
        if let data = try? encoder.encode(subs) {
            AppGroupStore.set(data, forKey: subscriptionsKey)
            CloudSyncService.shared.pushSubscriptions(data)
        }
    }

    /// v1.9.2: atomic-ish append for AppIntents (Siri/Shortcuts). Loads the
    /// freshest on-disk list, appends, and saves in ONE call — narrowing the
    /// load→save window vs doing it across two StorageService calls in the
    /// Intent body. NOTE: this is not a cross-process lock; if the main app
    /// and an out-of-process Intent invocation race, a lost update is still
    /// theoretically possible. The window is now microseconds and both paths
    /// are additive, so the worst case is one of two near-simultaneous *adds*
    /// is dropped — never existing-data loss.
    @discardableResult
    func appendSubscription(_ sub: Subscription) -> [Subscription] {
        var subs = loadSubscriptions()
        subs.append(sub)
        saveSubscriptions(subs)
        return subs
    }

    // MARK: - Changes log (v1.6)

    /// Load the SubscriptionChange log. Gracefully returns [] on any decode
    /// error (we'd rather show an empty Changes Window than crash on
    /// forward-compat drift).
    func loadChanges() -> [SubscriptionChange] {
        guard let data = AppGroupStore.data(forKey: changesKey) else { return [] }
        return (try? decoder.decode([SubscriptionChange].self, from: data)) ?? []
    }

    /// Persist the change log, applying H5 prune-on-write BEFORE save.
    ///
    /// Prune rule: keep any entry that is (within the last 14 days OR among
    /// the 200 most-recent). Sorted newest-first so the view doesn't need
    /// to re-sort on every render.
    func saveChanges(_ changes: [SubscriptionChange]) {
        let pruned = Self.prune(changes)
        if let data = try? encoder.encode(pruned) {
            AppGroupStore.set(data, forKey: changesKey)
            CloudSyncService.shared.pushChanges(data)
        }
    }

    /// Exposed for unit tests of the prune policy.
    /// Hard cap: 200 most-recent entries. Anything beyond gets dropped.
    static func prune(_ changes: [SubscriptionChange], now: Date = Date()) -> [SubscriptionChange] {
        let sorted = changes.sorted { $0.detectedAt > $1.detectedAt }
        return Array(sorted.prefix(changeLogMaxEntries))
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = AppGroupStore.data(forKey: settingsKey) else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        if let data = try? encoder.encode(settings) {
            AppGroupStore.set(data, forKey: settingsKey)
            CloudSyncService.shared.pushSettings(data)
        }
    }

    // MARK: - Export / Import

    /// Native export format
    struct ExportData: Codable {
        let subscriptions: [Subscription]
        let settings: AppSettings
        let exportedAt: Date?
        let version: String?
    }

    /// Chrome extension export format (no exportedAt/version, has extra settings fields)
    private struct ChromeExportData: Decodable {
        let subscriptions: [Subscription]
        let settings: ChromeSettings?

        struct ChromeSettings: Decodable {
            var primaryCurrency: String?
            var reminderDaysBefore: [Int]?
            var enableNotifications: Bool?
            var language: String?
            // Chrome-only fields (ignored)
            // theme, enableUsageTracking, enableCloudSync
        }
    }

    func exportData(subscriptions: [Subscription], settings: AppSettings) -> Data? {
        let export = ExportData(
            subscriptions: subscriptions,
            settings: settings,
            exportedAt: Date(),
            version: "1.0.0"
        )
        return try? encoder.encode(export)
    }

    func importData(from data: Data) throws -> (subscriptions: [Subscription], settings: AppSettings) {
        // Try native format first
        if let imported = try? decoder.decode(ExportData.self, from: data) {
            return (imported.subscriptions, imported.settings)
        }

        // Try Chrome extension format
        let chrome = try decoder.decode(ChromeExportData.self, from: data)
        var settings = AppSettings()
        if let cs = chrome.settings {
            if let currency = cs.primaryCurrency { settings.primaryCurrency = currency }
            if let days = cs.reminderDaysBefore { settings.reminderDaysBefore = days }
            if let notif = cs.enableNotifications { settings.enableNotifications = notif }
            if let lang = cs.language { settings.language = lang }
        }
        return (chrome.subscriptions, settings)
    }

    // MARK: - Clear

    func clearAll() {
        AppGroupStore.removeObject(forKey: subscriptionsKey)
        AppGroupStore.removeObject(forKey: settingsKey)
    }
}
