import Foundation
import SwiftUI

// ┌───────────── MailWatchdog — v1.6 Watch pillar ─────────────────────────────┐
// │                                                                            │
// │  State machine over a MailBridge. Ties together:                           │
// │    - Incremental scan cursors (per-account, persisted to UserDefaults)     │
// │    - NSBackgroundActivityScheduler (D2: power-aware 24h with ±2h tolerance)│
// │    - ChangeDetector (diff against known subs)                              │
// │    - SubscriptionStore.recordAndPersist (dedup + prune + notify)           │
// │    - NotificationService.scheduleImmediate (grouped body per scan run)     │
// │                                                                            │
// │  State transitions:                                                        │
// │                                                                            │
// │         ┌──────────── idle ────────────┐                                  │
// │         │   connectAppleMail() tap     │                                  │
// │         ▼                              ▼                                  │
// │  requestingPermission              scanNow()                              │
// │         │                              │                                  │
// │      grant│deny                   scan running                            │
// │         │ └─► permissionDenied    scanning(progress, messagesSeen)       │
// │         ▼                              │                                  │
// │      initial scan              done    │  bridge throws                  │
// │         │                       │      │    permissionDenied─► permissionDenied│
// │         ▼                       │      │    mailNotRunning──► error       │
// │       idle (with last scan)◄────┘      │    timeout────────► error (resume │
// │                                         │                      saved)     │
// │                                         └──► idle                         │
// │                                                                            │
// │  D2 scheduler: 24h interval ±2h tolerance; respects thermal/power/App Nap. │
// │  A single NSBackgroundActivityScheduler instance with id                   │
// │  "com.suber.mailwatchdog.daily". scheduleDailyScan() creates it on         │
// │  enable, cancelDailyScan() invalidates on disable.                         │
// │                                                                            │
// │  Callbacks to wire externally:                                             │
// │    - onScanComplete: called with scan summary + detected changes after     │
// │      every successful scan, so SuberApp can fire the grouped notification  │
// │      and route new changes into SubscriptionStore.                         │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

@MainActor
final class MailWatchdog: ObservableObject {

    // MARK: - State

    enum ScanState: Equatable {
        case idle
        case requestingPermission
        case scanning(progress: Double, messagesSeen: Int)
        case error(String)
        case permissionDenied
    }

    @Published private(set) var state: ScanState = .idle

    /// Wall-clock timestamp of the most recent scan completion, regardless of
    /// whether anything was found. nil if no scan has ever completed.
    @Published private(set) var lastCompletedAt: Date?

    /// Count of changes detected in the last completed scan (surfaced in
    /// Settings "Last scan: 2h ago · found 3 changes").
    @Published private(set) var lastScanChangesCount: Int = 0

    // MARK: - Dependencies (injected)

    private let bridge: MailBridge
    private let defaults: UserDefaults

    /// Called on a successful scan. Owner (SuberApp) uses this to:
    ///   - route detected changes into SubscriptionStore.recordAndPersist
    ///   - fire a single grouped notification via NotificationService
    var onScanComplete: ((ScanSummary, [SubscriptionChange]) async -> Void)?

    /// Read current subscriptions so ChangeDetector can diff against them.
    /// Injected as a closure so MailWatchdog doesn't pull a hard reference to
    /// SubscriptionStore (preserves testability).
    var loadExistingSubscriptions: () -> [Subscription] = { [] }

    // MARK: - Scheduler

    private var scheduler: NSBackgroundActivityScheduler?
    private static let schedulerIdentifier = "com.suber.mailwatchdog.daily"

    // MARK: - Constants

    /// D2: hard cap per scan. Exceeded → save resume cursor, abort, retry next scan.
    private let perScanTimeout: TimeInterval = 60

    /// Initial scan looks back this far. Later scans use the per-account cursor.
    private let initialScanLookbackDays: Int = 30

    private static let lastScanDateKey = "mailwatchdog.lastScanDate"
    private static let cursorPrefix = "mailwatchdog.cursor."

    // MARK: - Init

