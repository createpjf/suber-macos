import SwiftUI

// ┌───────────── FirstCatchBanner — D8 once-forever trust-fall payoff ─────────┐
// │                                                                            │
// │  Fires ONCE in the app's lifetime — the first time the Changes Window      │
// │  opens with at least one real change. Gated by AutopilotFlags              │
// │  .hasSeenFirstCatch (default false, set true on dismiss).                  │
// │                                                                            │
// │  Copy: "Suber caught your first change. Tap a row to review."              │
// │  Icon: SF Symbol `target`, controlAccentColor tint (subtle, not green —    │
// │  greens go with the earned-success CancellationSuccessBanner).             │
// │                                                                            │
// │  Why this exists: user granted Mail access (trust fall). First detection   │
// │  is the payoff. Skipping it makes Autopilot feel like a silent cron job.   │
// │                                                                            │
// │  A1 (eng re-review): BannerCoordinator picks at most one banner at a       │
// │  time. This one sits at priority 2 (between earned-success and daily       │
// │  unread).                                                                   │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct FirstCatchBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        AutopilotBannerView(
            icon: "target",
            iconTint: .accentColor,
            // U-03: AutopilotBannerView's title/subtitle are Strings (the
            // success banner passes computed copy) — localize at this call site.
            title: String(localized: "Suber caught your first change."),
            subtitle: String(localized: "Tap a row to review."),
            onDismiss: onDismiss
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "Suber caught your first change. Tap a row to review. Button, dismiss."
        ))
    }
}

#if DEBUG
#Preview {
    FirstCatchBanner(onDismiss: {})
        .frame(width: 760)
}
#endif
