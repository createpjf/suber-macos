import XCTest
@testable import Suber

/// D7 (eng review iter-1): MailBridge protocol enables injectable StubMailBridge
/// for testing state transitions + timeout/permission/error paths without live
/// Apple Events.
@MainActor
final class MailWatchdogTests: XCTestCase {

    var defaults: UserDefaults!
    var bridge: StubMailBridge!
    var watchdog: MailWatchdog!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "watchdog-tests-\(UUID().uuidString)")!
        bridge = StubMailBridge()
        watchdog = MailWatchdog(bridge: bridge, defaults: defaults)
    }

    override func tearDown() {
        // Clean up per-account cursors
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        watchdog = nil
        bridge = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testFreshWatchdogIsIdle() {
        XCTAssertEqual(watchdog.state, .idle)
        XCTAssertNil(watchdog.lastCompletedAt)
        XCTAssertEqual(watchdog.lastScanChangesCount, 0)
    }

    // MARK: - Happy-path scan

    func testScanNowReturnsSuccessSummary() async throws {
        bridge.messagesToReturn = [
            makeMessage(id: "<1>", body: "Netflix renewed $15.99 monthly", sender: "a@netflix.com"),
            makeMessage(id: "<2>", body: "Spotify renewed $9.99 monthly", sender: "a@spotify.com"),
        ]
        let summary = try await watchdog.scanNow()

        XCTAssertEqual(summary.messagesScanned, 2)
        XCTAssertEqual(watchdog.state, .idle)
        XCTAssertNotNil(watchdog.lastCompletedAt)
    }

    func testScanFiresOnScanCompleteCallback() async throws {
        bridge.messagesToReturn = [
            makeMessage(id: "<1>", body: "Renewed $9.99 monthly", sender: "a@spotify.com"),
        ]

        var capturedSummary: ScanSummary?
        var capturedChanges: [SubscriptionChange] = []
        watchdog.onScanComplete = { summary, changes in
            capturedSummary = summary
            capturedChanges = changes
        }

        _ = try await watchdog.scanNow()

        XCTAssertNotNil(capturedSummary)
        XCTAssertEqual(capturedChanges.count, 1)
        XCTAssertEqual(capturedChanges.first?.type, .newCharge)
    }

    // MARK: - Permission denied → state mapping

    func testPermissionDeniedFlowsIntoState() async {
        bridge.errorToThrow = .permissionDenied(detail: nil)
        do {
            _ = try await watchdog.scanNow()
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(watchdog.state, .permissionDenied)
        }
    }

    func testMailNotRunningFlowsIntoErrorState() async {
        bridge.errorToThrow = .mailNotRunning
        do {
            _ = try await watchdog.scanNow()
            XCTFail("Expected throw")
        } catch {
            // state should be .error with a useful message
            if case .error(let msg) = watchdog.state {
                XCTAssertTrue(msg.lowercased().contains("mail"),
                              "error message mentions Mail, got: \(msg)")
            } else {
                XCTFail("expected .error state, got \(watchdog.state)")
            }
        }
    }

    // MARK: - Timeout preserves resume token

    func testTimeoutPersistsResumeCursors() async {
        bridge.errorToThrow = .timeout(resumeToken: ["Gmail": "<cursor-1>"])
        do {
            _ = try await watchdog.scanNow()
            XCTFail("Expected throw")
        } catch {
            // cursor should be persisted
            let persisted = defaults.string(forKey: "mailwatchdog.cursor.Gmail")
            XCTAssertEqual(persisted, "<cursor-1>",
                           "Resume cursor must be persisted so next scan picks up")
        }
    }

    // MARK: - Concurrent scan blocks

    func testConcurrentScanThrows() async {
        bridge.slowScanSeconds = 0.5  // Slow path to ensure we're mid-scan
        let task1: Task<ScanSummary, Error> = Task { try await self.watchdog.scanNow() }
        // Give task1 a moment to enter .scanning state
        try? await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await watchdog.scanNow()
            XCTFail("Second scanNow while first is in flight must throw")
        } catch {
            // expected
        }
        _ = try? await task1.value   // clean up
    }

    // MARK: - Cursor incremental-scan

    func testCursorAdvancesAfterSuccessfulScan() async throws {
        let now = Date()
        bridge.messagesToReturn = [
            makeMessage(id: "<oldest>", dateReceived: now.addingTimeInterval(-300),
                        body: "Renewed $9.99 monthly", sender: "a@netflix.com"),
            makeMessage(id: "<newest>", dateReceived: now,
                        body: "Renewed $9.99 monthly", sender: "a@netflix.com"),
        ]
        _ = try await watchdog.scanNow()
        // Both messages on the same account "TestAccount" — cursor should
        // be the newest id.
        XCTAssertEqual(defaults.string(forKey: "mailwatchdog.cursor.TestAccount"), "<newest>")
    }

    // MARK: - AppleMailBridge output parsing (AUDIT-v1.9.2 C-25)

    /// NSDataDetector is the single date-parse path (the unconfigured
    /// DateFormatter that used to sit in front of it never matched anything).
    /// Locale-formatted and ISO-ish date strings must both parse; records
    /// with unparseable dates are skipped, not crashed on.
    func testParseOutputParsesDatesViaDetector() {
        let bridge = AppleMailBridge()
        let fs = "\u{001F}"   // field separator (matches AppleMailBridge)
        let rs = "\u{001E}"   // record separator
        let raw = [
            // Mail.app locale-formatted date.
            "<a@x>\(fs)Gmail\(fs)Sunday, March 16, 2025 at 10:24:33 PM\(fs)Receipt\(fs)a@x.com\(fs)$9.99",
            // ISO-ish date.
            "<b@x>\(fs)Gmail\(fs)2025-03-17 08:00:00\(fs)Receipt\(fs)b@x.com\(fs)$5.00",
            // Unparseable date → record skipped.
            "<c@x>\(fs)Gmail\(fs)not a date at all\(fs)Receipt\(fs)c@x.com\(fs)$1.00",
        ].joined(separator: rs) + rs

        let messages = bridge.parseOutput(raw)

        XCTAssertEqual(messages.count, 2, "Two parseable dates, one skipped")
        XCTAssertEqual(Set(messages.map(\.id)), ["<a@x>", "<b@x>"])
        let first = messages.first { $0.id == "<a@x>" }!
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: first.dateReceived)
        XCTAssertEqual(ymd.year, 2025)
        XCTAssertEqual(ymd.month, 3)
        XCTAssertEqual(ymd.day, 16)
    }

    // MARK: - AppleMailBridge osascript pipe drain (AUDIT-v1.9.2 C-07)

    /// Output beyond the ~64 KB kernel pipe buffer must not deadlock —
    /// stdout/stderr are drained while osascript runs. Before the fix this
    /// test burned the full timeout and threw .timeout.
    func testRunOSAScriptDrainsLargeOutputWithoutDeadlock() async throws {
        let bridge = AppleMailBridge()
        // 16 chars doubled 13 times = 131,072 chars — well past the 64 KB
        // pipe buffer. Pure string work; no Apple Events, no TCC prompt.
        let script = """
        set s to "0123456789abcdef"
        repeat 13 times
            set s to s & s
        end repeat
        return s
        """
        let output = try await bridge.runOSAScript(script, timeout: 30)
        XCTAssertGreaterThan(output.count, 65_536,
                             "Full >64 KB output must come through without deadlocking")
    }

    // MARK: - Helpers

    private func makeMessage(
        id: String,
        account: String = "TestAccount",
        dateReceived: Date = Date(),
        body: String,
        sender: String
    ) -> MailMessage {
        MailMessage(
            id: id, account: account, dateReceived: dateReceived,
            subject: "Receipt", sender: sender, body: body
        )
    }
}

// MARK: - StubMailBridge (D7 injectable test bridge)

/// Test-only MailBridge that returns canned messages or throws canned errors.
/// Exported as file-scope so MailWatchdogTests can mutate its state between cases.
final class StubMailBridge: MailBridge, @unchecked Sendable {
    var messagesToReturn: [MailMessage] = []
    var errorToThrow: MailBridgeError?
    /// If > 0, the scan will take roughly this long (useful for testing
    /// concurrent-call guard). Ignored when errorToThrow is non-nil.
    var slowScanSeconds: Double = 0

    /// Account count returned by ping(). Defaults to 1 so connectAppleMail
    /// passes its TCC-probe step in tests by default.
    var pingAccountCount: Int = 1

    func ping(timeout: TimeInterval) async throws -> Int {
        if let err = errorToThrow { throw err }
        return pingAccountCount
    }

    func scan(since: Date, keywords: [String], timeout: TimeInterval) async throws -> [MailMessage] {
        if let err = errorToThrow { throw err }
        if slowScanSeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(slowScanSeconds * 1_000_000_000))
        }
        return messagesToReturn
    }
}
