import Foundation

/// Groups `StatementTransaction`s by normalized merchant and scores each group
/// against "does this look like a recurring subscription?" heuristics.
///
/// Heuristic:
/// 1. Merchants with fewer than 2 charges are skipped.
/// 2. Interval is the MEDIAN gap between consecutive charges (not mean — one
///    anomaly shouldn't blow up detection).
/// 3. Interval is matched to weekly / monthly / quarterly with generous tolerances;
///    yearly is deliberately skipped (needs ≥2 years of history, rarely available).
/// 4. Amount stability (coefficient of variation) filters out variable-amount merchants
///    like groceries. A KnownServices match relaxes this gate so Netflix promo-price
///    transitions don't get rejected.
enum RecurringChargeDetector {

    /// Main entry. Returns candidates sorted by (confidence desc, amount desc).
    static func detect(transactions: [StatementTransaction]) -> [CandidateSubscription] {
        // 1. Group by normalized merchant
        var groups: [String: [StatementTransaction]] = [:]
        for tx in transactions {
            let key = MerchantNormalizer.normalize(tx.merchantRaw)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(tx)
        }

        var candidates: [CandidateSubscription] = []

        for (normalizedKey, txs) in groups where txs.count >= 2 {
            guard let candidate = scoreGroup(normalizedKey: normalizedKey, txs: txs) else { continue }
            candidates.append(candidate)
        }

        candidates.sort { a, b in
            if a.confidence != b.confidence {
                return confidenceRank(a.confidence) > confidenceRank(b.confidence)
            }
            return a.amount > b.amount
        }
        return candidates
    }

    // MARK: - Private

    private static func confidenceRank(_ c: ImportConfidence) -> Int {
        switch c {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private static func scoreGroup(normalizedKey: String, txs: [StatementTransaction]) -> CandidateSubscription? {
        let sortedTxs = txs.sorted { $0.date < $1.date }

        // Compute intervals in days between consecutive charges
        let cal = Calendar.current
        var intervals: [Int] = []
        for i in 1..<sortedTxs.count {
            let days = cal.dateComponents([.day], from: sortedTxs[i - 1].date, to: sortedTxs[i].date).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return nil }

        let medianInterval = median(intervals)
        guard let cycle = cycleFor(medianInterval: medianInterval) else { return nil }

        // Amount stability
        let amounts = sortedTxs.map(\.amount)
        let amountMedian = median(amounts)
        guard amountMedian > 0 else { return nil }
        let amountCV = coefficientOfVariation(amounts)

        // Try to match to a known service using a representative merchant string.
        // Use the most common raw form (falls back to first).
        let sampleRaw = mostCommonMerchantRaw(txs)
        let knownService = KnownServices.findMatch(in: sampleRaw)

        // Gate: amount too drifty AND not a known service → skip.
        // Threshold of 0.2 CV catches grocery / food-delivery variable spends while
        // tolerating Netflix-style small promo price swings.
        if amountCV > 0.2 && knownService == nil {
            return nil
        }

        // Build confidence score
        var score = 0
        if knownService != nil { score += 3 }
        score += min(Int(txs.count - 2) * 2, 6) // +2 per extra occurrence beyond the minimum 2, cap at +6
        if amountCV < 0.05 { score += 2 }
        else if amountCV > 0.15 { score -= 2 }

        let confidence: ImportConfidence
        if score >= 5 { confidence = .high }
        else if score >= 2 { confidence = .medium }
        else { confidence = .low }

        // Currency: most common in the group
        let currency = mostCommonCurrency(txs)

        let lastDate = sortedTxs.last!.date
        let firstDate = sortedTxs.first!.date
        let billingDay = cal.component(.day, from: lastDate)

        // Name / category
        let name = knownService?.names.first ?? MerchantNormalizer.displayName(from: normalizedKey)
        let category = knownService?.category

        return CandidateSubscription(
            name: name,
            normalizedMerchant: normalizedKey,
            sampleMerchantRaw: sampleRaw,
            amount: amountMedian,
            currency: currency,
            cycle: cycle,
            billingDay: billingDay,
            startDate: firstDate,
            lastChargeDate: lastDate,
            category: category,
            occurrences: sortedTxs.count,
            confidence: confidence
        )
    }

    /// Median interval → BillingCycle.
    /// Tolerances account for banks batching on weekends / month length variance.
    private static func cycleFor(medianInterval: Int) -> BillingCycle? {
        switch medianInterval {
        case 4...10: return .weekly
        case 26...35: return .monthly
        case 85...95: return .quarterly
        default: return nil
        }
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// std-dev / |mean|; 0 when mean is 0.
    private static func coefficientOfVariation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean != 0 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance) / abs(mean)
    }

    private static func mostCommonCurrency(_ txs: [StatementTransaction]) -> String {
        var counts: [String: Int] = [:]
        for t in txs { counts[t.currency, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "USD"
    }

    private static func mostCommonMerchantRaw(_ txs: [StatementTransaction]) -> String {
        var counts: [String: Int] = [:]
        for t in txs { counts[t.merchantRaw, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? txs.first?.merchantRaw ?? ""
    }
}
