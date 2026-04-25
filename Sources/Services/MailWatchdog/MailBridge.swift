import Foundation

// ┌───────────── MailBridge — the testable seam (D7 protocol) ─────────────────┐
// │                                                                            │
// │  MailWatchdog depends on this protocol, not AppleMailBridge directly, so   │
// │  unit tests can drive the state machine with canned messages and injected  │
// │  errors (timeout, permission denied, Mail not running) without poking      │
// │  live Apple Events.                                                        │
// │                                                                            │
// │  Production:  `AppleMailBridge` — osascript wrapper, goes through TCC.     │
// │  Tests:       `StubMailBridge` (in Tests/) — returns the messages you set. │
// │                                                                            │
// │  Scan contract:                                                            │
// │    - Filter by `since`: messages received AFTER this date (strict >)       │
// │    - Filter by `keywords`: subject-line substring match, any keyword OR'd  │
// │    - Respect `timeout`: throw MailBridgeError.timeout if scan exceeds it   │
// │    - D8 policy: returned MailMessages carry raw body for extraction.       │
// │      Caller (MailWatchdog) extracts then lets them fall out of scope —     │
// │      the extractor NEVER persists body text.                               │
// │                                                                            │
// │  Errors are explicit so the state machine can transition correctly:        │
// │    - .permissionDenied      → MailWatchdog.state = .permissionDenied       │
// │    - .mailNotRunning        → MailWatchdog.state = .error("mail not running")│
// │    - .timeout(resumeToken:) → saves resume cursor, scan aborts             │
// │    - .unknown               → generic error state                          │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// One Mail message, value type, scoped to a single scan(...) call.
/// Never persisted. Only the extracted CandidateSubscription (amount, date,
/// merchant) reaches StorageService.
struct MailMessage: Equatable {
    /// Stable Apple Mail message ID (e.g. "<x@y>"). Used as the resume cursor
    /// for incremental scans.
    let id: String
    /// Account the message belongs to (for per-account cursor persistence).
    let account: String
    /// When the message was received.
    let dateReceived: Date
    let subject: String
    let sender: String
    /// Plain-text body. Caller MUST NOT persist this — D8 policy.
    let body: String
}

/// Errors a MailBridge may throw. Each one maps to a specific state transition
/// in MailWatchdog so the UI can show the right error affordance.
enum MailBridgeError: Error, Equatable {
    /// User denied the TCC Apple Events prompt. Recoverable via System Settings.
    case permissionDenied
    /// Mail.app isn't running (no accounts available to query).
    case mailNotRunning
    /// No accounts configured in Mail.app.
    case noAccountsConfigured
    /// Scan exceeded `timeout`. Resume token is the last-successfully-scanned
    /// message ID per account; the next scan starts from there.
    case timeout(resumeToken: [String: String])
    /// Anything else (osascript syntax error, AppleScript engine fault, etc.)
    case unknown(String)
}

/// Protocol boundary. Implementers see subject-line keywords only — no body
/// scanning at the bridge level. Body scanning belongs to the extractor.
protocol MailBridge {
    /// Lightweight liveness check. Sends the smallest possible Apple Event
    /// to Mail (`count of accounts`) — used by `MailWatchdog.connectAppleMail`
    /// to trigger the macOS TCC permission prompt without iterating mailboxes.
    ///
    /// The TCC prompt blocks osascript synchronously while the user reads it,
    /// so callers should pass a generous timeout (60s+) — humans take time to
    /// read + decide. A short timeout will kill the prompt mid-read and the
    /// user will see it disappear without granting.
    ///
    /// - Returns: number of configured Mail accounts (0+). Doesn't matter
    ///   semantically — we use the call's success/failure to detect TCC state.
    /// - Throws: `.permissionDenied` if user denied; `.mailNotRunning` if Mail
    ///   isn't reachable; `.timeout` if it took too long; `.unknown` otherwise.
    func ping(timeout: TimeInterval) async throws -> Int

    /// Scan Mail for messages matching subject keywords since `since`.
    ///
    /// - Parameters:
    ///   - since: per-account cutoff. Messages received on or before this date
    ///     are skipped. For initial scan, use `.distantPast` minus N days via
    ///     Calendar math at the caller site.
    ///   - keywords: subject-line substrings. OR'd together — any one matches.
    ///     H1 (eng re-review): these are domain constants, NOT user-facing
    ///     strings. Do not pull them into a String Catalog.
    ///   - timeout: max wall-clock seconds for the whole scan. Bridge throws
    ///     `.timeout(resumeToken:)` if exceeded.
    /// - Returns: matching messages. Empty array is a valid "clean scan" result.
    func scan(since: Date, keywords: [String], timeout: TimeInterval) async throws -> [MailMessage]
}

/// Summary of one scan pass — surfaced to the UI (Settings "Last scan: …")
/// and to NotificationService for the grouped body composition.
struct ScanSummary: Equatable {
    let startedAt: Date
    let completedAt: Date
    let messagesScanned: Int
    let changesDetected: Int
    /// Per-account (message-ID) cursor at the end of the scan. Persisted so
    /// the NEXT scan can query `since = matching message's dateReceived`.
    let resumeCursors: [String: String]
}

// MARK: - H1 (eng re-review): extractor keywords are NOT user-facing strings
//
// These subject-line substrings drive the Mail scan predicate. They are
// MATCHING HEURISTICS, not UI copy. Must NOT be pulled into Localizable.xcstrings
// — if a translator localized "receipt" → "reçu", the English-receipt Netflix
// emails would stop matching. Keep them as Swift string literals with the
// sentinel comment below; LocalizationCatalogTests (Slice 8) will assert no
// catalog key matches these literals.
//
// NSLocalizedString ignore — DO NOT localize (extractor keywords)
enum MailScanKeywords {
    /// English + Simplified Chinese keyword set. Matches billing receipts,
    /// trial-ending notices, and renewal confirmations across the two locales.
    /// Keep this array small; every additional keyword broadens the scan
    /// and risks false-positives that the extractor then has to reject.
    static let all: [String] = [
        "receipt",
        "subscription",
        "renewal",
        "发票",      // "invoice"
        "订阅",      // "subscription"
        "续费",      // "renewal"
    ]
}
