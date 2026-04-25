import Foundation

/// Provides currency conversion with offline-first strategy:
/// 1. Hardcoded fallback rates (always available)
/// 2. Cached rates from previous API fetch (UserDefaults)
/// 3. Live rates from frankfurter.app (refreshed every 24h)
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    // v1.6.2: Migrated off UserDefaults(suiteName:) — see AppGroupStore.swift
    // for the macOS 26.4 (Tahoe) cfprefsd regression that necessitated this.
    private let ratesKey = "suber-exchange-rates"
    private let updatedAtKey = "suber-rates-updated-at"
    private let refreshInterval: TimeInterval = 86400 // 24 hours

    /// Rates relative to USD (1 USD = X units of currency)
    private(set) var rates: [String: Double]

    // MARK: - Hardcoded Fallback (approximate)

    private static let fallbackRates: [String: Double] = [
        "USD": 1.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "CNY": 7.24,
        "JPY": 154.5,
        "KRW": 1380.0,
        "CAD": 1.37,
        "AUD": 1.55,
        "CHF": 0.88,
        "HKD": 7.82,
        "SGD": 1.35,
        "SEK": 10.8,
        "NOK": 11.0,
        "DKK": 6.88,
        "INR": 83.5,
        "BRL": 5.05,
        "MXN": 17.2,
        "TWD": 31.8,
        "THB": 36.0,
        "RUB": 92.0,
    ]

    private init() {
        // Load cached rates, or fall back to hardcoded
        if let data = AppGroupStore.data(forKey: ratesKey),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            rates = cached
        } else {
            rates = Self.fallbackRates
        }
    }

    // MARK: - Conversion

    /// Convert an amount from one currency to another.
    func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }

        let fromRate = rates[from] ?? 1.0
        let toRate = rates[to] ?? 1.0

        // Convert: amount in `from` → USD → `to`
        let usdAmount = amount / fromRate
        return usdAmount * toRate
    }

    // MARK: - Refresh

    /// Fetch latest rates from API if stale (>24h since last refresh).
    func refreshIfNeeded() async {
        // updatedAt persisted as TimeInterval since 1970 (Double).
        let lastUpdatedTI = AppGroupStore.double(forKey: updatedAtKey)
        let lastUpdated = lastUpdatedTI > 0 ? Date(timeIntervalSince1970: lastUpdatedTI) : .distantPast
        guard Date().timeIntervalSince(lastUpdated) > refreshInterval else { return }
        await refreshRates()
    }

    /// Force fetch latest rates from frankfurter.app.
    func refreshRates() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apiRates = json["rates"] as? [String: Any] else { return }

            var newRates: [String: Double] = ["USD": 1.0]
            for (code, value) in apiRates {
                if let rate = value as? Double {
                    newRates[code] = rate
                } else if let rate = value as? Int {
                    newRates[code] = Double(rate)
                }
            }

            // Only update if we got a reasonable number of rates
            guard newRates.count > 10 else { return }

            rates = newRates

            // Cache to app-group container (file-based, see AppGroupStore).
            if let encoded = try? JSONEncoder().encode(newRates) {
                AppGroupStore.set(encoded, forKey: ratesKey)
                AppGroupStore.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
            }
        } catch {
            // Silently fail — we always have cached or fallback rates
        }
    }
}
