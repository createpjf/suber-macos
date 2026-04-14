import Foundation

/// Parses `suber://add?name=Netflix&amount=15.99&currency=USD&cycle=monthly` URLs.
enum URLSchemeHandler {

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