    init(
        bridge: MailBridge = AppleMailBridge(),
        // v1.6.2: Switched from `UserDefaults(suiteName: "group.com.suber.app")`
        // to `.standard` because the suite-name path triggered the macOS 26.4
        // (Tahoe) cfprefsd regression that fires `kTCCServiceSystemPolicyAppData`
        // ("data from other apps") prompt at launch. MailWatchdog cursors are
        // internal — the widget doesn't read them — so they don't need the
        // shared app-group container.
        defaults: UserDefaults = .standard
    ) {
        self.bridge = bridge
        self.defaults = defaults
        // Restore persisted lastCompletedAt so Settings shows the right
        // "Last scan: X ago" across app restarts.
        if let raw = defaults.object(forKey: Self.lastScanDateKey) as? TimeInterval,
           raw > 0 {
            self.lastCompletedAt = Date(timeIntervalSince1970: raw)
        }
    }

    // MARK: - First-run path

    /// Called when user flips the Watch Apple Mail toggle ON + confirms the
    /// consent sheet. Triggers the macOS TCC permission prompt on the first
    /// Apple Event Suber sends; subsequent calls return instantly.
    ///
    /// ⚠️ Uses a 60-second probe timeout, NOT the per-scan 60s budget. The
    /// macOS TCC prompt blocks osascript synchronously while the user reads
    /// and decides — humans take time. A 10s probe will kill the osascript
    /// process mid-prompt; the user sees it disappear without granting and
    /// thinks the connection failed. 60s is generous for the human in the
    /// loop without being insulting.
    ///
    /// On success → kick off the initial scan (which uses its own 60s budget
    /// per the `perScanTimeout` constant). On failure → map to specific state
    /// so the Settings banner can guide the user (.permissionDenied,
    /// .error("Mail not running"), or generic error).
    func connectAppleMail() async {
        state = .requestingPermission
        do {
            // Lightweight probe: just `count of accounts`. First time triggers
            // TCC; subsequent calls are instant. NOT an iterate-all-mailboxes
            // scan (which is heavyweight and can time out on large inboxes).
            _ = try await bridge.ping(timeout: 60)

            // Permission granted. Kick off the initial scan.
            state = .idle
            do {
                _ = try await scanNow()
            } catch {
                // scanNow handled its own state; don't override.
            }
        } catch MailBridgeError.permissionDenied {
            state = .permissionDenied
        } catch MailBridgeError.mailNotRunning {
            state = .error("Mail not running — open Mail.app once, then tap Scan now.")
        } catch MailBridgeError.timeout {
            // TCC prompt was up but timed out — user took too long, OR Mail
            // isn't responding. Either way the right next step is "try again".
            state = .error("Connection timed out. Make sure Mail.app is open and try again.")
        } catch {
            state = .error(humanMessage(from: error))
        }
    }

    // MARK: - Manual / scheduled scan

