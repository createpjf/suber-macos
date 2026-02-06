import Foundation

enum CurrencyFormatter {
    /// Format with 2 decimal places: "$9.99"
    static func format(_ amount: Double, currency: String) -> String {
        let symbol = AppConstants.currencySymbols[currency] ?? currency
        return "\(symbol)\(String(format: "%.2f", amount))"
    }

    /// Format omitting decimals for whole numbers: "$9" or "$9.99"
    static func formatShort(_ amount: Double, currency: String) -> String {
        let symbol = AppConstants.currencySymbols[currency] ?? currency
        if amount == floor(amount) {
            return "\(symbol)\(Int(amount))"
        }
        return "\(symbol)\(String(format: "%.2f", amount))"
    }
}
