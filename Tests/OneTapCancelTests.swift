import XCTest
@testable import Suber

/// URL resolution priority: per-sub override → KnownServices → DuckDuckGo fallback.
/// D5 idempotent markPendingCancellation: re-tap doesn't reset the anchor.
final class OneTapCancelTests: XCTestCase {

    // AUDIT-v1.9.2 C-01: sandbox ALL file I/O into fresh per-test temp dirs.
    // The old setUp/tearDown cleared the user's REAL App Group container
    // (removeObject has no snapshot hook); the sandbox gives the same
    // cross-test isolation without ever touching real data.
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-onetapcancel-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-onetapcancel-backup-\(UUID().uuidString)")
        AppGroupStore.testOverrideDirectory = tempStoreDir
        DataBackupManager.testOverrideDirectory = tempBackupDir
    }

    override func tearDown() {
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
        if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    // MARK: - URL resolution priority

    func testPerSubOverrideWins() {
        var sub = makeSub(name: "Netflix")
        sub.cancellationURL = "https://my.own.url/cancel"
        let resolved = OneTapCancelService.resolveURL(for: sub)
        XCTAssertEqual(resolved?.absoluteString, "https://my.own.url/cancel",
                       "Per-sub override must take priority over KnownServices")
    }

    func testKnownServicesFallbackForNetflix() {
        let sub = makeSub(name: "Netflix")
        let resolved = OneTapCancelService.resolveURL(for: sub)
        XCTAssertEqual(resolved?.absoluteString, "https://www.netflix.com/cancelplan")
    }

    func testKnownServicesFallbackForAppleBilled() {
        // iCloud+ routes to the Apple Subscriptions deep-link.
        let sub = makeSub(name: "iCloud+")
        let resolved = OneTapCancelService.resolveURL(for: sub)
        XCTAssertEqual(resolved?.absoluteString, "itms-apps://apps.apple.com/account/subscriptions")
    }

    func testDuckDuckGoFallbackForUnknownService() {
        let sub = makeSub(name: "NEVERHEARDOFIT")
        let resolved = OneTapCancelService.resolveURL(for: sub)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.host, "duckduckgo.com")
        XCTAssertTrue(resolved?.absoluteString.contains("NEVERHEARDOFIT") ?? false,
                      "Fallback URL should include the service name in the query")
    }

    func testDuckDuckGoFallbackEncodesSpecialCharacters() {
        let url = OneTapCancelService.duckDuckGoFallback(for: "Service & Co.")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("%26") ?? false,
                      "Ampersand should be URL-encoded")
    }

    func testDuckDuckGoFallbackHandlesEmptyName() {
        XCTAssertNil(OneTapCancelService.duckDuckGoFallback(for: ""))
        XCTAssertNil(OneTapCancelService.duckDuckGoFallback(for: "   "))
    }

    // MARK: - hasKnownCancelPage heuristic

    func testHasKnownCancelPageForKnownService() {
        XCTAssertTrue(OneTapCancelService.hasKnownCancelPage(for: makeSub(name: "Netflix")))
        XCTAssertTrue(OneTapCancelService.hasKnownCancelPage(for: makeSub(name: "Spotify")))
    }

    func testHasKnownCancelPageForOverrideURL() {
        var sub = makeSub(name: "Obscure Service")
        sub.cancellationURL = "https://obscure.example.com/cancel"
        XCTAssertTrue(OneTapCancelService.hasKnownCancelPage(for: sub))
    }

    func testHasKnownCancelPageFalseForUnknown() {
        XCTAssertFalse(OneTapCancelService.hasKnownCancelPage(for: makeSub(name: "COMPLETELY UNKNOWN")))
    }

    // MARK: - KnownServices cancellation-URL database

    func testKnownServicesTop10HaveURLs() {
        // Plan called out Netflix, Spotify, Apple subs, YouTube Premium,
        // Disney+, ChatGPT, Claude, iCloud+, 爱奇艺, 网易云音乐 as the top-10
        // seed list. Most should have direct URLs; 网易云音乐 is one of the
        // App-only exceptions.
        XCTAssertNotNil(KnownServices.cancellationURL(for: "Netflix"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "Spotify"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "YouTube Premium"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "Disney+"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "ChatGPT"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "Claude"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "iCloud+"))
        XCTAssertNotNil(KnownServices.cancellationURL(for: "爱奇艺"))
    }

    func testKnownServicesTop40SeedCount() {
        let withURL = KnownServices.all.filter { $0.cancellationURL != nil }
        XCTAssertGreaterThanOrEqual(withURL.count, 40,
                                    "Plan specified top-40 seed; got \(withURL.count)")
    }

    // MARK: - D5 idempotent markPendingCancellation

    @MainActor
    func testMarkPendingCancellationRetapKeepsAnchorStable() {
        // Covered more thoroughly in SubscriptionStoreChangeLogTests; this
        // test re-states the contract at the One-Tap-Cancel level so a
        // future refactor of OneTapCancelService doesn't accidentally
        // call setAt = now on every tap.
        // (AppGroupStore is cleared in setUp/tearDown — no per-test dance needed.)
        let store = SubscriptionStore()
        var data = SubscriptionFormData()
        data.name = "Netflix"; data.amount = "15.99"; data.currency = "USD"
        data.cycle = .monthly; data.billingDay = 15
        store.add(data)

        let id = store.subscriptions[0].id
        let firstTap = Date(timeIntervalSince1970: 1_700_000_000)
        let reTap = Date(timeIntervalSince1970: 1_700_000_000 + 86_400 * 3)

        store.markPendingCancellation(id: id, now: firstTap)
        store.markPendingCancellation(id: id, now: reTap)

        XCTAssertEqual(store.subscriptions[0].pendingCancellationSetAt, firstTap,
                       "D5: re-tap does NOT move the anchor")
    }

    // MARK: - Helper

    private func makeSub(name: String) -> Subscription {
        Subscription(
            id: UUID(), name: name, amount: 9.99, currency: "USD",
            cycle: .monthly, billingDay: 15, startDate: Date(),
            category: "Test", status: .active,
            createdAt: Date(), updatedAt: Date()
        )
    }
}
