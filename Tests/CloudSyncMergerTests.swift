import XCTest
@testable import Suber

/// v1.9.1 — Tests for the cloud-sync merge rules.
///
/// **Why this exists.** v1.9.0 shipped with `CloudSyncService.onRemoteChange`
/// unconditionally calling `subscriptionStore.importSubscriptions(remote)`.
/// On a user's first v1.9.0 launch with iCloud sync enabled, an old stale
/// 1-sub KVS snapshot replaced their 9 live subs. v1.9.1 introduces
/// `CloudSyncMerger` which classifies every remote update against three
/// rules: replace (legitimate fresh-device), reject (suspected stale), or
/// merge (combine by id, last-write-wins). This file is the regression net
/// guarding those rules — if anyone weakens the "reject stale" guard or
/// re-introduces the unconditional overwrite path, these tests catch it.
final class CloudSyncMergerTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a Subscription with a deterministic id and an explicit
    /// updatedAt so merge-conflict tests can assert which side won.
    private func makeSub(idSeed: Int,
                         name: String,
                         amount: Double,
                         updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                         createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Subscription {
        Subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", idSeed))")!,
            name: name,
            amount: amount,
            currency: "USD",
            cycle: .monthly,
            billingDay: 1,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            category: "Test",
            status: .active,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Rule 1: replace when local empty + remote non-empty

    /// Fresh-install / new-device case. Local has nothing; KVS hands us a
    /// non-empty list. Rule 1 says: trust it, replace local. This is the
    /// ONLY scenario where unconditional overwrite is allowed.
    func testRule1_replaceWhenLocalEmptyAndRemoteHasData() {
        let remote = [makeSub(idSeed: 1, name: "Netflix", amount: 15.99)]
        let result = CloudSyncMerger.mergeSubscriptions(local: [], remote: remote)

        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied, got \(result)")
        }
        XCTAssertEqual(merged.map(\.name), ["Netflix"])
    }

    // MARK: - Rule 2: reject stale remote (THE bug v1.9.1 exists to fix)

    /// **Critical regression test.** This is the EXACT shape of the v1.9.0
    /// data-loss bug: user has 9 real subs locally, iCloud KVS still holds
    /// a stale 1-sub snapshot. Rule 2 must REJECT — never overwrite N
    /// subs with fewer subs from the remote when local is non-empty.
    /// If this test ever turns green via `.applied` instead of
    /// `.rejectedAsStale`, v1.9.0's data-loss bug has returned.
    func testRule2_rejectsStaleRemoteAgainstLargerLocal_TheBugThatPromptedV191() {
        let local = (0..<9).map { i in makeSub(idSeed: i, name: "Sub-\(i)", amount: 10.0) }
        let remote = [makeSub(idSeed: 999, name: "Stale Netflix Premium", amount: 22.99)]

        let result = CloudSyncMerger.mergeSubscriptions(local: local, remote: remote)

        guard case .rejectedAsStale(let l, let r) = result else {
            return XCTFail("Expected .rejectedAsStale (v1.9.0 regression!), got \(result)")
        }
        XCTAssertEqual(l, 9)
        XCTAssertEqual(r, 1)
    }

    /// Edge case: even a one-fewer-sub mismatch must reject. The "stale"
    /// definition is conservative — any remote count below local is
    /// suspect. Users can apply smaller backups intentionally via the
    /// Restore UI.
    func testRule2_rejectsEvenWhenRemoteIsOnlyOneFewer() {
        let local = (0..<3).map { i in makeSub(idSeed: i, name: "Sub-\(i)", amount: 10.0) }
        let remote = (0..<2).map { i in makeSub(idSeed: i, name: "Sub-\(i)", amount: 10.0) }

        let result = CloudSyncMerger.mergeSubscriptions(local: local, remote: remote)

        if case .rejectedAsStale = result { /* ok */ } else {
            XCTFail("Conservative rule: any remote count < local must reject. got \(result)")
        }
    }

    // MARK: - Rule 3: merge by id, last-write-wins

    /// Two devices each added a different sub. Remote count >= local count
    /// → Rule 3 merges. Result must contain BOTH devices' adds.
    func testRule3_mergeUnionsLocalAndRemoteByID() {
        let shared = makeSub(idSeed: 1, name: "Netflix", amount: 15.99)
        let local = [shared, makeSub(idSeed: 2, name: "Spotify", amount: 9.99)]
        let remote = [shared, makeSub(idSeed: 3, name: "ChatGPT", amount: 19.99)]

        let result = CloudSyncMerger.mergeSubscriptions(local: local, remote: remote)

        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied for union merge, got \(result)")
        }
        let names = Set(merged.map(\.name))
        XCTAssertEqual(names, ["Netflix", "Spotify", "ChatGPT"])
    }

    /// Conflict resolution: same id on both sides, different `updatedAt`.
    /// Higher updatedAt wins regardless of which side it's on.
    func testRule3_lastWriteWinsByUpdatedAt() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)

        let localOlder = makeSub(idSeed: 1, name: "Netflix old", amount: 15.99,
                                 updatedAt: older)
        let remoteNewer = makeSub(idSeed: 1, name: "Netflix new", amount: 22.99,
                                  updatedAt: newer)

        let result = CloudSyncMerger.mergeSubscriptions(local: [localOlder],
                                                       remote: [remoteNewer])
        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied, got \(result)")
        }
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "Netflix new",
                       "Newer updatedAt must win regardless of side")
    }

    /// Reverse direction: local newer than remote, same id.
    func testRule3_localNewerThanRemoteWins() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)

        let localNewer = makeSub(idSeed: 1, name: "Netflix v2", amount: 22.99,
                                 updatedAt: newer)
        let remoteOlder = makeSub(idSeed: 1, name: "Netflix v1", amount: 15.99,
                                  updatedAt: older)
        // Add a 2nd remote-only sub so remote.count >= local.count
        // (otherwise Rule 2 would reject before Rule 3 runs).
        let remoteOnly = makeSub(idSeed: 2, name: "Spotify", amount: 9.99)

        let result = CloudSyncMerger.mergeSubscriptions(local: [localNewer],
                                                       remote: [remoteOlder, remoteOnly])
        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied, got \(result)")
        }
        let netflix = merged.first { $0.id == localNewer.id }
        XCTAssertEqual(netflix?.name, "Netflix v2",
                       "Local newer must beat remote older for same id")
    }

    // MARK: - Edge: both empty

    func testNoOpWhenBothSidesEmpty() {
        let result = CloudSyncMerger.mergeSubscriptions(local: [], remote: [])
        XCTAssertEqual(result, .noOp)
    }

    // MARK: - Settings merger

    /// User hasn't customised anything → factory defaults → safe to accept
    /// remote.
    func testSettings_factoryDefaultLocalAcceptsRemote() {
        var remote = AppSettings()
        remote.primaryCurrency = "EUR"
        remote.enableCloudSync = true

        let merged = CloudSyncMerger.mergeSettings(local: AppSettings(), remote: remote)
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.primaryCurrency, "EUR")
    }

    /// User has customised — local wins, remote dropped. Prevents the
    /// silent revert-on-sync UX.
    func testSettings_customisedLocalRejectsRemote() {
        var local = AppSettings()
        local.primaryCurrency = "GBP"  // user changed
        var remote = AppSettings()
        remote.primaryCurrency = "EUR"

        let merged = CloudSyncMerger.mergeSettings(local: local, remote: remote)
        XCTAssertNil(merged, "Customised local must keep its values")
    }
}
