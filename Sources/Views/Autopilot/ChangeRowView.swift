import SwiftUI

// ┌───────────── ChangeRowView — decision prompt, not log line ────────────────┐
// │                                                                            │
// │  Design review D4 (I1): the 80%-of-the-time row users see in the Changes  │
// │  Window. Renders as a decision surface with delta math DONE for the user   │
// │  and the primary action INLINE — not a ledger-style log entry.             │
// │                                                                            │
// │  Shape:                                                                    │
// │    ┌──────────────────────────────────────────────────────────────────┐    │
// │    │ [icon]  Netflix raised to $22.99/mo                              │    │
// │    │         was $15.99 · +44% · +$84/year                            │    │
// │    │                               [Open cancel page] [Ignore]        │    │
// │    └──────────────────────────────────────────────────────────────────┘    │
// │                                                                            │
// │  Type-specific variants share the same hierarchy:                          │
// │    - priceChange (up/down): orange ↗ / green ↘                             │
// │    - newCharge: blue + [Add subscription]                                  │
// │    - duplicate: yellow + [Open service] [Dismiss]                          │
// │    - trialExpiring: purple + [Open cancel page] [Keep]                     │
// │    - cancellationConfirmed: green log-style (subdued single line)          │
// │    - cancellationFailed: red warning + [Try again] [Mark cancelled manually]│
// │                                                                            │
// │  Row height ≈ 72pt (decision prompt), 44pt (confirmed log variant).        │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct ChangeRowView: View {
    let change: SubscriptionChange
    let subscription: Subscription?     // nil for .newCharge (hydrated via pendingSubscriptionData)
    let primaryCurrency: String         // for annual-savings display

    let onOpenCancelPage: () -> Void
    let onAcceptNewPrice: () -> Void
    let onAdd: () -> Void               // .newCharge → pre-filled SubscriptionFormView
    let onIgnore: () -> Void
    let onDismiss: () -> Void           // for duplicate / confirmed rows
    let onMarkCancelledManually: () -> Void

    var body: some View {
        switch change.type {
        case .priceChange:       priceChangeRow
        case .newCharge:         newChargeRow
        case .duplicate:         duplicateRow
        case .trialExpiring:     trialExpiringRow
        case .cancellationConfirmed: confirmedLogRow
        case .cancellationFailed:    failedRow
        }
    }

    // MARK: - priceChange (hero row)

    @ViewBuilder private var priceChangeRow: some View {
        let direction = priceDirection
        let isIncrease = direction > 0
        let iconSymbol = isIncrease ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
        let tint: Color = isIncrease ? .orange : .green

        rowShell(icon: iconSymbol, tint: tint) {
            VStack(alignment: .leading, spacing: 2) {
                // Hero line: "{Service} raised to $22.99/mo" (or "lowered to")
                Text(priceChangeHeadline)
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                // Supporting line: "was $15.99 · +44% · +$84/year"
                Text(priceChangeSupport)
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            if isIncrease {
                Button("Open cancel page") { onOpenCancelPage(); markAck() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Accept") { onAcceptNewPrice(); markAck() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                // Price drop: no cancel action, just acknowledge.
                Button("Accept") { onAcceptNewPrice(); markAck() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button("Ignore") { onIgnore(); markAck() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - newCharge row

    @ViewBuilder private var newChargeRow: some View {
        rowShell(icon: "plus.circle.fill", tint: .blue) {
            VStack(alignment: .leading, spacing: 2) {
                Text(newChargeHeadline)
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(newChargeSupport)
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            Button("Add subscription") { onAdd() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Ignore") { onIgnore(); markAck() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - duplicate row

    @ViewBuilder private var duplicateRow: some View {
        rowShell(icon: "exclamationmark.2", tint: .yellow) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Possible duplicate charge")
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(change.newValue ?? "")
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            Button("Dismiss") { onDismiss(); markAck() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - trialExpiring row

    @ViewBuilder private var trialExpiringRow: some View {
        rowShell(icon: "hourglass.circle.fill", tint: .purple) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trialExpiringHeadline)
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(trialExpiringSupport)
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            if subscription != nil {
                Button("Open cancel page") { onOpenCancelPage(); markAck() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button("Keep") { onIgnore(); markAck() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - cancellationConfirmed (subdued, log-style)

    @ViewBuilder private var confirmedLogRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 24)
            Text(confirmedHeadline)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(relativeDate(change.detectedAt))
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textDim)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Theme.bgSecondary)
    }

    // MARK: - cancellationFailed (warning row)

    @ViewBuilder private var failedRow: some View {
        rowShell(icon: "xmark.octagon.fill", tint: .red) {
            VStack(alignment: .leading, spacing: 2) {
                Text(failedHeadline)
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(failedSupport)
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            Button("Try again") { onOpenCancelPage(); markAck() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("Mark cancelled manually") { onMarkCancelledManually(); markAck() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Shared shell

    @ViewBuilder
    private func rowShell<Content: View, Trailing: View>(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28)
            content()
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .frame(maxWidth: .infinity)
        .background(Theme.bgSecondary)
        .overlay(
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Copy helpers

    private var serviceName: String {
        subscription?.name ?? change.pendingSubscriptionData?.name ?? "Subscription"
    }

    /// Signed Double (new − prev) in the sub's display currency. Positive = rise.
    private var priceDirection: Double {
        guard let prev = parseAmount(change.previousValue),
              let curr = parseAmount(change.newValue) else { return 0 }
        return curr - prev
    }

    private var priceChangeHeadline: String {
        guard let curr = parseAmount(change.newValue) else {
            return "\(serviceName) price changed"
        }
        let currency = parseCurrency(change.newValue) ?? subscription?.currency ?? primaryCurrency
        let cycleLabel = subscription?.cycle.shortLabel ?? ""
        let priceStr = String(format: "%.2f", curr)
        let verb = priceDirection >= 0 ? "raised to" : "lowered to"
        return "\(serviceName) \(verb) \(symbol(for: currency))\(priceStr)\(cycleLabel)"
    }

    private var priceChangeSupport: String {
        guard let prev = parseAmount(change.previousValue),
              let curr = parseAmount(change.newValue) else { return "" }
        let prevStr = String(format: "%.2f", prev)
        let currency = parseCurrency(change.previousValue) ?? subscription?.currency ?? primaryCurrency
        let pct = prev > 0 ? Int(((curr - prev) / prev * 100).rounded()) : 0
        let sign = pct >= 0 ? "+" : ""
        let annualSavings = annualImpact()
        let annualStr = annualSavings >= 0 ? "+$\(annualSavings)/year" : "-$\(-annualSavings)/year"
        return "was \(symbol(for: currency))\(prevStr) · \(sign)\(pct)% · \(annualStr)"
    }

    private var newChargeHeadline: String {
        let hydratedName = change.pendingSubscriptionData?.name ?? "Unknown service"
        return "New sub: \(hydratedName)"
    }

    private var newChargeSupport: String {
        guard let data = change.pendingSubscriptionData else { return change.newValue ?? "" }
        let amount = data.amount.isEmpty ? "?" : data.amount
        return "\(symbol(for: data.currency))\(amount)\(data.cycle.shortLabel) · detected via \(sourceLabel)"
    }

    private var trialExpiringHeadline: String {
        "\(serviceName) trial ending"
    }

    private var trialExpiringSupport: String {
        change.newValue ?? "Trial ends soon"
    }

    private var confirmedHeadline: String {
        let annual = annualImpact()
        let savings = annual != 0 ? " · saved $\(abs(annual))/year" : ""
        return "✓ Cancelled: \(serviceName)\(savings)"
    }

    private var failedHeadline: String {
        "\(serviceName) didn't cancel — still active"
    }

    private var failedSupport: String {
        "Charge detected after cancellation window"
    }

    // MARK: - Parsing helpers

    private func parseAmount(_ raw: String?) -> Double? {
        guard let raw = raw else { return nil }
        // Format stored is "22.99 USD" or similar. Split on space, first is number.
        let first = raw.split(separator: " ").first.map(String.init) ?? raw
        return Double(first.trimmingCharacters(in: .whitespaces))
    }

    private func parseCurrency(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let parts = raw.split(separator: " ").map(String.init)
        return parts.count >= 2 ? parts[1] : nil
    }

    /// Annual impact in whole dollars (primary currency). Positive = more spent,
    /// negative = savings. Used by priceChange support line and confirmed summary.
    private func annualImpact() -> Int {
        guard let sub = subscription else { return 0 }
        let deltaInSubCurrency = priceDirection
        let converted = ExchangeRateService.shared.convert(
            deltaInSubCurrency, from: sub.currency, to: primaryCurrency
        )
        return Int(sub.cycle.annualAmount(converted).rounded(.down))
    }

    private func relativeDate(_ d: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: d, relativeTo: Date())
    }

    private var sourceLabel: String {
        switch change.source {
        case .csvImport: return "CSV import"
        case .ocrImport: return "screenshot"
        case .mailWatchdog: return "Apple Mail"
        case .backgroundCheck: return "Suber"
        }
    }

    private func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        default: return "\(currency) "
        }
    }

    /// Mark the change acknowledged on any user action. Callers wrap this in
    /// their action closure so the badge updates immediately on click.
    private func markAck() { /* caller handles via store */ }
}

// MARK: - Preview

#if DEBUG
#Preview("priceChange up") {
    let sub = Subscription(
        id: UUID(), name: "Netflix", amount: 15.99, currency: "USD",
        cycle: .monthly, billingDay: 15, startDate: .now, category: "Entertainment",
        status: .active, createdAt: .now, updatedAt: .now
    )
    let change = SubscriptionChange(
        subscriptionID: sub.id, type: .priceChange,
        previousValue: "15.99 USD", newValue: "22.99 USD",
        source: .mailWatchdog,
        previousBaseAmount: 15.99, newBaseAmount: 22.99
    )
    ChangeRowView(
        change: change, subscription: sub, primaryCurrency: "USD",
        onOpenCancelPage: {}, onAcceptNewPrice: {},
        onAdd: {}, onIgnore: {}, onDismiss: {}, onMarkCancelledManually: {}
    )
    .frame(width: 720)
}

#Preview("newCharge") {
    let form: SubscriptionFormData = {
        var f = SubscriptionFormData()
        f.name = "Spotify"; f.amount = "9.99"; f.currency = "USD"
        f.cycle = .monthly
        return f
    }()
    let change = SubscriptionChange(
        subscriptionID: nil, type: .newCharge,
        previousValue: nil, newValue: "9.99 USD / mo",
        source: .mailWatchdog,
        pendingSubscriptionData: form,
        newBaseAmount: 9.99
    )
    ChangeRowView(
        change: change, subscription: nil, primaryCurrency: "USD",
        onOpenCancelPage: {}, onAcceptNewPrice: {},
        onAdd: {}, onIgnore: {}, onDismiss: {}, onMarkCancelledManually: {}
    )
    .frame(width: 720)
}

#Preview("cancellationConfirmed") {
    let sub = Subscription(
        id: UUID(), name: "Netflix", amount: 22.99, currency: "USD",
        cycle: .monthly, billingDay: 15, startDate: .now, category: "Entertainment",
        status: .cancelled, createdAt: .now, updatedAt: .now
    )
    let change = SubscriptionChange(
        subscriptionID: sub.id, type: .cancellationConfirmed,
        previousValue: "22.99 USD", newValue: "0 USD",
        source: .backgroundCheck,
        previousBaseAmount: 22.99, newBaseAmount: 0
    )
    ChangeRowView(
        change: change, subscription: sub, primaryCurrency: "USD",
        onOpenCancelPage: {}, onAcceptNewPrice: {},
        onAdd: {}, onIgnore: {}, onDismiss: {}, onMarkCancelledManually: {}
    )
    .frame(width: 720)
}
#endif
