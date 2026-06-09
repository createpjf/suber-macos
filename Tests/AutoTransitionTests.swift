import XCTest
@testable import Suber

/// A4 (eng re-review): data-source-gated auto-transition. The plan's biggest
/// trust issue — v1.5-style users who manually added subs (no Mail / no CSV)
/// must NOT get false-positive auto-cancellations.
///
/// D4 window logic: check full window from pendingCancellationSetAt to now
/// for matching transactions. Zero → .cancelled. Match → .active + logs
/// cancellationFailed. No data source → stay pending.
@MainActor
final class AutoTransitionTests: XCTestCase {

    var store: SubscriptionStore!
    let suiteName = "group.com.suber.app"

    override func setUp() {
        super.setUp()
        // v1.9.2: SubscriptionStore loads from the file-based AppGroupStore
        // (since v1.6.2), NOT legacy UserDefaults — so clearing only the
        // UserDefaults suite left `suber-changes` dirty between test methods.
        // A cancellationConfirmed written by testZeroCharges… leaked through
        // the AppGroupStore file and tripped testNoDataSourceLeavesSubPending
        // (depending on method execution order). Clear BOTH stores.
        AppGroupStore.removeObject(forKey: "suber-subscriptions")
        AppGroupStore.removeObject(forKey: "suber-changes")
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removeObject(forKey: "suber-subscriptions")
        defaults.removeObject(forKey: "suber-changes")
        store = SubscriptionStore()
    }

    override func tearDown() {
        AppGroupStore.removeObject(forKey: "suber-subscriptions")
        AppGroupStore.removeObject(forKey: "suber-changes")
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
        defaults.removeObject(forKey: "suber-subscriptions")
        defaults.removeObject(forKey: "suber-changes")
        super.tearDown()
    }

    // MARK: - Happy path: confirmed cancellation

    func testZeroChargesInWindowTransitionsToCancelled() {
        let pendingSetAt = daysAgo(35)
        let sub = makePendingSub(name: "Netflix", setAt: pendingSetAt, billingDay: dayOfMonth(pendingSetAt))
        addSubscription(sub)

        store.checkPendingCancellationTransitions(
            transactions: [],   // no matching charges
            dataSourceCoversWindow: true,
            now: Date()
        )

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.status, .cancelled)
        XCTAssertNil(updated.pendingCancellationSetAt,
                     "Transition clears the anchor")

