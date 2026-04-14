import SwiftUI

@main
struct SuberApp: App {
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var settingsStore = SettingsStore()

    // NOTE: HotkeyService (Option+S global shortcut) was removed — its
    // NSEvent.addGlobalMonitorForEvents triggered repeated TCC Accessibility /
    // Input-Monitoring requests which, on ad-hoc signed builds, corrupted event
    // routing and broke MenuBarExtra clicks. Revisit with Carbon
    // RegisterEventHotKey when properly signed.

    var body: some Scene {
        MenuBarExtra("Suber", image: "MenuBarIcon") {
            MenuBarView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .frame(width: 480)
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.bgPrimary)
                .onAppear {
                    setupCloudSync()
                    Task { await ExchangeRateService.shared.refreshIfNeeded() }
                }
                .onOpenURL { url in handleURL(url) }
                .onReceive(settingsStore.$settings) { settings in
                    if settings.enableCloudSync {
                        CloudSyncService.shared.startSync()
                    } else {
                        CloudSyncService.shared.stopSync()
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .handlesExternalEvents(matching: ["suber"])
    }

    private func handleURL(_ url: URL) {
        guard let data = URLSchemeHandler.parse(url) else { return }
        subscriptionStore.add(data)
    }

    private func setupCloudSync() {
        guard settingsStore.settings.enableCloudSync else { return }

        CloudSyncService.shared.startSync()

        CloudSyncService.shared.onRemoteChange = { [weak subscriptionStore, weak settingsStore] subsData, settingsData in
            if let data = subsData,
               let subs = try? JSONDecoder.suberDecoder.decode([Subscription].self, from: data) {
                subscriptionStore?.importSubscriptions(subs)
            }
            if let data = settingsData,
               let settings = try? JSONDecoder.suberDecoder.decode(AppSettings.self, from: data) {
                settingsStore?.update { $0 = settings }
            }
        }
    }
}

// MARK: - Shared Decoder

extension JSONDecoder {
    /// Shared decoder matching StorageService's date handling.
    static let suberDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: str) { return date }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }

            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnly.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()
}
