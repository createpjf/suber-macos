import Foundation

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case monthly
    case yearly
    case weekly
    case quarterly
    case oneTime = "one-time"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .weekly: return "Weekly"
        case .quarterly: return "Quarterly"
        case .oneTime: return "One-time"
        }
    }

    var shortLabel: String {
        switch self {
        case .monthly: return "/mo"
        case .yearly: return "/yr"
        case .weekly: return "/wk"
        case .quarterly: return "/qtr"
        case .oneTime: return ""
        }
    }
}

enum SubscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case cancelled
    case trial

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

struct Subscription: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var url: String?
    var logo: String?
    var amount: Double
    var currency: String
    var cycle: BillingCycle
    var billingDay: Int
    var startDate: Date
    var trialEndDate: Date?
    var category: String
    var status: SubscriptionStatus
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

struct SubscriptionFormData {
    var name: String = ""
    var url: String = ""
    var logo: String?
    var amount: String = ""
    var currency: String = "USD"
    var cycle: BillingCycle = .monthly
    var billingDay: Int = Calendar.current.component(.day, from: Date())
    var startDate: Date = Date()
    var trialEndDate: Date?
    var category: String = "Other"
    var status: SubscriptionStatus = .active
    var notes: String = ""

    init() {}

    init(from sub: Subscription) {
        name = sub.name
        url = sub.url ?? ""
        logo = sub.logo
        amount = sub.amount == floor(sub.amount)
            ? String(format: "%.0f", sub.amount)
            : String(format: "%.2f", sub.amount)
        currency = sub.currency
        cycle = sub.cycle
        billingDay = sub.billingDay
        startDate = sub.startDate
        trialEndDate = sub.trialEndDate
        category = sub.category
        status = sub.status
        notes = sub.notes ?? ""
    }

    var parsedAmount: Double? {
        Double(amount)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil && parsedAmount! > 0
    }
}
