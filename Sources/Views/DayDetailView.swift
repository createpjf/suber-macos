import SwiftUI

struct DayDetailView: View {
    let date: Date
    let subscriptions: [Subscription]
    let onEdit: (Subscription) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var dragOffset: CGFloat = 0
    /// v1.6: pending-cancel confirmation sheet target.
    @State private var pendingCancelSub: Subscription?

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Theme.textDim)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Header
            HStack {
                Text(DateHelpers.formatDate(date))
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.bgPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()
                .background(Theme.border)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(subscriptions) { sub in
                        VStack(spacing: 0) {
                            Button(action: { onEdit(sub) }) {
                                HStack(spacing: 10) {
                                    LogoView(subscription: sub, size: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sub.name)
                                            .font(AppFont.medium(13))
                                            .foregroundColor(Theme.textPrimary)
                                        Text(sub.category)
                                            .font(AppFont.regular(10))
                                            .foregroundColor(Theme.textSecondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(CurrencyFormatter.formatShort(sub.amount, currency: sub.currency))
                                            .font(AppFont.medium(13))
                                            .foregroundColor(Theme.textPrimary)
                                        Text(sub.cycle.shortLabel)
                                            .font(AppFont.regular(10))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // v1.6: pending-cancel banner under the row when
                            // the sub is in that state. A4 nudge to manually
                            // confirm for no-data-source users.
                            if sub.status == .pendingCancellation {
                                pendingCancelBanner(for: sub)
                            } else if sub.status != .cancelled {
                                // Active/paused/trial → show "Open cancel page…" action.
                                cancelActionRow(for: sub)
                            }
                        }

                        if sub.id != subscriptions.last?.id {
                            Divider()
                                .background(Theme.border)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(subscriptions.count) * 96 + 8, 360))
        }
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onClose()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        // v1.6 One-Tap Cancel confirmation sheet (D10).
        .sheet(item: $pendingCancelSub) { sub in
            CancelConfirmationSheet(
                subscription: sub,
                hasDataSource: hasDataSource,
                onOpenCancelPage: {
                    pendingCancelSub = nil
                    subscriptionStore.markPendingCancellation(id: sub.id)
                    OneTapCancelService.openCancelPage(for: sub)
                },
                onMarkCancelledManually: {
                    pendingCancelSub = nil
                    subscriptionStore.markCancelledManually(id: sub.id)
                },
                onCancel: { pendingCancelSub = nil }
            )
        }
    }

    // MARK: - v1.6 Cancel row

    @ViewBuilder
    private func cancelActionRow(for sub: Subscription) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: { pendingCancelSub = sub }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                    Text(cancelButtonLabel(for: sub))
                        .font(AppFont.regular(11))
                }
                .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func pendingCancelBanner(for sub: Subscription) -> some View {
        let daysLeft = daysUntilNextBilling(sub: sub)
        let dueDate = BillingCalculator.getNextBillingDate(sub)
        VStack(spacing: 8) {
            PendingCancellationIndicator.detailBanner(
                dueDate: dueDate,
                daysLeft: daysLeft
            )

            HStack(spacing: 8) {
                // Re-open URL (D5 idempotent: doesn't reset pendingCancellationSetAt).
                Button(action: {
                    OneTapCancelService.openCancelPage(for: sub)
                }) {
                    Text("Open cancel page again")
                        .font(AppFont.regular(11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // A4 nudge: manual-mark path for users without a data source.
                if !hasDataSource {
                    Button(action: {
                        subscriptionStore.markCancelledManually(id: sub.id)
                    }) {
                        Text("Mark as cancelled")
                            .font(AppFont.regular(11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Helpers

    /// A4 data-source detector — mirrors ListView's implementation.
    private var hasDataSource: Bool {
        if settingsStore.settings.autopilot.watchAppleMail { return true }
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        return subscriptionStore.changes.contains { change in
            change.source == .csvImport && change.detectedAt >= threshold
        }
    }

    private func cancelButtonLabel(for sub: Subscription) -> String {
        OneTapCancelService.hasKnownCancelPage(for: sub)
            ? "Open cancel page…"
            : "Find cancel page…"
    }

    private func daysUntilNextBilling(sub: Subscription) -> Int? {
        guard sub.cycle != .oneTime else { return nil }
        return BillingCalculator.getDaysUntilBilling(sub)
    }
}
