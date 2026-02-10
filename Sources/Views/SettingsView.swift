import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var showClearConfirm = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var updateState: UpdateCheckState = .idle

    enum UpdateCheckState {
        case idle
        case checking
        case available(UpdateService.Release)
        case upToDate
        case downloading
        case error(String)
    }

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

                // Update
                section("UPDATE") {
                    updateSectionContent
                }
                .onAppear {
                    if case .idle = updateState {
                        checkForUpdate()
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
                        Text("v\(UpdateService.currentVersion)")
                            .font(AppFont.regular(12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Button(action: {
                        if let url = URL(string: "https://github.com/createpjf/suber-macos") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            githubLogo
                            Text("Website")
                                .font(AppFont.regular(13))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
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

    // MARK: - Update Section

    @ViewBuilder
    private var updateSectionContent: some View {
        switch updateState {
        case .idle:
            actionButton("Check for Updates", icon: "arrow.clockwise") {
                checkForUpdate()
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking...")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
            }
        case .available(let release):
            VStack(spacing: 8) {
                HStack {
                    Text("v\(release.version) available")
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("Current: v\(UpdateService.currentVersion)")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textDim)
                }
                actionButton("Download Update", icon: "arrow.down.circle") {
                    downloadUpdate(release)
                }
            }
        case .upToDate:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.success)
                Text("You're up to date (v\(UpdateService.currentVersion))")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button(action: { checkForUpdate() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Downloading...")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
            }
        case .error(let msg):
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.warning)
                    Text(msg)
                        .font(AppFont.regular(12))
                        .foregroundColor(Theme.textSecondary)
                }
                actionButton("Retry", icon: "arrow.clockwise") {
                    checkForUpdate()
                }
            }
        }
    }

    private func checkForUpdate() {
        updateState = .checking
        Task {
            do {
                if let release = try await UpdateService.checkForUpdate() {
                    await MainActor.run { updateState = .available(release) }
                } else {
                    await MainActor.run { updateState = .upToDate }
                }
            } catch {
                await MainActor.run { updateState = .error("Check failed") }
            }
        }
    }

    private func downloadUpdate(_ release: UpdateService.Release) {
        guard let dmgURL = release.dmgURL else {
            updateState = .error("No DMG available")
            return
        }
        updateState = .downloading
        Task {
            do {
                _ = try await UpdateService.downloadAndOpen(dmgURL, version: release.version)
                await MainActor.run { updateState = .upToDate }
            } catch {
                await MainActor.run { updateState = .error("Download failed") }
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

    private var githubLogo: some View {
        Image("github-mark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 14, height: 14)
            .opacity(0.6)
    }
}
