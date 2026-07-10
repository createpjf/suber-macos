import SwiftUI

struct EmailParseView: View {
    let onResult: (SubscriptionTextParser.ParsedSubscription) -> Void
    let onCancel: () -> Void

    @State private var emailText = ""
    @State private var parsed: SubscriptionTextParser.ParsedSubscription?
    @State private var hasParsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Paste billing email")
                    .font(AppFont.medium(15))
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

            if !hasParsed {
                // Input area
                VStack(spacing: 12) {
                    TextEditor(text: $emailText)
                        .font(AppFont.regular(12))
                        .foregroundColor(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(maxHeight: .infinity)
                        .background(Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            Group {
                                if emailText.isEmpty {
                                    Text("Paste your billing email or receipt text here...")
                                        .font(AppFont.regular(12))
                                        .foregroundColor(Theme.textDim)
                                        .padding(14)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )

                    Button(action: parseText) {
                        Text("Parse")
                            .font(AppFont.medium(14))
                            .foregroundColor(emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.textDim : Theme.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.bgCell : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            } else if let result = parsed {
                // Results preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        resultRow("Service", value: result.name)
                        resultRow("Amount", value: result.amount.map { amt in
                            let sym = result.currency.flatMap { AppConstants.currencySymbols[$0] } ?? ""
                            return "\(sym)\(amt)"
                        })
                        resultRow("Currency", value: result.currency)
                        resultRow("Cycle", value: result.cycle?.label)
                        resultRow("Category", value: result.category)
                        resultRow("Domain", value: result.url)

                        if result.name == nil && result.amount == nil {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.warning)
                                Text("Could not extract subscription details. Try pasting more text.")
                                    .font(AppFont.regular(12))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Action buttons
                HStack(spacing: 10) {
                    Button(action: {
                        hasParsed = false
                        parsed = nil
                    }) {
                        Text("Back")
                            .font(AppFont.medium(14))
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.bgCell)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        onResult(result)
                    }) {
                        Text("Apply")
                            .font(AppFont.medium(14))
                            .foregroundColor(Theme.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.bgPrimary)
    }

    private func parseText() {
        let trimmed = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parsed = SubscriptionTextParser.parse(trimmed)
        hasParsed = true
    }

    @ViewBuilder
    // AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — literal labels.
    private func resultRow(_ label: LocalizedStringKey, value: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: value != nil ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12))
                .foregroundColor(value != nil ? Theme.success : Theme.textDim)
            Text(label)
                .font(AppFont.medium(12))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value ?? "—")
                .font(AppFont.regular(12))
                .foregroundColor(value != nil ? Theme.textPrimary : Theme.textDim)
                .lineLimit(1)
            Spacer()
        }
    }
}
