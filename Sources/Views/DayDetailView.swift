import SwiftUI

struct DayDetailView: View {
    let date: Date
    let subscriptions: [Subscription]
    let onEdit: (Subscription) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var settingsStore: SettingsStore
    /// v1.8.0: popover-root overlay coordinator for CancelConfirmationSheet.
    @EnvironmentObject private var overlayPresenter: OverlayPresenter

    @State private var dragOffset: CGFloat = 0
    // AUDIT-v1.9.2 U-07: the pending-cancel banner button mutated status with
    // one click, no confirm/undo — inconsistent with CancelConfirmationSheet's
    // two-step protection for the same action. The button stages the sub here;
    // the root view presents the confirm alert.
    @State private var pendingMarkCancelled: Subscription?

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
                // AUDIT-v1.9.2 U-10: icon-only close button needs a label.
                .accessibilityLabel(Text("Close"))
                .help("Close")
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
                                        Text(AppConstants.localizedCategory(sub.category))
                                            .font(AppFont.regular(10))
                                            .foregroundColor(Theme.textSecondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        // AUDIT-v1.9.2 U-06: show the user's split
                                        // share (effectiveAmount, ÷N hint) like
                                        // SubCardView — not the un-split face price.
                                        HStack(spacing: 3) {
                                            if sub.splitCount > 1 {
                                                Text("÷\(sub.splitCount)")
                                                    .font(AppFont.regular(9))
                                                    .foregroundColor(Theme.textDim)
                                            }
                                            Text(CurrencyFormatter.formatShort(sub.effectiveAmount, currency: sub.currency))
                                                .font(AppFont.medium(13))
                                                .foregroundColor(Theme.textPrimary)
                                        }
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
        // v1.8.0: CancelConfirmationSheet 走 OverlayPresenter (popover root).
        .alert(
            "Mark \(pendingMarkCancelled?.name ?? "") as cancelled?",
            isPresented: Binding(
                get: { pendingMarkCancelled != nil },
                set: { if !$0 { pendingMarkCancelled = nil } }
            ),
            presenting: pendingMarkCancelled
        ) { sub in
            Button("Cancel", role: .cancel) {}
            Button("Mark as cancelled", role: .destructive) {
                subscriptionStore.markCancelledManually(id: sub.id)
            }
        } message: { sub in
            Text("Suber will stop tracking charges for \(sub.name). If you haven't actually cancelled, you'll see the next bill on your card and can undo this.")
        }
    }

    /// v1.8.0: presents CancelConfirmationSheet via OverlayPresenter so it
    /// renders at popover root instead of being pinned to this view's bounds.
    private func presentCancelConfirmation(for sub: Subscription) {
        overlayPresenter.present(
            CancelConfirmationSheet(
                subscription: sub,
                hasDataSource: hasDataSource,
                onOpenCancelPage: {
                    overlayPresenter.dismiss()
                    subscriptionStore.markPendingCancellation(id: sub.id)
                    OneTapCancelService.openCancelPage(for: sub)
                },
                onMarkCancelledManually: {
                    overlayPresenter.dismiss()
                    subscriptionStore.markCancelledManually(id: sub.id)
                },
                onCancel: { overlayPresenter.dismiss() }
            )
        )
    }

    // MARK: - v1.6 Cancel row

    @ViewBuilder
    private func cancelActionRow(for sub: Subscription) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: { presentCancelConfirmation(for: sub) }) {
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
                        // AUDIT-v1.9.2 U-07: confirm before mutating (see
                        // pendingMarkCancelled).
                        pendingMarkCancelled = sub
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
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return subscriptionStore.changes.contains { change in
            change.source == .csvImport && change.detectedAt >= threshold
        }
    }

    // AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — both values are
    // translated catalog keys, but Text(String) never looked them up.
    private func cancelButtonLabel(for sub: Subscription) -> LocalizedStringKey {
        OneTapCancelService.hasKnownCancelPage(for: sub)
            ? "Open cancel page…"
            : "Find cancel page…"
    }

    private func daysUntilNextBilling(sub: Subscription) -> Int? {
        guard sub.cycle != .oneTime else { return nil }
        return BillingCalculator.getDaysUntilBilling(sub)
    }
}
