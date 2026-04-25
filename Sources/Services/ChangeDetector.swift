import Foundation

// ┌───────────── ChangeDetector — v1.6 Sense pillar ───────────────────────────┐
// │                                                                            │
// │  Pure function. Given incoming candidates + known subs + a prior-run       │
// │  transaction batch, emits [SubscriptionChange] for the Sentinel loop.      │
// │                                                                            │
// │  Thresholds (CEO review):                                                  │
// │    priceChange:  |Δ|/prev ≥ 0.05  AND  |Δ|(USD) ≥ $1                       │
// │    duplicate:    same merchant, same calendar day, count ≥ 2               │
// │    trialExpiring:status == .trial  AND  trialEndDate within next 3 days    │
// │    newCharge:    merchant normalized-key not found in any existing sub     │
// │                                                                            │
// │  Cross-currency (eng re-review M3): all amount comparisons happen in       │
// │  USD-canonical space via ExchangeRateService.convert. The dedup hash       │
// │  stored on each SubscriptionChange also uses USD-canonical amounts so      │
// │  flipping display currency doesn't re-insert the same change.              │
// │                                                                            │
// │  Called from:                                                              │
// │    - ImportWindowView.onAdd (user-confirmed CSV/OCR batch)                 │
// │    - MailWatchdog scan completion                                          │
// │    - CSV import completion                                                 │
// │                                                                            │
// │  NOT called from: app launch (that's auto-transition, different path).    │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘
enum ChangeDetector {

    /// Thresholds folded into one place so tests can verify exact boundary
    /// conditions (5% AND $1).
    struct Thresholds {
        static let priceChangeRelative: Double = 0.05    // 5%
        static let priceChangeAbsoluteUSD: Double = 1.0  // $1 floor, AFTER conversion
        static let trialExpirationWindowDays: Int = 3
    }

    /// Main entry point.
    ///
    /// - Parameters:
    ///   - incoming: candidates produced by CSVParser/OCR/MailSubscriptionExtractor
    ///   - existing: current state of the user's subscriptions
    ///   - priorRun: optional same-batch transactions for duplicate detection within
    ///     a single scan (e.g., CSV row 14 and row 19 are same merchant same day)
    ///   - source: provenance tag stamped on every emitted change
    ///   - rates: exchange-rate service (injected for testability)
    ///   - now: current time (injected for testability)
    /// - Returns: changes found, in no particular order. Caller dedups via hash
    ///   when persisting (SubscriptionStore.recordAndPersist).
    static func diff(
        incoming: [CandidateSubscription],
        against existing: [Subscription],
        priorRun: [StatementTransaction]? = nil,
        source: SubscriptionChange.ChangeSource,
        rates: ExchangeRateService = .shared,
        now: Date = Date()
    ) -> [SubscriptionChange] {
        var changes: [SubscriptionChange] = []

        // Index existing subs by normalized merchant key for O(1) lookup.
        // Uses the same MerchantNormalizer the import pipeline uses, so
        // "Netflix.com", "NETFLIX.COM CA 866-..." and "ALIPAY*NETFLIX"
        // collapse to the same key and match each other.
        let existingByKey: [String: Subscription] = Dictionary(
            uniqueKeysWithValues: existing.compactMap { sub in
                let key = MerchantNormalizer.normalize(sub.name)
                return key.isEmpty ? nil : (key, sub)
            }
        )

        // MARK: - priceChange + newCharge
        for candidate in incoming {
            let candidateKey = MerchantNormalizer.normalize(candidate.name)
            guard !candidateKey.isEmpty else { continue }

            if let match = existingByKey[candidateKey] {
                // Known sub. Check for priceChange.
                if let change = priceChangeIfThresholdMet(
                    existing: match,
                    candidate: candidate,
                    source: source,
                    rates: rates,
                    now: now
                ) {
                    changes.append(change)
                }
            } else {
                // Unknown merchant → newCharge (needs user Add flow per D3).
                changes.append(makeNewCharge(candidate: candidate, source: source, now: now))
            }
        }

        // MARK: - duplicate (within priorRun batch if provided)
        if let priorRun = priorRun {
            changes.append(contentsOf: duplicatesInBatch(priorRun, source: source, now: now))
        }

        // MARK: - trialExpiring (from existing, not incoming)
        changes.append(contentsOf: trialsExpiringSoon(existing: existing, source: source, now: now))

        return changes
    }

    // MARK: - priceChange helper

