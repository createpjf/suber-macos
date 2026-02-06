import SwiftUI

enum SortBy: String, CaseIterable, Identifiable {
    case nextBilling = "Next Billing"
    case name = "Name"
    case amount = "Amount"
    case dateAdded = "Date Added"

    var id: String { rawValue }
}

struct ListView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
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
                    Picker("", selection: $sortBy) {
                        ForEach(SortBy.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .tint(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            // List
            if filteredSubscriptions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text(subscriptionStore.subscriptions.isEmpty ? "📦" : "🔍")
                        .font(.system(size: 32))
                    Text(subscriptionStore.subscriptions.isEmpty ? "No subscriptions yet" : "No matching subscriptions")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    if subscriptionStore.subscriptions.isEmpty {
                        Text("Tap + to add your first one")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textDim)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredSubscriptions) { sub in
                            SubCardView(subscription: sub)
                                .onTapGesture { onEdit(sub) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var filteredSubscriptions: [Subscription] {
        var subs = subscriptionStore.subscriptions

        // Filter by status
        if statusFilter != "all" {
            subs = subs.filter { $0.status.rawValue == statusFilter }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            subs = subs.filter {
                $0.name.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        // Sort
        switch sortBy {
        case .name:
            subs.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .amount:
            subs.sort { $0.amount > $1.amount }
        case .nextBilling:
            subs.sort { BillingCalculator.getNextBillingDate($0) < BillingCalculator.getNextBillingDate($1) }
        case .dateAdded:
            subs.sort { $0.createdAt > $1.createdAt }
        }

        return subs
    }
}
