import Foundation

// ┌───────────── IMAPProvider — preset list (Gmail / Outlook / etc.) ──────────┐
// │                                                                            │
// │  Preset host/port + UI hints for the major IMAP providers users add        │
// │  through Settings → Autopilot → "Add IMAP account…".                       │
// │                                                                            │
// │  Why a preset list and not free-form host/port:                            │
// │  - Most users don't know imap.gmail.com:993 by heart                       │
// │  - Each provider has slightly different requirements (Gmail wants App      │
// │    Password not regular password; Outlook needs OAuth-not-SMTP-auth        │
// │    for normal accounts but App Passwords work; Yahoo requires App          │
// │    Password too)                                                           │
// │  - Presets carry the per-provider help text so the UI can guide users      │
// │    to the right setup page                                                 │
// │                                                                            │
// │  Generic stays as the escape hatch for self-hosted / FastMail / Migadu /   │
// │  any IMAP server we don't preset.                                          │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum IMAPProvider: String, Codable, CaseIterable, Identifiable {
    case gmail
    case icloud
    case outlook
    case yahoo
    case fastmail
    case generic

    var id: String { rawValue }

    /// Display name shown in the provider picker.
    var displayName: String {
        switch self {
        case .gmail:    return "Gmail"
        case .icloud:   return "iCloud"
        case .outlook:  return "Outlook"
        case .yahoo:    return "Yahoo"
        case .fastmail: return "Fastmail"
        case .generic:  return "Other (IMAP)"
        }
    }

    /// Default IMAP host. Generic returns nil (user must enter).
    var defaultHost: String? {
        switch self {
        case .gmail:    return "imap.gmail.com"
        case .icloud:   return "imap.mail.me.com"
        case .outlook:  return "outlook.office365.com"
        case .yahoo:    return "imap.mail.yahoo.com"
        case .fastmail: return "imap.fastmail.com"
        case .generic:  return nil
        }
    }

    /// IMAP-over-TLS port. 993 is the universal answer; we keep it
    /// configurable per-provider in case someone runs a non-standard port.
    var defaultPort: UInt16 { 993 }

    /// Mailbox to SELECT for the scan. Gmail's INBOX excludes auto-labeled
    /// receipts (Promotions, Updates tabs); "[Gmail]/All Mail" sees
    /// everything. Other providers use INBOX directly.
    var scanMailbox: String {
        switch self {
        case .gmail: return "[Gmail]/All Mail"
        default:     return "INBOX"
        }
    }

    /// Multi-step guidance shown under the password field. Each provider's
    /// path is non-trivial enough that one-line hints (v1.6/v1.7) caused
    /// users to skip critical steps (v1.8.1: Gmail's "enable IMAP first" was
    /// the most-skipped → most "Gmail doesn't work" reports). All hints
    /// follow the Outlook pattern from v1.7.1: numbered list + final line
    /// explicitly telling the user "NOT your account password".
    var setupHint: String {
        switch self {
        case .gmail:
            // v1.8.1: 4 steps. The IMAP-enable step (1) is the one users
            // skip most — Gmail defaults IMAP to OFF. Without it, even a
            // valid App Password fails LOGIN with cryptic responses.
            return """
                Gmail (@gmail.com / Google Workspace) requires:
                1. Enable IMAP at mail.google.com → Settings ⚙ → See all settings → Forwarding and POP/IMAP → IMAP access: Enable
                2. Enable 2-Step Verification at myaccount.google.com → Security
                3. Create App Password at myaccount.google.com/apppasswords (select 'Mail')
                4. Paste the 16-char App Password here, NOT your Gmail login password

                Google Workspace: your admin may have disabled IMAP org-wide. Ask them to enable it in Admin Console.
                """
        case .icloud:
            return """
                iCloud (@icloud.com / @me.com / @mac.com) requires:
                1. Enable 2-Factor Authentication at appleid.apple.com → Sign-In and Security
                2. Generate App-Specific Password under Sign-In and Security → App-Specific Passwords
                3. Use the app-specific password here, NOT your Apple ID password
                """
        case .outlook:
            // v1.8.0: 细化提示。Microsoft 个人账号（@outlook.com / @hotmail.com /
            // @live.com）2024-2025 起逐步禁用 Basic Auth，必须走 App Password
            // 而且要求账号开启两步验证。当用户填错 App Password 时，IMAP
            // 服务器返回的是 `[AUTHENTICATIONFAILED] basic auth disabled`
            // 这种具体消息 — IMAPAccountSheet.runTest() 会原样展示给用户。
            return """
                Outlook personal accounts (@outlook.com / @hotmail.com / @live.com):
                1. Enable 2-Step Verification at account.live.com → Security
                2. Create App Password under Security → Advanced security options
                3. Use the 16-char App Password here, NOT your account password

                Some legacy accounts have IMAP disabled by default — enable in Outlook.com Settings.
                """
        case .yahoo:
            return """
                Yahoo:
                1. Sign in at login.yahoo.com → Account Security
                2. Generate App Password (Mail) — distinct from your account password
                3. Use the generated App Password here, NOT your Yahoo login password

                Yahoo aggressively expires App Passwords — regenerate if auth fails after a long gap.
                """
        case .fastmail:
            return """
                Fastmail:
                1. Settings → Privacy & Security → App passwords → New app password
                2. Give it 'Mail (IMAP)' access
                3. Use the generated app password here, NOT your account password
                """
        case .generic:
            return "Use your IMAP server's host (e.g. mail.example.com) and an app password if your provider supports them."
        }
    }
}

