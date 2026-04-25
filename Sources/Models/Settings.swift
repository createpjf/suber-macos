import Foundation

struct AppSettings: Codable, Equatable {
    var primaryCurrency: String = "USD"
    var reminderDaysBefore: [Int] = [1, 3]
    var enableNotifications: Bool = true
    var launchAtLogin: Bool = false
    var enableCloudSync: Bool = false
    /// v1.6: in-app language override. "system" = follow macOS Preferred
    /// Languages (default behavior). "en" / "zh-Hans" = force that locale
    /// via `AppleLanguages` UserDefaults override. Requires a restart of
    /// Suber to fully take effect (NSLocalizedString-cached strings only
    /// re-resolve at process launch).
    ///
    /// v1.5 default was "en"; we honor that as a coercion to "system" on
    /// first read so existing users default to system locale. New installs
    /// default to "system" via the AppSettings init().
    var language: String = "system"

    // v1.6 Autopilot. Nested so v1.5 clients reading v1.6 payloads can ignore
    // the whole block, and v1.6 reading v1.5 gets the defaults.
    var autopilot: AutopilotSettings = AutopilotSettings()

    // Forward-compat custom decoder: v1.5 payloads don't have the `autopilot`
    // key; defaultIfMissing keeps this non-crashing across sync boundaries.
    enum CodingKeys: String, CodingKey {
        case primaryCurrency, reminderDaysBefore, enableNotifications
        case launchAtLogin, enableCloudSync, language, autopilot
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryCurrency = try c.decodeIfPresent(String.self, forKey: .primaryCurrency) ?? "USD"
        reminderDaysBefore = try c.decodeIfPresent([Int].self, forKey: .reminderDaysBefore) ?? [1, 3]
        enableNotifications = try c.decodeIfPresent(Bool.self, forKey: .enableNotifications) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        enableCloudSync = try c.decodeIfPresent(Bool.self, forKey: .enableCloudSync) ?? false
        // Coerce v1.5's default "en" → "system" so existing users see no
        // change in behavior. They'll opt back into forced English via the
        // new picker if they actually want override.
        let raw = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        language = (raw == "en" && !c.contains(.autopilot)) ? "system" : raw
        autopilot = try c.decodeIfPresent(AutopilotSettings.self, forKey: .autopilot) ?? AutopilotSettings()
    }
}

/// v1.6 Autopilot section (Settings → Autopilot).
///
/// Design review D6 (I3): two groups — "Apple Mail" (connection) and "Alert me
/// about" (behavior). Defaults chosen per the design-review pass: Watch OFF
/// (opt-in), price/newSub ON, duplicate OFF (noisy).
struct AutopilotSettings: Codable, Equatable {
    /// Master toggle. Off on fresh install — user must explicitly opt in via
    /// Settings → Autopilot. Flipping true triggers the consent sheet, then
    /// the TCC permission prompt via MailWatchdog.connectAppleMail().
    var watchAppleMail: Bool = false

    // "Alert me about" toggles. What the Change Sentinel surfaces to the user.
    var alertOnPriceChanges: Bool = true
    var alertOnNewSubscriptions: Bool = true
    /// Default OFF per D6 — "can be noisy; leave off unless you've seen dupes."
    var alertOnDuplicates: Bool = false
}
