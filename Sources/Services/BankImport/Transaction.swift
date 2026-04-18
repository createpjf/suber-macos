import Foundation

/// A single row in a parsed bank / pay-platform statement.
struct StatementTransaction: Equatable {
    /// When the charge happened (normalized to the day, time-of-day ignored).
    let date: Date

    /// Merchant / counterparty as it appeared in the statement, unmodified.
    /// Normalization for grouping lives in `MerchantNormalizer`.
    let merchantRaw: String

    /// Positive value. Outflow-only; incoming / refund rows are filtered at parse time.
    let amount: Double

    /// ISO 4217 currency code (e.g. "USD", "CNY"). Fallback: "CNY" for Alipay/WeChat, "USD" for Generic.
    let currency: String
}

/// Confidence bucket surfaced to the user in the review list.
enum ImportConfidence: String {
    case high    // known service match or very stable amount + many occurrences
    case medium  // recognized cycle + amount stable enough
    case low     // cycle recognized but amount drifted or few occurrences
}

/// A recurring-charge hypothesis produced by `RecurringChargeDetector`.
/// Maps 1:1 into `SubscriptionFormData` once the user confirms.
struct CandidateSubscription: Identifiable, Equatable {
    let id: UUID = UUID()

    /// Best-guess canonical name. `KnownServices` match takes precedence, else
    /// a title-cased version of the normalized merchant.
    var name: String

    /// The normalized merchant key used for grouping. Kept so the review UI can
    /// show the raw merchant string on demand.
    let normalizedMerchant: String

    /// One sample of the raw merchant string — used if the user wants to see
    /// what the statement actually said.
    let sampleMerchantRaw: String

    /// Median charge amount across the group, in `currency`.
    let amount: Double

    let currency: String
    let cycle: BillingCycle

    /// Day-of-month of the most-recent charge. Used as `Subscription.billingDay`.
    let billingDay: Int

    /// Earliest charge date observed. Used as `Subscription.startDate`.
    let startDate: Date

    /// Most-recent charge date — shown in the review list ("last: Mar 15").
    let lastChargeDate: Date

    /// Category from `KnownServices` if matched, else nil (user picks in review).
    var category: String?

    /// Number of charges that contributed to this candidate.
    let occurrences: Int

    let confidence: ImportConfidence
}
