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

    @State private var currentView: AppView = .calendar
    @State private var showAddForm = false
    @State private var editingSubscription: Subscription?
    @State private var showBankImport = false

    /// Candidates from an OCR'd multi-subscription screenshot, pending review.
    /// Setting this to non-nil displays the `ImportReviewListView` overlay;
    /// same component used for the bank-statement import flow.
    @State private var ocrMultiCandidates: [CandidateSubscription]?

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
                        onImport: { showBankImport = true }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .settings:
                    SettingsView(onImport: { showBankImport = true })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Add form overlay (replaces .sheet to avoid closing the popover)
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
                            ocrMultiCandidates = parsedList.map(candidateFromParsed)
                        }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Bank-statement import overlay
            if showBankImport {
                formOverlay {
                    BankImportView(
                        existingSubscriptions: subscriptionStore.subscriptions,
                        onAdd: { forms in
                            for data in forms {
                                subscriptionStore.add(data)
                            }
                            showBankImport = false
                        },
                        onCancel: { showBankImport = false }
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // OCR multi-subscription review overlay — same review UI as the
            // bank-statement flow, populated from parsed screenshot text.
            if let candidates = ocrMultiCandidates {
                formOverlay {
                    ImportReviewListView(
                        candidates: candidates,
                        existingSubscriptions: subscriptionStore.subscriptions,
                        onAdd: { forms in
                            for data in forms {
                                subscriptionStore.add(data)
                            }
                            ocrMultiCandidates = nil
                        },
                        onCancel: { ocrMultiCandidates = nil }
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
        .animation(.easeOut(duration: 0.2), value: showBankImport)
        .animation(.easeOut(duration: 0.2), value: ocrMultiCandidates == nil)
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
