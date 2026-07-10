import SwiftUI

// ┌───────────── ChangesListView — Changes Window container ───────────────────┐
// │                                                                            │
// │  Rendered inside the existing Window("import") scene when                  │
// │  ImportPresenter.mode == .reviewChanges. Shows:                            │
// │    - optional top banner slot (BannerCoordinator picks one — A1)           │
// │    - scrollable list of ChangeRowView entries (filtered to unacknowledged  │
// │      in last 14 days by default; filter toggle shows full history)         │
// │    - toolbar with Done button                                              │
// │                                                                            │
// │  Slice 3 scope: wire the list + type-specific row rendering. The 3 banner │
// │  states (SinceYouWereAway, FirstCatch, CancellationSuccess) ship in       │
// │  Slice 4. The toolbar shows a placeholder banner-slot for now so the      │
// │  layout math doesn't jump when Slice 4 lands.                             │
// │                                                                            │
// │  Window size: D12 says min 640×480, default 760×520. The parent scene     │
// │  enforces .windowResizability(.contentMinSize) so we set min via .frame   │
// │  on the root.                                                              │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct ChangesListView: View {
    let initialChanges: [SubscriptionChange]   // from presenter, frozen at open
    let onDone: () -> Void

    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    // v1.6 Slice 4: banner state. Flags is a lightweight @StateObject so
    // dismiss() updates propagate into the next render.
    @StateObject private var flags = AutopilotFlags()
    @State private var activeBanner: BannerCoordinator.Kind?
    /// Badge unread count SNAPSHOT taken once at window-open time.
    /// We need this because onAppear will immediately call
    /// markAllChangesAcknowledged() which zeros unreadChangeCount — the
    /// banner would disappear before it even rendered. So we freeze the
    /// count here BEFORE we clear.
    @State private var frozenUnreadCount: Int = 0

    @State private var showingHistory = false  // full-history toggle

    var body: some View {
        VStack(spacing: 0) {
            // Banner slot (A1): at most ONE banner renders, picked by
            // BannerCoordinator priority. Dismiss cascades to the next
            // eligible banner on the next render (if any).
            bannerSlot

            // Filter bar: current count + toggle for full history.
            filterBar

            Divider()

            if displayedChanges.isEmpty {
                // Empty state is shipped by ChangesWindowEmptyView in Slice 4.
                // For now a placeholder so the layout isn't blank during Slice 3.
                emptyPlaceholder
            } else {
                list
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Theme.bgPrimary)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done", action: onDone)
                    .keyboardShortcut(.return)
            }
        }
        .onAppear {
            // Freeze the unread count BEFORE clearing, so the SinceYouWereAway
            // banner still has data to render from.
            frozenUnreadCount = subscriptionStore.unreadChangeCount
            // Pick the banner BEFORE we acknowledge changes — otherwise the
            // unreadCount-dependent banner would evaluate to nil.
            refreshActiveBanner()
            // User opened the window — mark all unread as acknowledged so the
            // badge clears on open (v1.6 Sentinel retention loop).
            subscriptionStore.markAllChangesAcknowledged()
        }
    }

    // MARK: - Banner slot

    @ViewBuilder private var bannerSlot: some View {
        if let kind = activeBanner {
            switch kind {
            case .cancellationSuccess(let savings, let names):
                CancellationSuccessBanner(
                    annualSavings: savings,
                    serviceNames: names,
                    onDismiss: { dismissBanner(kind) }
                )
            case .firstCatch:
                FirstCatchBanner(onDismiss: { dismissBanner(kind) })
            case .sinceYouWereAway(let count):
                SinceYouWereAwayBanner(
                    count: count,
                    lastShownAt: flags.lastBannerShownAt,
                    onReview: { dismissBanner(kind) },  // Review = ack + dismiss
                    onDismiss: { dismissBanner(kind) }
                )
            }
        }
    }

    private func refreshActiveBanner() {
        let coordinator = BannerCoordinator(flags: flags)
        activeBanner = coordinator.activeBanner(
            changes: subscriptionStore.changes,
            subscriptions: subscriptionStore.subscriptions,
            unreadCount: frozenUnreadCount,
            primaryCurrency: settingsStore.settings.primaryCurrency
        )
    }

    private func dismissBanner(_ kind: BannerCoordinator.Kind) {
        let coordinator = BannerCoordinator(flags: flags)
        coordinator.dismiss(kind)
        // Cascade: re-evaluate for next-priority banner.
        refreshActiveBanner()
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Text(summaryText)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Toggle(isOn: $showingHistory) {
                Text("Show full history")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bgPrimary)
    }

    private var summaryText: String {
        // AUDIT-v1.9.2 U-03: String(localized:) — computed String channel.
        let count = displayedChanges.count
        if showingHistory {
            return String(localized: "\(count) changes total")
        }
        return count == 1
            ? String(localized: "1 change to review")
            : String(localized: "\(count) changes to review")
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedChanges) { change in
                    ChangeRowView(
                        change: change,
                        subscription: subscription(for: change),
                        primaryCurrency: settingsStore.settings.primaryCurrency,
                        onOpenCancelPage: { handleOpenCancelPage(change) },
                        onAcceptNewPrice: { handleAcceptNewPrice(change) },
                        onAdd: { handleAdd(change) },
                        onIgnore: { handleIgnore(change) },
                        onDismiss: { handleIgnore(change) },
                        onMarkCancelledManually: { handleMarkCancelled(change) }
                    )
                }
            }
        }
    }

    // MARK: - Empty placeholder (real empty states land in Slice 4)

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(Theme.textDim)
            Text("No changes to review")
                .font(AppFont.medium(14))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data derivation

    /// Active list: either the initial Sentinel snapshot (unack in last 14d) or
    /// the full store history. Driven by `showingHistory` toggle.
    private var displayedChanges: [SubscriptionChange] {
        let source = showingHistory ? subscriptionStore.changes : initialChanges
        return source.sorted { $0.detectedAt > $1.detectedAt }
    }

    private func subscription(for change: SubscriptionChange) -> Subscription? {
        guard let id = change.subscriptionID else { return nil }
        return subscriptionStore.subscriptions.first(where: { $0.id == id })
    }

    // MARK: - Row actions

    private func handleOpenCancelPage(_ change: SubscriptionChange) {
        // Slice 6 wires the actual URL-open + markPendingCancellation. For now,
        // mark the change acknowledged so the UI updates — prevents the row
        // from sticking around visually during Slice 3 testing.
        subscriptionStore.markChangeAcknowledged(id: change.id)
    }

    private func handleAcceptNewPrice(_ change: SubscriptionChange) {
        guard let subID = change.subscriptionID,
              subscriptionStore.subscriptions.contains(where: { $0.id == subID }),
              let raw = change.newValue?.split(separator: " ").first,
              let newAmount = Double(raw) else {
            subscriptionStore.markChangeAcknowledged(id: change.id)
            return
        }
        // AUDIT-v1.9.2 C-06: route through the store so the accepted price is
        // persisted (direct array mutation never called save() — the new
        // amount rolled back to the old price on relaunch).
        subscriptionStore.acceptNewPrice(id: subID, amount: newAmount)
        subscriptionStore.markChangeAcknowledged(id: change.id)
    }

    private func handleAdd(_ change: SubscriptionChange) {
        // D3 (eng review iter-1): newCharge → pre-filled SubscriptionFormView.
        // Slice 4 wires the routing to open the form. For Slice 3, we take the
        // simple path of using the hydrated form directly.
        guard let form = change.pendingSubscriptionData else {
            subscriptionStore.markChangeAcknowledged(id: change.id)
            return
        }
        subscriptionStore.add(form)
        subscriptionStore.markChangeAcknowledged(id: change.id)
    }

    private func handleIgnore(_ change: SubscriptionChange) {
        subscriptionStore.markChangeAcknowledged(id: change.id)
    }

    private func handleMarkCancelled(_ change: SubscriptionChange) {
        // Slice 6 does the full "Mark cancelled manually" nudge flow (A4).
        // For Slice 3, acknowledge only.
        subscriptionStore.markChangeAcknowledged(id: change.id)
    }
}
