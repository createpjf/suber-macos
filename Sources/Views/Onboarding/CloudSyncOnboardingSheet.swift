import SwiftUI

// ┌──────────── iCloudOnboardingSheet — v1.9.0 first-launch consent ───────────┐
// │                                                                            │
// │  Why this exists. v1.6 → v1.8 ran iCloud sync as default-OFF, hidden in   │
// │  Settings → General. Most users never flipped it on. When v1.8.0's        │
// │  LegacyDataMigration overwrote one user's 9 live subs, there was NO       │
// │  remote backup to restore from — only a local plist (which had been       │
// │  the source of the corruption to begin with).                             │
// │                                                                            │
// │  v1.9.0 fix: surface the choice on first launch with the recommendation   │
// │  to enable. We never force it on — that's a privacy / sovereignty rule —  │
// │  but we make the trade-off visible.                                        │
// │                                                                            │
// │  Presentation: rendered through `OverlayPresenter` (popover-root) NOT     │
// │  `.sheet(isPresented:)`. The v1.7.1 lesson — `.sheet` inside a            │
// │  MenuBarExtra popover dies on focus loss — applies double here because   │
// │  the user's first interaction is reading copy, not pressing buttons.     │
// │                                                                            │
// │  Lifecycle:                                                                │
// │    1. SuberApp.MenuBarContainerView.onAppear checks                       │
// │       `@AppStorage("iCloud.onboarded")`.                                   │
// │    2. If false AND `NSUbiquitousKeyValueStore.default` is reachable,      │
// │       present this sheet via OverlayPresenter.                            │
// │    3. User picks Enable / Skip — both write `iCloud.onboarded = true`     │
// │       so we never re-prompt.                                              │
// │    4. Choice flows into `settingsStore.update { $0.enableCloudSync = … }`.│
// │                                                                            │
// │  Localized since the v1.9.2 U-02 backfill — every literal below has a     │
// │  zh-Hans entry in Localizable.xcstrings (was en-only in v1.9.0).           │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct CloudSyncOnboardingSheet: View {
    /// Called when user picks "Enable iCloud Sync" — caller writes
    /// `enableCloudSync = true` and dismisses the overlay.
    let onEnable: () -> Void
    /// Called when user picks "Skip" — caller leaves `enableCloudSync` as-is
    /// (still false) and dismisses the overlay.
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {

            // Hero icon + title block
            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 16)

                Text("Sync your subscriptions across Macs")
                    .font(AppFont.bold(17))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Recommended for safety — Suber can keep a remote copy you can restore from.")
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            // Trust bullets — same vertical-stack pattern as AutopilotConsentSheet
            // (Pass 4 anti-AI-slop rule: never a 3-column grid).
            VStack(alignment: .leading, spacing: 14) {
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Stays in sync across all your Macs",
                    detail: "Add a sub on one Mac — see it on the others within seconds."
                )
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Recovers if anything breaks",
                    detail: "If a future bug ever loses local data, your iCloud copy restores it."
                )
                TrustBullet(
                    symbol: "checkmark.circle",
                    title: "Free, private, your account only",
                    detail: "Uses iCloud Key-Value storage. Apple syncs it; Suber's servers see nothing."
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.bgCell)
            )
            .padding(.horizontal, 20)

            // Privacy footnote
            // AUDIT-v1.9.2 U-09: v1.9.0 moved the toggle out of General into a
            // top-level "iCloud Sync" section — keep this path in sync.
            Text("You can change this any time in Settings → iCloud Sync.")
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            // Buttons — Enable is default action; Skip is bordered + cancel-key.
            HStack(spacing: 12) {
                Spacer()
                Button("Skip — I'll decide later", action: onSkip)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Enable iCloud Sync", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        // Width follows OverlayPresenter (480pt popover); same pattern as
        // AutopilotConsentSheet after v1.8.1's hard-coded-540 fix.
        .frame(maxWidth: .infinity)
    }
}
