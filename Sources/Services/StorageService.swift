import Foundation

final class StorageService {
    static let shared = StorageService()

    private let defaults = UserDefaults.standard
    private let subscriptionsKey = "subreminder-subscriptions"
    private let settingsKey = "subreminder-settings"

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
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
            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: str) { return date }

            // Try standard ISO 8601 (Swift's default export)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }

            // Try date-only "yyyy-MM-dd" (Chrome's startDate)
            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnly.date(from: str) { return date }

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
        guard let data = defaults.data(forKey: subscriptionsKey) else { return [] }
        return (try? decoder.decode([Subscription].self, from: data)) ?? []
    }

    func saveSubscriptions(_ subs: [Subscription]) {
        if let data = try? encoder.encode(subs) {
            defaults.set(data, forKey: subscriptionsKey)
        }
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey) else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: settingsKey)
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
        defaults.removeObject(forKey: subscriptionsKey)
        defaults.removeObject(forKey: settingsKey)
    }
}
