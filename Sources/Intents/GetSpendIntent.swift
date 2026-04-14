import AppIntents
import Foundation

/// Shortcuts action: Get the current monthly subscription spend.
struct GetSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Monthly Spend"
    static var description = IntentDescription("Get your total monthly subscription spend from Suber.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let subs = StorageService.shared.loadSubscriptions()
        let settings = StorageService.shared.loadSettings()
        let currency = settings.primaryCurrency

        let total = subs
            .filter { $0.status == .active || $0.status == .trial }
            .reduce(0.0) { sum, sub in
                let monthly = BillingCalculator.getMonthlyEquivalent(sub)
                return sum + ExchangeRateService.shared.convert(monthly, from: sub.currency, to: currency)
            }

        let formatted = CurrencyFormatter.formatShort(total, currency: currency)
        let count = subs.filter { $0.status == .active }.count

        return .result(dialog: "You're spending \(formatted) per month across \(count) active subscription\(count == 1 ? "" : "s").")
    }
}

// MARK: - App Shortcuts Provider

struct SuberShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetSpendIntent(),
            phrases: [
                "How much am I spending on subscriptions in \(.applicationName)",
                "Get my monthly spend from \(.applicationName)",
            ],
            shortTitle: "Monthly Spend",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: AddSubscriptionIntent(),
            phrases: [
                "Add a subscription in \(.applicationName)",
                "Track a new subscription with \(.applicationName)",
            ],
            shortTitle: "Add Subscription",
            systemImageName: "plus.circle"
        )
    }
}
