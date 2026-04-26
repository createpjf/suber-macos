import Foundation
import Network

// ┌───────────── IMAPClient — minimal IMAP4rev1 over TLS ──────────────────────┐
// │                                                                            │
// │  Implements just the subset Suber needs:                                   │
// │    LOGIN <user> <password>            authenticate                         │
// │    SELECT <mailbox>                    open mailbox for reading            │
// │    UID SEARCH <criteria>               find matching message UIDs          │
// │    UID FETCH <uids> <parts>            pull subjects + bodies              │
// │    LOGOUT                              clean disconnect                    │
// │                                                                            │
// │  Why hand-roll IMAP rather than pull in MailCore2 / SwiftMailCore?         │
// │    The full IMAP4rev1 spec is huge; we don't need it. Hand-rolling 5       │
// │    commands is ~500 lines and avoids dragging in C++/Obj-C dependencies    │
// │    that would otherwise be the only non-Swift code in Suber. Keeps the    │
// │    notarization story simple: 100% Swift, 100% first-party. If we ever    │
// │    need APPEND / IDLE / extensions, switch to MailCore2 then.              │
// │                                                                            │
// │  Implementation notes:                                                     │
// │    - All commands are TAGGED — server replies with the tag in the final   │
// │      OK/NO/BAD line. We track outstanding tags by a monotonic counter.    │
// │    - Server can interleave UNTAGGED data lines (starting with `*`) with   │
// │      a tagged final response. We accumulate untagged into the response.   │
// │    - FETCH bodies arrive as IMAP literals: `{NNN}\r\n<NNN bytes>` after   │
// │      which response parsing resumes. We read exactly NNN bytes raw, not   │
// │      line-by-line.                                                        │
// │    - All I/O uses Network framework's NWConnection over TLS to port 993.  │
// │    - Errors map to MailBridgeError so MailWatchdog's state machine can    │
// │      route to the right UI affordance (.permissionDenied for auth fail,  │
// │      .timeout for hung reads, etc.).                                      │
// │                                                                            │
// │  D8 privacy: bodies fetched by this client live in `FetchedMessage`       │
// │  values that are scoped to a single scan() call in the bridge. They       │
// │  fall out of scope once `MailSubscriptionExtractor.extract` runs, and    │
// │  never reach StorageService. Same contract as AppleMailBridge.           │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// One-shot IMAP session. Construct → connect → login → operate → logout/close.
/// Not designed for long-lived connections (we open a fresh session per scan).
actor IMAPClient {

    // MARK: - Configuration

    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    // MARK: - State

    private var connection: NWConnection?
    private var nextTagNumber: Int = 1
    /// Buffered bytes from the server that haven't been parsed into lines yet.
    /// IMAP responses can split mid-CRLF across NWConnection.receive callbacks.
    private var receiveBuffer: Data = Data()

    // MARK: - Lifecycle

    /// Establish TLS connection + read server greeting. Greeting line starts
    /// with `* OK ...` for normal servers; some return `* PREAUTH` if the
    /// connection is already authenticated (rare, e.g. localhost dovecot
    /// with auth_anonymous, not relevant for Gmail/iCloud).
    func connect(timeout: TimeInterval) async throws {
        guard connection == nil else { return }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 993
        )
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = Int(timeout)
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let conn = NWConnection(to: endpoint, using: parameters)
        connection = conn

        // Wait for ready state. v1.7: IMAPContinuationGuard provides the
        // race-safe one-shot resume primitive (see that file for context).
        // RES-01: clear stateUpdateHandler on success so the captured closure
        //         doesn't outlive the connect() return.
        // IMAP-03: cancel the NWConnection in the timeout branch so a stuck
        //          TLS handshake doesn't leave a zombie socket behind.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guarded = IMAPContinuationGuard(continuation)

            conn.stateUpdateHandler = { [weak conn] state in
                switch state {
                case .ready:
                    conn?.stateUpdateHandler = nil   // RES-01
                    guarded.resumeSuccess()
                case .failed(let error):
                    guarded.resume(throwing: MailBridgeError.unknown("IMAP connect failed: \(error.localizedDescription)"))
                case .cancelled:
                    guarded.resume(throwing: MailBridgeError.unknown("IMAP connection cancelled"))
                default:
                    break
                }
            }

            conn.start(queue: .global(qos: .utility))

            // Hard wall-clock timeout.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak conn] in
                conn?.cancel()                       // IMAP-03
                guarded.resume(throwing: MailBridgeError.timeout(resumeToken: [:]))
            }
        }

        // Read the server greeting line. Discard.
        _ = try await readUntaggedResponseLine(timeout: timeout)
    }

    /// Send LOGOUT and close. Best-effort; doesn't throw if already disconnected.
    func close() async {
        guard let conn = connection else { return }
        _ = try? await sendCommand("LOGOUT", expectingResponse: true, timeout: 5)
        conn.cancel()
        connection = nil
        receiveBuffer.removeAll()
    }

    // MARK: - Commands

    /// LOGIN — plain-text auth. With Gmail / iCloud / Yahoo / Outlook we use
    /// App Passwords (not the user's main password). Throws permissionDenied
    /// on auth failure so MailWatchdog can route to the right UI state.
    func login(user: String, password: String, timeout: TimeInterval) async throws {
        // IMAP LOGIN syntax: LOGIN "user" "password"
        // Both args are quoted strings; we escape \ and " inside.
        let userQuoted = quoteIMAPString(user)
        let passQuoted = quoteIMAPString(password)
        let response = try await sendCommand("LOGIN \(userQuoted) \(passQuoted)",
                                              expectingResponse: true,
                                              timeout: timeout)
        if response.status == .no || response.status == .bad {
            // Server rejected credentials. The text usually contains
            // "Authentication failed" or similar.
            throw MailBridgeError.permissionDenied
        }
    }

    /// SELECT a mailbox to read messages from. Returns EXISTS count
    /// (number of messages in the mailbox).
    func select(mailbox: String, timeout: TimeInterval) async throws -> Int {
        let response = try await sendCommand("SELECT \(quoteIMAPString(mailbox))",
                                              expectingResponse: true,
                                              timeout: timeout)
        if response.status != .ok {
            throw MailBridgeError.unknown("SELECT \(mailbox) failed: \(response.text)")
        }
        // Parse "* NNN EXISTS" line for message count.
        for line in response.untagged {
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[2] == "EXISTS", let n = Int(parts[1]) {
                return n
            }
        }
        return 0
    }

    /// UID SEARCH with criteria like:
    ///   `SINCE 01-Mar-2026 (OR (OR SUBJECT "receipt" SUBJECT "subscription") SUBJECT "renewal")`
    ///
    /// Returns the matching UIDs (which are stable across the session, unlike
    /// sequence numbers — important for the FETCH that follows).
    func uidSearch(_ criteria: String, timeout: TimeInterval) async throws -> [Int] {
        let response = try await sendCommand("UID SEARCH \(criteria)",
                                              expectingResponse: true,
                                              timeout: timeout)
        if response.status != .ok {
            throw MailBridgeError.unknown("UID SEARCH failed: \(response.text)")
        }
        // Parse "* SEARCH 12 34 56" line for UIDs.
        for line in response.untagged {
            if line.hasPrefix("SEARCH ") || line == "SEARCH" {
                let raw = line.dropFirst("SEARCH".count).trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { return [] }
                return raw.split(separator: " ").compactMap { Int($0) }
            }
        }
        return []
    }

    /// UID FETCH bodies for the given UIDs. Pulls envelope (sender, subject,
    /// date) + RFC822.TEXT (raw body). For our use case (regex extraction),
    /// raw text is fine even with MIME boundary noise mixed in.
    ///
    /// Splits the request into chunks of 50 UIDs to avoid hitting server-side
    /// command-length limits.
    func uidFetch(uids: [Int], timeout: TimeInterval) async throws -> [FetchedMessage] {
        guard !uids.isEmpty else { return [] }

        var all: [FetchedMessage] = []
        for chunk in uids.chunked(into: 50) {
            let uidList = chunk.map(String.init).joined(separator: ",")
            // We ask for ENVELOPE (parsed sender/subject/date) + RFC822.HEADER
            // (for Message-ID lookup) + BODY[TEXT] (the body for extraction).
            let response = try await sendCommand(
                "UID FETCH \(uidList) (UID ENVELOPE BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)] BODY.PEEK[TEXT])",
                expectingResponse: true,
                timeout: timeout
            )
            if response.status != .ok {
                throw MailBridgeError.unknown("UID FETCH failed: \(response.text)")
            }
            all.append(contentsOf: parseFetchResponse(response.untagged))
        }
        return all
    }

    // MARK: - Response shape

    enum CommandStatus { case ok, no, bad }

    struct CommandResponse {
        let status: CommandStatus
        let text: String           // text of the tagged final line (after OK/NO/BAD)
        let untagged: [String]     // accumulated `* ...` data lines, with leading `*` stripped
    }

    struct FetchedMessage {
        let uid: Int
        let messageID: String      // RFC 5322 Message-ID (or empty if absent)
        let subject: String
        let from: String
        let date: Date
        let bodyText: String       // raw, never persisted
    }

    // MARK: - Command transport

    /// Send a tagged command and read until the matching tagged response.
    /// `expectingResponse: false` is for LOGOUT where we don't care about the result.
    private func sendCommand(_ command: String,
                              expectingResponse: Bool,
                              timeout: TimeInterval) async throws -> CommandResponse {
        guard let conn = connection else {
            throw MailBridgeError.unknown("not connected")
        }

        let tag = "S\(nextTagNumber)"
        nextTagNumber += 1
        let line = "\(tag) \(command)\r\n"

        // Send. IMAP-02: a half-open or blackholed connection can leave the
        // completion callback hanging forever, which leaves the wrapping Task
        // permanently suspended (the caller's wall-clock loop guards reads,
        // not sends). Add a wall-clock timeout matching the read budget.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guarded = IMAPContinuationGuard(continuation)
            conn.send(content: Data(line.utf8), completion: .contentProcessed { error in
                if let error = error {
                    guarded.resume(throwing: MailBridgeError.unknown(error.localizedDescription))
                } else {
                    guarded.resumeSuccess()
                }
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guarded.resume(throwing: MailBridgeError.timeout(resumeToken: [:]))
            }
        }

        guard expectingResponse else {
            return CommandResponse(status: .ok, text: "", untagged: [])
        }

        // Read until we see the tagged response line.
        var untagged: [String] = []
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let line = try await readResponseLine(timeout: deadline.timeIntervalSinceNow)

            if line.hasPrefix("\(tag) ") {
                // Tagged final line: "S1 OK LOGIN completed."
                let rest = String(line.dropFirst(tag.count + 1))
                let (status, text) = parseTaggedStatusLine(rest)
                return CommandResponse(status: status, text: text, untagged: untagged)
            } else if line.hasPrefix("* ") {
                // Untagged data line. Strip the "* " prefix.
                let body = String(line.dropFirst(2))

                // Some untagged lines (FETCH responses) include literals.
                // Check for `{NNN}` at end of line — if present, we need to
                // read NNN raw bytes next, then resume parsing.
                let withLiterals = try await readLiteralsIfPresent(line: body, deadline: deadline)
                untagged.append(withLiterals)
            } else if line.hasPrefix("+ ") {
                // Server requesting continuation. Suber's commands don't use
                // continuations (we don't send literals for LOGIN/SELECT/etc),
                // so this shouldn't happen. Treat as an error.
                throw MailBridgeError.unknown("unexpected continuation: \(line)")
            } else {
                // Unknown line shape. Log and continue.
                NSLog("Suber IMAP: unexpected line: \(line)")
            }
        }

        throw MailBridgeError.timeout(resumeToken: [:])
    }

    /// Some IMAP responses (FETCH bodies) include literals: `... {NNN}\r\n<NNN bytes>...`.
    /// When we see `{NNN}` at the end of a line, read exactly NNN raw bytes,
    /// append them to the line as a quoted blob, then continue reading the
    /// rest of the FETCH response until the closing `)`.
    private func readLiteralsIfPresent(line: String, deadline: Date) async throws -> String {
        var assembled = line
        // Loop because a single FETCH response can contain MULTIPLE literals
        // (one for HEADER, one for TEXT).
        while let literalSize = parseTrailingLiteralSize(assembled) {
            let bytes = try await readExactBytes(literalSize, timeout: deadline.timeIntervalSinceNow)
            // Append the literal as raw text. We use a sentinel so the parser
            // doesn't get confused — wrap in <<LITERAL>>...<<END>> markers.
            // Then read the next continuation line that follows the literal.
            let text = String(data: bytes, encoding: .utf8)
                   ?? String(data: bytes, encoding: .isoLatin1) ?? ""
            assembled = assembled + "\n<<LITERAL>>\(text)<<END>>"
            // After a literal there's MORE response content on a continuation
            // line. Read it (without timeout reset — total budget is shared).
            let nextLine = try await readResponseLine(timeout: deadline.timeIntervalSinceNow)
            assembled += "\n" + nextLine
        }
        return assembled
    }

    /// "BODY[TEXT] {1234}" → 1234. Returns nil if no `{N}` literal at end.
    private func parseTrailingLiteralSize(_ line: String) -> Int? {
        guard let openBrace = line.lastIndex(of: "{"),
              let closeBrace = line.lastIndex(of: "}"),
              closeBrace > openBrace,
              closeBrace == line.index(before: line.endIndex)
        else { return nil }
        let inside = line[line.index(after: openBrace)..<closeBrace]
        return Int(inside)
    }

    private func parseTaggedStatusLine(_ rest: String) -> (CommandStatus, String) {
        let upper = rest.uppercased()
        if upper.hasPrefix("OK") {
            return (.ok, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if upper.hasPrefix("NO") {
            return (.no, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if upper.hasPrefix("BAD") {
            return (.bad, String(rest.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        return (.bad, rest)
    }

    // MARK: - Wire reading

    /// Read bytes from connection until we see a CRLF, return the line
    /// (without the CRLF).
    private func readResponseLine(timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeout, 1))
        while Date() < deadline {
            // Look for CRLF in the buffer.
            if let range = receiveBuffer.range(of: Data([0x0D, 0x0A])) {
                let lineData = receiveBuffer.subdata(in: 0..<range.lowerBound)
                receiveBuffer.removeSubrange(0..<range.upperBound)
                return String(data: lineData, encoding: .utf8)
                    ?? String(data: lineData, encoding: .isoLatin1) ?? ""
            }
            // Need more bytes from the wire.
            try await readMoreIntoBuffer(timeout: deadline.timeIntervalSinceNow)
        }
        throw MailBridgeError.timeout(resumeToken: [:])
    }

    /// Read at most one `*` untagged line, ignoring tagged responses.
    /// Used by `connect()` for the server greeting.
    private func readUntaggedResponseLine(timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeout, 1))
        while Date() < deadline {
            let line = try await readResponseLine(timeout: deadline.timeIntervalSinceNow)
            if line.hasPrefix("* ") || line.hasPrefix("*\r") {
                return line
            }
        }
        throw MailBridgeError.timeout(resumeToken: [:])
    }

    /// Read exactly `count` bytes (used for IMAP literals).
    private func readExactBytes(_ count: Int, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(max(timeout, 1))
        while receiveBuffer.count < count, Date() < deadline {
            try await readMoreIntoBuffer(timeout: deadline.timeIntervalSinceNow)
        }
        guard receiveBuffer.count >= count else {
            throw MailBridgeError.timeout(resumeToken: [:])
        }
        let bytes = receiveBuffer.subdata(in: 0..<count)
        receiveBuffer.removeSubrange(0..<count)
        return bytes
    }

    /// Pull whatever the server has into the buffer.
    private func readMoreIntoBuffer(timeout: TimeInterval) async throws {
        guard let conn = connection else {
            throw MailBridgeError.unknown("not connected")
        }
        // RECV-01: flatten the previously-nested Task + double `[weak self]`.
        // Resume happens directly from the receive callback for the error /
        // EOF / empty paths; only the buffer-append path needs to hop into
        // actor isolation (Task) before resuming. The guard is thread-safe
        // so it's fine to call from either context.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let guarded = IMAPContinuationGuard(continuation)

            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                if let error = error {
                    guarded.resume(throwing: MailBridgeError.unknown("recv: \(error.localizedDescription)"))
                    return
                }
                if let data = data, !data.isEmpty {
                    Task { [weak self] in
                        await self?.appendToBuffer(data)
                        guarded.resumeSuccess()
                    }
                    return
                }
                if isComplete {
                    guarded.resume(throwing: MailBridgeError.unknown("server closed connection"))
                    return
                }
                guarded.resumeSuccess()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guarded.resume(throwing: MailBridgeError.timeout(resumeToken: [:]))
            }
        }
    }

    private func appendToBuffer(_ data: Data) {
        receiveBuffer.append(data)
    }

    // MARK: - FETCH response parsing

    /// Parse a series of "FETCH (UID 12 ENVELOPE (...) BODY[HEADER...] ... BODY[TEXT] {NNN}\n<literal>)"
    /// untagged lines into FetchedMessage values.
    ///
    /// Robustness choice: we use forgiving regex-based extraction rather than
    /// a full grammar parser. Real IMAP servers vary in subtle ways
    /// (Yahoo's ENVELOPE quotes differ from Gmail's), and our use case is
    /// extracting price + currency from the body text — we don't need every
    /// envelope field. If parsing fails for one message, log and skip it.
    private func parseFetchResponse(_ untagged: [String]) -> [FetchedMessage] {
        var results: [FetchedMessage] = []
        for line in untagged {
            // Lines are like: "12 FETCH (UID 4567 ENVELOPE (...) BODY[HEADER...] ... <<LITERAL>>...<<END>>)"
            guard line.contains("FETCH") else { continue }
            guard let msg = parseSingleFetch(line) else { continue }
            results.append(msg)
        }
        return results
    }

    private func parseSingleFetch(_ line: String) -> FetchedMessage? {
        // UID — `UID NNN`
        let uid = firstCapturedInt(in: line, pattern: #"UID\s+(\d+)"#) ?? 0

        // ENVELOPE shape: `ENVELOPE ("date-string" "subject" ((from-name NIL host user) ...) ...)`
        // We extract subject + from + date with forgiving patterns.
        let envelope = extractParenthesized(after: "ENVELOPE", in: line) ?? ""

        let date = parseEnvelopeDate(envelope)
        let subject = unquoteIMAP(extractEnvelopeNthString(envelope, index: 1)) ?? ""
        let from = extractEnvelopeFromAddress(envelope) ?? ""

        // Body literal: marked by our <<LITERAL>>...<<END>> sentinel.
        // FETCH can contain TWO literals (HEADER then TEXT). We want the TEXT
        // part — the second one if both present, the first if only one.
        let literals = extractLiterals(line)
        let bodyText = literals.last ?? ""

        // Message-ID: from the header literal (the FIRST one).
        let messageID = extractMessageID(literals.first ?? "")

        return FetchedMessage(
            uid: uid,
            messageID: messageID,
            subject: subject,
            from: from,
            date: date,
            bodyText: bodyText
        )
    }

    private func extractLiterals(_ line: String) -> [String] {
        var results: [String] = []
        var rest = Substring(line)
        while let start = rest.range(of: "<<LITERAL>>"),
              let end = rest.range(of: "<<END>>", range: start.upperBound..<rest.endIndex) {
            results.append(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return results
    }

    private func extractMessageID(_ headerText: String) -> String {
        // RFC 5322 header line: "Message-ID: <abc@example.com>"
        let pattern = #"(?im)^Message-ID:\s*<([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(headerText.startIndex..., in: headerText)
        guard let match = regex.firstMatch(in: headerText, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: headerText)
        else { return "" }
        return "<\(String(headerText[r]))>"
    }

    private func parseEnvelopeDate(_ envelope: String) -> Date {
        // First quoted string in ENVELOPE is the date.
        guard let dateStr = extractEnvelopeNthString(envelope, index: 0) else {
            return Date()
        }
        // RFC 5322 dates: "Mon, 12 Mar 2026 10:24:33 +0000"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        if let d = formatter.date(from: dateStr) { return d }
        formatter.dateFormat = "d MMM yyyy HH:mm:ss Z"
        if let d = formatter.date(from: dateStr) { return d }
        return Date()
    }

    /// Pull the Nth top-level quoted string from an envelope's flat shape.
    /// Index 0 = date, index 1 = subject in standard ENVELOPE order.
    private func extractEnvelopeNthString(_ envelope: String, index: Int) -> String? {
        var depth = 0
        var found = 0
        var inQuote = false
        var current = ""
        var collecting = false
        var escape = false

        for ch in envelope {
            if escape {
                if collecting { current.append(ch) }
                escape = false
                continue
            }
            if inQuote {
                if ch == "\\" { escape = true; if collecting { current.append(ch) }; continue }
                if ch == "\"" {
                    inQuote = false
                    if collecting {
                        if found == index { return current }
                        found += 1
                        current = ""
                        collecting = false
                    }
                    continue
                }
                if collecting { current.append(ch) }
                continue
            }
            if ch == "\"" {
                if depth == 0 {
                    inQuote = true
                    collecting = true
                    current = ""
                }
                continue
            }
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth -= 1; continue }
        }
        return nil
    }

    private func extractEnvelopeFromAddress(_ envelope: String) -> String? {
        // The "from" field in ENVELOPE is a list of address structs:
        // ((personal NIL mailbox host)) — index 2 in the flat envelope.
        // Format: ENVELOPE ("date" "subject" ( ( "name" NIL "user" "host" ) ) ...)
        // We just want "user@host" without quotes.
        // Forgiving extraction: find the first ( ( "..." ... "user" "host" ) )
        let pattern = #"\(\s*\(\s*(?:"[^"]*"|NIL)\s+(?:"[^"]*"|NIL)\s+"([^"]+)"\s+"([^"]+)"\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(envelope.startIndex..., in: envelope)
        guard let match = regex.firstMatch(in: envelope, range: range),
              match.numberOfRanges > 2,
              let userR = Range(match.range(at: 1), in: envelope),
              let hostR = Range(match.range(at: 2), in: envelope)
        else { return nil }
        return "\(envelope[userR])@\(envelope[hostR])"
    }

    private func unquoteIMAP(_ s: String?) -> String? {
        guard var s = s else { return nil }
        s = s.replacingOccurrences(of: "\\\\", with: "\\")
        s = s.replacingOccurrences(of: "\\\"", with: "\"")
        return s
    }

    /// Find first capture group as an Int.
    private func firstCapturedInt(in s: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let match = regex.firstMatch(in: s, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: s)
        else { return nil }
        return Int(s[r])
    }

    /// For `KEY (...)` — return the parenthesized content after KEY.
    /// Handles balanced parens and quoted strings.
    private func extractParenthesized(after key: String, in s: String) -> String? {
        guard let keyRange = s.range(of: key) else { return nil }
        var idx = keyRange.upperBound
        // Skip whitespace.
        while idx < s.endIndex, s[idx].isWhitespace { idx = s.index(after: idx) }
        guard idx < s.endIndex, s[idx] == "(" else { return nil }
        let openIdx = idx
        var depth = 0
        var inQuote = false
        var escape = false

        while idx < s.endIndex {
            let ch = s[idx]
            if escape { escape = false }
            else if inQuote {
                if ch == "\\" { escape = true }
                else if ch == "\"" { inQuote = false }
            } else {
                if ch == "\"" { inQuote = true }
                else if ch == "(" { depth += 1 }
                else if ch == ")" {
                    depth -= 1
                    if depth == 0 {
                        let inner = s.index(after: openIdx)..<idx
                        return String(s[inner])
                    }
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    // MARK: - Wire-format helpers

    /// IMAP quoted string: wrap in `"..."`, escape `\` and `"` inside.
    private func quoteIMAPString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
