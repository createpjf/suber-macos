import Foundation
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings

    init() {
        settings = StorageService.shared.loadSettings()
    }

    func update(_ modify: (inout AppSettings) -> Void) {
        modify(&settings)
        save()
    }

    func reset() {
        settings = AppSettings()
        save()
    }

    func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        save()

        if settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    func toggleReminderDay(_ day: Int) {
        if settings.reminderDaysBefore.contains(day) {
            settings.reminderDaysBefore.removeAll { $0 == day }
        } else {
            settings.reminderDaysBefore.append(day)
            settings.reminderDaysBefore.sort()
        }
        save()
    }

    private func save() {
        StorageService.shared.saveSettings(settings)
    }
}
