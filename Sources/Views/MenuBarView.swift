import SwiftUI

enum AppView: Hashable {
    case calendar
    case list
    case dashboard
    case settings
}

struct MenuBarView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var importPresenter: ImportPresenter

    /// Opens the "Import Subscriptions" Window scene declared in SuberApp.
    /// We keep import flows in a separate window so TCC / file-picker / system
    /// notification dialogs stack above them correctly — the MenuBarExtra
    /// popover has a higher window level than modal alerts and would otherwise
    /// occlude them.
    @Environment(\.openWindow) private var openWindow

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
                case .dashboard:
                    DashboardView(
                        onAdd: { showAddForm = true },
                        onImport: startBankImport
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .settings:
                    SettingsView(onImport: startBankImport)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Add form overlay (still in-popover — single-sub add is lightweight
            // and doesn't touch the file system).
            if showAddForm {
                formOverlay {
                    SubscriptionFormView(
                        mode: .add,
                        onSave: { data in
                            subscriptionStore.add(data)
                            showAddForm = false
                        },
                        onCancel: { showAddForm = false },
                        onDelete: nil,
                        onMultiResult: { parsedList in
                            // OCR'd N subscriptions from a screenshot — punt
                            // the review flow to the separate window so
                            // system dialogs can stack above it.
                            let candidates = parsedList.map(candidateFromParsed)
                            showAddForm = false
                            importPresenter.showCandidates(candidates)
                            openWindow(id: "import")
                        }
                    )
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

    // MARK: - Import triggers

    private func startBankImport() {
        importPresenter.showBankStatement()
        openWindow(id: "import")
    }

    @ViewBuilder
    private func formOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bgPrimary)
    }

    /// Converts a single-image parse into the CandidateSubscription shape the
    /// review UI already speaks. Since OCR can't tell us recurrence history,
    /// we synthesize `occurrences: 1` + `lastChargeDate: startDate` and let
    /// `confidence` reflect whether the parse captured both name and amount.
    private func candidateFromParsed(_ parsed: SubscriptionTextParser.ParsedSubscription) -> CandidateSubscription {
        let name = parsed.name ?? "Untitled"
        let amount = Double(parsed.amount ?? "0") ?? 0
        let currency = parsed.currency ?? settingsStore.settings.primaryCurrency
        let startDate = parsed.startDate ?? Date()
        let hasBoth = parsed.name != nil && parsed.amount != nil
        return CandidateSubscription(
            name: name,
            normalizedMerchant: MerchantNormalizer.normalize(name),
            sampleMerchantRaw: name,
            amount: amount,
            currency: currency,
            cycle: parsed.cycle ?? .monthly,
            billingDay: Calendar.current.component(.day, from: startDate),
            startDate: startDate,
            lastChargeDate: startDate,
            category: parsed.category,
            occurrences: 1,
            confidence: hasBoth ? .high : .medium
        )
    }
}
