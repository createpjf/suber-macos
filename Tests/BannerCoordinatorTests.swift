import XCTest
@testable import Suber

/// A1 (eng re-review): BannerCoordinator picks ONE banner per render based on
/// priority: cancellationSuccess > firstCatch > sinceYouWereAway. Dismiss
/// cascades — dismissing the top banner reveals the next-priority banner on
/// the next render (if eligible).
@MainActor
final class BannerCoordinatorTests: XCTestCase {

    var flags: AutopilotFlags!
    var coordinator: BannerCoordinator!

    override func setUp() {
        super.setUp()
        let suite = UserDefaults(suiteName: "banner-coord-tests-\(UUID())")!
        flags = AutopilotFlags(defaults: suite)
        coordinator = BannerCoordinator(flags: flags)
    }

    override func tearDown() {
        flags.resetForTests()
        flags = nil
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Priority order

    func testCancellationSuccessBeatsEverything() {
        // Edge case: all three conditions eligible simultaneously. The rare
        // earned-success moment must win over the utility and first-catch.
        let now = Date()
        let sub = makeSub(name: "Netflix", amount: 22.99)
        let confirmed = SubscriptionChange(
            subscriptionID: sub.id, type: .cancellationConfirmed,
            detectedAt: now,
            previousValue: "22.99 USD", newValue: "0 USD",
            source: .backgroundCheck,
            previousBaseAmount: 22.99, newBaseAmount: 0
        )
        let kind = coordinator.activeBanner(
            changes: [confirmed],
            subscriptions: [sub],
            unreadCount: 5,             // makes sinceYouWereAway eligible
            primaryCurrency: "USD",
            now: now
        )
        if case .cancellationSuccess = kind {
            // pass
        } else {
            XCTFail("Expected cancellationSuccess, got \(String(describing: kind))")
        }
    }

    func testFirstCatchBeatsSinceYouWereAway() {
        let now = Date()
        let anyChange = SubscriptionChange(
            subscriptionID: nil, type: .newCharge,
            detectedAt: now, previousValue: nil, newValue: "9.99 USD",
            source: .mailWatchdog, newBaseAmount: 9.99
        )
        // hasSeenFirstCatch = false (default) → firstCatch eligible
        // unreadCount > 0 → sinceYouWereAway also eligible
        let kind = coordinator.activeBanner(
            changes: [anyChange],
            subscriptions: [],
            unreadCount: 3,
            primaryCurrency: "USD",
            now: now
        )
        XCTAssertEqual(kind, .firstCatch)
    }

    func testSinceYouWereAwayOnlyEligibleLast() {
        let now = Date()
        flags.hasSeenFirstCatch = true   // first-catch no longer eligible
        let kind = coordinator.activeBanner(
            changes: [],
            subscriptions: [],
            unreadCount: 5,
            primaryCurrency: "USD",
            now: now
        )
        XCTAssertEqual(kind, .sinceYouWereAway(count: 5))
    }

    // MARK: - No eligible banner

    func testReturnsNilWhenNothingEligible() {
        flags.hasSeenFirstCatch = true
        let kind = coordinator.activeBanner(
            changes: [],
            subscriptions: [],
            unreadCount: 0,
            primaryCurrency: "USD"
        )
        XCTAssertNil(kind)
    }

    func testFirstCatchNotEligibleAfterSeen() {
        flags.hasSeenFirstCatch = true
        let anyChange = SubscriptionChange(
            subscriptionID: nil, type: .newCharge,
            detectedAt: Date(), previousValue: nil, newValue: "9.99 USD",
            source: .mailWatchdog, newBaseAmount: 9.99
        )
        let kind = coordinator.activeBanner(
            changes: [anyChange],
            subscriptions: [],
            unreadCount: 0,
            primaryCurrency: "USD"
        )
        XCTAssertNil(kind, "After hasSeenFirstCatch + no unread, no banner")
    }

    func testSinceYouWereAwayNotEligibleSameDay() {
        flags.hasSeenFirstCatch = true
        flags.lastBannerShownAt = Date()   // shown today already
        let kind = coordinator.activeBanner(
            changes: [],
            subscriptions: [],
            unreadCount: 5,
            primaryCurrency: "USD"
        )
        XCTAssertNil(kind, "Same-day re-open doesn't re-show the banner")
    }

    func testSinceYouWereAwayEligibleNextDay() {
        flags.hasSeenFirstCatch = true
        // lastBannerShownAt = 2 days ago → next-day re-open re-eligible
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        flags.lastBannerShownAt = twoDaysAgo

        let kind = coordinator.activeBanner(
            changes: [],
            subscriptions: [],
            unreadCount: 5,
            primaryCurrency: "USD"
        )
        XCTAssertEqual(kind, .sinceYouWereAway(count: 5))
    }

    // MARK: - Dismiss cascade

    func testDismissCascadesToNextPriority() {
        // Use a fully-deterministic timeline: change detected 60s before
        // dismissal, dismissal at `now`, second-pass evaluated at now+1s.
        // Avoids the Date-Double round-trip precision quirk where
        // `change.detectedAt == flags.lastCelebrationAckedAt` could flip
        // the strict `>` comparison either way.
        let detected = Date(timeIntervalSince1970: 1_700_000_000)
        let dismissedAt = detected.addingTimeInterval(60)
        let sub = makeSub(name: "Netflix", amount: 22.99)
        let confirmed = SubscriptionChange(
            subscriptionID: sub.id, type: .cancellationConfirmed,
            detectedAt: detected, previousValue: "22.99 USD", newValue: "0 USD",
            source: .backgroundCheck,
            previousBaseAmount: 22.99, newBaseAmount: 0
        )

        // Round 1: success banner wins (lastCelebrationAckedAt is nil)
        let first = coordinator.activeBanner(
            changes: [confirmed], subscriptions: [sub],
            unreadCount: 5, primaryCurrency: "USD", now: dismissedAt
        )
        if case .cancellationSuccess = first {} else {
            XCTFail("First banner should be cancellationSuccess")
            return
        }

        // User dismisses success banner → flags.lastCelebrationAckedAt = dismissedAt
        coordinator.dismiss(first!, now: dismissedAt)
        XCTAssertNotNil(flags.lastCelebrationAckedAt)

        // Round 2: confirmed.detectedAt (older) <= ackedAt → success NOT eligible
        // firstCatch takes over (hasSeenFirstCatch still false)
        let second = coordinator.activeBanner(
            changes: [confirmed], subscriptions: [sub],
            unreadCount: 5, primaryCurrency: "USD",
            now: dismissedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(second, .firstCatch,
                       "Dismiss cascade: next-priority firstCatch should appear")
    }

    // MARK: - Annual savings math

    func testCancellationSuccessComputesAggregateSavings() {
        let now = Date()
        let netflix = makeSub(name: "Netflix", amount: 22.99, cycle: .monthly)
        let spotify = makeSub(name: "Spotify", amount: 9.99, cycle: .monthly)
        // Both confirmed today.
        let c1 = SubscriptionChange(
            subscriptionID: netflix.id, type: .cancellationConfirmed,
            detectedAt: now, previousValue: nil, newValue: nil,
            source: .backgroundCheck, newBaseAmount: 22.99
        )
        let c2 = SubscriptionChange(
            subscriptionID: spotify.id, type: .cancellationConfirmed,
            detectedAt: now, previousValue: nil, newValue: nil,
            source: .backgroundCheck, newBaseAmount: 9.99
        )

        let kind = coordinator.activeBanner(
            changes: [c1, c2],
            subscriptions: [netflix, spotify],
            unreadCount: 0, primaryCurrency: "USD",
            now: now
        )

        // Savings = 22.99*12 + 9.99*12 ≈ 275.88 + 119.88 ≈ 395 → floor to 394
        if case .cancellationSuccess(let savings, let names) = kind {
            XCTAssertEqual(savings, 394)
            XCTAssertEqual(Set(names), Set(["Netflix", "Spotify"]))
        } else {
            XCTFail("Expected cancellationSuccess")
        }
    }

    // MARK: - Helper

    private func makeSub(
        name: String,
        amount: Double,
        cycle: BillingCycle = .monthly
    ) -> Subscription {
        let now = Date()
        return Subscription(
            id: UUID(), name: name, amount: amount, currency: "USD",
            cycle: cycle, billingDay: 15, startDate: now, category: "Test",
            status: .cancelled, createdAt: now, updatedAt: now
        )
    }
}
