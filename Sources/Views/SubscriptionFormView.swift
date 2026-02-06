import SwiftUI

enum FormMode {
    case add
    case edit(Subscription)
}

struct SubscriptionFormView: View {
    let mode: FormMode
    let onSave: (SubscriptionFormData) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?

    @State private var formData: SubscriptionFormData
    @State private var showDeleteConfirm = false

    init(mode: FormMode, onSave: @escaping (SubscriptionFormData) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete

        switch mode {
        case .add:
            _formData = State(initialValue: SubscriptionFormData())
        case .edit(let sub):
            _formData = State(initialValue: SubscriptionFormData(from: sub))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEdit ? "Edit Subscription" : "Add Subscription")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.bgSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Theme.border)

            // Form
            ScrollView {
                VStack(spacing: 12) {
                    // Name
                    formField("Name") {
                        TextField("e.g. Netflix", text: $formData.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                    }

                    // URL + Logo
                    HStack(spacing: 10) {
                        formField("Website URL") {
                            TextField("https://netflix.com", text: $formData.url)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                        }
                        if !formData.url.isEmpty, let _ = URL(string: formData.url) {
                            LogoView(subscription: previewSubscription, size: 32)
                                .padding(.top, 14)
                        }
                    }

                    // Amount + Currency
                    HStack(spacing: 10) {
                        formField("Amount") {
                            TextField("9.99", text: $formData.amount)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                        }
                        formField("Currency") {
                            Picker("", selection: $formData.currency) {
                                ForEach(AppConstants.currencies, id: \.self) { c in
                                    Text("\(c) \(AppConstants.currencySymbols[c] ?? "")").tag(c)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.textPrimary)
                        }
                        .frame(width: 120)
                    }

                    // Billing Cycle + Billing Day
                    HStack(spacing: 10) {
                        formField("Billing Cycle") {
                            Picker("", selection: $formData.cycle) {
                                ForEach(BillingCycle.allCases) { cycle in
                                    Text(cycle.label).tag(cycle)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.textPrimary)
                        }

                        if formData.cycle != .weekly && formData.cycle != .oneTime {
                            formField("Billing Day") {
                                HStack {
                                    TextField("15", value: $formData.billingDay, format: .number)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textPrimary)
                                        .frame(width: 36)
                                    Stepper("", value: $formData.billingDay, in: 1...31)
                                        .labelsHidden()
                                }
                            }
                            .frame(width: 120)
                        }
                    }

                    // Start Date
                    formField("Start Date") {
                        DatePicker("", selection: $formData.startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Theme.textPrimary)
                    }

                    // Category + Status
                    HStack(spacing: 10) {
                        formField("Category") {
                            Picker("", selection: $formData.category) {
                                ForEach(AppConstants.categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.textPrimary)
                        }

                        formField("Status") {
                            Picker("", selection: $formData.status) {
                                ForEach(SubscriptionStatus.allCases) { status in
                                    Text(status.label).tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.textPrimary)
                        }
                    }

                    // Trial End Date
                    if formData.status == .trial {
                        formField("Trial End Date") {
                            DatePicker("", selection: Binding(
                                get: { formData.trialEndDate ?? Date() },
                                set: { formData.trialEndDate = $0 }
                            ), displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(Theme.textPrimary)
                        }
                    }

                    // Notes
                    formField("Notes") {
                        TextEditor(text: $formData.notes)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(height: 50)
                    }
                }
                .padding(16)
            }

            Divider().background(Theme.border)

            // Action Buttons
            HStack(spacing: 8) {
                if isEdit {
                    Button(action: { showDeleteConfirm = true }) {
                        Text("Delete")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.danger)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    if formData.isValid { onSave(formData) }
                }) {
                    Text(isEdit ? "Save" : "Add")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(formData.isValid ? Theme.bgPrimary : Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(formData.isValid ? Theme.accent : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!formData.isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.bgPrimary)
        .alert("Delete Subscription", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete?() }
        } message: {
            Text("Are you sure you want to delete this subscription?")
        }
    }

    // MARK: - Helpers

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var previewSubscription: Subscription {
        Subscription(
            id: UUID(),
            name: formData.name.isEmpty ? "Preview" : formData.name,
            url: formData.url.isEmpty ? nil : formData.url,
            logo: nil,
            amount: 0,
            currency: formData.currency,
            cycle: formData.cycle,
            billingDay: formData.billingDay,
            startDate: formData.startDate,
            category: formData.category,
            status: formData.status,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @ViewBuilder
    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
    }
}
