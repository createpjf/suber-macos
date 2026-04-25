import SwiftUI

// ┌───────────── PendingCancellationIndicator — .pendingCancellation visual ───┐
// │                                                                            │
// │  Design review Pass 2: `.pendingCancellation` reconciled across 4 view     │
// │  contexts at size-appropriate fidelity. This file centralizes the shared   │
// │  visual language so all four sites stay in sync (fix once, fix everywhere).│
// │                                                                            │
// │  Common language:                                                          │
// │    - Dashed stroke (pattern [4,2] / [6,3]) in systemOrange @ 0.6 alpha      │
// │    - Short status label: "Pending cancel" or "Nd" countdown badge          │
// │                                                                            │
// │  Size tiers:                                                               │
// │    .tile   (~40pt calendar day)  → dashed border only + tiny "Nd" badge    │
// │    .row    (~64pt list row)      → dashed leading strip + "Pending cancel" │
// │    .card   (~100pt dashboard)    → dashed border + "Pending cancel · Nd"   │
// │    .detail (~300pt card/detail)  → full inline banner row                  │
// │                                                                            │
// │  WCAG: systemOrange at 0.6 alpha verified against windowBackgroundColor    │
// │  and controlBackgroundColor at ≥3:1 (non-text graphic threshold).          │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// Size tier for the indicator. Caller picks based on the enclosing view's size.
enum PendingCancellationTier {
    case tile    // ~40pt — CalendarDayCellView
    case row     // ~64pt — ListView row
    case card    // ~100pt — DashboardView card
    case detail  // ~300pt — SubCardView / DayDetail full card
}

/// Pure-visual helpers. Consumers compose these into their view trees; we
/// don't wrap-and-hide the host view (keeps the existing layout code legible).
enum PendingCancellationIndicator {

    /// Days until billing day. Nil if >30 away (we only show countdowns for
    /// actionable windows). Caller passes in the value; helper doesn't compute.
    static func daysLeftLabel(daysLeft: Int?) -> String? {
        guard let d = daysLeft, d >= 0, d <= 30 else { return nil }
        if d == 0 { return "Today" }
        return "\(d)d"
    }

    /// systemOrange tinted to 0.6 alpha — the shared semantic color for the
    /// pending-cancel state across all tiers.
    static var tint: Color {
        Color(nsColor: NSColor.systemOrange.withAlphaComponent(0.6))
    }

    /// Dashed-border shape for a given tier. Applied as `.overlay(...)`.
    static func dashedBorder(tier: PendingCancellationTier) -> some View {
        let radius: CGFloat
        let lineWidth: CGFloat
        let dash: [CGFloat]
        switch tier {
        case .tile:
            radius = 10; lineWidth = 1.5; dash = [4, 2]
        case .row:
            radius = 12; lineWidth = 1.5; dash = [5, 2]
        case .card:
            radius = 12; lineWidth = 2; dash = [6, 3]
        case .detail:
            radius = 16; lineWidth = 2; dash = [6, 3]
        }
        return RoundedRectangle(cornerRadius: radius)
            .strokeBorder(tint, style: StrokeStyle(lineWidth: lineWidth, dash: dash))
    }

    /// Compact "Nd" countdown badge for the .tile tier (only). Shown in the
    /// top-right corner of a 40pt calendar day cell. Text size 9pt fits.
    static func tileCountdownBadge(daysLeft: Int?) -> some View {
        Group {
            if let label = daysLeftLabel(daysLeft: daysLeft) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color(nsColor: NSColor.systemOrange))
                    )
            }
        }
    }

    /// "Pending cancel" label used in the .row tier (and, optionally, .card).
    static func pendingLabel(daysLeft: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(nsColor: NSColor.systemOrange))
            Text("Pending cancel")
                .font(AppFont.regular(10))
                .foregroundColor(Color(nsColor: NSColor.systemOrange))
            if let d = daysLeftLabel(daysLeft: daysLeft) {
                Text("· \(d)")
                    .font(AppFont.regular(10))
                    .foregroundColor(Color(nsColor: NSColor.systemOrange))
            }
        }
    }

    /// Full inline detail banner used in .detail tier. Shows "Pending
    /// cancellation — due by {date} ({N} days)" with a leading warning icon.
    static func detailBanner(dueDate: Date?, daysLeft: Int?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(nsColor: NSColor.systemOrange))
            VStack(alignment: .leading, spacing: 2) {
                Text("Pending cancellation")
                    .font(AppFont.medium(12))
                    .foregroundColor(Theme.textPrimary)
                if let dueDate, let daysLeft {
                    Text("Due by \(formatDate(dueDate)) · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text("Suber is watching for the next charge.")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: NSColor.systemOrange).opacity(0.12))
        )
    }

    private static func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}
