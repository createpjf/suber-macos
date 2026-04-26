import SwiftUI

// ┌───────────── IMAPAccountSheet — add / edit IMAP account ───────────────────┐
// │                                                                            │
// │  Modal sheet shown when user taps "Add IMAP account…" in Settings →        │
// │  Autopilot. Single-account UI (v1.7); the data model already supports     │
// │  multi-account but UI complexity is deferred.                              │
// │                                                                            │
// │  Fields:                                                                   │
// │    Provider picker (Gmail / iCloud / Outlook / Yahoo / Fastmail / Other)   │
// │    Email address                                                           │
// │    App Password (Keychain-stored, never shown back)                        │
// │    Host (auto-filled from provider; editable for Generic)                  │
// │    Port (auto-filled to 993; editable for Generic)                         │
// │                                                                            │
// │  Test connection button: runs `GenericIMAPBridge.ping(timeout: 30)`        │
// │  before the user commits. Surfaces the actual error if it fails (wrong    │
// │  password, host unreachable, etc.) so users can fix it now rather than    │
// │  discover at first scan time.                                              │
// │                                                                            │
// │  Save: writes account to AppSettings.autopilot.imapAccount + password to   │
// │  Keychain. SuberApp's onReceive picks up the settings change and rebuilds │
// │  the composite bridge so next scan includes IMAP.                          │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct IMAPAccountSheet: View {
    /// Pre-filled when editing an existing account; nil when adding new.
    let existing: IMAPAccount?
    let onSave: (IMAPAccount, String) -> Void   // (account, password)
    let onCancel: () -> Void

    // Form state
    @State private var provider: IMAPProvider
    @State private var email: String
    @State private var password: String = ""
    @State private var host: String
    @State private var portString: String

    // Test connection state
    @State private var testing: Bool = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(accountCount: Int)
        case failure(message: String)
    }

    init(existing: IMAPAccount?,
         onSave: @escaping (IMAPAccount, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        let p = existing?.provider ?? .gmail
        _provider = State(initialValue: p)
        _email = State(initialValue: existing?.email ?? "")
        _host = State(initialValue: existing?.host ?? p.defaultHost ?? "")
        _portString = State(initialValue: String(existing?.port ?? p.defaultPort))
        // Password field intentionally starts empty — we never display the
        // existing password back. User re-enters when editing.
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 12) {
                providerRow
                emailRow
                passwordRow
                if provider == .generic {
                    hostRow
                    portRow
                }
                hint
                testRow
            }
            .padding(.horizontal, 24)

            Divider().padding(.horizontal, 16)

            footer
        }
        .padding(.vertical, 16)
        .frame(width: 480)
        .background(Theme.bgPrimary)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "envelope.arrow.triangle.branch")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(Theme.accent)
            Text(existing == nil ? "Add IMAP account" : "Edit IMAP account")
                .font(AppFont.bold(16))
                .foregroundColor(Theme.textPrimary)
            Text("Suber connects directly via IMAP — useful when you don't run macOS Mail.app, or have an account that's not in Mail.")
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
    }

    private var providerRow: some View {
        HStack {
            Text("Provider")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .leading)
            Picker("", selection: $provider) {
                ForEach(IMAPProvider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .onChange(of: provider) { _, newValue in
                // Auto-fill host/port from preset.
                if let h = newValue.defaultHost { host = h }
                portString = String(newValue.defaultPort)
                testResult = nil
            }
        }
    }

    private var emailRow: some View {
        HStack {
            Text("Email")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .leading)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
        }
    }

    private var passwordRow: some View {
        HStack {
            Text("App password")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .leading)
            SecureField("App password (not your account password)", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var hostRow: some View {
        HStack {
            Text("IMAP host")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .leading)
            TextField("imap.example.com", text: $host)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
        }
    }

    private var portRow: some View {
        HStack {
            Text("Port")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 100, alignment: .leading)
            TextField("993", text: $portString)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            Spacer()
        }
    }

    private var hint: some View {
        Text(provider.setupHint)
            .font(AppFont.regular(11))
            .foregroundColor(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var testRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 4) {
                    if testing {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(testing ? "Testing…" : "Test connection")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canTest)

            Spacer()

            switch testResult {
            case .success(let count):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Connected · \(count) account\(count == 1 ? "" : "s")")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                }
            case .failure(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text(message)
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            case .none:
                EmptyView()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Add account" : "Save", action: handleSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Validation

    private var canTest: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        !host.isEmpty &&
        UInt16(portString) != nil &&
        !testing
    }

    private var canSave: Bool {
        canTest && !testing
    }

    // MARK: - Actions

    private func runTest() async {
        guard let port = UInt16(portString) else { return }
        testing = true
        testResult = nil

        let account = IMAPAccount(provider: provider, email: email, host: host, port: port)
        let bridge = GenericIMAPBridge(account: account, passwordResolver: { password })

        do {
            let count = try await bridge.ping(timeout: 30)
            testResult = .success(accountCount: count)
        } catch MailBridgeError.permissionDenied(let detail) {
            // v1.8.0: surface server's actual response so users can self-
            // diagnose. Outlook personal accounts especially benefit —
            // `[AUTHENTICATIONFAILED] basic auth disabled` is way more
            // actionable than generic "check email and app password".
            let baseMsg = "Authentication failed."
            if let detail = detail, !detail.isEmpty {
                testResult = .failure(message: "\(baseMsg) Server said: \(detail)")
            } else {
                testResult = .failure(message: "\(baseMsg) Check the email and app password.")
            }
        } catch MailBridgeError.timeout {
            testResult = .failure(message: "Connection timed out. Check the host and port (or local proxy/VPN settings).")
        } catch {
            testResult = .failure(message: error.localizedDescription)
        }
        testing = false
    }

    private func handleSave() {
        guard let port = UInt16(portString) else { return }
        let account = IMAPAccount(provider: provider, email: email, host: host, port: port)
        onSave(account, password)
    }
}

#if DEBUG
#Preview {
    IMAPAccountSheet(existing: nil, onSave: { _, _ in }, onCancel: {})
}
#endif
