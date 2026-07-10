import Foundation

// ┌───────────── AppleMailBridge — osascript implementation ───────────────────┐
// │                                                                            │
// │  Concrete MailBridge that runs AppleScript against Mail.app via osascript. │
// │  First call triggers macOS TCC Apple Events prompt ("Allow Suber to        │
// │  control Mail?"). Permission persists until user revokes in System         │
// │  Settings → Privacy & Security → Automation.                               │
// │                                                                            │
// │  Predicate shape (verified in Slice 1 load-bearing gate):                  │
// │    tell application "Mail"                                                 │
// │      repeat with acct in accounts                                          │
// │        repeat with mbox in mailboxes of acct                               │
// │          messages of mbox whose                                            │
// │            (date received > since) and                                     │
// │            (subject contains "receipt" or ... or ...)                       │
// │        end repeat                                                          │
// │      end repeat                                                            │
// │    end tell                                                                │
// │                                                                            │
// │  If Slice 1's benchmark exposed predicate push-down as broken, the full   │
// │  Watchdog design switches to "fetch all message-IDs since cursor, filter   │
// │  in Swift" — THIS FILE is where that alt-implementation would live.        │
// │  Document the decision here when you run the benchmark.                    │
// │                                                                            │
// │  Output format: one message per line, ASCII-safe delimiters between        │
// │  fields. We can't rely on AppleScript JSON (old systems lack `NSJSON`      │
// │  Script Suite support), so we use a well-defined record separator.        │
// │                                                                            │
// │    <id>\u{001F}<account>\u{001F}<iso-date>\u{001F}<subject>\u{001F}<sender>\u{001F}<body>\u{001E}│
// │                                                                            │
// │  (U+001F = field sep, U+001E = record sep — ASCII control chars never     │
// │  appear in real email text.)                                               │
// └────────────────────────────────────────────────────────────────────────────┘

final class AppleMailBridge: MailBridge {

    // ASCII control chars as delimiters — never appear in real subject/body text.
    private static let fieldSep = "\u{001F}"   // unit separator
    private static let recordSep = "\u{001E}"  // record separator

    // MARK: - Liveness probe (TCC trigger)

