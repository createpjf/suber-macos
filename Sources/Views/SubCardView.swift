import SwiftUI

struct SubCardView: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 10) {
            LogoView(subscription: subscription, size: 36)

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(subscription.category)
                        .font(AppFont.regular(10))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.bgPrimary)
                        .clipShape(Capsule())

                    if let daysText = daysUntilText {
                        Text(daysText)
                            .font(AppFont.regular(10))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.formatShort(subscription.amount, currency: subscription.currency))
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                Text(subscription.cycle.shortLabel)
                    .font(AppFont.regular(10))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        AppConstants.statusColors[subscription.status] ?? Theme.textSecondary
    }

    private var daysUntilText: String? {
        if subscription.cycle == .oneTime { return nil }
        let days = BillingCalculator.getDaysUntilBilling(subscription)
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "in \(days)d"
    }
}
