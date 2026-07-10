import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    /// v1.9.0: needed to present DataRestoreView via popover-root overlay.
    @EnvironmentObject var overlayPresenter: OverlayPresenter

    var onImport: (() -> Void)? = nil

    @State private var showClearConfirm = false
    @State private var importError: String?
    @State private var showImportError = false
    // v1.9.2: JSON import confirmation — import is a destructive whole-list
    // replace, so we stage the decoded result and require explicit confirm.
    // StorageService.importData(from:) returns this exact tuple shape.
    @State private var pendingImport: (subscriptions: [Subscription], settings: AppSettings)?
    @State private var showImportConfirm = false

    // v1.6: language override — restart prompt state.
    @State private var pendingLanguageChoice: LanguageOverride.Choice?
    @State private var showRestartAlert = false

    // v1.8.0: observe Sparkle-backed UpdateService for canCheck / lastChecked
    // reactive UI binding.
    @ObservedObject private var updates = UpdateService.shared

    // AUDIT-v1.9.2 U-12: observe sync events so the iCloud row can show the
    // last merge/conflict instead of a static string.
    @ObservedObject private var syncStatus = CloudSyncUIStatus.shared

    private let reminderOptions = [1, 2, 3, 5, 7]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // v1.9.0: iCloud sync promoted to top of Settings.
                // Rationale — see CHANGELOG [1.9.0] "Data Safety": iCloud
                // sync is the remote-redundancy layer in the 4-layer
                // protection scheme. Putting it at the top makes the
                // safety story discoverable instead of buried in General.
                section("iCloud Sync") {
                    iCloudSyncRow
                }

                divider

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

                    // AUDIT-v1.9.2 U-11: surface rate freshness — refresh fails
                    // silently and conversions may run on built-in approximate
                    // rates indefinitely with no hint.
                    if let updated = ExchangeRateService.shared.lastUpdatedAt {
                        Text("Rates updated \(updated.formatted(.relative(presentation: .named)))")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.textDim)
                    } else {
                        Text("Using built-in approximate rates — multi-currency totals may be off.")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
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
                // v1.9.0: iCloud sync was moved out to its own top-of-Settings
                // section — see body header. General now only holds Launch at
                // login.
                section("General") {
                    ToggleRow(label: "Launch at login", isOn: Binding(
                        get: { settingsStore.settings.launchAtLogin },
                        set: { _ in settingsStore.toggleLaunchAtLogin() }
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

                        // v1.9.0: explicit, user-driven Restore — replaces the
                        // dangerous automatic LegacyDataMigration disabled in
                        // v1.8.4. Safe to invoke any time; live data is
                        // backed up automatically before the restore writes.
                        actionButton("Restore from backup…", icon: "arrow.uturn.backward.circle") {
                            presentRestore()
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
                        // AUDIT-v1.9.2 U-13: Esc/Return parity with the
                        // NSAlert-backed confirms elsewhere in the app.
                        .keyboardShortcut(.cancelAction)

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
                        // AUDIT-v1.9.2 U-13 fix-up: no keyboard shortcut on the
                        // destructive button — Apple HIG says destructive
                        // actions must never be the Return-key default. Esc
                        // (bound on Cancel above) is the only shortcut here.
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
            // U-03: `importError ?? "Unknown error"` is a String expression —
            // the fallback literal must be localized explicitly.
            Text(importError ?? String(localized: "Unknown error"))
        }
        .alert("Replace all subscriptions?",
               isPresented: $showImportConfirm,
               presenting: pendingImport) { result in
            Button("Replace", role: .destructive) { applyPendingImport() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { result in
            // U-03: single literal (no `+` concatenation) — a concatenated
            // expression is a String and renders verbatim, skipping the catalog.
            Text("This will replace your current \(subscriptionStore.subscriptions.count) subscriptions with \(result.subscriptions.count) from the file. Your current data is backed up automatically first.")
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

    // AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — section titles are
    // literals at every call site; Text(String) skipped the catalog.
    @ViewBuilder
    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
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

    // AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — same reason as
    // section(_:) above.
    @ViewBuilder
    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Restore (v1.9.0)

    /// Push DataRestoreView through OverlayPresenter so the confirm dialog
    /// renders at popover root (480pt full width) and survives focus events.
    private func presentRestore() {
        overlayPresenter.present(
            DataRestoreView(onClose: { [overlayPresenter] in
                overlayPresenter.dismiss()
            })
            .environmentObject(subscriptionStore)
            .environmentObject(settingsStore)
            .environmentObject(overlayPresenter)
        )
    }

    // MARK: - iCloud Sync Row (v1.9.0)

    /// Promoted iCloud sync UI. Toggle + a one-line status that tells the
    /// user what the toggle is for in concrete terms — "subscriptions sync
    /// across all your Macs", not "enableCloudSync".
    @ViewBuilder
    private var iCloudSyncRow: some View {
        let isOn = settingsStore.settings.enableCloudSync
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(label: "iCloud sync", isOn: Binding(
                get: { settingsStore.settings.enableCloudSync },
                set: { val in settingsStore.update { $0.enableCloudSync = val } }
            ))

            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.system(size: 11))
                    .foregroundColor(isOn ? Theme.success : Theme.textDim)
                Text(isOn
                     ? "On — subscriptions sync to your iCloud account."
                     : "Off — subscriptions stay on this Mac only.")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // AUDIT-v1.9.2 U-12: last sync event (merge applied / conflict
            // rejected) with a relative timestamp — previously NSLog-only.
            if isOn, let event = syncStatus.lastEvent, let at = syncStatus.lastEventAt {
                Text("\(event) · \(at.formatted(.relative(presentation: .named)))")
                    .font(AppFont.regular(11))
                    .foregroundColor(syncStatus.lastEventIsWarning ? Theme.warning : Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            // AUDIT-v1.9.2 C-37: try? swallowed write errors (full disk,
            // revoked iCloud Drive permission, read-only volume) — the user
            // thought the backup succeeded when nothing was written. Reuse
            // the import-error alert pipeline to surface the failure.
            do {
                try data.write(to: url)
            } catch {
                // U-03: runtime-built String → String(localized:) so the
                // prefix localizes (the description is system-localized).
                importError = String(localized: "Export failed: \(error.localizedDescription)")
                showImportError = true
            }
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
                // v1.9.2: stage + confirm before the destructive replace.
                pendingImport = result
                showImportConfirm = true
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }

    /// Applies a previously-staged JSON import after the user confirms.
    private func applyPendingImport() {
        guard let result = pendingImport else { return }
        subscriptionStore.replaceAll(result.subscriptions, reason: .userImport)
        settingsStore.update { $0 = result.settings }
        pendingImport = nil
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
