import XCTest
@testable import Suber

/// Q1 (eng re-review): BillingCycle.annualAmount is the single source for the
/// "how much does this sub cost per year" math used by ChangeRowView,
/// CancellationSuccessBanner, and the monthly trend chart. One helper, one
/// rounding policy, one place to fix when a bug ships.
final class AnnualCostTests: XCTestCase {

    // MARK: - Cycle math (full-precision return)

    func testMonthlyCycleMultipliesBy12() {
        XCTAssertEqual(BillingCycle.monthly.annualAmount(10), 120)
        XCTAssertEqual(BillingCycle.monthly.annualAmount(22.99), 275.88, accuracy: 0.001)
    }

    func testWeeklyCycleMultipliesBy52() {
        XCTAssertEqual(BillingCycle.weekly.annualAmount(5), 260)
    }

    func testWeeklyAnnualAgreesAcrossDashboardAndAnnualCost() {
        // AUDIT-v1.9.2 C-36: Dashboard annualizes via getMonthlyEquivalent × 12,
        // banners via annualAmount. 4.33 vs 52 weeks/year gave the same sub two
        // yearly figures ($519.60 vs $520.00) — both paths must agree.
        let sub = makeSub(amount: 10, currency: "USD", cycle: .weekly)
        let dashboardAnnual = BillingCalculator.getMonthlyEquivalent(sub) * 12
        let bannerAnnual = BillingCycle.weekly.annualAmount(10)
        XCTAssertEqual(dashboardAnnual, bannerAnnual, accuracy: 0.0001)
        XCTAssertEqual(bannerAnnual, 520)
    }

    func testQuarterlyCycleMultipliesBy4() {
        XCTAssertEqual(BillingCycle.quarterly.annualAmount(30), 120)
    }

    func testYearlyCycleReturnsIdentity() {
        XCTAssertEqual(BillingCycle.yearly.annualAmount(188), 188)
    }

    func testOneTimeCycleReturnsZero() {
        // One-time purchases have no annual cost. Including them in "annual
        // savings" would inflate the cancellation success banner's number.
        XCTAssertEqual(BillingCycle.oneTime.annualAmount(500), 0)
    }

    // MARK: - Cross-currency via AnnualCost.inTargetCurrency

    func testCrossCurrencyConvertsBeforeAnnualizing() {
        // 188 CNY/year converted to USD. Actual rate is whatever
        // ExchangeRateService is currently using (may be cached API data).
        // Verify the helper's output matches convert() * cycle math.
        let sub = makeSub(amount: 188, currency: "CNY", cycle: .yearly)
        let usd = AnnualCost.inTargetCurrency(sub: sub, target: "USD")
        let expected = ExchangeRateService.shared.convert(188, from: "CNY", to: "USD")
        XCTAssertEqual(usd, expected, accuracy: 0.01,
                       "Helper must delegate currency conversion to ExchangeRateService")
    }

    func testSameCurrencyNoConversion() {
        let sub = makeSub(amount: 22.99, currency: "USD", cycle: .monthly)
        let usd = AnnualCost.inTargetCurrency(sub: sub, target: "USD")
        XCTAssertEqual(usd, 22.99 * 12, accuracy: 0.001)
    }

    func testSplitCountReducesPerPersonAnnual() {
        // Family plan split 4 ways: $20/mo per family, $5/mo per person,
        // $60/yr per person.
        let sub = makeSub(amount: 20, currency: "USD", cycle: .monthly, splitCount: 4)
        let annual = AnnualCost.inTargetCurrency(sub: sub, target: "USD")
        XCTAssertEqual(annual, 60, accuracy: 0.001)
    }

    // MARK: - annualSavings (rounds DOWN to whole dollars)

    func testAnnualSavingsRoundsDown() {
        // $22.99/mo = $275.88/yr → should display as $275 (not $276).
        // Under-promise, over-deliver: never overstate savings to the user.
        let sub = makeSub(amount: 22.99, currency: "USD", cycle: .monthly)
        XCTAssertEqual(AnnualCost.annualSavings(sub: sub, target: "USD"), 275)
    }

    func testAnnualSavingsWholeDollarInput() {
        let sub = makeSub(amount: 10, currency: "USD", cycle: .monthly)
        XCTAssertEqual(AnnualCost.annualSavings(sub: sub, target: "USD"), 120)
    }

    func testAnnualSavingsOneTimeIsZero() {
        let sub = makeSub(amount: 500, currency: "USD", cycle: .oneTime)
        XCTAssertEqual(AnnualCost.annualSavings(sub: sub, target: "USD"), 0)
    }

    // MARK: - Helper

    private func makeSub(
        amount: Double,
        currency: String,
        cycle: BillingCycle,
        splitCount: Int = 1
    ) -> Subscription {
        let now = Date()
        return Subscription(
            id: UUID(),
            name: "Test",
            amount: amount,
            currency: currency,
            cycle: cycle,
            billingDay: 1,
            startDate: now,
            category: "Test",
            status: .active,
            splitCount: splitCount,
            createdAt: now,
            updatedAt: now
        )
    }
}
