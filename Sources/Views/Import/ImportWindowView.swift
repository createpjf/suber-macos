import SwiftUI

/// Container for the secondary "Import" window scene. Switches on
/// `ImportPresenter.mode` to render either the bank-statement flow or the
/// multi-subscription review list.
///
/// Lives in a regular `Window` scene (not the MenuBarExtra popover) so macOS
/// sorts TCC / file picker / system notification windows above it correctly.
struct ImportWindowView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var presenter: ImportPresenter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .frame(minWidth: 520, minHeight: 520)
            .background(Theme.bgPrimary)
            .onDisappear {
                // Covers the case where the user clicks the red title-bar
                // close button (bypassing our in-view Cancel/Add handlers).
                presenter.reset()
                WindowActivationCoordinator.relinquishIfNoWindows()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.mode {
        case .idle:
            // Window was opened with no mode set — shouldn't normally happen,
            // but give the user a graceful "close me" state rather than a blank.
            VStack(spacing: 12) {
                Spacer()
                Text("Nothing to import right now.")
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                Button(action: closeWindow) {
                    Text("Close")
                        .font(AppFont.medium(12))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case .bankStatement:
            BankImportView(
                existingSubscriptions: subscriptionStore.subscriptions,
                onAdd: { forms in
                    for data in forms {
                        subscriptionStore.add(data)
                    }
                    closeWindow()
                },
                onCancel: closeWindow
            )

        case .reviewCandidates(let candidates):
            ImportReviewListView(
                candidates: candidates,
                existingSubscriptions: subscriptionStore.subscriptions,
                onAdd: { forms in
                    for data in forms {
                        subscriptionStore.add(data)
                    }
                    closeWindow()
                },
                onCancel: closeWindow
            )

        case .reviewChanges(let changes):
            // v1.6 Sentinel: Changes Window for reviewing detected price rises,
            // new subs, duplicates, and confirmed cancellations. Row actions
            // live in ChangesListView (Accept / Ignore / Add / Open cancel page).
            ChangesListView(
                initialChanges: changes,
                onDone: closeWindow
            )
        }
    }

    /// Reset the presenter, dismiss the window, and flip activation policy
    /// back to `.accessory` once the window is fully gone so we stop
    /// showing a Dock icon.
    private func closeWindow() {
        presenter.reset()
        dismiss()
        WindowActivationCoordinator.relinquishIfNoWindows()
    }
}
