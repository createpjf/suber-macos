import XCTest
@testable import Suber

/// Unit tests for the IMAP bridge stack — provider presets, account model,
/// Keychain round-trip, search-criteria builder, composite-bridge dedup.
///
/// We do NOT exercise IMAPClient against a real server here. Live-server tests
/// would need a test Gmail account + secret in CI, which is out of scope for
/// v1.7. The client's protocol-correctness is verified by hand against
/// imap.gmail.com when the user adds their first account (the "Test
/// connection" button in IMAPAccountSheet runs ping() against real servers).
final class IMAPBridgeTests: XCTestCase {

    // MARK: - IMAPProvider presets

    func testProviderPresetsHaveCorrectHosts() {
        XCTAssertEqual(IMAPProvider.gmail.defaultHost, "imap.gmail.com")
        XCTAssertEqual(IMAPProvider.icloud.defaultHost, "imap.mail.me.com")
        XCTAssertEqual(IMAPProvider.outlook.defaultHost, "outlook.office365.com")
        XCTAssertEqual(IMAPProvider.yahoo.defaultHost, "imap.mail.yahoo.com")
        XCTAssertEqual(IMAPProvider.fastmail.defaultHost, "imap.fastmail.com")
        XCTAssertNil(IMAPProvider.generic.defaultHost,
                     "Generic must require user input — no preset host")
    }

    func testAllProvidersUseTLS993() {
        for p in IMAPProvider.allCases {
            XCTAssertEqual(p.defaultPort, 993,
                          "\(p.displayName) should default to 993 (IMAPS)")
        }
    }

    func testGmailUsesAllMailMailbox() {
        // Gmail's INBOX excludes auto-labeled receipts (Promotions tab etc).
        // [Gmail]/All Mail sees everything. Critical for billing-receipt scan.
        XCTAssertEqual(IMAPProvider.gmail.scanMailbox, "[Gmail]/All Mail")
    }

    func testNonGmailProvidersUseINBOX() {
        for p in IMAPProvider.allCases where p != .gmail {
            XCTAssertEqual(p.scanMailbox, "INBOX",
                          "\(p.displayName) should scan INBOX")
        }
    }

    func testProviderSetupHintsAreNonEmpty() {
        // Every provider should give the user actionable guidance to obtain
        // an App Password. Empty hint = bad UX.
        for p in IMAPProvider.allCases {
            XCTAssertFalse(p.setupHint.isEmpty, "\(p.displayName) missing setupHint")
        }
    }

    // MARK: - IMAPAccount construction defaults

    func testAccountAutoFillsHostFromProvider() {
        let acct = IMAPAccount(provider: .gmail, email: "user@gmail.com")
        XCTAssertEqual(acct.host, "imap.gmail.com")
        XCTAssertEqual(acct.port, 993)
    }

    func testAccountRespectsExplicitOverrides() {
        let acct = IMAPAccount(
            provider: .generic,
            email: "user@example.com",
            host: "mail.example.com",
            port: 1143
        )
        XCTAssertEqual(acct.host, "mail.example.com")
        XCTAssertEqual(acct.port, 1143)
    }

    func testAccountDefaultDisplayName() {
        let acct = IMAPAccount(provider: .yahoo, email: "user@yahoo.com")
        XCTAssertEqual(acct.displayName, "Yahoo · user@yahoo.com")
    }

