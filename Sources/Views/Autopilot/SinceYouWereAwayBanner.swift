import SwiftUI

// ┌───────────── SinceYouWereAwayBanner — D5 number-first layout ──────────────┐
// │                                                                            │
// │  Design review D5 (I2) pick: A — number-first.                            │
// │                                                                            │
// │    [ 3 ]   new changes since yesterday        [ Review → ]      ✕         │
// │                                                                            │
// │  - Hero number: .largeTitle semibold 24pt, leading                         │
// │  - Body: .body 13pt secondaryLabel                                          │
// │  - Primary: .borderedProminent [Review → ]                                  │
// │  - "since yesterday" replaces "while you were away" (less passive)          │
// │  - For >7 days since last launch: "since last week" / "since you last      │
// │    opened Suber" variants                                                   │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct SinceYouWereAwayBanner: View {
    let count: Int
    let lastShownAt: Date?   // for picking the copy variant (nil = first show)
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        // Instead of using the generic AutopilotBannerView (which has a
        // fixed 20pt leading icon), this banner has a custom leading
        // treatment — the number IS the icon. Same 56pt rhythm + chrome.
        HStack(spacing: 12) {
            // Hero number — 24pt semibold, fixed width so plurals don't jostle
            Text("\(count)")
                .font(AppFont.bold(24))
                .foregroundColor(Theme.textPrimary)
                .frame(minWidth: 36, alignment: .leading)
                .accessibilityHidden(true)  // full label is on the HStack

            Text(bodyCopy)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onReview) {
                HStack(spacing: 4) {
                    Text("Review")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.return)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                    .frame(width: 24, height: 24)
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
            VStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Spacer()
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(count) new changes \(bodyCopySuffix). Button, Review."))
    }

    // MARK: - Copy variants

    /// Design review D5: "since yesterday" for daily, "since last week" /
    /// "since you last opened Suber" for longer gaps.
    private var bodyCopy: String {
        // AUDIT-v1.9.2 U-03: String(localized:) — computed String channel.
        String(localized: "new changes \(bodyCopySuffix)")
    }

    private var bodyCopySuffix: String {
        guard let lastShownAt else { return String(localized: "since yesterday") }
        let daysSince = Calendar.current.dateComponents(
            [.day], from: lastShownAt, to: Date()
        ).day ?? 0
        if daysSince <= 1 { return String(localized: "since yesterday") }
        if daysSince <= 7 { return String(localized: "since last week") }
        return String(localized: "since you last opened Suber")
    }
}

#if DEBUG
#Preview("3 since yesterday") {
    SinceYouWereAwayBanner(count: 3, lastShownAt: nil, onReview: {}, onDismiss: {})
        .frame(width: 760)
}
#Preview("1 since last week") {
    SinceYouWereAwayBanner(
        count: 1,
        lastShownAt: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
        onReview: {}, onDismiss: {}
    )
    .frame(width: 760)
}
#Preview("12 since last open") {
    SinceYouWereAwayBanner(
        count: 12,
        lastShownAt: Calendar.current.date(byAdding: .day, value: -21, to: Date()),
        onReview: {}, onDismiss: {}
    )
    .frame(width: 760)
}
#endif
