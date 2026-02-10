import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var showClearConfirm = false
    @State private var importError: String?
    @State private var showImportError = false

    private let reminderOptions = [1, 2, 3, 5, 7]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Currency
                section("CURRENCY") {
                    HStack {
                        Text("Primary Currency")
                            .font(AppFont.regular(13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settingsStore.settings.primaryCurrency },
                            set: { newVal in settingsStore.update { $0.primaryCurrency = newVal } }
                        )) {
                            ForEach(AppConstants.currencies, id: \.self) { c in
                                Text("\(AppConstants.currencySymbols[c] ?? "") \(c)").tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.textSecondary)
                        .frame(width: 100)
                    }
                }

                divider

                // Notifications
                section("NOTIFICATIONS") {
                    ToggleRow(label: "Enable Notifications", isOn: Binding(
                        get: { settingsStore.settings.enableNotifications },
                        set: { val in settingsStore.update { $0.enableNotifications = val } }
                    ))

                    if settingsStore.settings.enableNotifications {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remind Before")
                                .font(AppFont.regular(11))
                                .foregroundColor(Theme.textSecondary)

                            HStack(spacing: 6) {
                                ForEach(reminderOptions, id: \.self) { day in
                                    let isSelected = settingsStore.settings.reminderDaysBefore.contains(day)
                                    Button(action: { settingsStore.toggleReminderDay(day) }) {
                                        Text("\(day)d")
                                            .font(AppFont.medium(11))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? Theme.textPrimary : Theme.bgSecondary)
                                            .foregroundColor(isSelected ? Theme.bgPrimary : Theme.textSecondary)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                divider

                // Launch at Login
                section("GENERAL") {
                    ToggleRow(label: "Launch at Login", isOn: Binding(
                        get: { settingsStore.settings.launchAtLogin },
                        set: { _ in settingsStore.toggleLaunchAtLogin() }
                    ))
                }

                divider

                // Data
                section("DATA") {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            actionButton("Export JSON", icon: "square.and.arrow.up") {
                                exportData()
                            }
                            actionButton("Import JSON", icon: "square.and.arrow.down") {
                                importData()
                            }
                        }

                        Button(action: { showClearConfirm = true }) {
                            HStack {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                Text("Clear All Data")
                                    .font(AppFont.medium(12))
                            }
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                divider

                // Quit
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                        Text("Quit Suber")
                            .font(AppFont.medium(13))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                divider

                // About
                section("ABOUT") {
                    HStack {
                        Text("Suber")
                            .font(AppFont.regular(13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text("v1.0.0")
                            .font(AppFont.regular(12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Button(action: {
                        if let url = URL(string: "https://github.com/createpjf/suber-macos") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                            Text("Website")
                                .font(AppFont.regular(13))
                        }
                        .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
        .alert("Clear All Data", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                subscriptionStore.clearAll()
                settingsStore.reset()
            }
        } message: {
            Text("This will permanently delete all subscriptions and reset settings.")
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.bold(10))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Divider().background(Theme.border)
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(AppFont.medium(12))
            }
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export/Import

    private func exportData() {
        guard let data = StorageService.shared.exportData(
            subscriptions: subscriptionStore.subscriptions,
            settings: settingsStore.settings
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "suber-backup-\(formatter.string(from: Date())).json"

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let result = try StorageService.shared.importData(from: data)
                subscriptionStore.importSubscriptions(result.subscriptions)
                settingsStore.update { settings in
                    settings = result.settings
                }
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }
}