    /// Sends the smallest possible Apple Event to Mail — `count of accounts`.
    /// First-time call triggers the macOS TCC prompt; subsequent calls are
    /// instant. Used by `MailWatchdog.connectAppleMail` to detect permission
    /// without iterating mailboxes (which is heavyweight + can time out).
    func ping(timeout: TimeInterval) async throws -> Int {
        let script = """
        tell application "Mail"
            return (count of accounts) as string
        end tell
        """
        let output: String
        do {
            output = try await runOSAScript(script, timeout: timeout)
        } catch let error as MailBridgeError {
            throw error
        } catch {
            throw MailBridgeError.unknown(error.localizedDescription)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? 0
    }

    // MARK: - Full scan

    func scan(
        since: Date,
        keywords: [String],
        timeout: TimeInterval
    ) async throws -> [MailMessage] {
        // Build the AppleScript program text.
        let script = buildScript(since: since, keywords: keywords)

        // Run osascript with a wall-clock timeout. If we hit it, throw .timeout
        // with an empty resume token (we'll implement partial-progress resume
        // in a follow-up — Slice 5 ships the full scan path for correctness).
        let output: String
        do {
            output = try await runOSAScript(script, timeout: timeout)
        } catch let error as MailBridgeError {
            throw error
        } catch {
            throw MailBridgeError.unknown(error.localizedDescription)
        }

        return parseOutput(output)
    }

    // MARK: - AppleScript program

    private func buildScript(since: Date, keywords: [String]) -> String {
        // Format date as AppleScript's native `date "..."` literal. AppleScript
        // accepts locale-dependent strings; stick to ISO-ish to avoid parsing
        // quirks across en-US / zh-Hans system locales.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        let sinceStr = df.string(from: since)

        // Build (subject contains "a" or subject contains "b" or ...) clauses.
        // Escape each keyword's double-quotes defensively (shouldn't appear in
        // practice, but we don't want AppleScript-injected surprises).
        let clauses = keywords
            .map { "subject contains \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: " or ")

        return """
        set results to ""
        set sinceDate to (date "\(sinceStr)")
        tell application "Mail"
            repeat with acct in accounts
                set acctName to name of acct
                repeat with mbox in mailboxes of acct
                    try
                        set matched to (messages of mbox whose ¬
                            (date received > sinceDate) and ¬
                            (\(clauses)))
                        repeat with msg in matched
                            set msgID to (message id of msg as string)
                            set msgDate to (date received of msg as string)
                            set msgSubject to (subject of msg as string)
                            set msgSender to (sender of msg as string)
                            try
                                set msgBody to (content of msg as string)
                            on error
                                set msgBody to ""
                            end try
                            set results to results & msgID & "\(Self.fieldSep)" & ¬
                                acctName & "\(Self.fieldSep)" & ¬
                                msgDate & "\(Self.fieldSep)" & ¬
                                msgSubject & "\(Self.fieldSep)" & ¬
                                msgSender & "\(Self.fieldSep)" & ¬
                                msgBody & "\(Self.recordSep)"
                        end repeat
                    on error errMsg number errNum
                        -- Ignore per-mailbox failures (e.g. sync in progress).
                        -- Continue so we collect what we can.
                    end try
                end repeat
            end repeat
        end tell
        return results
        """
    }

    // MARK: - osascript runner

    /// Internal (not private) so tests can regression-check the large-output
    /// path without driving a full scan (AUDIT-v1.9.2 C-07).
    func runOSAScript(_ script: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MailBridgeError.unknown("failed to launch osascript: \(error.localizedDescription)")
        }

        // AUDIT-v1.9.2 C-07: drain stdout/stderr WHILE osascript runs. Reading
        // only after exit deadlocks: once script output exceeds the ~64 KB
        // kernel pipe buffer, osascript blocks on write and never exits.
        let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
        let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

        // Wait with timeout. If timeout fires, terminate the process and throw.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw MailBridgeError.timeout(resumeToken: [:])
            }
            // Yield. 50ms poll — small enough to feel snappy on cancellation,
            // long enough that we don't burn CPU waiting on AppleScript.
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let status = process.terminationStatus
        let stdoutData = await stdoutTask.value
        let stderrData = await stderrTask.value
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        if status != 0 {
            // Classify common TCC / Mail errors so MailWatchdog can route to
            // the right UI state.
            let lower = stderrStr.lowercased()
            if lower.contains("not authorized") || lower.contains("not allowed") || lower.contains("1743") {
                throw MailBridgeError.permissionDenied(detail: nil)
            }
            if lower.contains("can\u{2019}t get application") || lower.contains("can't get application") ||
               lower.contains("connection is invalid") || lower.contains("-600") {
                throw MailBridgeError.mailNotRunning
            }
            throw MailBridgeError.unknown(stderrStr.isEmpty ? "osascript exit \(status)" : stderrStr)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    // MARK: - Output parsing

    /// Parse the record-separated output into [MailMessage]. Safe against
    /// malformed lines (skips them; never throws for parse errors).
    func parseOutput(_ raw: String) -> [MailMessage] {
        guard !raw.isEmpty else { return [] }
        // Mail.app's `date received as string` returns locale-formatted dates
        // like "Sunday, March 16, 2025 at 10:24:33 PM". NSDataDetector is the
        // single, explicit parse path — the unconfigured DateFormatter that
        // used to sit in front of it never matched (AUDIT-v1.9.2 C-25).
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

        return raw.components(separatedBy: Self.recordSep)
            .compactMap { record -> MailMessage? in
                let fields = record.components(separatedBy: Self.fieldSep)
                guard fields.count >= 6 else { return nil }
                let id = fields[0]
                let account = fields[1]
                let dateStr = fields[2]
                let subject = fields[3]
                let sender = fields[4]
                let body = fields[5]
                guard !id.isEmpty else { return nil }

                let date: Date
                if let match = detector?.firstMatch(
                    in: dateStr,
                    range: NSRange(dateStr.startIndex..., in: dateStr)
                ), let d = match.date {
                    date = d
                } else {
                    // Can't parse date → skip (we can't tell if it's in scan window).
                    return nil
                }

                return MailMessage(
                    id: id, account: account, dateReceived: date,
                    subject: subject, sender: sender, body: body
                )
            }
    }
}
