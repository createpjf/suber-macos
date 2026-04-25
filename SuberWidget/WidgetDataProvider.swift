import Foundation
import WidgetKit

// MARK: - Shared Data Reader

enum WidgetData {
    // v1.6.2: Read from file-based AppGroupStore instead of
    // UserDefaults(suiteName:). The latter is broken on macOS 26.4 (Tahoe)
    // — see Sources/Services/AppGroupStore.swift for the cfprefsd
    // regression context. AppGroupStore is shared with the main app via
    // project.yml SuberWidget.sources so reads here see exactly what
    // StorageService.saveSubscriptions() wrote.

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: str) { return date }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }

            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnly.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    static func loadSubscriptions() -> [Subscription] {
        guard let data = AppGroupStore.data(forKey: "suber-subscriptions") else { return [] }
        return (try? decoder.decode([Subscription].self, from: data)) ?? []
    }

    static func loadSettings() -> AppSettings {
        guard let data = AppGroupStore.data(forKey: "suber-settings") else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    static func loadExchangeRates() -> [String: Double] {
        guard let data = AppGroupStore.data(forKey: "suber-exchange-rates"),
              let rates = try? JSONDecoder().decode([String: Double].self, from: data) else {
            // Fallback rates
            return ["USD": 1.0, "EUR": 0.92, "GBP": 0.79, "CNY": 7.24, "JPY": 154.5,
                    "KRW": 1380.0, "CAD": 1.37, "AUD": 1.55, "CHF": 0.88, "HKD": 7.82,
                    "SGD": 1.35, "SEK": 10.8, "NOK": 11.0, "DKK": 6.88, "INR": 83.5,
                    "BRL": 5.05, "MXN": 17.2, "TWD": 31.8, "THB": 36.0, "RUB": 92.0]
        }
        return rates
    }

    static func convert(_ amount: Double, from: String, to: String, rates: [String: Double]) -> Double {
        guard from != to else { return amount }
        let fromRate = rates[from] ?? 1.0
        let toRate = rates[to] ?? 1.0
        return amount / fromRate * toRate
    }
}

// MARK: - Timeline Entry

struct SuberWidgetEntry: TimelineEntry {
    let date: Date
    let monthlySpend: Double
    let activeCount: Int
    let currency: String
    let upcomingBills: [UpcomingBill]

    struct UpcomingBill: Identifiable {
        let id: UUID
        let name: String
        let amount: Double
        let currency: String
        let daysUntil: Int
        let initial: String      // first letter for icon placeholder
    }
}

// MARK: - Timeline Provider

struct SuberTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SuberWidgetEntry {
        SuberWidgetEntry(
            date: Date(),
            monthlySpend: 49.97,
            activeCount: 5,
            currency: "USD",
            upcomingBills: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SuberWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SuberWidgetEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 2 hours
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func makeEntry() -> SuberWidgetEntry {
        let subscriptions = WidgetData.loadSubscriptions()
        let settings = WidgetData.loadSettings()

        let active = subscriptions.filter { $0.status == .active || $0.status == .trial }

        let rates = WidgetData.loadExchangeRates()
        let target = settings.primaryCurrency
        let monthlySpend = active.reduce(0.0) { sum, sub in
            let equiv = BillingCalculator.getMonthlyEquivalent(sub)
            return sum + WidgetData.convert(equiv, from: sub.currency, to: target, rates: rates)
        }

        // Upcoming bills in next 7 days
        let upcoming = active
            .compactMap { sub -> SuberWidgetEntry.UpcomingBill? in
                guard sub.cycle != .oneTime else { return nil }
                let days = BillingCalculator.getDaysUntilBilling(sub)
                guard days <= 7 else { return nil }
                return SuberWidgetEntry.UpcomingBill(
                    id: sub.id,
                    name: sub.name,
                    amount: sub.amount,
                    currency: sub.currency,
                    daysUntil: days,
                    initial: String(sub.name.prefix(1)).uppercased()
                )
            }
            .sorted { $0.daysUntil < $1.daysUntil }
            .prefix(4)
            .map { $0 }

        return SuberWidgetEntry(
            date: Date(),
            monthlySpend: monthlySpend,
            activeCount: active.count,
            currency: settings.primaryCurrency,
            upcomingBills: upcoming
        )
    }
}
