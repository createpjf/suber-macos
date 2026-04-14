import Foundation

struct AppSettings: Codable, Equatable {
    var primaryCurrency: String = "USD"
    var reminderDaysBefore: [Int] = [1, 3]
    var enableNotifications: Bool = true
    var launchAtLogin: Bool = false
    var enableGlobalShortcut: Bool = true
    var enableCloudSync: Bool = false
    var language: String = "en"
}
