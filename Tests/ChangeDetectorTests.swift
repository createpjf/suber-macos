import XCTest
@testable import Suber

/// Covers all ChangeType branches + cross-currency threshold + dedup hash
/// determinism + both threshold boundaries (5% AND $1 floor).
final class ChangeDetectorTests: XCTestCase {

    // MARK: - priceChange thresholds (5% AND $1 floor, both must hit)

    func testPriceChangeFiresWhenBothThresholdsMet() {
        let existing = makeSub(name: "Netflix", amount: 15.99, currency: "USD")
        let candidate = makeCandidate(name: "Netflix", amount: 22.99, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .csvImport
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.type, .priceChange)
    }

    func testPriceChangeSuppressedWhenUnderRelativeThreshold() {
        // 15.99 → 16.50: 3.2% (below 5% threshold), absolute delta $0.51 (also
        // below $1 floor). Either one suppresses.
        let existing = makeSub(name: "Netflix", amount: 15.99, currency: "USD")
        let candidate = makeCandidate(name: "Netflix", amount: 16.50, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .csvImport
        )
        XCTAssertTrue(changes.isEmpty, "Under-5% change should not fire")
    }

    func testPriceChangeSuppressedWhenOnlyRelativeMetButAbsoluteBelowDollar() {
        // $5.00 → $5.30: 6% (>5%) but absolute $0.30 (<$1 floor).
        // AND rule: both must hit. This suppresses.
        let existing = makeSub(name: "Cheap Sub", amount: 5.00, currency: "USD")
        let candidate = makeCandidate(name: "Cheap Sub", amount: 5.30, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .csvImport
        )
        XCTAssertTrue(changes.isEmpty,
                      "6% but under-$1 absolute should not fire (AND rule)")
    }

    func testPriceChangeFiresOnExactBoundary() {
        // 20.00 → 21.00: exactly 5% AND exactly $1 — both thresholds MEET
        // (>= comparison in ChangeDetector). Should fire.
        let existing = makeSub(name: "Boundary", amount: 20.00, currency: "USD")
        let candidate = makeCandidate(name: "Boundary", amount: 21.00, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .csvImport
        )
        XCTAssertEqual(changes.count, 1, "Exact 5% AND $1 boundary should fire")
    }

    // MARK: - Cross-currency