    private static func priceChangeIfThresholdMet(
        existing: Subscription,
        candidate: CandidateSubscription,
        source: SubscriptionChange.ChangeSource,
        rates: ExchangeRateService,
        now: Date
    ) -> SubscriptionChange? {
        // Compare in USD-canonical space (M3 fix).
        let previousUSD = rates.convert(existing.amount, from: existing.currency, to: "USD")
        let newUSD = rates.convert(candidate.amount, from: candidate.currency, to: "USD")
        let delta = newUSD - previousUSD
        let absDelta = abs(delta)

        // Both thresholds must hit: 5% AND $1 floor (AND, not OR — from CEO spec).
        let relativeOK = previousUSD > 0 && (absDelta / previousUSD) >= Thresholds.priceChangeRelative
        let absoluteOK = absDelta >= Thresholds.priceChangeAbsoluteUSD
        guard relativeOK && absoluteOK else { return nil }

        return SubscriptionChange(
            subscriptionID: existing.id,
            type: .priceChange,
            detectedAt: now,
            previousValue: String(format: "%.2f %@", existing.amount, existing.currency),
            newValue: String(format: "%.2f %@", candidate.amount, candidate.currency),
            source: source,
            previousBaseAmount: previousUSD,
            newBaseAmount: newUSD
        )
    }

    // MARK: - newCharge helper

    private static func makeNewCharge(
        candidate: CandidateSubscription,
        source: SubscriptionChange.ChangeSource,
        now: Date
    ) -> SubscriptionChange {
        // D6 (eng review iter-1): hydrate pendingSubscriptionData so the
        // Changes Window's Add button opens a pre-filled SubscriptionFormView.
        var form = SubscriptionFormData()
        form.name = candidate.name
        form.amount = candidate.amount == floor(candidate.amount)
            ? String(format: "%.0f", candidate.amount)
            : String(format: "%.2f", candidate.amount)
        form.currency = candidate.currency
        form.cycle = candidate.cycle
        form.billingDay = candidate.billingDay
        form.startDate = candidate.startDate
        form.category = candidate.category ?? "Other"
        form.status = .active

        return SubscriptionChange(
            subscriptionID: nil,    // no matching sub yet
            type: .newCharge,
            detectedAt: now,
            previousValue: nil,
            newValue: String(format: "%.2f %@ / %@", candidate.amount, candidate.currency, candidate.cycle.shortLabel),
            source: source,
            pendingSubscriptionData: form,
            previousBaseAmount: nil,
            newBaseAmount: candidate.amount  // already in candidate.currency; hash doesn't need USD here since no "previous" to compare
        )
    }

    // MARK: - duplicate helper

    /// Detects 2+ charges from the same merchant on the same calendar day
    /// within a single batch. This is INTRA-batch; the historical dedup
    /// (multi-scan, multi-day) is handled by the change log's hash.
    private static func duplicatesInBatch(
        _ txns: [StatementTransaction],
        source: SubscriptionChange.ChangeSource,
        now: Date
    ) -> [SubscriptionChange] {
        // Group by (normalized merchant, calendar day).
        var buckets: [String: [StatementTransaction]] = [:]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        for txn in txns {
            let merchantKey = MerchantNormalizer.normalize(txn.merchantRaw)
            guard !merchantKey.isEmpty else { continue }
            let dayKey = dayFormatter.string(from: txn.date)
            let bucketKey = "\(merchantKey)|\(dayKey)"
            buckets[bucketKey, default: []].append(txn)
        }

        return buckets.values
            .filter { $0.count >= 2 }
            .map { group in
                let first = group[0]
                let total = group.reduce(0.0) { $0 + $1.amount }
                return SubscriptionChange(
                    subscriptionID: nil,
                    type: .duplicate,
                    detectedAt: now,
                    previousValue: nil,
                    newValue: String(format: "%d charges of %.2f %@ on %@",
                                     group.count, first.amount, first.currency,
                                     dayFormatter.string(from: first.date)),
                    source: source,
                    newBaseAmount: total    // hash uses total for cross-currency stability
                )
            }
    }

    // MARK: - trialExpiring helper

    private static func trialsExpiringSoon(
        existing: [Subscription],
        source: SubscriptionChange.ChangeSource,
        now: Date
    ) -> [SubscriptionChange] {
        let threshold = Calendar.current.date(
            byAdding: .day,
            value: Thresholds.trialExpirationWindowDays,
            to: now
        ) ?? now

        return existing.compactMap { sub -> SubscriptionChange? in
            guard sub.status == .trial,
                  let trialEnd = sub.trialEndDate,
                  trialEnd >= now,
                  trialEnd <= threshold
            else { return nil }

            let daysLeft = Calendar.current.dateComponents([.day], from: now, to: trialEnd).day ?? 0
            return SubscriptionChange(
                subscriptionID: sub.id,
                type: .trialExpiring,
                detectedAt: now,
                previousValue: nil,
                newValue: "\(daysLeft)d until trial ends",
                source: source,
                newBaseAmount: sub.amount   // hash stable across same sub's re-detection
            )
        }
    }
}