    func testAccountIsCodableRoundTrip() throws {
        let original = IMAPAccount(provider: .fastmail, email: "user@fastmail.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IMAPAccount.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Keychain round-trip

    /// Smoke test that Keychain helpers handle save/load/delete cycle.
    /// Uses a test-only email so we don't clobber real user credentials.
    func testKeychainRoundTrip() throws {
        let testEmail = "imap-bridge-test-\(UUID().uuidString)@suber.invalid"
        let testPassword = "abcd-efgh-ijkl-mnop"

        // Clean slate
        IMAPCredentialStore.delete(email: testEmail)
        XCTAssertFalse(IMAPCredentialStore.has(email: testEmail))

        // Save
        XCTAssertTrue(IMAPCredentialStore.save(password: testPassword, for: testEmail))
        XCTAssertTrue(IMAPCredentialStore.has(email: testEmail))

        // Load
        XCTAssertEqual(IMAPCredentialStore.load(email: testEmail), testPassword)

        // Update (save again, different value)
        let newPassword = "wxyz-1234-5678-9012"
        XCTAssertTrue(IMAPCredentialStore.save(password: newPassword, for: testEmail))
        XCTAssertEqual(IMAPCredentialStore.load(email: testEmail), newPassword)

        // Delete
        XCTAssertTrue(IMAPCredentialStore.delete(email: testEmail))
        XCTAssertFalse(IMAPCredentialStore.has(email: testEmail))
        XCTAssertNil(IMAPCredentialStore.load(email: testEmail))
    }

    // MARK: - GenericIMAPBridge SEARCH criteria builder

    func testSearchCriteriaWithSingleKeyword() {
        let bridge = GenericIMAPBridge(
            account: .init(provider: .gmail, email: "x@gmail.com"),
            passwordResolver: { "stub" }
        )
        let criteria = bridge.buildSearchCriteria(
            since: Date(timeIntervalSince1970: 1_710_000_000),  // ~2024-03-09
            keywords: ["receipt"]
        )
        // Date should be `09-Mar-2024` (IMAP format).
        XCTAssertTrue(criteria.contains("SINCE 09-Mar-2024"),
                      "Expected IMAP date format dd-MMM-yyyy; got: \(criteria)")
        // Single keyword shouldn't introduce OR.
        XCTAssertTrue(criteria.contains("SUBJECT \"receipt\""))
        XCTAssertFalse(criteria.contains("OR"))
    }

    func testSearchCriteriaWithMultipleKeywordsBuildsORTree() {
        let bridge = GenericIMAPBridge(
            account: .init(provider: .gmail, email: "x@gmail.com"),
            passwordResolver: { "stub" }
        )
        let criteria = bridge.buildSearchCriteria(
            since: Date(),
            keywords: ["receipt", "subscription", "renewal"]
        )
        // Should contain N-1 ORs for N keywords (left-fold).
        let orCount = criteria.components(separatedBy: "OR").count - 1
        XCTAssertEqual(orCount, 2, "3 keywords → 2 ORs in the tree")
        // All keywords should be present, each properly quoted.
        XCTAssertTrue(criteria.contains("SUBJECT \"receipt\""))
        XCTAssertTrue(criteria.contains("SUBJECT \"subscription\""))
        XCTAssertTrue(criteria.contains("SUBJECT \"renewal\""))
    }

    func testSearchCriteriaEscapesQuotesInKeywords() {
        // Defensive — extractor keywords don't contain quotes today, but the
        // builder must escape them safely so a future keyword like
        // [`he said "hi"`] can't break IMAP syntax.
        let bridge = GenericIMAPBridge(
            account: .init(provider: .gmail, email: "x@gmail.com"),
            passwordResolver: { "stub" }
        )
        let criteria = bridge.buildSearchCriteria(
            since: Date(),
            keywords: ["he said \"hi\""]
        )
        // The escaped keyword should appear with escaped inner quotes.
        XCTAssertTrue(criteria.contains("\\\""), "Inner quotes must be backslash-escaped")
    }

    // MARK: - CompositeMailBridge

    @MainActor
    func testCompositeBridgeMergesResults() async throws {
        let bridgeA = StubMailBridge()
        bridgeA.messagesToReturn = [
            MailMessage(id: "<a@1>", account: "a",
                        dateReceived: Date(), subject: "A", sender: "a@x.com", body: "$10")
        ]

        let bridgeB = StubMailBridge()
        bridgeB.messagesToReturn = [
            MailMessage(id: "<b@1>", account: "b",
                        dateReceived: Date(), subject: "B", sender: "b@x.com", body: "$20")
        ]

        let composite = CompositeMailBridge(bridges: [bridgeA, bridgeB])
        let results = try await composite.scan(
            since: Date.distantPast,
            keywords: ["receipt"],
            timeout: 10
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.id)), ["<a@1>", "<b@1>"])
    }

    @MainActor
    func testCompositeBridgeDedupsByMessageID() async throws {
        // Same message landing in BOTH Apple Mail (iCloud account) AND
        // a separate IMAP bridge to imap.mail.me.com — should dedup.
        let bridgeA = StubMailBridge()
        bridgeA.messagesToReturn = [
            MailMessage(id: "<dup@example.com>", account: "icloud",
                        dateReceived: Date(), subject: "Receipt", sender: "x", body: "$5")
        ]
        let bridgeB = StubMailBridge()
        bridgeB.messagesToReturn = [
            MailMessage(id: "<dup@example.com>", account: "imap-icloud",
                        dateReceived: Date(), subject: "Receipt", sender: "x", body: "$5")
        ]

        let composite = CompositeMailBridge(bridges: [bridgeA, bridgeB])
        let results = try await composite.scan(
            since: Date.distantPast,
            keywords: [],
            timeout: 10
        )
        XCTAssertEqual(results.count, 1, "Same Message-ID should dedup across bridges")
    }

    @MainActor
    func testCompositeBridgePartialFailureReturnsWhatSucceeded() async throws {
        let working = StubMailBridge()
        working.messagesToReturn = [
            MailMessage(id: "<ok@1>", account: "a",
                        dateReceived: Date(), subject: "ok", sender: "x", body: "$5")
        ]
        let broken = StubMailBridge()
        broken.errorToThrow = .unknown("simulated network failure")

        let composite = CompositeMailBridge(bridges: [working, broken])
        let results = try await composite.scan(
            since: Date.distantPast,
            keywords: [],
            timeout: 10
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "<ok@1>")
    }

    @MainActor
    func testCompositeBridgePingSumsAccountCounts() async throws {
        let a = StubMailBridge(); a.pingAccountCount = 2
        let b = StubMailBridge(); b.pingAccountCount = 3
        let composite = CompositeMailBridge(bridges: [a, b])

        let total = try await composite.ping(timeout: 5)
        XCTAssertEqual(total, 5)
    }

    @MainActor
    func testCompositeBridgePingThrowsWhenAllFail() async {
        let a = StubMailBridge(); a.errorToThrow = .permissionDenied
        let b = StubMailBridge(); b.errorToThrow = .permissionDenied
        let composite = CompositeMailBridge(bridges: [a, b])

        do {
            _ = try await composite.ping(timeout: 5)
            XCTFail("Should have thrown when all bridges fail")
        } catch let error as MailBridgeError {
            XCTAssertEqual(error, .permissionDenied,
                           "Should propagate permissionDenied (most actionable)")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
