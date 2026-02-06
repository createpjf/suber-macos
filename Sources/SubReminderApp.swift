import SwiftUI

@main
struct SubReminderApp: App {
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        MenuBarExtra("Suber", image: "MenuBarIcon") {
            MenuBarView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .frame(width: 480)
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.bgPrimary)
        }
        .menuBarExtraStyle(.window)
    }
}
