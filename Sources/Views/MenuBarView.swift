import SwiftUI

enum AppView: Hashable {
    case calendar
    case list
    case settings
}

struct MenuBarView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var currentView: AppView = .calendar
    @State private var showAddForm = false
    @State private var editingSubscription: Subscription?

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                TopBarView(
                    currentView: $currentView,
                    onAdd: { showAddForm = true }
                )

                Divider()
                    .background(Theme.border)

                switch currentView {
                case .calendar:
                    CalendarView(onEdit: { editingSubscription = $0 })
                        .frame(maxWidth: .infinity)
                case .list:
                    ListView(onEdit: { editingSubscription = $0 })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .settings:
                    SettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Add form overlay (replaces .sheet to avoid closing the popover)
            if showAddForm {
                formOverlay {
                    SubscriptionFormView(mode: .add) { data in
                        subscriptionStore.add(data)
                        showAddForm = false
                    } onCancel: {
                        showAddForm = false
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Edit form overlay
            if let sub = editingSubscription {
                formOverlay {
                    SubscriptionFormView(mode: .edit(sub)) { data in
                        subscriptionStore.update(id: sub.id, with: data)
                        editingSubscription = nil
                    } onCancel: {
                        editingSubscription = nil
                    } onDelete: {
                        subscriptionStore.delete(id: sub.id)
                        editingSubscription = nil
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Theme.bgPrimary)
        .clipped()
        .animation(.easeOut(duration: 0.2), value: showAddForm)
        .animation(.easeOut(duration: 0.2), value: editingSubscription?.id)
    }

    @ViewBuilder
    private func formOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bgPrimary)
    }
}
