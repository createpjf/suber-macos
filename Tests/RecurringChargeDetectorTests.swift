import XCTest
@testable import Suber

final class RecurringChargeDetectorTests: XCTestCase {

    // MARK: - Fixtures

    private func date(_ yyyy_mm_dd: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return Calendar.current.startOfDay(for: f.date(from: yyyy_mm_dd)!)
    }

    private func tx(_ merchant: String, _ amount: Double, _ dates: [String], currency: String = "USD") -> [StatementTransaction] {
        dates.map { StatementTransaction(date: date($0), merchantRaw: merchant, amount: amount, currency: currency) }
    }

    // MARK: - Positive detection

    func test_monthly_netflix_detected_as_high_confidence() {
        let txs = tx("Netflix", 15.99, [
            "2025-11-14", "2025-12-14", "2026-01-14", "2026-02-14", "2026-03-14",
        ])
        let candidates = RecurringChargeDetector.detect(transactions: txs)
        XCTAssertEqual(candidates.count, 1)
        let c = candidates[0]
        XCTAssertEqual(c.cycle, .monthly)
        XCTAssertEqual(c.amount, 15.99, accuracy: 0.01)
        XCTAssertEqual(c.occurrences, 5)
        XCTAssertEqual(c.confidence, .high)  // KnownServices match + many occurrences + stable amount
        XCTAssertEqual(c.category, "Streaming")
        XCTAssertEqual(c.name, "Netflix")
    }

    func test_weekly_subscription_detected() {
        let txs = tx("NYTimes Weekly", 2.99, [
            "2026-01-06", "2026-01-13", "2026-01-20", "2026-01-27", "2026-02-03",
        ])
        let c = RecurringChargeDetector.detect(transactions: txs).first
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.cycle, .weekly)
    }

    func test_quarterly_detected() {
        let txs = tx("JetBrains", 89, [
            "2025-06-01", "2025-09-01", "2025-12-01", "2026-03-01",
        ])
        let c = RecurringChargeDetector.detect(transactions: txs).first
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.cycle, .quarterly)
    }

    func test_chinese_service_detected() {
        let txs = tx("爱奇艺", 29.9, [
            "2025-12-01", "2026-01-01", "2026-02-01", "2026-03-01",
        ], currency: "CNY")
        let c = RecurringChargeDetector.detect(transactions: txs).first
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.cycle, .monthly)
        XCTAssertEqual(c?.name, "爱奇艺")
        XCTAssertEqual(c?.category, "Streaming")
        XCTAssertEqual(c?.currency, "CNY")
    }

    // MARK: - Negative detection (filter out non-subscriptions)

    func test_single_charge_not_recurring() {
        let txs = tx("Amazon", 49.99, ["2026-01-15"])
        XCTAssertTrue(RecurringChargeDetector.detect(transactions: txs).isEmpty)
    }

    func test_grocery_store_variable_amounts_filtered() {
        // Whole Foods visits: same merchant, drifty amounts, monthly-ish
        // Not a known service, amount CV > 0.2 → should be filtered
        let txs = [
            StatementTransaction(date: date("2025-12-01"), merchantRaw: "Whole Foods Market", amount: 87.34, currency: "USD"),
            StatementTransaction(date: date("2026-01-03"), merchantRaw: "Whole Foods Market", amount: 142.11, currency: "USD"),
            StatementTransaction(date: date("2026-02-05"), merchantRaw: "Whole Foods Market", amount: 65.22, currency: "USD"),
            StatementTransaction(date: date("2026-03-02"), merchantRaw: "Whole Foods Market", amount: 201.88, currency: "USD"),
        ]
        XCTAssertTrue(RecurringChargeDetector.detect(transactions: txs).isEmpty)
    }

    func test_irregular_intervals_not_recurring() {
        // Random café visits over the year — not at a predictable interval
        let txs = tx("Coffee Shop", 4.50, [
            "2026-01-03", "2026-01-15", "2026-01-22", "2026-02-12", "2026-03-20",
        ])
        XCTAssertTrue(RecurringChargeDetector.detect(transactions: txs).isEmpty)
    }

    // MARK: - Noise tolerance

    func test_processor_prefix_variants_collapsed() {
        // All three use the same descriptor after the ALIPAY* prefix, so the
        // MerchantNormalizer should produce the same key ("netflix") for each.
        let txs = [
            StatementTransaction(date: date("2025-12-14"), merchantRaw: "ALIPAY*NETFLIX",    amount: 15.99, currency: "CNY"),
            StatementTransaction(date: date("2026-01-14"), merchantRaw: "ALIPAY *NETFLIX",   amount: 15.99, currency: "CNY"),
            StatementTransaction(date: date("2026-02-14"), merchantRaw: "ALIPAY NETFLIX",    amount: 15.99, currency: "CNY"),
        ]
        let candidates = RecurringChargeDetector.detect(transactions: txs)
        XCTAssertEqual(candidates.count, 1, "All three Netflix variants should collapse to one candidate")
        XCTAssertEqual(candidates.first?.occurrences, 3)
    }

    func test_known_service_relaxes_amount_drift() {
        // Netflix price changed mid-cycle. CV > 0.15 but <0.2, KnownServices match still produces candidate.
        let txs = [
            StatementTransaction(date: date("2025-11-14"), merchantRaw: "Netflix", amount: 11.99, currency: "USD"),
            StatementTransaction(date: date("2025-12-14"), merchantRaw: "Netflix", amount: 11.99, currency: "USD"),
            StatementTransaction(date: date("2026-01-14"), merchantRaw: "Netflix", amount: 15.99, currency: "USD"),
            StatementTransaction(date: date("2026-02-14"), merchantRaw: "Netflix", amount: 15.99, currency: "USD"),
        ]
        let c = RecurringChargeDetector.detect(transactions: txs).first
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.cycle, .monthly)
    }

    // MARK: - Ordering

    func test_results_sorted_by_confidence_then_amount() {
        let highAmount = tx("Apple Music", 9.99, [
            "2025-12-14", "2026-01-14", "2026-02-14",
        ])
        let lowAmount = tx("Spotify", 5.99, [
            "2025-12-14", "2026-01-14", "2026-02-14", "2026-03-14",
        ])
        let candidates = RecurringChargeDetector.detect(transactions: highAmount + lowAmount)
        XCTAssertEqual(candidates.count, 2)
        // Both match known services → both high confidence; Apple Music has higher amount.
        XCTAssertEqual(candidates[0].name, "Apple Music")
    }
}
