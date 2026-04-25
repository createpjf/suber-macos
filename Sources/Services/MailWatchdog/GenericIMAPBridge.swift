import Foundation

// ┌───────────── GenericIMAPBridge — IMAP4rev1 implementation of MailBridge ───┐
// │                                                                            │
// │  Slots into MailWatchdog the same way AppleMailBridge does, just talks     │
// │  IMAP-over-TLS instead of osascript. Wraps IMAPClient for the transport,  │
// │  maps Suber's domain types to/from IMAP commands.                          │
// │                                                                            │
// │  Constructor takes account config + a credential resolver closure (so      │
// │  tests can inject a stub password without going through Keychain).         │
// │                                                                            │
// │  D8 privacy: bodies fetched from IMAP go straight into the                 │
// │  MailMessage value type and fall out of scope after                        │
// │  MailSubscriptionExtractor processes them. NEVER persisted. Same           │
// │  contract as AppleMailBridge.                                              │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

final class GenericIMAPBridge: MailBridge {

    let account: IMAPAccount

    /// Resolves the App Password at scan time. Defaults to Keychain lookup;
    /// tests inject a fixed string. Lazy on purpose — credentials live as
    /// briefly as possible (resolve, use, drop reference).
    private let passwordResolver: () -> String?

    init(account: IMAPAccount,
         passwordResolver: (() -> String?)? = nil) {
        self.account = account
        if let resolver = passwordResolver {
            self.passwordResolver = resolver
        } else {
            // Default: read from Keychain at scan time.
            let email = account.email
            self.passwordResolver = { IMAPCredentialStore.load(email: email) }
        }
    }

    // MARK: - MailBridge

    /// Lightweight liveness check. Connects, logs in, logs out. If LOGIN
    /// succeeds we know:
    ///   (1) host/port reachable
    ///   (2) TLS works
    ///   (3) credentials valid
    /// Returns 1 (count of accounts — convention from MailBridge protocol;
    /// for IMAP we have one account per bridge instance).
    func ping(timeout: TimeInterval) async throws -> Int {
        guard let password = passwordResolver(), !password.isEmpty else {
            throw MailBridgeError.permissionDenied
        }
        let client = IMAPClient(host: account.host, port: account.port)
        do {
            try await client.connect(timeout: timeout)
            try await client.login(user: account.email, password: password, timeout: timeout)
            await client.close()
            return 1
        } catch {
            await client.close()
            throw error
        }
    }

    /// Scan: connect, login, SELECT mailbox, UID SEARCH SINCE date matching
    /// any keyword, FETCH bodies, parse → MailMessage.
    func scan(since: Date,
              keywords: [String],
              timeout: TimeInterval) async throws -> [MailMessage] {
        guard let password = passwordResolver(), !password.isEmpty else {
            throw MailBridgeError.permissionDenied
        }

        let deadline = Date().addingTimeInterval(timeout)
        let perCallTimeout = { max(deadline.timeIntervalSinceNow, 1) }

        let client = IMAPClient(host: account.host, port: account.port)

        do {
            try await client.connect(timeout: perCallTimeout())
            try await client.login(user: account.email, password: password, timeout: perCallTimeout())
            _ = try await client.select(mailbox: account.provider.scanMailbox, timeout: perCallTimeout())

            // Build the SEARCH criteria. IMAP date format: dd-Mon-yyyy.
            // SUBJECT criteria are AND'd by default — we want OR. So the
            // structure is `SINCE date (OR SUBJECT a (OR SUBJECT b SUBJECT c))`
            // — left-folded OR tree of SUBJECT clauses.
            let criteria = buildSearchCriteria(since: since, keywords: keywords)
            let uids = try await client.uidSearch(criteria, timeout: perCallTimeout())

            guard !uids.isEmpty else {
                await client.close()
                return []
            }

            let fetched = try await client.uidFetch(uids: uids, timeout: perCallTimeout())
            await client.close()

            // Map IMAPClient.FetchedMessage → MailMessage (the Suber domain type).
            return fetched.map { msg in
                MailMessage(
                    id: msg.messageID.isEmpty ? "imap-\(account.email)-\(msg.uid)" : msg.messageID,
                    account: account.email,
                    dateReceived: msg.date,
                    subject: msg.subject,
                    sender: msg.from,
                    body: msg.bodyText
                )
            }
        } catch let error as MailBridgeError {
            await client.close()
            throw error
        } catch {
            await client.close()
            // Map low-level Network errors to MailBridgeError so the state
            // machine can route correctly. Most failures during connect/login
            // either timed out or the credentials are wrong.
            let desc = error.localizedDescription.lowercased()
            if desc.contains("auth") || desc.contains("login") || desc.contains("password") {
                throw MailBridgeError.permissionDenied
            }
            throw MailBridgeError.unknown(error.localizedDescription)
        }
    }

    // MARK: - Search criteria builder

    /// Build IMAP UID SEARCH criteria for `SINCE <date> + any-keyword-match`.
    /// IMAP date format: `01-Mar-2026`. UTC-pinned so the SINCE filter is
    /// stable regardless of where the user's machine sits — IMAP servers
    /// interpret SINCE as a UTC day boundary anyway.
    /// Keywords go through OR-tree because SUBJECT criteria default-AND.
    func buildSearchCriteria(since: Date, keywords: [String]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "dd-MMM-yyyy"
        let dateStr = formatter.string(from: since)

        if keywords.isEmpty {
            return "SINCE \(dateStr)"
        }

        // Left-fold OR: keywords [a, b, c] → OR SUBJECT a (OR SUBJECT b SUBJECT c)
        let escaped = keywords.map { escapeSearchString($0) }
        let subjectTree = orFoldSubjects(escaped)
        return "SINCE \(dateStr) \(subjectTree)"
    }

    private func orFoldSubjects(_ keywords: [String]) -> String {
        switch keywords.count {
        case 0: return ""
        case 1: return "SUBJECT \(keywords[0])"
        default:
            // OR a (OR b (OR c d))
            var result = "SUBJECT \(keywords.last!)"
            for kw in keywords.dropLast().reversed() {
                result = "OR SUBJECT \(kw) \(result)"
            }
            return result
        }
    }

    /// IMAP SEARCH SUBJECT requires a quoted string. Escape inner quotes/backslashes.
    private func escapeSearchString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
