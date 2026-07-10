import SwiftUI

// ┌───────────── CancelConfirmationSheet — D10 trust-primed confirmation ──────┐
// │                                                                            │
// │  Design review D10 (J2) copy — chosen Option B (trust-primed):             │
// │                                                                            │
// │    Open Netflix's cancel page                      (action title, no "?")  │
// │                                                                            │
// │    Suber will open Netflix's cancellation page in                          │
// │    your browser. You'll cancel there. Suber will check                     │
// │    next month and confirm when the charges stop.                           │
// │                                                                            │
// │    ────────────────────────────────────                                    │
// │    Already cancelled on Netflix? Mark as cancelled  (tertiary link)        │
// │                                                                            │
// │                     [ Not now ]  [ Open cancel page ]                      │
// │                                                                            │
// │  The "Suber will check next month" promise is conditional: we ONLY say it  │
// │  when the user actually has a data source configured (Watchdog or CSV). If │
// │  they're manual-only (A4), we say "You'll cancel there. Suber can't        │
// │  verify automatically — tap Mark as cancelled below when you're done."    │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct CancelConfirmationSheet: View {
    let subscription: Subscription
    /// True if MailWatchdog enabled OR there's a recent CSV import — the
    /// auto-verify promise is honest only in this case.
    let hasDataSource: Bool
    let onOpenCancelPage: () -> Void
    let onMarkCancelledManually: () -> Void
    let onCancel: () -> Void

    // D5 tertiary-link gate. Two-step confirm for "Mark as cancelled" so users
    // don't accidentally set Netflix to cancelled with a stray click.
    @State private var showingMarkConfirm = false

    var body: some View {
        VStack(spacing: 20) {

            // Icon + action title
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 8)

                Text("Open \(subscription.name)'s cancel page")
                    .font(AppFont.bold(16))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            // Body copy — sets the mental model (user cancels, Suber verifies)
            Text(bodyCopy)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            // Tertiary affordance: "already cancelled elsewhere"
            Divider().padding(.horizontal, 24)
            markCancelledTertiary
            Divider().padding(.horizontal, 24)

            // Buttons
            HStack(spacing: 12) {
                Spacer()
                Button("Not now", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Open cancel page", action: onOpenCancelPage)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.bgPrimary)
        .alert("Mark \(subscription.name) as cancelled?",
               isPresented: $showingMarkConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Mark as cancelled", role: .destructive) {
                onMarkCancelledManually()
            }
        } message: {
            Text("Suber will stop tracking charges for \(subscription.name). If you haven't actually cancelled, you'll see the next bill on your card and can undo this.")
        }
    }

    // MARK: - Body copy

    private var bodyCopy: String {
        // AUDIT-v1.9.2 U-03: String(localized:) — both keys were already in
        // the catalog but this computed String rendered verbatim (English).
        if hasDataSource {
            return String(localized: "Suber will open \(subscription.name)'s cancellation page in your browser. You'll cancel there. Suber will check next month and confirm when the charges stop.")
        }
        // A4: no data source → honest about the limitation.
        return String(localized: "Suber will open \(subscription.name)'s cancellation page in your browser. You'll cancel there. Suber can't verify automatically — tap Mark as cancelled below when you're done.")
    }

    // MARK: - Tertiary

    private var markCancelledTertiary: some View {
        HStack(spacing: 6) {
            Text("Already cancelled on \(subscription.name)?")
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textSecondary)
            Button("Mark as cancelled") {
                showingMarkConfirm = true
            }
            .buttonStyle(.plain)
            .font(AppFont.medium(11))
            .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 24)
    }
}

#if DEBUG
#Preview("With data source") {
    CancelConfirmationSheet(
        subscription: Subscription(
            id: UUID(), name: "Netflix", amount: 22.99, currency: "USD",
            cycle: .monthly, billingDay: 15, startDate: .now,
            category: "Entertainment", status: .active,
            createdAt: .now, updatedAt: .now
        ),
        hasDataSource: true,
        onOpenCancelPage: {},
        onMarkCancelledManually: {},
        onCancel: {}
    )
}

#Preview("No data source (A4)") {
    CancelConfirmationSheet(
        subscription: Subscription(
            id: UUID(), name: "Netflix", amount: 22.99, currency: "USD",
            cycle: .monthly, billingDay: 15, startDate: .now,
            category: "Entertainment", status: .active,
            createdAt: .now, updatedAt: .now
        ),
        hasDataSource: false,
        onOpenCancelPage: {},
        onMarkCancelledManually: {},
        onCancel: {}
    )
}
#endif
