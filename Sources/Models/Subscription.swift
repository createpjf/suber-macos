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
    var splitCount: Int
    var createdAt: Date
    var updatedAt: Date

    /// The per-person amount after splitting.
    var effectiveAmount: Double {
        amount / Double(max(splitCount, 1))
    }

    // Custom Codable to default splitCount to 1 for backward compat
    enum CodingKeys: String, CodingKey {
        case id, name, url, logo, amount, currency, cycle, billingDay, startDate
        case trialEndDate, category, status, notes, splitCount, createdAt, updatedAt
    }

    init(id: UUID, name: String, url: String? = nil, logo: String? = nil,
         amount: Double, currency: String, cycle: BillingCycle, billingDay: Int,
         startDate: Date, trialEndDate: Date? = nil, category: String,
         status: SubscriptionStatus, notes: String? = nil, splitCount: Int = 1,
         createdAt: Date, updatedAt: Date) {
        self.id = id; self.name = name; self.url = url; self.logo = logo
        self.amount = amount; self.currency = currency; self.cycle = cycle
        self.billingDay = billingDay; self.startDate = startDate
        self.trialEndDate = trialEndDate; self.category = category
        self.status = status; self.notes = notes
        self.splitCount = max(splitCount, 1)
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        amount = try c.decode(Double.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        cycle = try c.decode(BillingCycle.self, forKey: .cycle)
        billingDay = try c.decode(Int.self, forKey: .billingDay)
        startDate = try c.decode(Date.self, forKey: .startDate)
        trialEndDate = try c.decodeIfPresent(Date.self, forKey: .trialEndDate)
        category = try c.decode(String.self, forKey: .category)
        status = try c.decode(SubscriptionStatus.self, forKey: .status)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        splitCount = try c.decodeIfPresent(Int.self, forKey: .splitCount) ?? 1
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
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
    var splitCount: Int = 1

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
        splitCount = sub.splitCount
    }

    var parsedAmount: Double? {
        Double(amount)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil && parsedAmount! > 0
    }
}
