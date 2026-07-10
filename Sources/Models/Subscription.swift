import Foundation

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case monthly
    case yearly
    case weekly
    case quarterly
    case oneTime = "one-time"

    var id: String { rawValue }

    // AUDIT-v1.9.2 U-02: labels flow into the UI as Strings (form pickers,
    // card price rows) — String(localized:) so zh-Hans resolves. Note: the
    // widget target compiles this file but doesn't bundle the catalog, so
    // widget-rendered labels fall back to English (see project.yml).
    var label: String {
        switch self {
        case .monthly: return String(localized: "Monthly")
        case .yearly: return String(localized: "Yearly")
        case .weekly: return String(localized: "Weekly")
        case .quarterly: return String(localized: "Quarterly")
        case .oneTime: return String(localized: "One-time")
        }
    }

    var shortLabel: String {
        switch self {
        case .monthly: return String(localized: "/mo")
        case .yearly: return String(localized: "/yr")
        case .weekly: return String(localized: "/wk")
        case .quarterly: return String(localized: "/qtr")
        case .oneTime: return ""
        }
    }
}

// ┌───────────── Status transitions (v1.6) ─────────────────────────┐
// │                                                                 │
// │     ┌─────────┐   toggle    ┌────────┐                          │
// │     │ active  │◄───────────►│ paused │                          │
// │     └────┬────┘             └────────┘                          │
// │          │ trial period ends                                    │
// │     ┌────▼────┐                                                 │
// │     │  trial  │                                                 │
// │     └────┬────┘                                                 │
// │          │ user taps "Open cancel page…"                        │
// │     ┌────▼─────────────────┐                                    │
// │     │ pendingCancellation  │                                    │
// │     └──┬───────────────┬───┘                                    │
// │        │ charge seen   │ no charge in window (data-source gated)│
// │        │ in window     │                                        │
// │     ┌──▼──────┐     ┌──▼────────┐                               │
// │     │ active  │     │ cancelled │                               │
// │     │ +Failed │     └───────────┘                               │
// │     └─────────┘                                                 │
// │                                                                 │
// │ D7 (CEO) fallback: unknown raw case → decodes to .active        │
// │ (forward-compat for iCloud sync from v1.7+ clients)             │
// └─────────────────────────────────────────────────────────────────┘
enum SubscriptionStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case cancelled
    case trial
    /// v1.6: user tapped "Open cancel page…"; awaiting verification via Mail scan
    /// or CSV import. Transitions to .cancelled (no charge) or back to .active
    /// (charge detected) per D4 auto-transition logic, gated on data-source
    /// availability per eng re-review A4.
    case pendingCancellation = "pending_cancellation"

    var id: String { rawValue }

    // AUDIT-v1.9.2 U-02: explicit switch (was rawValue.capitalized) so every
    // status name is a static catalog key. English output is identical.
    var label: String {
        switch self {
        case .active: return String(localized: "Active")
        case .paused: return String(localized: "Paused")
        case .cancelled: return String(localized: "Cancelled")
        case .trial: return String(localized: "Trial")
        case .pendingCancellation: return String(localized: "Pending cancel")
        }
    }

    // MARK: Codable (D7 manual fallback)
    // Unknown raw values decode to .active with a warning log. Keeps v1.5.x
    // clients non-crashing if an iCloud sync ever delivers a future status
    // case they don't know about. Overrides the synthesized init(from:) that
    // would throw on unknown cases.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let match = SubscriptionStatus(rawValue: raw) {
            self = match
        } else {
            NSLog("Suber: unknown SubscriptionStatus '\(raw)' → falling back to .active")
            self = .active
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

    /// v1.6: user-overrideable cancel URL. If nil, falls back to
    /// `KnownServices.cancellationURL(for: name)`, then DuckDuckGo search.
    var cancellationURL: String?

    /// v1.6: timestamp set when status transitions to `.pendingCancellation`.
    /// D5 (eng review): re-tapping "Open cancel page" on an already-pending
    /// sub does NOT reset this — anchor stays pinned to the original tap so
    /// D4's auto-transition window doesn't move.
    /// A4 (eng re-review): auto-transition from pending only fires when the
    /// period between pendingCancellationSetAt and now is covered by at least
    /// one data source (Mail scan OR CSV import) — prevents false-positive
    /// cancellation confirmation for v1.5-style manual-only users.
    var pendingCancellationSetAt: Date?

    /// The per-person amount after splitting.
    var effectiveAmount: Double {
        amount / Double(max(splitCount, 1))
    }

    // Custom Codable to default splitCount to 1 for backward compat.
    // cancellationURL + pendingCancellationSetAt are both optional/nil-defaulting
    // so v1.5 clients reading v1.6 data ignore them, and v1.6 reading v1.5 data
    // gets nil (the expected default).
    enum CodingKeys: String, CodingKey {
        case id, name, url, logo, amount, currency, cycle, billingDay, startDate
        case trialEndDate, category, status, notes, splitCount, createdAt, updatedAt
        case cancellationURL, pendingCancellationSetAt
    }

    init(id: UUID, name: String, url: String? = nil, logo: String? = nil,
         amount: Double, currency: String, cycle: BillingCycle, billingDay: Int,
         startDate: Date, trialEndDate: Date? = nil, category: String,
         status: SubscriptionStatus, notes: String? = nil, splitCount: Int = 1,
         createdAt: Date, updatedAt: Date,
         cancellationURL: String? = nil, pendingCancellationSetAt: Date? = nil) {
        self.id = id; self.name = name; self.url = url; self.logo = logo
        self.amount = amount; self.currency = currency; self.cycle = cycle
        self.billingDay = billingDay; self.startDate = startDate
        self.trialEndDate = trialEndDate; self.category = category
        self.status = status; self.notes = notes
        self.splitCount = max(splitCount, 1)
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.cancellationURL = cancellationURL
        self.pendingCancellationSetAt = pendingCancellationSetAt
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
        cancellationURL = try c.decodeIfPresent(String.self, forKey: .cancellationURL)
        pendingCancellationSetAt = try c.decodeIfPresent(Date.self, forKey: .pendingCancellationSetAt)
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
        // AUDIT-v1.9.2 C-09: Double("inf")/"1e999" parse to ±∞ (and "nan" to
        // NaN); JSONEncoder's default .throw strategy then fails on EVERY
        // subsequent save/backup/cloud push. Non-finite values must never
        // enter the model.
        guard let value = Double(amount), value.isFinite else { return nil }
        return value
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount != nil && parsedAmount! > 0
    }
}
