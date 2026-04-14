import AppIntents
import Foundation

/// Shortcuts action: Add a new subscription to Suber.
struct AddSubscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Subscription"
    static var description = IntentDescription("Add a new subscription to Suber.")

    @Parameter(title: "Service Name")
    var name: String

    @Parameter(title: "Amount", default: 0.0)
    var amount: Double

    @Parameter(title: "Currency", default: "USD")
    var currency: String

    @Parameter(title: "Billing Cycle", default: "monthly")
    var cycle: String

    @Parameter(title: "Category", default: "Other")
    var category: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var data = SubscriptionFormData()
        data.name = name
        data.amount = amount == 0 ? "0" : String(format: "%.2f", amount)
        data.currency = currency.uppercased()
        data.category = category

        switch cycle.lowercased() {
        case "yearly", "annual": data.cycle = .yearly
        case "weekly": data.cycle = .weekly
        case "quarterly": data.cycle = .quarterly
        case "one-time", "onetime": data.cycle = .oneTime
        default: data.cycle = .monthly
        }

        // Write directly via StorageService (Intents may not have access to @MainActor stores)
        var subs = StorageService.shared.loadSubscriptions()
        let sub = Subscription(
            id: UUID(),
            name: data.name.trimmingCharacters(in: .whitespaces),
            amount: Double(data.amount) ?? amount,
            currency: data.currency,
            cycle: data.cycle,
            billingDay: Calendar.current.component(.day, from: Date()),
            startDate: Date(),
            category: data.category,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        subs.append(sub)
        StorageService.shared.saveSubscriptions(subs)

        let formatted = CurrencyFormatter.formatShort(sub.amount, currency: sub.currency)
        return .result(dialog: "Added \(name) — \(formatted)/\(data.cycle.shortLabel.isEmpty ? "one-time" : String(data.cycle.shortLabel.dropFirst()))")
    }
}
