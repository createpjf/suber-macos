import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    var onImport: (() -> Void)? = nil

    @State private var showClearConfirm = false
    @State private var importError: String?
    @State private var showImportError = false

    // v1.6: language override — restart prompt state.
    @State private var pendingLanguageChoice: LanguageOverride.Choice?
    @State private var showRestartAlert = false

    // v1.8.0: observe Sparkle-backed UpdateService for canCheck / lastChecked
    // reactive UI binding.
    @ObservedObject private var updates = UpdateService.shared

    private let reminderOptions = [1, 2, 3, 5, 7]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Currency
                section("Currency") {
                    HStack {
                        Text("Primary currency")
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

                // Language (v1.6 — in-app override of macOS Preferred Languages)
                section("Language") {
                    HStack {
                        Text("App language")
                            .font(AppFont.regular(13))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: {
                                LanguageOverride.Choice(rawValue: settingsStore.settings.language) ?? .system
                            },
                            set: { newChoice in
                                let current = LanguageOverride.Choice(rawValue: settingsStore.settings.language) ?? .system
                                settingsStore.update { $0.language = newChoice.rawValue }
                                LanguageOverride.apply(newChoice)
                                if LanguageOverride.wouldRequireRestart(currentSetting: current, newSetting: newChoice) {
                                    pendingLanguageChoice = newChoice
                                    showRestartAlert = true
                                }
                            }
                        )) {
                            ForEach(LanguageOverride.Choice.allCases) { choice in
                                Text(choice.displayName).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.textSecondary)
                        .frame(width: 140)
                    }

                    Text("Suber follows your macOS language by default. Override here to force English or 简体中文.")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                divider

                // Autopilot (v1.6 — Watch / Sense / Act)
                section("Autopilot") {
                    AutopilotSettingsSection()
                }

                divider

                // Notifications
                section("Notifications") {
                    ToggleRow(label: "Enable notifications", isOn: Binding(
                        get: { settingsStore.settings.enableNotifications },
                        set: { val in settingsStore.update { $0.enableNotifications = val } }
                    ))

                    if settingsStore.settings.enableNotifications {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remind before")
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

                // General
                section("General") {
                    ToggleRow(label: "Launch at login", isOn: Binding(
                        get: { settingsStore.settings.launchAtLogin },
                        set: { _ in settingsStore.toggleLaunchAtLogin() }
                    ))

                    ToggleRow(label: "iCloud sync", isOn: Binding(
                        get: { settingsStore.settings.enableCloudSync },
                        set: { val in settingsStore.update { $0.enableCloudSync = val } }
                    ))
                }

                divider

                // Data
                section("Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            actionButton("Export JSON", icon: "square.and.arrow.up") {
                                exportData()
                            }
                            actionButton("Import JSON", icon: "square.and.arrow.down") {
                                importData()
                            }
                        }

                        if let onImport = onImport {
                            actionButton("Import from bank statement…", icon: "doc.badge.arrow.up") {
                                onImport()
                            }
                        }

                        Button(action: { showClearConfirm = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Clear all data")
                                    .font(AppFont.medium(11))
                            }
                            .foregroundColor(Theme.danger)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }

                divider

                // Update (v1.8.0: Sparkle 2 — see UpdateService.swift)
                section("Update") {
                    updateSectionContent
                }

                divider

                // About + Quit (merged footer)
                VStack(alignment: .leading, spacing: 10) {
                    Text("About")
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)

                    HStack {
                        Text("Suber \(UpdateService.currentVersion)")
                            .font(AppFont.regular(12))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://github.com/createpjf/suber-macos") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                githubLogo
                                Text("Website")
                                    .font(AppFont.regular(12))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Text("Quit Suber")
                            .font(AppFont.medium(12))
                            .foregroundColor(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .padding(.bottom, 16)
        }
        .overlay {
            if showClearConfirm {
                // Full-screen dimmed backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { showClearConfirm = false }

                // Confirmation dialog
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(Theme.danger)

                    Text("Clear All Data?")
                        .font(AppFont.bold(16))
                        .foregroundColor(Theme.textPrimary)

                    Text("This will permanently delete all subscriptions and reset settings.")
                        .font(AppFont.regular(12))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    HStack(spacing: 12) {
                        Button(action: { showClearConfirm = false }) {
                            Text("Cancel")
                                .font(AppFont.medium(13))
                                .foregroundColor(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            subscriptionStore.clearAll()
                            settingsStore.reset()
                            showClearConfirm = false
                        }) {
                            Text("Clear")
                                .font(AppFont.medium(13))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.danger)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(width: 300)
                .background(Theme.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20)
            }
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        // v1.6 language switch — restart prompt.
        .alert("Restart Suber to switch language?",
               isPresented: $showRestartAlert) {
            Button("Restart now") {
                LanguageOverride.relaunch()
            }
            Button("Later", role: .cancel) {
                pendingLanguageChoice = nil
            }
        } message: {
            Text("Already-rendered text won't change until Suber restarts. The new language takes effect across the whole app on the next launch.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)

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

    // MARK: - Update Section (v1.8.0 Sparkle-backed)

    /// Minimal Settings UI on top of UpdateService (Sparkle 2 wrapper).
    /// Sparkle drives its own update-prompt dialog (release notes, install
    /// confirm, progress, restart) — we just expose the trigger + auto-check
    /// preference + last-checked timestamp.
    @ViewBuilder
    private var updateSectionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Suber \(UpdateService.currentVersion)")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button(action: { updates.checkForUpdates() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Check for updates")
                            .font(AppFont.medium(12))
                    }
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!updates.canCheckForUpdates)
                .opacity(updates.canCheckForUpdates ? 1 : 0.5)
            }

            Toggle(isOn: Binding(
                get: { updates.automaticallyChecks },
                set: { updates.automaticallyChecks = $0 }
            )) {
                Text("Automatically check for updates")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textPrimary)
            }
            .toggleStyle(.checkbox)

            if let last = updates.lastCheckedAt {
                Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textDim)
            }
        }
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

        if Self.runFilePanelFromPopover(panel) == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if Self.runFilePanelFromPopover(panel) == .OK, let url = panel.url {
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

    /// Runs a save/open panel while temporarily dropping the MenuBarExtra
    /// popover's window level so TCC dialogs and the file picker itself can
    /// stack above it.
    private static func runFilePanelFromPopover(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        let popoverWindow = NSApp.keyWindow
        let originalLevel = popoverWindow?.level
        popoverWindow?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        if let originalLevel = originalLevel {
            popoverWindow?.level = originalLevel
        }
        return response
    }

    private var githubLogo: some View {
        Image("github-mark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 14, height: 14)
            .opacity(0.6)
    }
}
