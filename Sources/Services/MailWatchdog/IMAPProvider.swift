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

    /// One-line guidance shown under the password field. Each provider has
    /// a subtly different "how to get an App Password" path.
    var setupHint: String {
        switch self {
        case .gmail:
            return "Enable 2-Step Verification, then create an App Password at myaccount.google.com → Security → App passwords."
        case .icloud:
            return "Generate an app-specific password at appleid.apple.com → Sign-In and Security → App-Specific Passwords."
        case .outlook:
            return "Microsoft accounts: enable 2FA, then create an App Password at account.microsoft.com → Security → Advanced security options."
        case .yahoo:
            return "Generate an App Password at login.yahoo.com → Account Security → Generate app password."
        case .fastmail:
            return "Create an app password at fastmail.com → Settings → Privacy & Security → App passwords. Give it 'Mail (IMAP)' access."
        case .generic:
            return "Use your IMAP server's host (e.g. mail.example.com) and an app password if your provider supports them."
        }
    }
}
