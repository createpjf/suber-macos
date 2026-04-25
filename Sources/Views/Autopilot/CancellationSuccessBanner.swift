import SwiftUI

// ┌───────────── CancellationSuccessBanner — D11 earned savings ───────────────┐
// │                                                                            │
// │  Fires after cancellationConfirmed auto-transitions. Collapsed form when   │
// │  multiple subs confirm same day:                                           │
// │                                                                            │
// │    1 sub:   "✓ Netflix cancelled. You'll save $215/year."                  │
// │    2 subs:  "✓ Netflix and Spotify cancelled. You'll save $287/year."     │
// │    3 subs:  "✓ Netflix, Spotify, and Disney+ cancelled. You'll save $X."  │
// │    4+ subs: "✓ 5 subs cancelled. You'll save $512/year."                   │
// │                                                                            │
// │  Icon: `checkmark.circle.fill`, systemGreen                                │
// │  Dismiss persists lastCelebrationAckedAt so same confirmation doesn't      │
// │  re-banner across sessions.                                                │
// │                                                                            │
// │  Copy rules (design review D11):                                           │
// │   - Concrete annual savings REQUIRED (never "you saved some money")        │
// │   - Rounded DOWN to whole dollars (under-promise, over-deliver)            │
// │   - No exclamation marks; no emoji beyond the SF Symbol                    │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct CancellationSuccessBanner: View {
    /// Total annualized savings across the batch, in the user's primary currency.
    let annualSavings: Int
    /// Service names for the banner copy. Order as passed; coordinator caps 3.
    let serviceNames: [String]
    let onDismiss: () -> Void

    var body: some View {
        AutopilotBannerView(
            icon: "checkmark.circle.fill",
            iconTint: .green,
            title: title,
            subtitle: nil,
            onDismiss: onDismiss
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibleLabel))
    }

    // MARK: - Copy generation

    private var title: String {
        let savingsPart = annualSavings > 0
            ? " You'll save $\(annualSavings)/year."
            : ""
        return "\(servicesPhrase) cancelled.\(savingsPart)"
    }

    /// Natural-language service list. Oxford comma for 3; digit for 4+.
    private var servicesPhrase: String {
        switch serviceNames.count {
        case 0: return "Subscription"
        case 1: return "✓ \(serviceNames[0])"
        case 2: return "✓ \(serviceNames[0]) and \(serviceNames[1])"
        case 3: return "✓ \(serviceNames[0]), \(serviceNames[1]), and \(serviceNames[2])"
        default: return "✓ \(serviceNames.count) subs"
        }
    }

    /// VoiceOver-friendly variant: spells out "will save X dollars per year"
    /// so screen readers don't trip on the "$X/year" abbreviation.
    private var accessibleLabel: String {
        let savingsPart = annualSavings > 0
            ? " You will save \(annualSavings) dollars per year."
            : ""
        let namesPart: String = {
            switch serviceNames.count {
            case 0: return "Subscription"
            case 1: return serviceNames[0]
            case 2: return "\(serviceNames[0]) and \(serviceNames[1])"
            case 3: return "\(serviceNames[0]), \(serviceNames[1]), and \(serviceNames[2])"
            default: return "\(serviceNames.count) subscriptions"
            }
        }()
        return "\(namesPart) cancelled.\(savingsPart) Button, dismiss."
    }
}

#if DEBUG
#Preview("1 sub") {
    CancellationSuccessBanner(
        annualSavings: 215,
        serviceNames: ["Netflix"],
        onDismiss: {}
    )
    .frame(width: 760)
}

#Preview("2 subs") {
    CancellationSuccessBanner(
        annualSavings: 287,
        serviceNames: ["Netflix", "Spotify"],
        onDismiss: {}
    )
    .frame(width: 760)
}

#Preview("4+ subs") {
    CancellationSuccessBanner(
        annualSavings: 512,
        serviceNames: ["Netflix", "Spotify", "Disney+", "ChatGPT", "Claude"],
        onDismiss: {}
    )
    .frame(width: 760)
}
#endif
