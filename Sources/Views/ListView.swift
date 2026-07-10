import SwiftUI

enum SortBy: String, CaseIterable, Identifiable {
    case nextBilling = "Next Billing"
    case name = "Name"
    case amount = "Amount"
    case dateAdded = "Date Added"

    var id: String { rawValue }

    /// AUDIT-v1.9.2 U-03: rawValue rendered as a runtime String and bypassed
    /// the String Catalog. rawValue stays the stable identifier; display goes
    /// through these literal keys (identical English copy).
    var label: LocalizedStringKey {
        switch self {
        case .nextBilling: return "Next Billing"
        case .name: return "Name"
        case .amount: return "Amount"
        case .dateAdded: return "Date Added"
        }
    }
}

struct ListView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    /// v1.8.0: popover-root overlay coordinator. CancelConfirmationSheet
    /// is now pushed via overlayPresenter.present rather than .popoverOverlay
    /// on this view (which caused inline rendering — see OverlayPresenter docs).
    @EnvironmentObject var overlayPresenter: OverlayPresenter
    let onEdit: (Subscription) -> Void

    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var sortBy: SortBy = .nextBilling

    var body: some View {
        VStack(spacing: 6) {
            // Search + Filter
            VStack(spacing: 6) {
                SearchBarView(text: $searchText)

                HStack {
                    FilterBarView(selected: $statusFilter)
                    Menu {
                        ForEach(SortBy.allCases) { sort in
                            Button(action: { sortBy = sort }) {
                                if sort == sortBy {
                                    Label(sort.label, systemImage: "checkmark")
                                } else {
                                    Text(sort.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortBy.label)
                                .font(AppFont.regular(12))
                                .foregroundColor(Theme.textPrimary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // List
            if filteredSubscriptions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    // AUDIT-v1.9.2 U-16: SF Symbols instead of emoji — matches
                    // the Dashboard/Restore/Changes empty states and follows
                    // appearance + text color.
                    Image(systemName: subscriptionStore.subscriptions.isEmpty ? "shippingbox" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Theme.textDim)
                    Text(subscriptionStore.subscriptions.isEmpty ? "No subscriptions yet" : "No matching subscriptions")
                        .font(AppFont.regular(13))
                        .foregroundColor(Theme.textSecondary)
                    if subscriptionStore.subscriptions.isEmpty {
                        Text("Tap + to add your first one")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.textDim)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredSubscriptions) { sub in
                            SubCardView(
                                subscription: sub,
                                onOpenCancelPage: { presentCancelConfirmation(for: sub) },
                                // AUDIT-v1.9.2 U-16: edit affordance (hover
                                // cursor + context-menu entry) for the
                                // tap-to-edit card.
                                onEdit: { onEdit(sub) }
                            )
                            .environmentObject(subscriptionStore)
                            .onTapGesture { onEdit(sub) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        // v1.8.0: CancelConfirmationSheet 走 OverlayPresenter，由
        // MenuBarView 根节点渲染（见 OverlayPresenter.swift header）。
    }

    /// v1.8.0: presents CancelConfirmationSheet via OverlayPresenter so it
    /// renders at popover root (not inline at section bounds).
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
                    markSubscriptionCancelledManually(sub)
                },
                onCancel: { overlayPresenter.dismiss() }
            )
        )
    }

    /// A4: true if Suber has a data source that can verify an auto-transition.
    /// Drives the confirmation sheet's honesty — we only promise "Suber will
    /// check next month" when we actually can.
    private var hasDataSource: Bool {
        if settingsStore.settings.autopilot.watchAppleMail { return true }
        // CSV-only user: if they've ever imported one, the next import will
        // cover the window. Heuristic: any change sourced from csvImport in
        // the last 90 days → yes, they use CSV.
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return subscriptionStore.changes.contains { change in
            change.source == .csvImport && change.detectedAt >= threshold
        }
    }

    private func markSubscriptionCancelledManually(_ sub: Subscription) {
        subscriptionStore.markCancelledManually(id: sub.id)
    }

    private var filteredSubscriptions: [Subscription] {
        var subs = subscriptionStore.subscriptions

        // Filter by status
        if statusFilter != "all" {
            subs = subs.filter { $0.status.rawValue == statusFilter }
        }

        // Filter by search text (matches name, category, url, and notes)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            subs = subs.filter {
                $0.name.lowercased().contains(query) ||
                $0.category.lowercased().contains(query) ||
                ($0.url?.lowercased().contains(query) ?? false) ||
                ($0.notes?.lowercased().contains(query) ?? false)
            }
        }

        // Sort
        switch sortBy {
        case .name:
            subs.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .amount:
            subs.sort { $0.amount > $1.amount }
        case .nextBilling:
            // Pre-compute billing dates to avoid O(2N log N) redundant calculations.
            // SAFETY-01: dictionary contains every sub.id by construction, but
            // nil-coalesce defends against future filtering between the
            // Dictionary build and the sort closure.
            let billingDates = Dictionary(uniqueKeysWithValues: subs.map { ($0.id, BillingCalculator.getNextBillingDate($0)) })
            subs.sort { (billingDates[$0.id] ?? .distantFuture) < (billingDates[$1.id] ?? .distantFuture) }
        case .dateAdded:
            subs.sort { $0.createdAt > $1.createdAt }
        }

        return subs
    }
}
