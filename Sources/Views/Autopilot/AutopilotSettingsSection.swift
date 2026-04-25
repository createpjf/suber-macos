import SwiftUI

// ┌───────────── AutopilotSettingsSection — Settings → Autopilot ──────────────┐
// │                                                                            │
// │  Design review D6 (I3): two visual groups.                                 │
// │                                                                            │
// │    Apple Mail  (connection group)                                          │
// │      - Watch Apple Mail    [toggle]                                        │
// │        Helper: "Reads billing receipts (renewals, invoices, trials)        │
// │                 once a day. Nothing is stored except amounts and dates."   │
// │      - Scan now            [button]          disabled if OFF or scanning   │
// │      - Last scan: X ago · found N changes    (or permission / error state) │
// │                                                                            │
// │    Alert me about  (behavior group)                                        │
// │      - Price changes        [toggle, default ON]                           │
// │      - New subscriptions    [toggle, default ON]                           │
// │      - Duplicate charges    [toggle, default OFF — noisy]                  │
// │                                                                            │
// │  Consent sheet fires on Watch toggle ON → user confirms → MailWatchdog.   │
// │  connectAppleMail() triggers the macOS TCC prompt.                         │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct AutopilotSettingsSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var watchdog: MailWatchdog

    @State private var showConsentSheet = false
    /// v1.7 IMAP: state for the add/edit account modal.
    @State private var showIMAPSheet = false
    @State private var imapAccountBeingEdited: IMAPAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: Group 1 — Apple Mail (connection)

            groupHeader("Apple Mail")

            VStack(alignment: .leading, spacing: 10) {
                // Watch toggle — intercepts the false→true transition to show
                // the consent sheet before firing connectAppleMail().
                ToggleRow(
                    label: "Watch Apple Mail",
                    isOn: Binding(
                        get: { settingsStore.settings.autopilot.watchAppleMail },
                        set: handleWatchToggle
                    )
                )

                Text("Reads billing receipts (renewals, invoices, trials) once a day. Nothing is stored except amounts and dates.")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Scan now + Last scan line
                HStack(spacing: 12) {
                    Button("Scan now") {
                        Task { try? await watchdog.scanNow() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!scanNowEnabled)

                    Text(lastScanText)
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()
                }

                // Permission-denied / error banners inline within the group.
                stateBanner
            }

            Divider().background(Theme.border)

            // MARK: Group 2 — Other email accounts (IMAP, v1.7)

            groupHeader("Other email accounts")

            VStack(alignment: .leading, spacing: 10) {
                if let account = settingsStore.settings.autopilot.imapAccount {
                    imapAccountRow(account)
                } else {
                    addIMAPAccountButton
                }

                Text("Connect Gmail, Outlook, Yahoo, Fastmail, or any IMAP server directly. Useful when the account isn't in macOS Mail.app, or you don't run Mail.app at all. App password lives in your local Keychain.")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().background(Theme.border)

            // MARK: Group 3 — Alert me about (behavior)

            groupHeader("Alert me about")

            VStack(alignment: .leading, spacing: 10) {
                ToggleRow(
                    label: "Price changes",
                    isOn: settingsBinding(\.autopilot.alertOnPriceChanges)
                )
                Text("e.g. Netflix raised from $15.99 to $22.99")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)

                ToggleRow(
                    label: "New subscriptions",
                    isOn: settingsBinding(\.autopilot.alertOnNewSubscriptions)
                )
                Text("When a receipt matches a service you don't already track")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)

                ToggleRow(
                    label: "Duplicate charges",
                    isOn: settingsBinding(\.autopilot.alertOnDuplicates)
                )
                Text("When the same service charges twice in one day. Can be noisy — leave off unless you've seen duplicates.")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showConsentSheet) {
            AutopilotConsentSheet(
                onConfirm: {
                    showConsentSheet = false
                    // Persist the toggle flip, then trigger TCC prompt.
                    settingsStore.update { $0.autopilot.watchAppleMail = true }
                    Task {
                        await watchdog.connectAppleMail()
                        // If permission denied, unwind the toggle so the UI
                        // honestly reflects state.
                        if watchdog.state == .permissionDenied {
                            settingsStore.update { $0.autopilot.watchAppleMail = false }
                        } else {
                            watchdog.scheduleDailyScan()
                        }
                    }
                },
                onCancel: {
                    showConsentSheet = false
                    // User backed out — leave toggle OFF.
                }
            )
        }
        // v1.7 IMAP: add/edit account modal.
        .sheet(isPresented: $showIMAPSheet) {
            IMAPAccountSheet(
                existing: imapAccountBeingEdited,
                onSave: { account, password in
                    // Save credential to Keychain FIRST so the bridge has it
                    // before settings.imapAccount triggers the rebuild.
                    IMAPCredentialStore.save(password: password, for: account.email)
                    settingsStore.update { $0.autopilot.imapAccount = account }
                    showIMAPSheet = false
                    imapAccountBeingEdited = nil
                },
                onCancel: {
                    showIMAPSheet = false
                    imapAccountBeingEdited = nil
                }
            )
        }
    }

    // MARK: - IMAP UI helpers (v1.7)

    @ViewBuilder
    private var addIMAPAccountButton: some View {
        Button {
            imapAccountBeingEdited = nil
            showIMAPSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add IMAP account…")
            }
            .font(AppFont.regular(12))
            .foregroundColor(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func imapAccountRow(_ account: IMAPAccount) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.arrow.triangle.branch")
                .font(.system(size: 16))
                .foregroundColor(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(AppFont.medium(12))
                    .foregroundColor(Theme.textPrimary)
                Text("\(account.host):\(String(account.port))")
                    .font(AppFont.regular(10))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            Button("Edit") {
                imapAccountBeingEdited = account
                showIMAPSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                IMAPCredentialStore.delete(email: account.email)
                settingsStore.update { $0.autopilot.imapAccount = nil }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove account and delete password from Keychain")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.bgCell)
        )
    }

    // MARK: - Toggle handler

    /// Intercepts the Watch toggle. OFF→ON shows the consent sheet first.
    /// ON→OFF disables the scheduler and flips immediately.
    private func handleWatchToggle(_ newValue: Bool) {
        if newValue {
            showConsentSheet = true   // don't flip yet; confirm path will
        } else {
            settingsStore.update { $0.autopilot.watchAppleMail = false }
            watchdog.cancelDailyScan()
        }
    }

    // MARK: - State-driven banners

    @ViewBuilder
    private var stateBanner: some View {
        switch watchdog.state {
        case .permissionDenied:
            permissionDeniedBanner
        case .error(let message):
            errorBanner(message)
        default:
            EmptyView()
        }
    }

    private var permissionDeniedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("Suber can't access Mail.")
                    .font(AppFont.medium(12))
                    .foregroundColor(Theme.textPrimary)
                Text("Open System Settings → Privacy & Security → Automation and allow Suber to control Mail.")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings →") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.yellow.opacity(0.12))
        )
        .overlay(
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3),
            alignment: .leading
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(Theme.textSecondary)
            Text(message)
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.bgSecondary)
        )
    }

    // MARK: - Derived copy

    private var scanNowEnabled: Bool {
        guard settingsStore.settings.autopilot.watchAppleMail else { return false }
        if case .scanning = watchdog.state { return false }
        if case .requestingPermission = watchdog.state { return false }
        return true
    }

    private var lastScanText: String {
        switch watchdog.state {
        case .scanning(_, let seen):
            return seen > 0 ? "Scanning… \(seen) messages" : "Scanning…"
        case .requestingPermission:
            // First-run TCC prompt is up. Make it crystal clear what to do —
            // the previous "Waiting for permission…" copy left users staring
            // at a blank label while the macOS dialog blocked osascript.
            return "Look for the macOS permission dialog and click OK."
        case .error(let message):
            // Surface the error directly. Errors include the actionable next
            // step (e.g. "Connection timed out. Make sure Mail.app is open").
            return message
        default:
            break
        }
        guard let last = watchdog.lastCompletedAt else {
            return settingsStore.settings.autopilot.watchAppleMail
                ? "Never scanned yet"
                : "Off"
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        let ago = rel.localizedString(for: last, relativeTo: Date())
        let count = watchdog.lastScanChangesCount
        let countPart = count > 0 ? " · found \(count) change\(count == 1 ? "" : "s")" : ""
        return "Last scan: \(ago)\(countPart)"
    }

    // MARK: - Binding helpers

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in settingsStore.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.medium(11))
            .foregroundColor(Theme.textSecondary)
            .textCase(.uppercase)
    }
}
