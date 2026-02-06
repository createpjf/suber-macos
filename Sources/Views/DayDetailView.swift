import SwiftUI

struct DayDetailView: View {
    let date: Date
    let subscriptions: [Subscription]
    let onEdit: (Subscription) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            HStack {
                Text(DateHelpers.formatDate(date))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.bgSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .background(Theme.border)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(subscriptions) { sub in
                        Button(action: { onEdit(sub) }) {
                            HStack(spacing: 10) {
                                LogoView(subscription: sub, size: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(sub.category)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textSecondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CurrencyFormatter.formatShort(sub.amount, currency: sub.currency))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(sub.cycle.shortLabel)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if sub.id != subscriptions.last?.id {
                            Divider()
                                .background(Theme.border)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
