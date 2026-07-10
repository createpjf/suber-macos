import XCTest
@testable import Suber

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

    func testNextBillingDateOneTimeIgnoresBillingDay() {
        // AUDIT-v1.9.2 C-35: the form hides billingDay for one-time purchases
        // (it defaults to today's day-of-month), so a mismatched billingDay
        // must not pull the date off startDate — list/detail and calendar
        // surfaces must show the same day.
        let sub = makeSub(cycle: .oneTime, billingDay: 10, startDate: "2026-06-25")
        let next = BillingCalculator.getNextBillingDate(sub)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: next), 2026)
        XCTAssertEqual(cal.component(.month, from: next), 6)
        XCTAssertEqual(cal.component(.day, from: next), 25)
        // Must equal the date the calendar surface computes for the same sub.
        XCTAssertEqual(BillingCalculator.getBillingDateInMonth(sub, year: 2026, month: 6), next)
        // strictlyAfter must not shift a one-time purchase either.
        XCTAssertEqual(BillingCalculator.getNextBillingDate(sub, strictlyAfter: makeDate("2026-07-01")), next)
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
        // AUDIT-v1.9.2 C-36: 52/12 weeks per month, not 4.33 — must stay on
        // the same 52-weeks/year basis as BillingCycle.annualAmount.
        let sub = makeSub(cycle: .weekly, amount: 10)
        XCTAssertEqual(BillingCalculator.getMonthlyEquivalent(sub), 10 * 52.0 / 12.0, accuracy: 0.0001)
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

    func testDaysBetweenAcrossDSTFallBack() {
        // AUDIT-v1.9.2 C-21: London clocks fall back Oct 25, 2026, so the
        // midnight-to-midnight span Oct 20 → Nov 1 is 12 days + 1 hour.
        // The old ceil(seconds/86400) reported 13; the calendar-aware day
        // difference must be 12. Fixed TimeZone keeps this deterministic
        // regardless of the machine's zone.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        let from = cal.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let to = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        XCTAssertEqual(to.timeIntervalSince(from), 12 * 86400 + 3600,
                       "precondition: span must cross the fall-back hour")
        XCTAssertEqual(BillingCalculator.daysBetween(from: from, to: to, calendar: cal), 12)

        // "Billing tomorrow" across the transition (25-hour day) must be 1, not 2.
        let oct25 = cal.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let oct26 = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        XCTAssertEqual(BillingCalculator.daysBetween(from: oct25, to: oct26, calendar: cal), 1)
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

    func testTotalSpentMonthlyOlderThanOneYear() {
        // AUDIT-v1.9.2 C-17: multi-unit dateComponents([.weekOfYear,.month,.year])
        // hierarchically decomposed a 29-month span into year=2/month=5 and
        // charged only 5 cycles. Expected: one charge per elapsed month PLUS
        // the initial charge on the start date (fencepost).
        let sub = makeSub(cycle: .monthly, billingDay: 15, startDate: "2024-01-15", amount: 15.49)
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: makeDate("2024-01-15"))
        let today = cal.startOfDay(for: Date())
        let elapsedMonths = cal.dateComponents([.month], from: start, to: today).month ?? 0
        XCTAssertGreaterThan(elapsedMonths, 12, "precondition: sub must be over a year old")
        let expected = Double(elapsedMonths + 1) * 15.49
        XCTAssertEqual(BillingCalculator.getTotalSpent(sub), expected, accuracy: 0.001)
    }

    func testTotalSpentWeeklyFullYear() {
        // AUDIT-v1.9.2 C-17: a weekly sub exactly 52 weeks old returned $0 —
        // the weekOfYear remainder of a full-year span is 0. 52 elapsed weeks
        // plus the initial charge = 53 charges.
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .weekOfYear, value: -52, to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let sub = makeSub(cycle: .weekly, startDate: formatter.string(from: start), amount: 10)
        XCTAssertEqual(BillingCalculator.getTotalSpent(sub), 53 * 10.0, accuracy: 0.001)
    }

    func testTotalSpentQuarterlyOlderThanOneYear() {
        // AUDIT-v1.9.2 C-17: quarterly divided the decomposed month remainder
        // by 3 (a ~9-quarter span counted 1 charge). Expected: one charge per
        // elapsed quarter plus the initial charge.
        let sub = makeSub(cycle: .quarterly, billingDay: 15, startDate: "2024-01-15", amount: 30)
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: makeDate("2024-01-15"))
        let today = cal.startOfDay(for: Date())
        let elapsedMonths = cal.dateComponents([.month], from: start, to: today).month ?? 0
        let expected = Double(elapsedMonths / 3 + 1) * 30
        XCTAssertEqual(BillingCalculator.getTotalSpent(sub), expected, accuracy: 0.001)
    }
}
