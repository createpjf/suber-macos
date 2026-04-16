import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Types

    struct MonthData: Identifiable {
        let id: String          // "yyyy-MM"
        let label: String       // "Jan", "Feb", ...
        let year: Int
        let month: Int
        let total: Double
        let isCurrent: Bool
    }

    struct CategoryData: Identifiable {
        let id: String          // category name
        let name: String
        let total: Double
        let percentage: Double
        let color: Int          // index for color palette
    }

    struct TopSubscription: Identifiable {
        let id: UUID
        let subscription: Subscription
        let monthlyEquivalent: Double
    }

    // MARK: - Published

    @Published var monthlySpend: Double = 0
    @Published var yearlySpend: Double = 0
    @Published var activeCount: Int = 0
    @Published var pausedCount: Int = 0
    @Published var trialCount: Int = 0
    @Published var monthTrend: [MonthData] = []
    @Published var categoryBreakdown: [CategoryData] = []
    @Published var topSubscriptions: [TopSubscription] = []

    // MARK: - Compute

    func update(subscriptions: [Subscription], currency: String) {
        let active = subscriptions.filter { $0.status == .active }
        let trials = subscriptions.filter { $0.status == .trial }
        let paused = subscriptions.filter { $0.status == .paused }

        activeCount = active.count
        pausedCount = paused.count
        trialCount = trials.count

        // Monthly / yearly spend (active + trial), converted to primary currency
        let billable = active + trials
        let monthly = billable.reduce(0.0) { sum, sub in
            let equiv = BillingCalculator.getMonthlyEquivalent(sub)
            return sum + ExchangeRateService.shared.convert(equiv, from: sub.currency, to: currency)
        }
        monthlySpend = monthly
        yearlySpend = monthly * 12

        // Monthly trend (past 5 months + current) — converts each sub into `currency`
        monthTrend = computeMonthTrend(subscriptions: subscriptions, currency: currency)

        // Category breakdown
        categoryBreakdown = computeCategoryBreakdown(subscriptions: billable, currency: currency)

        // Top 5 by monthly equivalent
        topSubscriptions = billable
            .map {
                let equiv = BillingCalculator.getMonthlyEquivalent($0)
                let converted = ExchangeRateService.shared.convert(equiv, from: $0.currency, to: currency)
                return TopSubscription(id: $0.id, subscription: $0, monthlyEquivalent: converted)
            }
            .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Private

    private func computeMonthTrend(subscriptions: [Subscription], currency: String) -> [MonthData] {
        let cal = Calendar.current
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        let currentMonth = cal.component(.month, from: now)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var result: [MonthData] = []

        for offset in stride(from: -5, through: 0, by: 1) {
            guard let monthDate = cal.date(byAdding: .month, value: offset, to: now) else { continue }
            let year = cal.component(.year, from: monthDate)
            let month = cal.component(.month, from: monthDate)
            let label = formatter.string(from: monthDate)
            let key = String(format: "%04d-%02d", year, month)

            let total = computeMonthTotal(subscriptions: subscriptions, year: year, month: month, currency: currency)
            let isCurrent = (year == currentYear && month == currentMonth)

            result.append(MonthData(id: key, label: label, year: year, month: month, total: total, isCurrent: isCurrent))
        }

        return result
    }

    private func computeMonthTotal(subscriptions: [Subscription], year: Int, month: Int, currency: String) -> Double {
        var total = 0.0

        for sub in subscriptions where sub.status == .active || sub.status == .trial {
            let amountInTarget = ExchangeRateService.shared.convert(sub.amount, from: sub.currency, to: currency)

            if sub.cycle == .weekly {
                let dates = BillingCalculator.getWeeklyBillingDatesInMonth(sub, year: year, month: month)
                total += Double(dates.count) * amountInTarget
            } else if BillingCalculator.getBillingDateInMonth(sub, year: year, month: month) != nil {
                total += amountInTarget
            }
        }

        return total
    }

    private func computeCategoryBreakdown(subscriptions: [Subscription], currency: String) -> [CategoryData] {
        var categoryTotals: [String: Double] = [:]

        for sub in subscriptions {
            let monthly = BillingCalculator.getMonthlyEquivalent(sub)
            let converted = ExchangeRateService.shared.convert(monthly, from: sub.currency, to: currency)
            categoryTotals[sub.category, default: 0] += converted
        }

        let grandTotal = categoryTotals.values.reduce(0, +)
        guard grandTotal > 0 else { return [] }

        return categoryTotals
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { index, pair in
                CategoryData(
                    id: pair.key,
                    name: pair.key,
                    total: pair.value,
                    percentage: pair.value / grandTotal * 100,
                    color: index
                )
            }
    }
}
