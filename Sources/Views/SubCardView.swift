import SwiftUI

struct SubCardView: View {
    let subscription: Subscription
    /// v1.6: optional One-Tap Cancel action. When nil, the context menu
    /// omits the cancel entry (keeps v1.4 DashboardView callers working
    /// without wiring every parent through to the store).
    var onOpenCancelPage: (() -> Void)? = nil
    /// AUDIT-v1.9.2 U-16: tap-to-edit had zero affordance (no pointer, no
    /// menu entry, no chevron). When set, the card shows a pointing-hand
    /// cursor on hover and an "Edit…" context-menu item.
    var onEdit: (() -> Void)? = nil

    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    @State private var isHovered = false
    // AUDIT-v1.9.2 U-07: "Mark as cancelled" sits one row under "Open cancel
    // page…" in the context menu — a misclick silently flipped status with no
    // undo. Menu items can't host dialogs, so the item only sets this flag and
    // the card body presents the confirm (same copy as CancelConfirmationSheet).
    @State private var showMarkCancelledConfirm = false

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
                    // U-02: display-localize the preset category (stored value
                    // stays the English identifier).
                    Text(AppConstants.localizedCategory(subscription.category))
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
            // AUDIT-v1.9.2 U-16: pointer affordance — the whole card is a
            // tap-to-edit target, so the cursor should say so.
            if onEdit != nil {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .contextMenu {
            // AUDIT-v1.9.2 U-16: the menu previously only offered cancel
            // actions, implying cancel was the card's sole operation.
            if let onEdit {
                Button("Edit…") { onEdit() }
            }
            if onOpenCancelPage != nil && subscription.status != .cancelled {
                Button(cancelMenuLabel) {
                    onOpenCancelPage?()
                }
                if subscription.status == .pendingCancellation {
                    // Already-pending context menu: let user mark manually
                    // in case they've already cancelled elsewhere and want
                    // to skip the auto-verify wait.
                    // AUDIT-v1.9.2 C-06: the store API persists the change and
                    // logs cancellationConfirmed. The old inline mutation never
                    // saved (status reverted on relaunch) and passed a
                    // subscription id to markChangeAcknowledged, which expects
                    // a change id — a permanent no-op.
                    Button("Mark as cancelled") {
                        showMarkCancelledConfirm = true
                    }
                }
            }
        }
        .alert("Mark \(subscription.name) as cancelled?", isPresented: $showMarkCancelledConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Mark as cancelled", role: .destructive) {
                subscriptionStore.markCancelledManually(id: subscription.id)
            }
        } message: {
            Text("Suber will stop tracking charges for \(subscription.name). If you haven't actually cancelled, you'll see the next bill on your card and can undo this.")
        }
        // AUDIT-v1.9.2 U-10: read the card as one element (name, price,
        // cycle, days-until) instead of six fragments.
        .accessibilityElement(children: .combine)
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
    /// AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — both values are
    /// translated catalog keys, but Button(String) never looked them up.
    private var cancelMenuLabel: LocalizedStringKey {
        OneTapCancelService.hasKnownCancelPage(for: subscription)
            ? "Open cancel page…"
            : "Find cancel page…"
    }

    private var daysUntilText: String? {
        if subscription.cycle == .oneTime { return nil }
        guard let count = daysUntilBillingCount else { return nil }
        // AUDIT-v1.9.2 U-03: String(localized:) — computed Strings render
        // verbatim, so these need explicit catalog lookups.
        if count == 0 { return String(localized: "Today") }
        if count == 1 { return String(localized: "Tomorrow") }
        return String(localized: "in \(count)d")
    }

    private var daysUntilBillingCount: Int? {
        if subscription.cycle == .oneTime { return nil }
        return BillingCalculator.getDaysUntilBilling(subscription)
    }
}
