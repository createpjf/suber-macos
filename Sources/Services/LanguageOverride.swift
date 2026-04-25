import Foundation

// ┌───────────── LanguageOverride — v1.6 in-app language switcher ─────────────┐
// │                                                                            │
// │  Bridges `AppSettings.language` (user preference) with the                 │
// │  `AppleLanguages` UserDefaults key that Foundation reads at process        │
// │  launch to pick which `.lproj` bundle to resolve strings from.             │
// │                                                                            │
// │  Why a restart is required:                                                │
// │    Foundation caches the locale's bundle resolution very early in process  │
// │    startup. SwiftUI views that render `Text("Connect Apple Mail")` look up │
// │    the `Localizable.strings` table once, then reuse that lookup. Changing  │
// │    `AppleLanguages` after launch flips the lookup table for NEW NSBundle   │
// │    queries but doesn't invalidate already-cached strings, so the UI ends   │
// │    up half-translated. The clean answer: write the override, prompt the    │
// │    user to restart, take effect uniformly on next launch.                  │
// │                                                                            │
// │  Pattern matches macOS norms: System Settings → Language & Region also     │
// │  requires a logout/login to fully apply. Suber's restart is much lighter.  │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum LanguageOverride {

    /// Possible values for `AppSettings.language`.
    enum Choice: String, CaseIterable, Identifiable {
        case system   = "system"
        case english  = "en"
        case chinese  = "zh-Hans"

        var id: String { rawValue }

        /// Human-readable label, IN THE TARGET LANGUAGE so users find their
        /// language regardless of which one is currently active. Pattern
        /// matches Mac System Settings' language picker.
        var displayName: String {
            switch self {
            case .system:  return "System default"
            case .english: return "English"
            case .chinese: return "简体中文"
            }
        }
    }

    /// Apply the user's choice to UserDefaults so it takes effect at the
    /// next app launch. Idempotent — safe to call repeatedly.
    static func apply(_ choice: Choice, defaults: UserDefaults = .standard) {
        switch choice {
        case .system:
            // Remove the override so Foundation falls back to the system
            // Preferred Languages order (default macOS behavior).
            defaults.removeObject(forKey: "AppleLanguages")
        case .english, .chinese:
            // Force this locale across all bundle lookups at next launch.
            defaults.set([choice.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Read the current effective override (what the next launch would use).
    /// Returns `.system` when no override is set.
    static func current(defaults: UserDefaults = .standard) -> Choice {
        guard let raw = defaults.array(forKey: "AppleLanguages") as? [String],
              let first = raw.first
        else { return .system }
        // Coerce "zh-Hans-CN" → "zh-Hans" etc.
        if first.hasPrefix("zh-Hans") { return .chinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// True if applying `desired` would change the next-launch behavior from
    /// what's currently effective. Used by the Settings picker to decide
    /// whether to show the "Restart Suber" prompt.
    static func wouldRequireRestart(currentSetting: Choice, newSetting: Choice) -> Bool {
        return currentSetting != newSetting
    }

    /// Trigger a clean process restart. macOS doesn't have a single
    /// `relaunch yourself` API; the standard pattern is to spawn a small
    /// shell helper that waits for our PID to exit, then opens our bundle
    /// again, and we exit immediately.
    static func relaunch() {
        guard let bundlePath = Bundle.main.bundleURL.path as String? else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        // Tiny launchd-friendly relauncher: wait for our PID, then reopen us.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open '\(bundlePath)'"
        ]
        do {
            try task.run()
        } catch {
            NSLog("Suber: relaunch failed: \(error.localizedDescription)")
            return
        }
        // Hand control back to AppKit for graceful shutdown. The shell helper
        // is detached and will fire after we exit.
        exit(0)
    }
}
