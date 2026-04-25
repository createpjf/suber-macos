import SwiftUI

// ┌───────────── AutopilotBannerView — shared banner chrome ───────────────────┐
// │                                                                            │
// │  Three banners share this rhythm so the app speaks with one voice:         │
// │    - SinceYouWereAwayBanner ("3 new changes since yesterday" + Review)     │
// │    - FirstCatchBanner ("Suber caught your first change.")                  │
// │    - CancellationSuccessBanner ("Netflix cancelled. You'll save $215/yr.") │
// │                                                                            │
// │  Design-review spec (D5/D8/D11):                                           │
// │    - Height: 56pt                                                          │
// │    - Background: Theme.bgSecondary (grouped surface)                       │
// │    - 1pt separator top + bottom                                            │
// │    - Horizontal padding 16pt, vertical 12pt                                │
// │    - Leading SF Symbol 20pt with accent tint (banner-specific)             │
// │    - Trailing ✕ dismiss, 24pt hit target (above HIG 22pt a11y minimum)     │
// │    - Primary action (if present) uses .borderedProminent                   │
// │                                                                            │
// │  A1 (eng re-review): BannerCoordinator picks at most ONE banner to show.   │
// │  Consumers never render two of these stacked.                              │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct AutopilotBannerView<Trailing: View>: View {
    let icon: String              // SF Symbol name
    let iconTint: Color           // semantic tint (controlAccentColor / systemGreen)
    let title: String             // primary copy
    let subtitle: String?         // optional secondary copy (banner-dependent)
    let onDismiss: () -> Void     // ✕ tap
    @ViewBuilder let trailing: () -> Trailing  // primary action button (or EmptyView)

    init(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.onDismiss = onDismiss
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(iconTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            trailing()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                    .frame(width: 24, height: 24) // a11y hit target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss banner"))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Theme.bgSecondary)
        .overlay(
            // 1pt separator top + bottom — rhythm marker shared across banners
            VStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Spacer()
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        )
    }
}

// Convenience overload: banner without a trailing primary action.
extension AutopilotBannerView where Trailing == EmptyView {
    init(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            onDismiss: onDismiss,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With action") {
    AutopilotBannerView(
        icon: "sparkles",
        iconTint: .accentColor,
        title: "3 new changes since yesterday",
        subtitle: nil,
        onDismiss: {},
        trailing: {
            Button("Review") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    )
    .frame(width: 760)
}

#Preview("Without action") {
    AutopilotBannerView(
        icon: "target",
        iconTint: .accentColor,
        title: "Suber caught your first change.",
        subtitle: "Tap a row to review.",
        onDismiss: {}
    )
    .frame(width: 760)
}
#endif
