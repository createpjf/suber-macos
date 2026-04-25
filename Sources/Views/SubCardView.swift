import SwiftUI

struct SubCardView: View {
    let subscription: Subscription
    /// v1.6: optional One-Tap Cancel action. When nil, the context menu
    /// omits the cancel entry (keeps v1.4 DashboardView callers working
    /// without wiring every parent through to the store).
    var onOpenCancelPage: (() -> Void)? = nil

    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            LogoView(subscription: subscription, size: 36)

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(subscription.category)
                        .font(AppFont.regular(10))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.bgPrimary)
                        .clipShape(Capsule())

                    // v1.6: pending-cancel label replaces the "in Xd" copy
                    // so the user sees the status transition immediately.
                    if subscription.status == .pendingCancellation {
                        PendingCancellationIndicator.pendingLabel(
                            daysLeft: daysUntilBillingCount
                        )
                    } else if let daysText = daysUntilText {
                        Text(daysText)
                            .font(AppFont.regular(10))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    if subscription.splitCount > 1 {
                        Text("÷\(subscription.splitCount)")
                            .font(AppFont.regular(9))
                            .foregroundColor(Theme.textDim)
                    }
                    Text(CurrencyFormatter.formatShort(subscription.effectiveAmount, currency: subscription.currency))
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                }
                Text(subscription.cycle.shortLabel)
                    .font(AppFont.regular(10))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Theme.bgCell : Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(cardStroke)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if onOpenCancelPage != nil && subscription.status != .cancelled {
                Button(cancelMenuLabel) {
                    onOpenCancelPage?()
                }
                if subscription.status == .pendingCancellation {
                    // Already-pending context menu: let user mark manually
                    // in case they've already cancelled elsewhere and want
                    // to skip the auto-verify wait.
                    Button("Mark as cancelled") {
                        subscriptionStore.markChangeAcknowledged(id: subscription.id)
                        var sub = subscription
                        sub.status = .cancelled
                        sub.pendingCancellationSetAt = nil
                        sub.updatedAt = Date()
                        if let i = subscriptionStore.subscriptions.firstIndex(where: { $0.id == sub.id }) {
                            subscriptionStore.subscriptions[i] = sub
                        }
                    }
                }
            }
        }
    }

    // MARK: - Visuals

    /// v1.6: pendingCancellation gets the dashed-border override; everything
    /// else keeps the existing hover/border behavior.
    @ViewBuilder
    private var cardStroke: some View {
        if subscription.status == .pendingCancellation {
            PendingCancellationIndicator.dashedBorder(tier: .row)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Theme.textDim : Theme.border, lineWidth: 1)
        }
    }

    private var statusColor: Color {
        if subscription.status == .pendingCancellation {
            return Color(nsColor: NSColor.systemOrange)
        }
        return AppConstants.statusColors[subscription.status] ?? Theme.textSecondary
    }

    // MARK: - Copy

    /// D10 button-label mental-model rule: match the confirmation sheet's
    /// button copy ("Open cancel page") so users see continuity.
    private var cancelMenuLabel: String {
        OneTapCancelService.hasKnownCancelPage(for: subscription)
            ? "Open cancel page…"
            : "Find cancel page…"
    }

    private var daysUntilText: String? {
        if subscription.cycle == .oneTime { return nil }
        guard let count = daysUntilBillingCount else { return nil }
        if count == 0 { return "Today" }
        if count == 1 { return "Tomorrow" }
        return "in \(count)d"
    }

    private var daysUntilBillingCount: Int? {
        if subscription.cycle == .oneTime { return nil }
        return BillingCalculator.getDaysUntilBilling(subscription)
    }
}