        // Should have logged a cancellationConfirmed change
        XCTAssertTrue(
            store.changes.contains(where: { $0.type == .cancellationConfirmed && $0.subscriptionID == sub.id }),
            "cancellationConfirmed change logged"
        )
    }

    // MARK: - Failure path: charge detected in window

    func testMatchingChargeInWindowTransitionsBackToActive() {
        let pendingSetAt = daysAgo(35)
        let sub = makePendingSub(name: "Netflix", setAt: pendingSetAt, billingDay: dayOfMonth(pendingSetAt))
        addSubscription(sub)

        // A Netflix charge landed 5 days ago — cancellation didn't take.
        let netflixCharge = StatementTransaction(
            date: daysAgo(5),
            merchantRaw: "NETFLIX.COM 866-579-7172",
            amount: 22.99,
            currency: "USD"
        )

        store.checkPendingCancellationTransitions(
            transactions: [netflixCharge],
            dataSourceCoversWindow: true,
            now: Date()
        )

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.status, .active,
                       "Matching charge → roll back to active")
        XCTAssertNil(updated.pendingCancellationSetAt)

        XCTAssertTrue(
            store.changes.contains(where: { $0.type == .cancellationFailed && $0.subscriptionID == sub.id }),
            "cancellationFailed change logged"
        )
    }

    // MARK: - A4 gate: no data source = stay pending

    func testNoDataSourceLeavesSubPending() {
        let pendingSetAt = daysAgo(35)
        let sub = makePendingSub(name: "Netflix", setAt: pendingSetAt, billingDay: dayOfMonth(pendingSetAt))
        addSubscription(sub)

        // Zero matching charges + NO data source covering the window
        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: false,
            now: Date()
        )

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.status, .pendingCancellation,
                       "A4: stay pending when no data source — would otherwise be false-positive confirm")
        XCTAssertNotNil(updated.pendingCancellationSetAt)

        XCTAssertFalse(
            store.changes.contains(where: { $0.type == .cancellationConfirmed && $0.subscriptionID == sub.id }),
            "No cancellationConfirmed logged — honesty wins over convenience"
        )
    }

    // MARK: - Billing-day gate

    func testBeforeBillingDueDateStaysPending() {
        // User tapped cancel 2 days ago; billing day is 30 days out.
        // Too early to evaluate — even zero charges doesn't confirm yet.
        let now = Date()
        let setAt = now.addingTimeInterval(-2 * 86_400)
        let billingDay = ((Calendar.current.component(.day, from: now) + 25) % 28) + 1
        let sub = makePendingSub(name: "Netflix", setAt: setAt, billingDay: billingDay)
        addSubscription(sub)

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: now
        )

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.status, .pendingCancellation,
                       "Before billing day passes, don't evaluate")
    }

    // MARK: - D5: re-tap idempotency across windows

    func testReTapDoesNotAllowFraudulentEarlyConfirm() {
        // Simulate: user taps cancel day 1. Re-taps day 20. Without D5
        // guard, the second tap would reset the anchor to day 20, making
        // the "full window" check skip the real charge that landed day 5.
        //
        // Verify: anchor stays at the FIRST tap, and the scan would
        // correctly detect the charge.
        let firstTap = daysAgo(40)
        let sub = makePendingSub(name: "Netflix", setAt: firstTap, billingDay: dayOfMonth(firstTap))
        addSubscription(sub)

        // User re-taps now (sub still pending) — markPendingCancellation
        // should idempotent.
        let reTap = daysAgo(10)
        store.markPendingCancellation(id: sub.id, now: reTap)

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.pendingCancellationSetAt, firstTap,
                       "D5: re-tap anchor is pinned to first tap")
    }

    // MARK: - Non-pending subs ignored

    func testActiveSubsNotTouched() {
        var data = SubscriptionFormData()
        data.name = "Netflix"; data.amount = "22.99"; data.currency = "USD"
        data.cycle = .monthly; data.billingDay = 15
        store.add(data)

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: Date()
        )

        XCTAssertEqual(store.subscriptions[0].status, .active,
                       "Active subs must not be touched by the transition check")
    }

    // MARK: - Cross-merchant matching (via MerchantNormalizer)

    func testMerchantNormalizationMatchesAgainstChargeVariants() {
        let pendingSetAt = daysAgo(35)
        let sub = makePendingSub(name: "Netflix", setAt: pendingSetAt, billingDay: dayOfMonth(pendingSetAt))
        addSubscription(sub)

        // Bank statement shows "Netflix.com 866-579-7172" — should still match
        // "Netflix" via MerchantNormalizer (phone strip + domain strip).
        let charge = StatementTransaction(
            date: daysAgo(5),
            merchantRaw: "Netflix.com 866-579-7172",
            amount: 22.99,
            currency: "USD"
        )

        store.checkPendingCancellationTransitions(
            transactions: [charge],
            dataSourceCoversWindow: true,
            now: Date()
        )

        let updated = store.subscriptions.first(where: { $0.id == sub.id })!
        XCTAssertEqual(updated.status, .active,
                       "Merchant normalizer collapses ALIPAY*NETFLIX* to netflix")
    }

    // MARK: - Helpers

    private func makePendingSub(name: String, setAt: Date, billingDay: Int) -> Subscription {
        Subscription(
            id: UUID(), name: name, amount: 22.99, currency: "USD",
            cycle: .monthly, billingDay: billingDay, startDate: setAt,
            category: "Entertainment", status: .pendingCancellation,
            createdAt: setAt, updatedAt: setAt,
            pendingCancellationSetAt: setAt
        )
    }

    /// Add via direct mutation (bypasses form-data path — tests need the
    /// sub in a specific pending state).
    private func addSubscription(_ sub: Subscription) {
        store.subscriptions.append(sub)
    }

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    private func dayOfMonth(_ date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }
}
