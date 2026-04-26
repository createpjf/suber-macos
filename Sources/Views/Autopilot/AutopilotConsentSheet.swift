import SwiftUI

// ┌───────────── AutopilotConsentSheet — D9 trust scaffold ────────────────────┐
// │                                                                            │
// │  The highest-stakes piece of copy in v1.6 (per outside-voice subagent +    │
// │  design review). Fires AFTER the user flips Watch Apple Mail ON in         │
// │  Settings but BEFORE the macOS TCC system prompt. Primes them so the       │
// │  system prompt doesn't read as "some app wants to control your email."     │
// │                                                                            │
// │  Design-review D9 copy (picked option B — scannable trust scaffold):       │
// │    - Title: "Let Suber watch Apple Mail for billing receipts"              │
// │    - Subtitle: "So you never miss a price rise, a new sub, or a            │
// │      duplicate charge."                                                     │
// │    - 3 trust bullets with SF Symbols:                                      │
// │        ✓ Only reads receipts — renewals, invoices, trial endings.          │
// │          Suber ignores everything else.                                     │
// │        ✓ Stays on this Mac — amounts and dates are saved. Nothing          │
// │          leaves your machine.                                               │
// │        ✓ Turn off any time — Settings → Autopilot. Or revoke in            │
// │          System Settings → Privacy → Automation.                            │
// │    - Footnote: "Next, macOS will ask you to allow Suber to control Mail.   │
// │      Click OK in that dialog to continue."                                  │
// │    - Attribution: "Made by Jinfeng Peng · github.com/createpjf/suber-macos"│
// │    - Buttons: [Cancel] / [Connect Apple Mail] (default, return key)         │
// │                                                                            │
// │  Vertical 3-bullet STACK, not 3-column grid (Pass 4 anti-AI-slop rule).    │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct AutopilotConsentSheet: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    // Developer attribution. Hard-coded; design review D9 explicitly specified
    // this copy. v1.7 i18n pass will extract to Localizable.xcstrings.
    private let developerName = "Jinfeng Peng"
    private let repoURL = URL(string: "https://github.com/createpjf/suber-macos")!

    var body: some View {
        VStack(spacing: 20) {

            // Icon + title block
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 8)

                Text("Let Suber watch Apple Mail for billing receipts")
                    .font(AppFont.bold(17))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("So you never miss a price rise, a new sub, or a duplicate charge.")
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            // Trust bullets (vertical stack — Pass 4 rule: no 3-column grid)
            VStack(alignment: .leading, spacing: 14) {
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Only reads receipts",
                    detail: "Renewals, invoices, trial endings. Suber ignores everything else."
                )
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Stays on this Mac",
                    detail: "Amounts and dates are saved. Nothing leaves your machine."
                )
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Turn off any time",
                    detail: "Settings → Autopilot. Or revoke in System Settings → Privacy → Automation."
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.bgCell)
            )
            .padding(.horizontal, 20)

            // TCC-prompt priming footnote
            Text("Next, macOS will ask you to allow Suber to control Mail. Click OK in that dialog to continue.")
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            // Developer attribution (clickable link to the repo)
            Link(destination: repoURL) {
                Text("Made by \(developerName) · github.com/createpjf/suber-macos")
                    .font(AppFont.regular(10))
                    .foregroundColor(Theme.textDim)
            }
            .buttonStyle(.plain)

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Connect Apple Mail", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        // v1.8.1: 写死 width: 540 超过了 popover 480pt → "Connect Apple Mail"
        // 主按钮被裁。改 maxWidth: .infinity 让 OverlayPresenter 控制
        // 实际宽度（popover 480 自适应）。
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.bgPrimary)
    }
}

// MARK: - TrustBullet row

private struct TrustBullet: View {
    let symbol: String
    let title: String
    let detail: String   // can't name this `body` — collides with View.body

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.green)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
#Preview {
    AutopilotConsentSheet(onConfirm: {}, onCancel: {})
}
#endif
