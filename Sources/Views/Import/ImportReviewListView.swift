import SwiftUI

/// Shows detected subscription candidates for the user to confirm before adding.
/// - High-confidence candidates default to selected.
/// - Low-confidence defaults off, with inline name + category edit.
/// - Candidates that already exist in the user's list are shown as dimmed, default off.
struct ImportReviewListView: View {
    let candidates: [CandidateSubscription]
    let existingSubscriptions: [Subscription]
    let onAdd: ([SubscriptionFormData]) -> Void
    let onCancel: () -> Void

    /// Per-candidate UI state (user can toggle selection + tweak name / category).
    @State private var rows: [ReviewRow]
    @State private var showLowConfidence = false

    init(
        candidates: [CandidateSubscription],
        existingSubscriptions: [Subscription],
        onAdd: @escaping ([SubscriptionFormData]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.existingSubscriptions = existingSubscriptions
        self.onAdd = onAdd
        self.onCancel = onCancel

        let existingKeys = Set(existingSubscriptions.map { $0.name.lowercased() })

        _rows = State(initialValue: candidates.map { c in
            let alreadyAdded = existingKeys.contains(c.name.lowercased())
            let selected = !alreadyAdded && c.confidence != .low
            return ReviewRow(
                candidate: c,
                name: c.name,
                category: c.category ?? "Other",
                isSelected: selected,
                alreadyAdded: alreadyAdded
            )
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(visibleRows) { row in
                        RowView(
                            row: binding(for: row.id),
                            onSelect: { toggle(row.id) }
                        )
                    }

                    if hiddenLowConfidenceCount > 0 {
                        Button(action: { showLowConfidence.toggle() }) {
                            Text(showLowConfidence
                                 ? "Hide low-confidence matches"
                                 : "Show \(hiddenLowConfidenceCount) low-confidence match\(hiddenLowConfidenceCount == 1 ? "" : "es")")
                                .font(AppFont.regular(11))
                                .foregroundColor(Theme.textDim)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }

            Divider().background(Theme.border)
            footer
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack {
            Text("Found \(candidates.count) possible subscription\(candidates.count == 1 ? "" : "s")")
                .font(AppFont.regular(12))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button(action: toggleSelectAll) {
                Text(allSelectableAreSelected ? "Deselect all" : "Select all")
                    .font(AppFont.medium(12))
                    .foregroundColor(Theme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.bgSecondary.opacity(0.5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: commit) {
                Text(selectedCount > 0
                     ? "Add \(selectedCount) subscription\(selectedCount == 1 ? "" : "s")"
                     : "Add subscriptions")
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedCount > 0 ? Theme.textPrimary : Theme.textDim)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Data helpers

    private var visibleRows: [ReviewRow] {
        showLowConfidence ? rows : rows.filter { $0.candidate.confidence != .low }
    }

    private var hiddenLowConfidenceCount: Int {
        rows.filter { $0.candidate.confidence == .low }.count
    }

    private var selectedCount: Int { rows.filter { $0.isSelected }.count }

    private var allSelectableAreSelected: Bool {
        let selectable = rows.filter { !$0.alreadyAdded }
        return !selectable.isEmpty && selectable.allSatisfy { $0.isSelected }
    }

    private func binding(for id: UUID) -> Binding<ReviewRow> {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else {
            fatalError("Row \(id) not found")
        }
        return $rows[idx]
    }

    private func toggle(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        guard !rows[idx].alreadyAdded else { return }
        rows[idx].isSelected.toggle()
    }

    private func toggleSelectAll() {
        let targetState = !allSelectableAreSelected
        for i in rows.indices where !rows[i].alreadyAdded {
            rows[i].isSelected = targetState
        }
    }

    private func commit() {
        let selected = rows.filter { $0.isSelected }
        let forms = selected.map { row -> SubscriptionFormData in
            var form = SubscriptionFormData()
            form.name = row.name
            form.amount = formatAmount(row.candidate.amount)
            form.currency = row.candidate.currency
            form.cycle = row.candidate.cycle
            form.billingDay = row.candidate.billingDay
            form.startDate = row.candidate.startDate
            form.category = row.category
            form.status = .active
            return form
        }
        onAdd(forms)
    }

    private func formatAmount(_ d: Double) -> String {
        d == floor(d) ? String(format: "%.0f", d) : String(format: "%.2f", d)
    }
}

// MARK: - Row model

struct ReviewRow: Identifiable {
    var id: UUID { candidate.id }
    let candidate: CandidateSubscription
    var name: String
    var category: String
    var isSelected: Bool
    var alreadyAdded: Bool
}

// MARK: - Row view

private struct RowView: View {
    @Binding var row: ReviewRow
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: row.alreadyAdded
                      ? "circle.slash"
                      : (row.isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 16))
                    .foregroundColor(checkboxColor)
            }
            .buttonStyle(.plain)
            .disabled(row.alreadyAdded)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Name", text: $row.name)
                        .textFieldStyle(.plain)
                        .font(AppFont.medium(13))
                        .foregroundColor(textColor)
                        .disabled(row.alreadyAdded)
                    Spacer()
                    Text(amountLabel)
                        .font(AppFont.medium(13))
                        .foregroundColor(textColor)
                }

                HStack(spacing: 6) {
                    confidenceBadge
                    Text(subtitleText)
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)

                    Spacer()

                    if !row.alreadyAdded {
                        Menu {
                            ForEach(AppConstants.categories, id: \.self) { cat in
                                Button(cat) { row.category = cat }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(row.category)
                                    .font(AppFont.regular(11))
                                    .foregroundColor(Theme.textSecondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Theme.textDim)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, lineWidth: 1)
        )
        .opacity(row.alreadyAdded ? 0.5 : 1)
    }

    // MARK: - Derived

    private var checkboxColor: Color {
        if row.alreadyAdded { return Theme.textDim }
        return row.isSelected ? Theme.textPrimary : Theme.textDim
    }

    private var textColor: Color {
        row.alreadyAdded ? Theme.textDim : Theme.textPrimary
    }

    private var amountLabel: String {
        let symbol = AppConstants.currencySymbols[row.candidate.currency] ?? ""
        let amt = row.candidate.amount
        let amtStr = amt == floor(amt) ? String(format: "%.0f", amt) : String(format: "%.2f", amt)
        return "\(symbol)\(amtStr)\(row.candidate.cycle.shortLabel)"
    }

    private var subtitleText: String {
        if row.alreadyAdded { return "Already in your list" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        // occurrences == 1 means this came from a one-shot OCR parse, not a
        // multi-transaction CSV run — show a screenshot-oriented subtitle.
        if row.candidate.occurrences == 1 {
            return "From screenshot · renews \(formatter.string(from: row.candidate.startDate))"
        }
        let last = formatter.string(from: row.candidate.lastChargeDate)
        return "\(row.candidate.occurrences) charges · last \(last)"
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        if !row.alreadyAdded {
            let (label, color): (String, Color) = {
                switch row.candidate.confidence {
                case .high: return ("High", Theme.success)
                case .medium: return ("Med", Theme.warning)
                case .low: return ("Low", Theme.textDim)
                }
            }()
            Text(label)
                .font(AppFont.medium(9))
                .foregroundColor(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
