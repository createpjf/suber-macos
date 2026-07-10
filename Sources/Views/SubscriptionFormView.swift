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

    /// Called when an image drop produces MORE than one detected subscription
    /// (e.g. a screenshot of iOS Settings > Subscriptions). Caller should
    /// dismiss this add form and route the parses to the multi-review flow.
    var onMultiResult: (([SubscriptionTextParser.ParsedSubscription]) -> Void)?

    @State private var formData: SubscriptionFormData
    @State private var showDeleteConfirm = false
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var showImageInput = false
    @State private var showEmailInput = false
    @State private var showSplit = false
    // AUDIT-v1.9.2 C-38: delayed overlay close must be cancellable — the old
    // asyncAfter callbacks outlived a close/reopen and yanked the fresh panel
    // shut, or wrote to unmounted @State after the popover closed early.
    @State private var overlayDismissTask: Task<Void, Never>? = nil

    init(
        mode: FormMode,
        onSave: @escaping (SubscriptionFormData) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onMultiResult: (([SubscriptionTextParser.ParsedSubscription]) -> Void)? = nil
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onMultiResult = onMultiResult

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
                if !isEdit {
                    // C-38: cancel any stale delayed close so it can't shut the
                    // panel being (re)opened here.
                    Button(action: { overlayDismissTask?.cancel(); showEmailInput = true }) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Theme.bgCell)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Parse billing email text"))
                    .help("Parse billing email text")

                    Button(action: { overlayDismissTask?.cancel(); showImageInput = true }) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Theme.bgCell)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Scan image to auto-fill"))
                    .help("Scan image to auto-fill")
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.bgCell)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                // AUDIT-v1.9.2 U-10: icon-only close button — label the
                // function, not the glyph.
                .accessibilityLabel(Text("Close"))
                .help("Close")
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
                                        .font(.system(size: 10, weight: .bold))
                                        // AUDIT-v1.9.2 U-14: teal now a Theme token.
                                        .foregroundColor(Theme.accentTeal)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.bgPrimary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                // AUDIT-v1.9.2 U-10: icon-only stepper needs a
                                // functional label for VoiceOver.
                                .accessibilityLabel(Text("Decrease price"))
                                .help("Decrease price")

                                HStack(spacing: 2) {
                                    Text(AppConstants.currencySymbols[formData.currency] ?? "$")
                                        .font(AppFont.regular(14))
                                        .foregroundColor(Theme.textSecondary)
                                    TextField("0.0", text: $formData.amount)
                                        .textFieldStyle(.plain)
                                        .font(AppFont.regular(14))
                                        .foregroundColor(Theme.textPrimary)
                                        // AUDIT-v1.9.2 C-39: two-param onChange —
                                        // single-param form is deprecated on macOS 14.
                                        .onChange(of: formData.amount) { _, newValue in
                                            let filtered = newValue.filter { $0.isNumber || $0 == "." }
                                            // Allow only one decimal point
                                            let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
                                            if parts.count > 2 {
                                                formData.amount = String(parts[0]) + "." + String(parts[1])
                                            } else if filtered != newValue {
                                                formData.amount = filtered
                                            }
                                        }
                                }

                                Button(action: { adjustAmount(1) }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Theme.accentTeal)
                                        .frame(width: 24, height: 24)
                                        .background(Theme.bgPrimary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Increase price"))
                                .help("Increase price")
                            }
                        }

                        menuField("Interval", displayText: formData.cycle.label) {
                            ForEach(BillingCycle.allCases) { cycle in
                                Button(cycle.label) { formData.cycle = cycle }
                            }
                        }
                        .frame(width: 150)
                    }

                    // Start date + Billing Day / End date
                    HStack(alignment: .top, spacing: 16) {
                        dateField("Start date", selection: $formData.startDate, showPicker: $showStartDatePicker)

                        if formData.status == .trial {
                            dateField("Trial end", selection: Binding(
                                get: { formData.trialEndDate ?? Date() },
                                set: { formData.trialEndDate = $0 }
                            ), showPicker: $showEndDatePicker)
                        } else if formData.cycle != .weekly && formData.cycle != .oneTime {
                            menuField("Billing day", displayText: "\(formData.billingDay)") {
                                ForEach(1...31, id: \.self) { day in
                                    Button("\(day)") { formData.billingDay = day }
                                }
                            }
                        }
                    }

                    // Category + Status + Currency
                    HStack(alignment: .top, spacing: 16) {
                        // U-02: categories display-localize through
                        // AppConstants.localizedCategory; the stored value
                        // stays the English identifier.
                        menuField("Category", displayText: AppConstants.localizedCategory(formData.category)) {
                            ForEach(AppConstants.categories, id: \.self) { cat in
                                Button(AppConstants.localizedCategory(cat)) { formData.category = cat }
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

                    // Notes
                    field("Notes") {
                        TextField("Optional notes...", text: $formData.notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(AppFont.regular(14))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(3...5)
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
        .overlay {
            // Delete confirmation overlay (replaces .alert to stay within menu bar popover)
            if showDeleteConfirm {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showDeleteConfirm = false }

                    VStack(spacing: 16) {
                        Text("Delete Subscription")
                            .font(AppFont.medium(15))
                            .foregroundColor(Theme.textPrimary)
                        Text("Are you sure you want to delete this subscription?")
                            .font(AppFont.regular(13))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button(action: { showDeleteConfirm = false }) {
                                Text("Cancel")
                                    .font(AppFont.medium(13))
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Theme.bgCell)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            // AUDIT-v1.9.2 U-13: Esc/Return parity with the
                            // NSAlert-backed confirms elsewhere in the app.
                            .keyboardShortcut(.cancelAction)
                            Button(action: {
                                showDeleteConfirm = false
                                onDelete?()
                            }) {
                                Text("Delete")
                                    .font(AppFont.medium(13))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Theme.danger)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            // AUDIT-v1.9.2 U-13 fix-up: no keyboard shortcut on
                            // the destructive button — Apple HIG says
                            // destructive actions must never be the Return-key
                            // default. Esc (bound on Cancel above) is the only
                            // shortcut here.
                        }
                    }
                    .padding(20)
                    .background(Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 10)
                    .padding(.horizontal, 30)
                }
            }
        }
        .overlay {
            if showImageInput {
                ImageDropZoneView(
                    onResult: { parsedList in
                        if parsedList.count > 1, let onMultiResult = onMultiResult {
                            // Multi-subscription screenshot — close this form
                            // and hand off to the multi-review flow above us.
                            showImageInput = false
                            onMultiResult(parsedList)
                        } else if let first = parsedList.first {
                            applyParsedData(first)
                        }
                    },
                    onCancel: { showImageInput = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showImageInput)
        .overlay {
            if showEmailInput {
                EmailParseView(
                    onResult: { parsed in
                        applyParsedData(parsed)
                        // C-38: cancellable — replaces asyncAfter.
                        scheduleOverlayDismiss(after: 0.5) { showEmailInput = false }
                    },
                    onCancel: { showEmailInput = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showEmailInput)
    }

    // MARK: - Image Scan

    private func applyParsedData(_ parsed: SubscriptionTextParser.ParsedSubscription) {
        if let name = parsed.name { formData.name = name }
        if let url = parsed.url { formData.url = url }
        if let amount = parsed.amount { formData.amount = amount }
        if let currency = parsed.currency { formData.currency = currency }
        if let cycle = parsed.cycle { formData.cycle = cycle }
        if let startDate = parsed.startDate { formData.startDate = startDate }
        if let trialEndDate = parsed.trialEndDate { formData.trialEndDate = trialEndDate }
        if let category = parsed.category { formData.category = category }
        if let status = parsed.status { formData.status = status }

        // Dismiss the image input after a brief delay so user sees the success
        // message. C-38: cancellable — replaces asyncAfter.
        scheduleOverlayDismiss(after: 1.0) { showImageInput = false }
    }

    /// AUDIT-v1.9.2 C-38: single-slot delayed close. Scheduling cancels any
    /// prior pending close; the open buttons cancel it too, so a stale
    /// callback can never close a newly reopened panel or write to @State
    /// after cancellation.
    private func scheduleOverlayDismiss(after seconds: Double, _ close: @escaping () -> Void) {
        overlayDismissTask?.cancel()
        overlayDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            close()
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

    // AUDIT-v1.9.2 U-03: the three field-label params below are
    // LocalizedStringKey (were String) — all call sites pass literals, and
    // Text(String) skipped the catalog so the form stayed English for zh users.
    @ViewBuilder
    private func field<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func dateField(_ label: LocalizedStringKey, selection: Binding<Date>, showPicker: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
            Button(action: { showPicker.wrappedValue.toggle() }) {
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
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .popover(isPresented: showPicker) {
                VStack(spacing: 6) {
                    DatePicker("", selection: selection, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .focusable(false)

                    Button(action: {
                        selection.wrappedValue = Date()
                    }) {
                        Text("Today")
                            .font(AppFont.medium(12))
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Theme.bgCell)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func menuField<MenuContent: View>(_ label: LocalizedStringKey, displayText: String, @ViewBuilder content: () -> MenuContent) -> some View {
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
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // AUDIT-v1.9.2 U-17: the fixed "yyyy/MM/dd" pattern was one of ~10 date
    // formats in the app and didn't reorder for zh. Route through the shared
    // locale-aware formatter. The unused longDateFormatter was dead code.
    private func formatDate(_ date: Date) -> String {
        DateHelpers.formatDate(date)
    }
}
