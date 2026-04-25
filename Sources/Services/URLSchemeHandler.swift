import Foundation

/// v1.6: Suber supports two URL schemes:
///   suber://add?name=...     — single-shot subscription creation
///   suber://changes          — open the Changes Window (v1.6 Sentinel)
///
/// Action surfaces:
///   - suber://add → SuberApp.handleURL → subscriptionStore.add(data)
///   - suber://changes → SuberApp.handleURL → importPresenter.showChanges + openWindow
enum SuberURLAction: Equatable {
    case add(SubscriptionFormData)
    case openChanges
}

/// Parses `suber://add?name=Netflix&amount=15.99&currency=USD&cycle=monthly` URLs
/// and `suber://changes` URLs.
enum URLSchemeHandler {

    /// v1.6 entry point: returns an action for the caller to dispatch.
    static func parseAction(_ url: URL) -> SuberURLAction? {
        guard url.scheme == "suber" else { return nil }
        switch url.host {
        case "changes":
            return .openChanges
        case "add":
            if let data = parse(url) { return .add(data) }
            return nil
        default:
            return nil
        }
    }

    /// Parse a suber:// URL and return form data. Returns nil if the URL is invalid or missing required params.
    static func parse(_ url: URL) -> SubscriptionFormData? {
        guard url.scheme == "suber", url.host == "add" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }

        let params = Dictionary(queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        }, uniquingKeysWith: { _, last in last })

        // name is required
        guard let name = params["name"], !name.isEmpty else { return nil }

        var data = SubscriptionFormData()
        data.name = name
        data.url = params["url"] ?? params["domain"] ?? ""
        data.amount = params["amount"] ?? "0"
        data.currency = params["currency"]?.uppercased() ?? StorageService.shared.loadSettings().primaryCurrency
        data.category = params["category"] ?? "Other"

        if let cycleStr = params["cycle"] {
            switch cycleStr.lowercased() {
            case "monthly": data.cycle = .monthly
            case "yearly", "annual": data.cycle = .yearly
            case "weekly": data.cycle = .weekly
            case "quarterly": data.cycle = .quarterly
            case "one-time", "onetime": data.cycle = .oneTime
            default: break
            }
        }

        if let dayStr = params["billingday"], let day = Int(dayStr), day >= 1, day <= 31 {
            data.billingDay = day
        }

        if let splitStr = params["split"], let split = Int(splitStr), split >= 1 {
            data.splitCount = split
        }

        return data
    }
}