    func testCrossCurrencyPriceChangeComparesInUSDCanonical() {
        // Existing: 100 CNY/mo ≈ $13.81 USD. Candidate: 120 CNY/mo ≈ $16.57 USD.
        // Absolute delta (USD): ~$2.76; relative: 20%. Both thresholds met.
        let existing = makeSub(name: "爱奇艺", amount: 100, currency: "CNY")
        let candidate = makeCandidate(name: "爱奇艺", amount: 120, currency: "CNY")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .mailWatchdog
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.type, .priceChange)
    }

    // MARK: - newCharge

    func testNewChargeFiresForUnknownMerchant() {
        let candidate = makeCandidate(name: "Unknown Service", amount: 9.99, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [], source: .mailWatchdog
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.type, .newCharge)
        XCTAssertNil(changes.first?.subscriptionID, "newCharge has no matching sub ID")
    }

    func testNewChargeHydratesPendingSubscriptionData() {
        // D6 (eng review iter-1): the Add button needs a pre-filled form.
        let candidate = makeCandidate(name: "Fresh Sub", amount: 9.99, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [], source: .mailWatchdog
        )
        let form = changes.first?.pendingSubscriptionData
        XCTAssertNotNil(form)
        XCTAssertEqual(form?.name, "Fresh Sub")
        XCTAssertEqual(form?.amount, "9.99")
        XCTAssertEqual(form?.currency, "USD")
    }

    func testKnownMerchantMatchesViaNormalization() {
        // Existing "Netflix" matches candidate "Netflix.com 866-123-4567" via
        // MerchantNormalizer — both normalize to "netflix". See
        // MerchantNormalizerTests for the full normalization test matrix.
        let existing = makeSub(name: "Netflix", amount: 15.99, currency: "USD")
        let candidate = makeCandidate(name: "Netflix.com 866-123-4567",
                                      amount: 15.99, currency: "USD")
        let changes = ChangeDetector.diff(
            incoming: [candidate], against: [existing], source: .csvImport
        )
        // Same amount + matched merchant → no priceChange, no newCharge.
        XCTAssertTrue(changes.isEmpty, "Matched merchant with same amount fires nothing")
    }

    // MARK: - duplicate (intra-batch)

    func testDuplicateFiresForSameDayMultipleCharges() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let txns = [
            StatementTransaction(date: day, merchantRaw: "Netflix", amount: 15.99, currency: "USD"),
            StatementTransaction(date: day, merchantRaw: "NETFLIX.COM", amount: 15.99, currency: "USD"),
        ]
        let changes = ChangeDetector.diff(
            incoming: [], against: [], priorRun: txns, source: .csvImport
        )
        XCTAssertEqual(changes.filter { $0.type == .duplicate }.count, 1,
                       "Two same-day Netflix charges should yield 1 duplicate change")
    }

    func testNoDuplicateWhenDifferentDays() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Date(timeIntervalSince1970: 1_700_086_400 + 86_400) // +2d
        let txns = [
            StatementTransaction(date: day1, merchantRaw: "Netflix", amount: 15.99, currency: "USD"),
            StatementTransaction(date: day2, merchantRaw: "Netflix", amount: 15.99, currency: "USD"),
        ]
        let changes = ChangeDetector.diff(
            incoming: [], against: [], priorRun: txns, source: .csvImport
        )
        XCTAssertTrue(changes.filter { $0.type == .duplicate }.isEmpty)
    }

    // MARK: - trialExpiring

    func testTrialExpiringFiresWithin3Days() {
        let now = Date()
        let endingIn2Days = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let sub = makeSub(name: "ChatGPT", amount: 20, currency: "USD",
                          status: .trial, trialEndDate: endingIn2Days)
        let changes = ChangeDetector.diff(
            incoming: [], against: [sub], source: .backgroundCheck, now: now
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.type, .trialExpiring)
    }

    func testTrialExpiringSuppressedBeyond3Days() {
        let now = Date()
        let endingIn5Days = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let sub = makeSub(name: "ChatGPT", amount: 20, currency: "USD",
                          status: .trial, trialEndDate: endingIn5Days)
        let changes = ChangeDetector.diff(
            incoming: [], against: [sub], source: .backgroundCheck, now: now
        )
        XCTAssertTrue(changes.isEmpty)
    }

    func testTrialExpiringNotFiredForNonTrialStatus() {
        let now = Date()
        let endingIn2Days = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let sub = makeSub(name: "Netflix", amount: 15.99, currency: "USD",
                          status: .active, trialEndDate: endingIn2Days)
        let changes = ChangeDetector.diff(
            incoming: [], against: [sub], source: .backgroundCheck, now: now
        )
        XCTAssertTrue(changes.isEmpty, "Non-trial status with trial date set should not fire")
    }

    // MARK: - Dedup hash determinism (M3 canonical-currency)

    func testDedupHashStableAcrossRepeatedRuns() {
        let sub = makeSub(name: "Netflix", amount: 15.99, currency: "USD")
        let candidate = makeCandidate(name: "Netflix", amount: 22.99, currency: "USD")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let run1 = ChangeDetector.diff(
            incoming: [candidate], against: [sub], source: .csvImport, now: now
        )
        let run2 = ChangeDetector.diff(
            incoming: [candidate], against: [sub], source: .csvImport, now: now
        )
        XCTAssertEqual(run1.first?.dedupHash, run2.first?.dedupHash,
                       "Same inputs → same hash (deterministic)")
    }

    func testDedupHashDiffersForDifferentChangeType() {
        // Constructing two SubscriptionChange manually to verify hash sensitivity.
        let subID = UUID()
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let priceChange = SubscriptionChange(
            subscriptionID: subID, type: .priceChange,
            detectedAt: anchor, previousValue: "15.99", newValue: "22.99",
            source: .csvImport,
            previousBaseAmount: 15.99, newBaseAmount: 22.99
        )
        let newCharge = SubscriptionChange(
            subscriptionID: subID, type: .newCharge,
            detectedAt: anchor, previousValue: "15.99", newValue: "22.99",
            source: .csvImport,
            previousBaseAmount: 15.99, newBaseAmount: 22.99
        )
        XCTAssertNotEqual(priceChange.dedupHash, newCharge.dedupHash)
    }

    // MARK: - Helpers

    private func makeSub(
        name: String,
        amount: Double,
        currency: String,
        status: SubscriptionStatus = .active,
        trialEndDate: Date? = nil
    ) -> Subscription {
        let now = Date()
        return Subscription(
            id: UUID(), name: name, amount: amount, currency: currency,
            cycle: .monthly, billingDay: 15, startDate: now,
            trialEndDate: trialEndDate, category: "Test",
            status: status, createdAt: now, updatedAt: now
        )
    }

    private func makeCandidate(
        name: String,
        amount: Double,
        currency: String
    ) -> CandidateSubscription {
        CandidateSubscription(
            name: name,
            normalizedMerchant: MerchantNormalizer.normalize(name),
            sampleMerchantRaw: name,
            amount: amount,
            currency: currency,
            cycle: .monthly,
            billingDay: 15,
            startDate: Date(),
            lastChargeDate: Date(),
            category: nil,
            occurrences: 3,
            confidence: .high
        )
    }
}
