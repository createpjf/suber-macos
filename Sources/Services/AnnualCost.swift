import Foundation

// ┌───────────── AnnualCost — Single Source of Money Math (v1.6) ──────────────┐
// │                                                                            │
// │  3+ user-visible surfaces need "how much does this sub cost per year":     │
// │                                                                            │
// │    ChangeRowView (priceChange row)  ─┐                                     │
// │    CancellationSuccessBanner        ─┼─► BillingCycle.annualAmount(...)    │
// │    Monthly trend chart              ─┘                                     │
// │                                                                            │
// │  One helper, one rounding policy, one source of truth. Fixes Q1 DRY        │
// │  finding from eng re-review.                                               │
// │                                                                            │
// │  Cross-currency rule: convert via ExchangeRateService BEFORE calling       │
// │  annualAmount. This helper does the cycle math, not currency conversion.   │
// │                                                                            │
// │  Rounding rule: this helper returns FULL precision. Rounding to whole      │
// │  dollars is a display-layer concern — the view decides whether to          │
// │  `Int(floor($0))` or `String(format: "%.2f", $0)`. Keeps rounding          │
// │  decisions out of the math, so snapshots/unit tests don't drift on         │
// │  tiny currency-conversion fluctuations.                                    │
// └────────────────────────────────────────────────────────────────────────────┘

extension BillingCycle {
    /// Annualize an amount in this cycle's currency. Full precision; caller
    /// applies display rounding. Returns 0 for `.oneTime` (not recurring).
    ///
    /// - Parameter amount: the per-cycle amount, in ANY currency (conversion
    ///   must happen before this call via `ExchangeRateService.convert`).
    /// - Returns: annualized amount at full Double precision.
    func annualAmount(_ amount: Double) -> Double {
        switch self {
        case .weekly:    return amount * 52
        case .monthly:   return amount * 12
        case .quarterly: return amount * 4
        case .yearly:    return amount
        case .oneTime:   return 0  // not recurring; one-time purchases have no annual cost
        }
    }
}

enum AnnualCost {
    /// Annualized amount for a subscription, in a target currency.
    /// Handles currency conversion + cycle math + split-count.
    ///
    /// Example: Netflix $22.99/mo USD, target USD → 22.99 * 12 = 275.88
    /// Example: 爱奇艺 ¥188/yr CNY, target USD → 188 / 7.24 ≈ 25.97
    static func inTargetCurrency(
        sub: Subscription,
        target: String,
        rates: ExchangeRateService = .shared
    ) -> Double {
        let converted = rates.convert(sub.effectiveAmount, from: sub.currency, to: target)
        return sub.cycle.annualAmount(converted)
    }

    /// Annualized SAVINGS when a sub is cancelled. Same as annualized cost,
    /// but rounded DOWN to whole dollars for display. The subtle whole-dollar
    /// rounding prevents "$215.40/year" copy which reads as over-precise /
    /// unearned. "$215/year" is a cleaner promise.
    ///
    /// Used by CancellationSuccessBanner: "You'll save $X/year."
    static func annualSavings(sub: Subscription, target: String) -> Int {
        let annual = inTargetCurrency(sub: sub, target: target)
        return Int(annual.rounded(.down))
    }
}
