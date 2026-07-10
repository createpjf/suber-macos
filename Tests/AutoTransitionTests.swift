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
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        // AUDIT-v1.9.2 C-01: sandbox ALL file I/O into fresh per-test temp
        // dirs. This both protects the user's REAL App Group container /
        // Backups/ ring (the old setUp cleared live keys with no snapshot)
        // and gives stronger cross-test isolation than key-clearing ever did
        // (the v1.9.2 `suber-changes` leak between test methods).
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-autotransition-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-autotransition-backup-\(UUID().uuidString)")
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

    // MARK: - AUDIT-v1.9.2 C-05: cycle-aware billing-due gate

    /// Yearly sub, cancel tapped mid-cycle in March, anniversary in November.
    /// The old computeBillingDue ignored the cycle and produced a synthetic
    /// March date → a scan right after it saw zero charges (of course — the
    /// real renewal is in November) and falsely confirmed the cancellation.
    func testYearlySubVerifiesAtAnniversaryNotSyntheticMonthlyDate() {
        let sub = makePendingSub(
            name: "Dropbox",
            setAt: date(2026, 3, 10, 14, 0),
            billingDay: 20,
            cycle: .yearly,
            startDate: date(2025, 11, 20)
        )
        addSubscription(sub)

        // Scan lands right after the OLD synthetic monthly due (2026-03-20).
        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 3, 21, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .pendingCancellation,
                       "Yearly sub must NOT be evaluated in March — its renewal is in November")

        // After the true anniversary (+1-day grace) it may evaluate.
        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 11, 21, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .cancelled,
                       "After the November anniversary + grace day, zero charges → confirmed")
    }

    /// A scan on the billing day's early morning must not confirm — that
    /// day's charge email may not have arrived yet. Evaluation opens the
    /// day AFTER the billing day (1-day grace).
    func testScanOnBillingDayMorningDoesNotConfirmEarly() {
        let sub = makePendingSub(
            name: "Netflix",
            setAt: date(2026, 3, 10, 14, 0),
            billingDay: 15,
            startDate: date(2026, 1, 15)
        )
        addSubscription(sub)

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 3, 15, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .pendingCancellation,
                       "Billing-day 09:00 scan is too early — the 14:00 charge email hasn't arrived")

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 3, 16, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .cancelled,
                       "Day after the billing day, zero charges → confirmed")
    }

    /// Cancel tapped ON the billing day: that day's charge is ambiguous
    /// relative to the tap (day-granular statement data can't order them),
    /// so verification waits one full cycle instead of confirming days later.
    func testSameDayCancelWaitsFullCycle() {
        let sub = makePendingSub(
            name: "Netflix",
            setAt: date(2026, 3, 15, 14, 0),   // tapped ON the billing day
            billingDay: 15,
            startDate: date(2026, 1, 15)
        )
        addSubscription(sub)

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 3, 20, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .pendingCancellation,
                       "Same-day cancel: wait for the NEXT cycle, not this ambiguous one")

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 4, 16, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .cancelled,
                       "After the next cycle's billing day + grace, zero charges → confirmed")
    }

    /// billingDay=31 in February: the old DateComponents(2026-02-31) path
    /// normalized to March 3. The cycle-aware gate clamps to Feb 28 like the
    /// rest of BillingCalculator, so evaluation opens March 1.
    func testFeb31OverflowClampsToFebEnd() {
        let sub = makePendingSub(
            name: "Adobe",
            setAt: date(2026, 2, 10, 12, 0),
            billingDay: 31,
            startDate: date(2026, 1, 31)
        )
        addSubscription(sub)

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 2, 28, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .pendingCancellation,
                       "Feb 28 morning is still within the clamped billing day")

        store.checkPendingCancellationTransitions(
            transactions: [],
            dataSourceCoversWindow: true,
            now: date(2026, 3, 1, 9, 0)
        )
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == sub.id })!.status,
                       .cancelled,
                       "Clamped Feb-28 billing day + grace → evaluation opens Mar 1, not Mar 4")
    }

    // MARK: - Helpers

    private func makePendingSub(
        name: String,
        setAt: Date,
        billingDay: Int,
        cycle: BillingCycle = .monthly,
        startDate: Date? = nil
    ) -> Subscription {
        Subscription(
            id: UUID(), name: name, amount: 22.99, currency: "USD",
            cycle: cycle, billingDay: billingDay, startDate: startDate ?? setAt,
            category: "Entertainment", status: .pendingCancellation,
            createdAt: setAt, updatedAt: setAt,
            pendingCancellationSetAt: setAt
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return Calendar(identifier: .gregorian).date(from: comps)!
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
