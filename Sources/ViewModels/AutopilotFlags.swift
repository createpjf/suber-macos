import Foundation
import SwiftUI

// ┌───────────── AutopilotFlags — v1.6 UI-state flags ─────────────────────────┐
// │                                                                            │
// │  Typed wrapper over the `autopilot.*` UserDefaults namespace.              │
// │                                                                            │
// │  A2 (eng re-review): catches typos at compile time. Single audit site      │
// │  for "what state does Autopilot persist."                                  │
// │                                                                            │
// │  H4 (eng re-review outside voice): `@AppStorage` does NOT support          │
// │  `Date?` cleanly — the RawRepresentable path Apple supports only works     │
// │  for non-optional Date, and wrapping `Date?` requires an extra layer.      │
// │  Pattern: back Date? values with a Double TimeInterval (default 0 = nil    │
// │  sentinel), expose Date? via computed getter/setter. Round-trips cleanly,  │
// │  stays typo-safe, and SwiftUI views that observe the wrapped Double will   │
// │  still re-render when the Date? "changes."                                 │
// │                                                                            │
// │  Consumers:                                                                │
// │    - BannerCoordinator (A1): reads hasSeenFirstCatch, lastBannerShownAt,   │
// │      lastCelebrationAckedAt to pick which banner to show                   │
// │    - ChangesWindowEmptyView: reads hasSeenFirstScan                        │
// │    - SubscriptionStore: writes hasSeenFirstScan on first scan completion   │
// │                                                                            │
// │  NOT here: MailWatchdog's per-account scan cursors                         │
// │  (lastScannedMessageID, lastScanDate). Different domain, scoped to         │
// │  MailWatchdog. Mixing them here would conflate UI-state with scan-state.   │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// Typed wrapper over Autopilot UI-state UserDefaults.
///
/// Usage:
///     struct MyView: View {
///         @StateObject private var flags = AutopilotFlags()
///         var body: some View {
///             if !flags.hasSeenFirstCatch { FirstCatchBanner(...) }
///         }
///     }
///
/// Or as a plain value object (non-SwiftUI call sites):
///     let flags = AutopilotFlags()
///     if flags.hasSeenFirstScan { ... }
@MainActor
final class AutopilotFlags: ObservableObject {

    // MARK: - Keys (namespaced under "autopilot.*")

    enum Key {
        static let hasSeenFirstScan  = "autopilot.hasSeenFirstScan"
        static let hasSeenFirstCatch = "autopilot.hasSeenFirstCatch"
        static let lastBannerShownAt = "autopilot.lastBannerShownAt"
        static let lastCelebrationAckedAt = "autopilot.lastCelebrationAckedAt"
    }

    // MARK: - Storage

    private let defaults: UserDefaults

    /// Inject a UserDefaults (use `.init(suiteName:)` for tests to avoid
    /// polluting the real app group's state).
    init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.suber.app") ?? .standard) {
        self.defaults = defaults
    }

    // MARK: - Bool flags

    /// True once the first Mail scan has completed (regardless of finding
    /// anything). Gates first-run empty state vs "You're all caught up."
    var hasSeenFirstScan: Bool {
        get { defaults.bool(forKey: Key.hasSeenFirstScan) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.hasSeenFirstScan)
        }
    }

    /// True once the FirstCatchBanner has been shown and dismissed.
    /// Fires exactly once per app lifetime.
    var hasSeenFirstCatch: Bool {
        get { defaults.bool(forKey: Key.hasSeenFirstCatch) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.hasSeenFirstCatch)
        }
    }

    // MARK: - Date? (TimeInterval-backed, H4 fix)

    /// Last time the "Since you were away" banner was shown. nil = never.
    /// Used by BannerCoordinator for once-per-day gating.
    var lastBannerShownAt: Date? {
        get { dateFromRaw(key: Key.lastBannerShownAt) }
        set { setRaw(key: Key.lastBannerShownAt, date: newValue) }
    }

    /// Last time the user dismissed a CancellationSuccessBanner.
    /// Used to collapse same-day multi-confirmation into one banner view.
    var lastCelebrationAckedAt: Date? {
        get { dateFromRaw(key: Key.lastCelebrationAckedAt) }
        set { setRaw(key: Key.lastCelebrationAckedAt, date: newValue) }
    }

    // MARK: - Date? ↔ TimeInterval helpers

    /// UserDefaults stores TimeInterval 0.0 = nil sentinel. Date(timeIntervalSince1970: 0)
    /// is 1970-01-01 UTC — safe as sentinel since no real value would ever
    /// fall there (all usage is "recent past / near future").
    private func dateFromRaw(key: String) -> Date? {
        let raw = defaults.double(forKey: key)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    private func setRaw(key: String, date: Date?) {
        objectWillChange.send()
        defaults.set(date?.timeIntervalSince1970 ?? 0, forKey: key)
    }

    // MARK: - Testing helpers

    /// Wipes every autopilot.* key. Test-only.
    func resetForTests() {
        defaults.removeObject(forKey: Key.hasSeenFirstScan)
        defaults.removeObject(forKey: Key.hasSeenFirstCatch)
        defaults.removeObject(forKey: Key.lastBannerShownAt)
        defaults.removeObject(forKey: Key.lastCelebrationAckedAt)
    }
}
