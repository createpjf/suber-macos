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
        // v1.8.1: 改 .frame(maxWidth: .infinity) 跟 AutopilotConsentSheet 一致。
        // 旧的 480pt 等于 popover 宽度但零边距，OverlayPresenter 包裹层有任何
        // padding 都会让按钮被裁。Inner padding 都是相对值，自适应。
        .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.setupHint)
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // v1.8.2: 一键跳转按钮，省去用户复制 URL 到浏览器的步骤
            if !provider.setupQuickLinks.isEmpty {
                quickLinksRow
            }
        }
    }

    /// v1.8.2: row of small bordered buttons that open each setupQuickLink
    /// in the user's default browser via NSWorkspace.shared.open.
    /// HStack works because providers currently have ≤ 2 links each;
    /// future > 3 links would need FlowLayout / LazyVGrid wrapping.
    @ViewBuilder
    private var quickLinksRow: some View {
        HStack(spacing: 8) {
            ForEach(provider.setupQuickLinks) { link in
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: link.symbol)
                            .font(.system(size: 10))
                        Text(link.label)
                            .font(AppFont.medium(11))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.bgCell)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var testRow: some View {
        // v1.8.1: split the row into Test button + (success-or-empty) on top,
        // and a full-width failure block underneath. Failure used to share
        // horizontal space with the button + .lineLimit(2) + .truncationMode
        // — Gmail's response includes a URL that got cut off, killing the
        // user's ability to self-diagnose. Now: full-width, multi-line,
        // selectable, with a Copy diagnostic button.
        VStack(alignment: .leading, spacing: 8) {
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

                if case .success(let count) = testResult {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Connected · \(count) account\(count == 1 ? "" : "s")")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()
            }

            if case .failure(let message) = testResult {
                failureBlock(message)
            }
        }
    }

    /// v1.8.1: full-width selectable error block with Copy diagnostic.
    /// Replaces the truncated single-line yellow-triangle row.
    @ViewBuilder
    private func failureBlock(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text(message)
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                    Text("Copy diagnostic")
                        .font(AppFont.regular(10))
                }
                .foregroundColor(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgCell))
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

        // v1.8.1 defensive normalization. Two common Gmail copy-paste bugs:
        //   1. Trailing whitespace from triple-click selection on the App
        //      Password page → IMAP LOGIN silently fails (Gmail doesn't tell
        //      you why because the wrong password is "auth failed" too).
        //   2. The "abcd efgh ijkl mnop" 4-4-4-4 display format on Google's
        //      page is human-readable; both stripped and spaced forms are
        //      accepted by Gmail's IMAP server, but stripping is what the
        //      Sparkle/Mail/Thunderbird ecosystem does — safer default.
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = Self.normalizeAppPassword(password)

        let account = IMAPAccount(provider: provider, email: cleanEmail, host: cleanHost, port: port)
        let bridge = GenericIMAPBridge(account: account, passwordResolver: { cleanPassword })

        do {
            let count = try await bridge.ping(timeout: 30)
            testResult = .success(accountCount: count)
            // Reflect the normalized values back in the form so handleSave
            // persists the cleaned versions and the user can see what worked.
            email = cleanEmail
            host = cleanHost
            password = cleanPassword
        } catch MailBridgeError.permissionDenied(let detail) {
            // v1.8.0: surface server's actual response so users can self-
            // diagnose. Outlook personal accounts especially benefit —
            // `[AUTHENTICATIONFAILED] basic auth disabled` is way more
            // actionable than generic "check email and app password".
            // v1.8.1: prepend a plain-English friendly hint when we recognize
            // the server's reason (5 patterns covered, see friendlyHintFor).
            let baseMsg = "Authentication failed."
            if let detail = detail, !detail.isEmpty {
                if let friendly = Self.friendlyHintFor(serverDetail: detail, provider: provider) {
                    testResult = .failure(message: "\(baseMsg) \(friendly)\n\nServer said: \(detail)")
                } else {
                    testResult = .failure(message: "\(baseMsg) Server said: \(detail)")
                }
            } else {
                testResult = .failure(message: "\(baseMsg) Check the email and app password.")
            }
        } catch MailBridgeError.timeout {
            testResult = .failure(message: "Connection timed out. Check the host and port (or local proxy/VPN settings — Clash/Stash etc. often intercept imap.* domains).")
        } catch {
            testResult = .failure(message: error.localizedDescription)
        }
        testing = false
    }

    private func handleSave() {
        guard let port = UInt16(portString) else { return }
        // v1.8.1: persist the normalized form (matches what runTest verified).
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = Self.normalizeAppPassword(password)
        let account = IMAPAccount(provider: provider, email: cleanEmail, host: cleanHost, port: port)
        onSave(account, cleanPassword)
    }

    // MARK: - v1.8.1 normalization + smart-hint helpers
    //
    // Static so they're trivially testable and don't capture form state.

    /// Trim outer whitespace; if the input matches Google's
    /// "abcd efgh ijkl mnop" 4-4-4-4 App Password display format, strip the
    /// inner spaces. Falls through unchanged for any other shape (Outlook /
    /// iCloud / Yahoo App Passwords vary in format; never modify those).
    static func normalizeAppPassword(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ $0.count == 4 }) {
            return parts.joined()
        }
        return trimmed
    }

    /// Recognize common server-rejection patterns and return a one-line
    /// human-readable explanation. Returns nil for unknown responses (UI
    /// then shows just the raw server text).
    static func friendlyHintFor(serverDetail: String, provider: IMAPProvider) -> String? {
        let lower = serverDetail.lowercased()

        // Gmail when user typed account password instead of App Password.
        if lower.contains("application-specific password required")
            || lower.contains("app password")
            || lower.contains("app-specific password") {
            return "You probably typed your account password — \(provider.displayName) needs an App Password (see numbered steps below the password field)."
        }

        // Outlook personal accounts after Microsoft disabled basic auth (2024+).
        if lower.contains("basic auth disabled")
            || lower.contains("basic authentication is disabled") {
            return "Microsoft has disabled basic authentication for this account — you must use an App Password (Outlook → Security → Advanced → App Passwords)."
        }

        // Gmail / Workspace where IMAP itself isn't enabled.
        if lower.contains("imap access is disabled") || lower.contains("imap is disabled") {
            return "IMAP is disabled on this account. For Gmail: enable at mail.google.com → Settings → Forwarding and POP/IMAP. For Workspace: ask your admin to enable it in Admin Console."
        }

        // Gmail security lockout — account flagged, needs interactive web login.
        if lower.contains("webloginrequired")
            || lower.contains("please log in via your web browser") {
            return "Gmail thinks this account needs a security check. Open mail.google.com in a browser, sign in, then try here again."
        }

        // Server advertises LOGINDISABLED capability.
        if lower.contains("logindisabled") {
            return "IMAP login is disabled for this account — enable in your provider's web settings, or check with your admin."
        }

        return nil
    }
}

#if DEBUG
#Preview {
    IMAPAccountSheet(existing: nil, onSave: { _, _ in }, onCancel: {})
}
#endif
