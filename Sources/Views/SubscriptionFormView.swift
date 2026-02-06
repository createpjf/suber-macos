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
                Text(isEdit ? "Edit subscription" : "Add subscription")
                    .font(AppFont.medium(16))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.bgCell)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Service
                    field("Service") {
                        TextField("Netflix, Spotify...", text: $formData.name)
                            .textFieldStyle(.plain)
                            .font(AppFont.regular(14))
                            .foregroundColor(Theme.textPrimary)
                    }

                    // Domain
                    field("Domain") {
                        TextField("netflix.com", text: $formData.url)
                            .textFieldStyle(.plain)
                            .font(AppFont.regular(14))
                            .foregroundColor(Theme.textPrimary)
                    }

                    // Price + Interval
                    HStack(alignment: .top, spacing: 16) {
                        field("Price") {
                            HStack(spacing: 6) {
                                Button(action: { adjustAmount(-1) }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(hex: "38b2ac"))
                                        .frame(width: 28, height: 28)
                                        .background(Theme.bgPrimary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)

                                HStack(spacing: 2) {
                                    Text(AppConstants.currencySymbols[formData.currency] ?? "$")
                                        .font(AppFont.regular(14))
                                        .foregroundColor(Theme.textSecondary)
                                    TextField("0.0", text: $formData.amount)
                                        .textFieldStyle(.plain)
                                        .font(AppFont.regular(14))
                                        .foregroundColor(Theme.textPrimary)
                                }

                                Button(action: { adjustAmount(1) }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(hex: "38b2ac"))
                                        .frame(width: 28, height: 28)
                                        .background(Theme.bgPrimary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        menuField("Interval", displayText: formData.cycle.label) {
                            ForEach(BillingCycle.allCases) { cycle in
                                Button(cycle.label) { formData.cycle = cycle }
                            }
                        }
                        .frame(width: 150)
                    }

                    // Start date + End date
                    HStack(alignment: .top, spacing: 16) {
                        dateField("Start date", selection: $formData.startDate)
                        dateField("End date", selection: Binding(
                            get: { formData.trialEndDate ?? Date() },
                            set: { formData.trialEndDate = $0 }
                        ))
                    }

                    // Category + Status + Currency
                    HStack(alignment: .top, spacing: 16) {
                        menuField("Category", displayText: formData.category) {
                            ForEach(AppConstants.categories, id: \.self) { cat in
                                Button(cat) { formData.category = cat }
                            }
                        }

                        menuField("Status", displayText: formData.status.label) {
                            ForEach(SubscriptionStatus.allCases) { status in
                                Button(status.label) { formData.status = status }
                            }
                        }

                        menuField("Currency", displayText: "\(AppConstants.currencySymbols[formData.currency] ?? "") \(formData.currency)") {
                            ForEach(AppConstants.currencies, id: \.self) { c in
                                Button("\(AppConstants.currencySymbols[c] ?? "") \(c)") { formData.currency = c }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            // Buttons
            HStack(spacing: 10) {
                if isEdit {
                    Button(action: { showDeleteConfirm = true }) {
                        Text("Delete")
                            .font(AppFont.medium(14))
                            .foregroundColor(Theme.danger)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Theme.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppFont.medium(14))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: {
                    if formData.isValid { onSave(formData) }
                }) {
                    Text("Save")
                        .font(AppFont.medium(14))
                        .foregroundColor(formData.isValid ? Theme.bgPrimary : Theme.textDim)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(formData.isValid ? Theme.accent : Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!formData.isValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
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

    private func adjustAmount(_ delta: Double) {
        let current = Double(formData.amount) ?? 0
        let newVal = max(0, current + delta)
        if newVal == floor(newVal) {
            formData.amount = String(format: "%.0f", newVal)
        } else {
            formData.amount = String(format: "%.2f", newVal)
        }
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

    // MARK: - Field Components

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func dateField(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
            ZStack {
                // Visible layout: date text on left, chevron on right
                HStack {
                    Text(formatDate(selection.wrappedValue))
                        .font(AppFont.regular(14))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // Hidden DatePicker overlay for interaction
                DatePicker("", selection: selection, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .blendMode(.destinationOver)
                    .opacity(0.015)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCell)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func menuField<MenuContent: View>(_ label: String, displayText: String, @ViewBuilder content: () -> MenuContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
            Menu {
                content()
            } label: {
                HStack {
                    Text(displayText)
                        .font(AppFont.regular(14))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
