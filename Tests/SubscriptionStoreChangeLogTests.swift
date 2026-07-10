import XCTest
@testable import Suber

/// Covers the change-log write path on SubscriptionStore:
///   - recordAndPersist dedup via M3 canonical-currency hash
///   - H5 prune-on-write 200-entry hard cap (AUDIT-v1.9.2 C-30: cap only —
///     the 14-day window is purely the unreadChangeCount badge policy)
///   - unreadChangeCount 14-day badge window
///   - markChangeAcknowledged / markAllChangesAcknowledged
///   - markPendingCancellation D5 idempotency
@MainActor
final class SubscriptionStoreChangeLogTests: XCTestCase {

    var store: SubscriptionStore!
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        // AUDIT-v1.9.2 C-01: sandbox ALL file I/O into fresh per-test temp
        // dirs — the old setUp/tearDown cleared the user's REAL App Group
        // container and recordAndPersist rotated real Backups/ snapshots.
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-changelog-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-changelog-backup-\(UUID().uuidString)")
        AppGroupStore.testOverrideDirectory = tempStoreDir
        DataBackupManager.testOverrideDirectory = tempBackupDir
        store = SubscriptionStore()
    }

    override func tearDown() {
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
        if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    // MARK: - recordAndPersist dedup

    func testRecordAndPersistDedupsByHash() {
        let change = makeChange(type: .priceChange, previousBase: 15.99, newBase: 22.99)

        store.recordAndPersist(changes: [change])
        store.recordAndPersist(changes: [change])  // same change, same day

        XCTAssertEqual(store.changes.count, 1,
                       "Same dedupHash → only one entry retained")
    }

    func testRecordAndPersistAcceptsDistinctHashes() {
        let netflix = makeChange(type: .priceChange, previousBase: 15.99, newBase: 22.99)
        let spotify = makeChange(type: .priceChange, previousBase: 9.99, newBase: 10.99)

        store.recordAndPersist(changes: [netflix, spotify])
        XCTAssertEqual(store.changes.count, 2)
    }

    // MARK: - H5 prune-on-write

    func testPruneKeepsRecent200WhenOverflowing() {
        // 250 distinct changes across 30 minutes — all recent, so this
        // isolates the 200-entry hard cap (the only prune rule; C-30).
        var many: [SubscriptionChange] = []
        let base = Date()
        for i in 0..<250 {
            let date = base.addingTimeInterval(-TimeInterval(i))  // staggered
            many.append(SubscriptionChange(
                subscriptionID: UUID(), type: .priceChange,
                detectedAt: date, previousValue: nil, newValue: "\(i)",
                source: .csvImport,
                previousBaseAmount: Double(i), newBaseAmount: Double(i + 1)
            ))
        }
        store.recordAndPersist(changes: many)

        // After save, load from storage to verify the prune persisted (not
        // just in-memory trim).
        let reloaded = StorageService.shared.loadChanges()
        XCTAssertLessThanOrEqual(reloaded.count, 200,
                                 "H5: prune-on-write caps at 200 entries")
    }

    func testMergeRemoteChangesPrunesTo200() {
        // 250 distinct remote changes merged into an empty log must end up
        // pruned to the 200-entry cap — both in memory and on disk. Guards the
        // v1.9.2 fix: mergeRemoteChanges used to bypass H5 prune.
        var remote: [SubscriptionChange] = []
        let base = Date()
        for i in 0..<250 {
            remote.append(SubscriptionChange(
                subscriptionID: UUID(), type: .priceChange,
                detectedAt: base.addingTimeInterval(-TimeInterval(i)),
                previousValue: nil, newValue: "\(i)",
                source: .csvImport,
                previousBaseAmount: Double(i), newBaseAmount: Double(i + 1)
            ))
        }

        store.mergeRemoteChanges(remote)

        XCTAssertLessThanOrEqual(store.changes.count, 200,
                                 "in-memory log must be pruned to 200")
        let reloaded = StorageService.shared.loadChanges()
        XCTAssertLessThanOrEqual(reloaded.count, 200,
                                 "persisted log must be pruned to 200")
    }

    func testPruneRetainsAllEntriesWithin14Days() {
        // 50 entries all within today → under the 200 cap, nothing pruned
        // (C-30: age never prunes; only the count cap does).
        var list: [SubscriptionChange] = []
        let now = Date()
        for i in 0..<50 {
            list.append(SubscriptionChange(
                subscriptionID: UUID(), type: .newCharge,
                detectedAt: now, previousValue: nil, newValue: "\(i)",
                source: .csvImport, newBaseAmount: Double(i)
            ))
        }
        store.recordAndPersist(changes: list)
        XCTAssertEqual(store.changes.count, 50)
    }

    func testPruneDropsEntriesOlderThan14DaysBeyondCap() {
        let calendar = Calendar.current
        let now = Date()
        let old = calendar.date(byAdding: .day, value: -30, to: now)!

        // 202 total (201 recent + 1 ancient) → the 200-most-recent survive;
        // the ancient one is dropped because it sorts last, not because of
        // its age (C-30: prune is a pure hard cap).
        var list: [SubscriptionChange] = []
        for i in 0..<201 {
            list.append(SubscriptionChange(
                subscriptionID: UUID(), type: .priceChange,
                detectedAt: now.addingTimeInterval(-Double(i)),
                previousValue: nil, newValue: "r\(i)",
                source: .csvImport, newBaseAmount: Double(i)
            ))
        }
        list.append(SubscriptionChange(
            subscriptionID: UUID(), type: .priceChange,
            detectedAt: old, previousValue: nil, newValue: "ancient",
            source: .csvImport, newBaseAmount: -1
        ))

        let pruned = StorageService.prune(list)
        // Expect none of the ancient ones, and at most 200 total.
        XCTAssertLessThanOrEqual(pruned.count, 200)
        XCTAssertFalse(pruned.contains { $0.newValue == "ancient" },
                       "Ancient entry outside 14d window must be pruned when over cap")
    }

    // MARK: - unreadChangeCount badge window (14 days)

    func testUnreadCountCountsOnlyUnacknowledgedWithin14Days() {
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -20, to: now)!

        let recentUnread = SubscriptionChange(
            id: UUID(), subscriptionID: UUID(), type: .priceChange,
            detectedAt: now, previousValue: nil, newValue: "recent",
            source: .csvImport, acknowledged: false, newBaseAmount: 1
        )
        let oldUnread = SubscriptionChange(
            id: UUID(), subscriptionID: UUID(), type: .priceChange,
            detectedAt: old, previousValue: nil, newValue: "old",
            source: .csvImport, acknowledged: false, newBaseAmount: 2
        )
        let recentAcked = SubscriptionChange(
            id: UUID(), subscriptionID: UUID(), type: .priceChange,
            detectedAt: now, previousValue: nil, newValue: "acked",
            source: .csvImport, acknowledged: true, newBaseAmount: 3
        )
        store.recordAndPersist(changes: [recentUnread, oldUnread, recentAcked])

        // Only recentUnread counts: old is outside 14d window, acked is
        // acknowledged.
        XCTAssertEqual(store.unreadChangeCount, 1)
    }

    // MARK: - ack helpers

    func testMarkChangeAcknowledged() {
        let c = makeChange(type: .priceChange, previousBase: 10, newBase: 12)
        store.recordAndPersist(changes: [c])
        XCTAssertEqual(store.unreadChangeCount, 1)

        store.markChangeAcknowledged(id: c.id)
        XCTAssertEqual(store.unreadChangeCount, 0)
    }

    func testMarkAllChangesAcknowledged() {
        let a = makeChange(type: .priceChange, previousBase: 1, newBase: 2)
        let b = makeChange(type: .newCharge, previousBase: nil, newBase: 5)
        store.recordAndPersist(changes: [a, b])
        XCTAssertEqual(store.unreadChangeCount, 2)

        store.markAllChangesAcknowledged()
        XCTAssertEqual(store.unreadChangeCount, 0)
    }

    // MARK: - D5 idempotent markPendingCancellation

    func testMarkPendingCancellationSetsAnchorAndStatus() {
        var data = SubscriptionFormData()
        data.name = "Netflix"; data.amount = "15.99"; data.currency = "USD"
        data.cycle = .monthly; data.billingDay = 15
        store.add(data)

        let id = store.subscriptions[0].id
        let firstTap = Date(timeIntervalSince1970: 1_700_000_000)
        store.markPendingCancellation(id: id, now: firstTap)

        XCTAssertEqual(store.subscriptions[0].status, .pendingCancellation)
        XCTAssertEqual(store.subscriptions[0].pendingCancellationSetAt, firstTap)
    }

    func testMarkPendingCancellationReTapDoesNotResetAnchor() {
        // D5: re-tapping "Open cancel page" on an already-pending sub re-opens
        // the URL (view layer does that) but does NOT mutate the anchor in the
        // model — D4 auto-transition window stays pinned to the original tap.
        var data = SubscriptionFormData()
        data.name = "Netflix"; data.amount = "15.99"; data.currency = "USD"
        data.cycle = .monthly; data.billingDay = 15
        store.add(data)

        let id = store.subscriptions[0].id
        let firstTap = Date(timeIntervalSince1970: 1_700_000_000)
        let secondTap = Date(timeIntervalSince1970: 1_700_000_000 + 86_400 * 3)

        store.markPendingCancellation(id: id, now: firstTap)
        store.markPendingCancellation(id: id, now: secondTap)

        XCTAssertEqual(store.subscriptions[0].pendingCancellationSetAt, firstTap,
                       "D5: re-tap must NOT reset pendingCancellationSetAt")
    }

    // MARK: - Helpers

    private func makeChange(
        type: SubscriptionChange.ChangeType,
        previousBase: Double?,
        newBase: Double?
    ) -> SubscriptionChange {
        SubscriptionChange(
            subscriptionID: UUID(),
            type: type,
            detectedAt: Date(),
            previousValue: previousBase.map { String($0) },
            newValue: newBase.map { String($0) },
            source: .csvImport,
            previousBaseAmount: previousBase,
            newBaseAmount: newBase
        )
    }
}
