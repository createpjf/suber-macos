import Foundation

// ┌───────────── BannerCoordinator — A1 priority single-slot picker ───────────┐
// │                                                                            │
// │  Three banners can share the ChangesListView top slot:                     │
// │    1. cancellationSuccess — earned, concrete $ savings, rare                │
// │    2. firstCatch          — once-forever trust-fall payoff                  │
// │    3. sinceYouWereAway    — daily utility                                   │
// │                                                                            │
// │  Coordinator picks ONE. User dismisses it, next-priority (if eligible)     │
// │  appears on re-open. Prevents 168pt banner stack on edge cases.            │
// │                                                                            │
// │  Eligibility rules:                                                        │
// │    - cancellationSuccess: there's >= 1 cancellationConfirmed change since  │
// │      flags.lastCelebrationAckedAt                                          │
// │    - firstCatch: !flags.hasSeenFirstCatch AND there's >= 1 change today    │
// │    - sinceYouWereAway: store.unreadChangeCount > 0 AND last shown !=       │
// │      today's date                                                          │
// │                                                                            │
// │  Pure function over state. SwiftUI reads `activeBanner(for:)` during       │
// │  render; dismiss() mutates flags so the next render picks differently.     │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

@MainActor
final class BannerCoordinator {
    enum Kind: Equatable {
        case cancellationSuccess(savings: Int, serviceNames: [String])
        case firstCatch
        case sinceYouWereAway(count: Int)
    }

    private let flags: AutopilotFlags
    private let calendar: Calendar

    init(flags: AutopilotFlags, calendar: Calendar = .current) {
        self.flags = flags
        self.calendar = calendar
    }

    /// Pick the highest-priority eligible banner, or nil if none.
    ///
    /// - Parameters:
    ///   - changes: the full store.changes log (NOT just the Window's initialChanges —
    ///     the coordinator needs to evaluate fresh state on every render).
    ///   - subscriptions: to resolve serviceNames for cancellationSuccess.
    ///   - unreadCount: store.unreadChangeCount (14-day badge window).
    ///   - primaryCurrency: for the annual-savings figure.
    ///   - now: injectable for tests.
    func activeBanner(
        changes: [SubscriptionChange],
        subscriptions: [Subscription],
        unreadCount: Int,
        primaryCurrency: String,
        now: Date = Date()
    ) -> Kind? {

        // Priority 1: cancellation-success (rare, high-emotional weight)
        if let banner = cancellationSuccessBanner(
            changes: changes,
            subscriptions: subscriptions,
            primaryCurrency: primaryCurrency,
            now: now
        ) { return banner }

        // Priority 2: first-catch (once-forever)
        if !flags.hasSeenFirstCatch && hasAnyChangeToday(changes: changes, now: now) {
            return .firstCatch
        }

        // Priority 3: since-you-were-away (daily utility)
        if unreadCount > 0 && !wasShownToday(flags.lastBannerShownAt, now: now) {
            return .sinceYouWereAway(count: unreadCount)
        }

        return nil
    }

    // MARK: - Dismissal actions (mutate AutopilotFlags)

    /// User clicked ✕ on the current banner. Bumps the appropriate flag so the
    /// same banner won't re-render until its next eligibility trigger.
    func dismiss(_ kind: Kind, now: Date = Date()) {
        switch kind {
        case .cancellationSuccess:
            flags.lastCelebrationAckedAt = now
        case .firstCatch:
            flags.hasSeenFirstCatch = true
        case .sinceYouWereAway:
            flags.lastBannerShownAt = now
        }
    }

    // MARK: - Cancellation-success eligibility

    /// Return a banner if any `cancellationConfirmed` change has landed since
    /// the last celebration ack — could span one or many subs.
    private func cancellationSuccessBanner(
        changes: [SubscriptionChange],
        subscriptions: [Subscription],
        primaryCurrency: String,
        now: Date
    ) -> Kind? {
        let sinceDate = flags.lastCelebrationAckedAt ?? .distantPast
        let confirmed = changes
            .filter { $0.type == .cancellationConfirmed && $0.detectedAt > sinceDate }
            .sorted { $0.detectedAt < $1.detectedAt }

        guard !confirmed.isEmpty else { return nil }

        // Resolve service names from subscriptionID → Subscription, capped at 3
        // per the design-review D11 spec ("N subs cancelled" for 4+).
        let names: [String] = confirmed.compactMap { change in
            guard let id = change.subscriptionID,
                  let sub = subscriptions.first(where: { $0.id == id }) else { return nil }
            return sub.name
        }

        // Annual savings: sum across matched subs. Use AnnualCost to stay in
        // sync with ChangeRowView's confirmed-log-row figure.
        let savings: Int = confirmed.reduce(0) { total, change in
            guard let id = change.subscriptionID,
                  let sub = subscriptions.first(where: { $0.id == id }) else { return total }
            return total + AnnualCost.annualSavings(sub: sub, target: primaryCurrency)
        }

        return .cancellationSuccess(savings: savings, serviceNames: names)
    }

    // MARK: - First-catch eligibility

    private func hasAnyChangeToday(changes: [SubscriptionChange], now: Date) -> Bool {
        // "Today" = calendar day, user's local timezone.
        changes.contains { calendar.isDate($0.detectedAt, inSameDayAs: now) }
    }

    // MARK: - Since-you-were-away eligibility

    private func wasShownToday(_ shownAt: Date?, now: Date) -> Bool {
        guard let shownAt else { return false }
        return calendar.isDate(shownAt, inSameDayAs: now)
    }
}
