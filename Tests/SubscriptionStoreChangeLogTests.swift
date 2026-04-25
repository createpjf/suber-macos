import XCTest
@testable import Suber

/// Covers the change-log write path on SubscriptionStore:
///   - recordAndPersist dedup via M3 canonical-currency hash
///   - H5 prune-on-write at 200-entry / 14-day threshold
///   - unreadChangeCount 14-day badge window
///   - markChangeAcknowledged / markAllChangesAcknowledged
///   - markPendingCancellation D5 idempotency
@MainActor
final class SubscriptionStoreChangeLogTests: XCTestCase {

    var store: SubscriptionStore!
    let suiteName = "group.com.suber.app"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removeObject(forKey: "suber-subscriptions")
        defaults.removeObject(forKey: "suber-changes")
        store = SubscriptionStore()
    }

    override func tearDown() {
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removeObject(forKey: "suber-subscriptions")
        defaults.removeObject(forKey: "suber-changes")
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
        // 250 distinct changes across 30 minutes → 200-entry cap kicks in
        // after the 14-day-window layer passes them all. Pass SAVE twice to
        // exercise the prune path inside saveChanges.
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

    func testPruneRetainsAllEntriesWithin14Days() {
        // 50 entries all within today → no pruning by count (under 200),
        // no pruning by age (all < 14d).
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

        // 201 recent + 1 ancient. Prune should keep the 200-most-recent, drop
        // the ancient one (and 1 of the recent ones, since cap is 200).
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

        let pruned = StorageService.prune(list, now: now)
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
