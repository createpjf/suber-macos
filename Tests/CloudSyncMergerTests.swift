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

    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        // AUDIT-v1.9.2 C-02: the tombstone-store tests below hit the real
        // AppGroupStore read/write path — sandbox into per-test temp dirs so
        // they never touch the user's live container (C-01 lesson).
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-merger-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-merger-backup-\(UUID().uuidString)")
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

    // MARK: - Deletion tombstones (AUDIT-v1.9.2 C-02)

    /// Delete PROPAGATION. Peer deleted Netflix: its push arrives one entry
    /// shorter plus the tombstone. Pre-tombstone, Rule 2 saw remote < local
    /// and rejected — the delete could never reach this device. The tombstone
    /// must filter the local side so the merge applies the delete.
    func testTombstone_deletePropagatesToPeerDevice() {
        let netflix = makeSub(idSeed: 1, name: "Netflix", amount: 15.99)
        let spotify = makeSub(idSeed: 2, name: "Spotify", amount: 9.99)
        let local = [netflix, spotify]        // still has the deleted sub
        let remote = [spotify]                // peer already dropped it

        let result = CloudSyncMerger.mergeSubscriptions(
            local: local, remote: remote, tombstones: [netflix.id])

        guard case .applied(let merged) = result else {
            return XCTFail("Tombstoned delete must merge, not reject. got \(result)")
        }
        XCTAssertEqual(merged.map(\.name), ["Spotify"],
                       "Peer's delete must propagate — Netflix removed locally")
    }

    /// RESURRECTION prevention. This device deleted Netflix; the peer hasn't
    /// synced yet and pushes a list that still contains it (with a newer
    /// updatedAt, the worst case for last-write-wins). Rule 3's union used to
    /// re-add it — corrupting monthly totals with a sub the user deleted.
    func testTombstone_preventsResurrectionOnDeletingDevice() {
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        let netflix = makeSub(idSeed: 1, name: "Netflix", amount: 15.99, updatedAt: newer)
        let spotify = makeSub(idSeed: 2, name: "Spotify", amount: 9.99)
        let local = [spotify]                 // post-delete
        let remote = [netflix, spotify]       // stale peer still has Netflix

        let result = CloudSyncMerger.mergeSubscriptions(
            local: local, remote: remote, tombstones: [netflix.id])

        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied, got \(result)")
        }
        XCTAssertEqual(merged.map(\.name), ["Spotify"],
                       "Deleted sub must NOT resurrect via Rule 3 union")
    }

    /// Rule 1 (fresh device) must not hydrate deleted subs either.
    func testTombstone_filtersFreshDeviceHydration() {
        let netflix = makeSub(idSeed: 1, name: "Netflix", amount: 15.99)
        let spotify = makeSub(idSeed: 2, name: "Spotify", amount: 9.99)

        let result = CloudSyncMerger.mergeSubscriptions(
            local: [], remote: [netflix, spotify], tombstones: [netflix.id])

        guard case .applied(let merged) = result else {
            return XCTFail("Expected .applied, got \(result)")
        }
        XCTAssertEqual(merged.map(\.name), ["Spotify"])
    }

    /// CROSS-VERSION guard: a pre-tombstone peer pushes the same
    /// `[Subscription]` JSON wire shape as ever — no tombstone field anywhere
    /// in the payload. It must decode and merge exactly as before (the
    /// tombstone set is a separate, additive KVS key; the subscriptions
    /// format is untouched in both directions).
    func testOldPayloadWithoutTombstonesStillDecodesAndMerges() throws {
        let legacyJSON = """
        [{
            "id": "00000000-0000-0000-0000-000000000042",
            "name": "Legacy Sub",
            "amount": 4.99,
            "currency": "USD",
            "cycle": "monthly",
            "billingDay": 5,
            "startDate": "2026-01-05T00:00:00Z",
            "category": "Test",
            "status": "active",
            "createdAt": "2026-01-05T00:00:00Z",
            "updatedAt": "2026-01-05T00:00:00Z"
        }]
        """
        let remote = try JSONDecoder.suberDecoder
            .decode([Subscription].self, from: Data(legacyJSON.utf8))

        let result = CloudSyncMerger.mergeSubscriptions(local: [], remote: remote)
        guard case .applied(let merged) = result else {
            return XCTFail("Legacy payload must merge as before, got \(result)")
        }
        XCTAssertEqual(merged.map(\.name), ["Legacy Sub"])
    }

    // MARK: - DeletionTombstones store

    func testTombstoneStore_recordPersistsAndLoads() {
        let id = UUID()
        DeletionTombstones.record(id)

        XCTAssertTrue(DeletionTombstones.activeIDs().contains(id))
        // Survives a reload from disk (fresh decode, not in-memory state).
        XCTAssertTrue(DeletionTombstones.load().contains { $0.id == id })
    }

    func testTombstoneStore_pruneDropsExpiredAndCapsCount() {
        let now = Date()
        let fresh = DeletionTombstone(id: UUID(), deletedAt: now)
        let expired = DeletionTombstone(
            id: UUID(), deletedAt: now.addingTimeInterval(-DeletionTombstones.maxAge - 1))

        let pruned = DeletionTombstones.prune([fresh, expired], now: now)
        XCTAssertEqual(pruned.map(\.id), [fresh.id], "expired tombstone must drop")

        let many = (0..<(DeletionTombstones.maxEntries + 50)).map {
            DeletionTombstone(id: UUID(), deletedAt: now.addingTimeInterval(-Double($0)))
        }
        XCTAssertEqual(DeletionTombstones.prune(many, now: now).count,
                       DeletionTombstones.maxEntries,
                       "hard cap keeps the newest \(DeletionTombstones.maxEntries)")
    }

    func testTombstoneStore_mergeRemoteUnionsWithLocal() throws {
        let localID = UUID()
        let remoteID = UUID()
        DeletionTombstones.record(localID)

        let remoteData = try JSONEncoder.suberEncoder.encode(
            [DeletionTombstone(id: remoteID, deletedAt: Date())])
        let merged = DeletionTombstones.mergeRemote(remoteData)

        XCTAssertTrue(merged.contains(localID))
        XCTAssertTrue(merged.contains(remoteID))
        // Union must also persist so a relaunch still knows the peer's delete.
        XCTAssertTrue(DeletionTombstones.activeIDs().contains(remoteID))
    }

    func testTombstoneStore_mergeRemoteWithNilDataDegradesToLocalSet() {
        let localID = UUID()
        DeletionTombstones.record(localID)
        // Pre-tombstone peers never write the KVS key → nil data.
        XCTAssertEqual(DeletionTombstones.mergeRemote(nil), [localID])
    }

    func testTombstoneStore_removeMatchingClearsRestoredIDs() {
        let id = UUID()
        DeletionTombstones.record(id)
        DeletionTombstones.removeMatching([id])
        XCTAssertFalse(DeletionTombstones.activeIDs().contains(id),
                       "user Restore/Import must lift the tombstone or the next merge re-deletes")
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
