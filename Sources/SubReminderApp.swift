import SwiftUI

@main
struct SubReminderApp: App {
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .frame(width: 480, height: 420)
                .background(Theme.bgPrimary)
        } label: {
            Image(systemName: "creditcard.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
