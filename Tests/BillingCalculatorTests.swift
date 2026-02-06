import XCTest
@testable import SubReminder

final class BillingCalculatorTests: XCTestCase {

    private func makeSub(
        cycle: BillingCycle = .monthly,
        billingDay: Int = 15,
        startDate: String = "2025-01-15",
        amount: Double = 9.99,
        status: SubscriptionStatus = .active
    ) -> Subscription {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: startDate)!

        return Subscription(
            id: UUID(),
            name: "Test",
            url: "https://example.com",
            amount: amount,
            currency: "USD",
            cycle: cycle,
            billingDay: billingDay,
            startDate: date,
            category: "Other",
            status: status,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeDate(_ str: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)!
    }

    // MARK: - getNextBillingDate

    func testNextBillingDateMonthly() {
        let sub = makeSub(cycle: .monthly, billingDay: 15, startDate: "2020-01-15")
        let next = BillingCalculator.getNextBillingDate(sub)
        // Should be on or after today
        XCTAssertGreaterThanOrEqual(next, Calendar.current.startOfDay(for: Date()))
        // Should be on day 15
        XCTAssertEqual(Calendar.current.component(.day, from: next), 15)
    }

    func testNextBillingDateOneTime() {
        let sub = makeSub(cycle: .oneTime, startDate: "2020-06-15")
        let next = BillingCalculator.getNextBillingDate(sub)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: next), 2020)
        XCTAssertEqual(cal.component(.month, from: next), 6)
        XCTAssertEqual(cal.component(.day, from: next), 15)
    }

    func testNextBillingDateWeekly() {
        let sub = makeSub(cycle: .weekly, startDate: "2020-01-06")
        let next = BillingCalculator.getNextBillingDate(sub)
        XCTAssertGreaterThanOrEqual(next, Calendar.current.startOfDay(for: Date()))
    }

    // MARK: - getBillingDateInMonth

    func testBillingDateInMonthMonthly() {
        let sub = makeSub(cycle: .monthly, billingDay: 15, startDate: "2025-01-15")
        let date = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 3)
        XCTAssertNotNil(date)
        XCTAssertEqual(Calendar.current.component(.day, from: date!), 15)
        XCTAssertEqual(Calendar.current.component(.month, from: date!), 3)
    }

    func testBillingDateInMonthBeforeStart() {
        let sub = makeSub(cycle: .monthly, billingDay: 15, startDate: "2025-06-15")
        let date = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 3)
        XCTAssertNil(date)
    }

    func testBillingDateInMonthYearlyOnlyAnniversary() {
        let sub = makeSub(cycle: .yearly, billingDay: 15, startDate: "2024-03-15")
        // March should show
        let marchDate = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 3)
        XCTAssertNotNil(marchDate)
        // June should not show
        let juneDate = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 6)
        XCTAssertNil(juneDate)
    }

    func testBillingDateInMonthQuarterlyEvery3Months() {
        let sub = makeSub(cycle: .quarterly, billingDay: 15, startDate: "2025-01-15")
        // January (start) - yes
        XCTAssertNotNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 1))
        // April (3 months later) - yes
        XCTAssertNotNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 4))
        // February - no
        XCTAssertNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 2))
        // March - no
        XCTAssertNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 3))
    }

    func testBillingDayClampingFeb() {
        let sub = makeSub(cycle: .monthly, billingDay: 31, startDate: "2025-01-31")
        let febDate = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 2)
        XCTAssertNotNil(febDate)
        // Feb has 28 days in 2025
        XCTAssertEqual(Calendar.current.component(.day, from: febDate!), 28)
    }

    func testBillingDateWeeklyReturnsNil() {
        let sub = makeSub(cycle: .weekly)
        let date = BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 3)
        XCTAssertNil(date)
    }

    func testBillingDateOneTimeOnlyStartMonth() {
        let sub = makeSub(cycle: .oneTime, startDate: "2025-05-10")
        XCTAssertNotNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 5))
        XCTAssertNil(BillingCalculator.getBillingDateInMonth(sub, year: 2025, month: 6))
    }

    // MARK: - getWeeklyBillingDatesInMonth

    func testWeeklyBillingDatesInMonth() {
        let sub = makeSub(cycle: .weekly, startDate: "2025-01-06")
        let dates = BillingCalculator.getWeeklyBillingDatesInMonth(sub, year: 2025, month: 2)
        // February 2025 should have 4 weekly dates from a Monday start
        XCTAssertTrue(dates.count >= 4)
        for date in dates {
            XCTAssertEqual(Calendar.current.component(.month, from: date), 2)
        }
    }

    func testWeeklyReturnsEmptyForNonWeekly() {
        let sub = makeSub(cycle: .monthly)
        let dates = BillingCalculator.getWeeklyBillingDatesInMonth(sub, year: 2025, month: 2)
        XCTAssertTrue(dates.isEmpty)
    }

    // MARK: - getMonthlyEquivalent

    func testMonthlyEquivalentYearly() {
        let sub = makeSub(cycle: .yearly, amount: 120)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 10.0)
    }

    func testMonthlyEquivalentWeekly() {
        let sub = makeSub(cycle: .weekly, amount: 10)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 43.3, accuracy: 0.1)
    }

    func testMonthlyEquivalentQuarterly() {
        let sub = makeSub(cycle: .quarterly, amount: 30)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 10.0)
    }

    func testMonthlyEquivalentOneTime() {
        let sub = makeSub(cycle: .oneTime, amount: 100)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 0)
    }

    func testMonthlyEquivalentMonthly() {
        let sub = makeSub(cycle: .monthly, amount: 15)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 15.0)
    }

    // MARK: - getDaysUntilBilling

    func testDaysUntilBillingNonNegative() {
        let sub = makeSub(cycle: .monthly, billingDay: 1, startDate: "2020-01-01")
        let days = BillingCalculator.getDaysUntilBilling(sub)
        XCTAssertGreaterThanOrEqual(days, 0)
    }

    // MARK: - getTotalSpent

    func testTotalSpentOneTime() {
        let sub = makeSub(cycle: .oneTime, startDate: "2020-01-01", amount: 50)
        XCTAssertEqual(BillingCalculator.getTotalSpent(sub), 50.0)
    }

    func testTotalSpentFutureStart() {
        let sub = makeSub(cycle: .monthly, startDate: "2099-01-01", amount: 10)
        XCTAssertEqual(BillingCalculator.getTotalSpent(sub), 0)
    }
}
