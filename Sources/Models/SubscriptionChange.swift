import Foundation
import CryptoKit

// ┌───────────── SubscriptionChange — v1.6 change log ─────────────────────────┐
// │                                                                            │
// │  Records anything interesting that happens to a subscription:              │
// │    - price rose or fell                                                    │
// │    - new charge detected (no matching sub yet — needs user to Add)         │
// │    - duplicate charge                                                      │
// │    - trial ending soon                                                     │
// │    - cancellation confirmed via D4 auto-transition                         │
// │    - cancellation failed (charge detected after pending window)            │
// │                                                                            │
// │  Flows:                                                                    │
// │                                                                            │
// │    CSV import          ─┐                                                  │
// │    OCR import          ─┼─► ChangeDetector.diff(...) ─► [SubscriptionChange]│
// │    Mail Watchdog scan  ─┤                     │                            │
// │    Background ticks    ─┘                     ▼                            │
// │                                 SubscriptionStore.recordAndPersist(...)    │
// │                                          (H5 prune-on-write, 200 cap)      │
// │                                                                            │
// │  Dedup hash (M3 fix): uses USD-canonical amount, NOT the display string.   │
// │  Prevents same-change re-insertion when user flips display currency.       │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘
struct SubscriptionChange: Codable, Identifiable, Equatable {
    let id: UUID
    let subscriptionID: UUID?    // nil for .newCharge (no matching sub yet)
    let type: ChangeType
    let detectedAt: Date
    let previousValue: String?   // display string (e.g. "15.99 USD"); opaque to detector
    let newValue: String?        // display string
    let source: ChangeSource
    var acknowledged: Bool

    /// D6 (eng review iter-1): hydration payload for .newCharge entries so
    /// the user can tap "Add" in the Changes Window and get a pre-filled form.
    /// Nil for all other change types. ~300-500 bytes when present.
    let pendingSubscriptionData: SubscriptionFormData?

    /// M3 (eng re-review): dedup hash, computed once at creation. Hashes the
    /// USD-canonical amounts passed in at construction time, NOT the display
    /// strings. Prevents re-insertion when the user flips display currency
    /// (CNY ↔ USD shouldn't mean the same change gets logged twice).
    let dedupHash: String

    // MARK: Types

    enum ChangeType: String, Codable {
        case newCharge
        case priceChange
        case duplicate
        case trialExpiring
        case cancellationConfirmed
        case cancellationFailed
        // .missedCharge DEFERRED to v1.6.1 per CEO review — needs two-cycle
        // evidence to avoid false positives on holiday-shifted billing days.
    }

    enum ChangeSource: String, Codable {
        case csvImport
        case ocrImport
        case mailWatchdog
        case backgroundCheck    // app-launch + scan-completion hook (P1)
    }

    // MARK: Designated initializer

    /// Create a change with an auto-computed M3 canonical-currency dedup hash.
    ///
    /// - Parameters:
    ///   - previousBaseAmount: USD-canonical previous amount (pass through
    ///     `ExchangeRateService.convert(_, from: sub.currency, to: "USD")`).
    ///     Pass nil for types without a "previous" value (newCharge, duplicate).
    ///   - newBaseAmount: USD-canonical new amount, same treatment.
    init(
        id: UUID = UUID(),
        subscriptionID: UUID?,
        type: ChangeType,
        detectedAt: Date = Date(),
        previousValue: String?,
        newValue: String?,
        source: ChangeSource,
        acknowledged: Bool = false,
        pendingSubscriptionData: SubscriptionFormData? = nil,
        previousBaseAmount: Double? = nil,
        newBaseAmount: Double? = nil
    ) {
        self.id = id
        self.subscriptionID = subscriptionID
        self.type = type
        self.detectedAt = detectedAt
        self.previousValue = previousValue
        self.newValue = newValue
        self.source = source
        self.acknowledged = acknowledged
        self.pendingSubscriptionData = pendingSubscriptionData
        self.dedupHash = Self.computeDedupHash(
            subscriptionID: subscriptionID,
            type: type,
            previousBaseAmount: previousBaseAmount,
            newBaseAmount: newBaseAmount,
            detectedAt: detectedAt
        )
    }

    /// Day-of-detection granularity: same logical change detected twice on the
    /// same calendar day collapses; detected on two different days is treated
    /// as distinct (a real re-occurrence, not a re-scan artifact).
    private static func computeDedupHash(
        subscriptionID: UUID?,
        type: ChangeType,
        previousBaseAmount: Double?,
        newBaseAmount: Double?,
        detectedAt: Date
    ) -> String {
        // Format base amounts to fixed precision so 15.989999... doesn't diverge
        // from 15.99 via floating-point drift across client-currency roundtrips.
        let prev = previousBaseAmount.map { String(format: "%.4f", $0) } ?? ""
        let curr = newBaseAmount.map    { String(format: "%.4f", $0) } ?? ""
        let dayKey = ISO8601DateFormatter.dayKey.string(from: detectedAt)
        let subKey = subscriptionID?.uuidString ?? ""
        let input = "\(subKey)|\(type.rawValue)|\(prev)|\(curr)|\(dayKey)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Day-granularity formatter used by dedup hash

private extension ISO8601DateFormatter {
    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current  // day-local; same calendar day in user's tz
        return f
    }()
}

// MARK: - Codable conformance for SubscriptionFormData

// SubscriptionFormData was previously a plain struct; now needs Codable so
// it can round-trip through .newCharge SubscriptionChange records for the
// D3 review-and-add flow. Date and SubscriptionStatus are already Codable;
// BillingCycle is Codable. Only thing that wasn't = this struct's conformance.
extension SubscriptionFormData: Codable {
    enum CodingKeys: String, CodingKey {
        case name, url, logo, amount, currency, cycle, billingDay
        case startDate, trialEndDate, category, status, notes, splitCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        amount = try c.decode(String.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        cycle = try c.decode(BillingCycle.self, forKey: .cycle)
        billingDay = try c.decode(Int.self, forKey: .billingDay)
        startDate = try c.decode(Date.self, forKey: .startDate)
        trialEndDate = try c.decodeIfPresent(Date.self, forKey: .trialEndDate)
        category = try c.decode(String.self, forKey: .category)
        status = try c.decode(SubscriptionStatus.self, forKey: .status)
        notes = try c.decode(String.self, forKey: .notes)
        splitCount = try c.decodeIfPresent(Int.self, forKey: .splitCount) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(logo, forKey: .logo)
        try c.encode(amount, forKey: .amount)
        try c.encode(currency, forKey: .currency)
        try c.encode(cycle, forKey: .cycle)
        try c.encode(billingDay, forKey: .billingDay)
        try c.encode(startDate, forKey: .startDate)
        try c.encodeIfPresent(trialEndDate, forKey: .trialEndDate)
        try c.encode(category, forKey: .category)
        try c.encode(status, forKey: .status)
        try c.encode(notes, forKey: .notes)
        try c.encode(splitCount, forKey: .splitCount)
    }
}

// SubscriptionFormData needs Equatable for SubscriptionChange's Equatable conformance.
extension SubscriptionFormData: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.url == rhs.url && lhs.logo == rhs.logo &&
        lhs.amount == rhs.amount && lhs.currency == rhs.currency &&
        lhs.cycle == rhs.cycle && lhs.billingDay == rhs.billingDay &&
        lhs.startDate == rhs.startDate && lhs.trialEndDate == rhs.trialEndDate &&
        lhs.category == rhs.category && lhs.status == rhs.status &&
        lhs.notes == rhs.notes && lhs.splitCount == rhs.splitCount
    }
}