    /// Run a scan now. Returns the summary on success; throws on failure.
    /// Safe to call repeatedly — ignores the call if already scanning.
    @discardableResult
    func scanNow() async throws -> ScanSummary {
        // Don't stack scans. If one is already running, bail.
        if case .scanning = state { throw MailBridgeError.unknown("scan already in progress") }

        let startedAt = Date()
        state = .scanning(progress: 0, messagesSeen: 0)

        do {
            // Per-account since-dates come from the persisted cursors. For the
            // initial scan (no cursor yet), use lookbackDays.
            let since = oldestSinceDate()
            let messages = try await bridge.scan(
                since: since,
                keywords: MailScanKeywords.all,
                timeout: perScanTimeout
            )

            state = .scanning(progress: 0.5, messagesSeen: messages.count)

            // Extract candidate subscriptions from the message bodies. D8:
            // messages fall out of scope after this, body text never hits disk.
            let candidates = MailSubscriptionExtractor.extract(from: messages)

            // Diff against known subs.
            let existing = loadExistingSubscriptions()
            let changes = ChangeDetector.diff(
                incoming: candidates,
                against: existing,
                priorRun: nil,
                source: .mailWatchdog
            )

            // Update per-account cursors to the most-recent message ID per
            // account so next scan is incremental.
            let cursors = computeCursors(from: messages)
            persistCursors(cursors)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastScanDateKey)

            let summary = ScanSummary(
                startedAt: startedAt,
                completedAt: Date(),
                messagesScanned: messages.count,
                changesDetected: changes.count,
                resumeCursors: cursors
            )

            // Hand off to the app-level scan-completion hook (which runs
            // recordAndPersist + notification + auto-transition check per P1).
            await onScanComplete?(summary, changes)

            lastCompletedAt = summary.completedAt
            lastScanChangesCount = changes.count
            state = .idle

            return summary
        } catch MailBridgeError.permissionDenied {
            state = .permissionDenied
            throw MailBridgeError.permissionDenied
        } catch MailBridgeError.mailNotRunning {
            state = .error("Mail not running — open Mail.app once, then tap Scan now.")
            throw MailBridgeError.mailNotRunning
        } catch MailBridgeError.timeout(let cursors) {
            // Save whatever we got. Next scan picks up from here.
            persistCursors(cursors)
            state = .error("Scan timed out — will retry in the background.")
            throw MailBridgeError.timeout(resumeToken: cursors)
        } catch {
            state = .error(humanMessage(from: error))
            throw error
        }
    }

    // MARK: - NSBackgroundActivityScheduler (D2)

    /// Install the daily scheduler. Safe to call multiple times; reinstalls
    /// if already scheduled. No-op if already running the same identifier.
    func scheduleDailyScan() {
        cancelDailyScan()   // invalidate any previous instance first

        let scheduler = NSBackgroundActivityScheduler(identifier: Self.schedulerIdentifier)
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60       // 24h
        scheduler.tolerance = 2 * 60 * 60       // ±2h
        scheduler.qualityOfService = .utility    // low priority; yields to user work
        scheduler.schedule { [weak self] completion in
            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.scanNow()
                } catch {
                    // Logged via state; scheduler finishes regardless.
                }
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    /// Tear down the scheduler (user disabled Watch Apple Mail).
    func cancelDailyScan() {
        scheduler?.invalidate()
        scheduler = nil
    }

    // MARK: - Cursor management

    /// Per-account cursor keys: `mailwatchdog.cursor.<account>` → message-id string.
    /// We store message IDs (not dates) so the next scan can strictly filter
    /// past them without re-reading messages.
    private func persistCursors(_ cursors: [String: String]) {
        for (account, messageID) in cursors {
            defaults.set(messageID, forKey: Self.cursorPrefix + account)
        }
    }

    /// Compute per-account most-recent message ID from the current scan batch.
    private func computeCursors(from messages: [MailMessage]) -> [String: String] {
        var byAccount: [String: MailMessage] = [:]
        for msg in messages {
            if let prev = byAccount[msg.account] {
                if msg.dateReceived > prev.dateReceived { byAccount[msg.account] = msg }
            } else {
                byAccount[msg.account] = msg
            }
        }
        return byAccount.mapValues { $0.id }
    }

    /// Oldest "since" date across all accounts. Used as the bridge's scan
    /// cutoff (we over-fetch, then filter in-proc by account cursors).
    private func oldestSinceDate() -> Date {
        // On first scan: lookback from now.
        let persistedTS = defaults.double(forKey: Self.lastScanDateKey)
        if persistedTS == 0 {
            return Calendar.current.date(byAdding: .day, value: -initialScanLookbackDays, to: Date())!
        }
        // Subsequent scan: use lastScanDate minus 1 day (safety margin for
        // clock skew / delayed delivery). Incremental cursor filtering
        // happens server-side via the predicate's date-received comparison.
        return Date(timeIntervalSince1970: persistedTS).addingTimeInterval(-86_400)
    }

    // MARK: - Error copy

    private func humanMessage(from error: Error) -> String {
        if let bridge = error as? MailBridgeError {
            switch bridge {
            case .permissionDenied: return "Suber can't access Mail. Open System Settings to allow it."
            case .mailNotRunning:   return "Mail not running — open Mail.app once, then tap Scan now."
            case .noAccountsConfigured: return "No Mail accounts configured."
            case .timeout:          return "Scan timed out — will retry in the background."
            case .unknown(let m):   return m
            }
        }
        return error.localizedDescription
    }
}