// ┌───────────── QuickLink — v1.8.2 一键跳转设置页 ───────────────────────────┐
// │                                                                            │
// │  v1.8.1 的 setupHint 文字里埋了 URL（mail.google.com /                    │
// │  myaccount.google.com/apppasswords 等），但是纯文本，用户必须手动复制     │
// │  到浏览器，UX 不好。v1.8.2 在 setupHint 下加一排可点击按钮，每个按钮    │
// │  对应一个最关键的设置页，点 → NSWorkspace.shared.open(url) → 浏览器       │
// │  直接打开，用户在那边完成操作（启用 IMAP / 创建 App Password）后切回      │
// │  Suber 粘贴。                                                              │
// │                                                                            │
// │  Empty for `.generic` — 用户自填 host，没有 canonical 设置页。           │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct QuickLink: Identifiable {
    let id = UUID()
    let label: String           // 短按钮文字 (e.g. "Enable IMAP")
    let url: URL                // 直链
    let symbol: String          // SF Symbol 名 (e.g. "envelope.badge")
}

extension IMAPProvider {
    /// Per-provider deep links to the most-needed setup pages. Renders as
    /// a row of small bordered buttons under setupHint. Each click opens
    /// the URL in the user's default browser via NSWorkspace.shared.open.
    var setupQuickLinks: [QuickLink] {
        switch self {
        case .gmail:
            return [
                QuickLink(
                    label: "Enable IMAP",
                    url: URL(string: "https://mail.google.com/mail/u/0/#settings/fwdandpop")!,
                    symbol: "envelope.badge"
                ),
                QuickLink(
                    label: "Create App Password",
                    url: URL(string: "https://myaccount.google.com/apppasswords")!,
                    symbol: "key.fill"
                ),
            ]
        case .icloud:
            return [
                QuickLink(
                    label: "Apple ID Sign-In and Security",
                    url: URL(string: "https://appleid.apple.com/account/manage")!,
                    symbol: "key.fill"
                ),
            ]
        case .outlook:
            return [
                QuickLink(
                    label: "Microsoft Account Security",
                    url: URL(string: "https://account.microsoft.com/security")!,
                    symbol: "key.fill"
                ),
            ]
        case .yahoo:
            return [
                QuickLink(
                    label: "Yahoo Account Security",
                    url: URL(string: "https://login.yahoo.com/account/security")!,
                    symbol: "key.fill"
                ),
            ]
        case .fastmail:
            return [
                QuickLink(
                    label: "Fastmail App Passwords",
                    url: URL(string: "https://app.fastmail.com/settings/security/integrations")!,
                    symbol: "key.fill"
                ),
            ]
        case .generic:
            return []   // 用户自填 host，没有 canonical 页
        }
    }
}
