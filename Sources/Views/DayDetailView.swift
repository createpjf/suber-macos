import SwiftUI

struct DayDetailView: View {
    let date: Date
    let subscriptions: [Subscription]
    let onEdit: (Subscription) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Theme.textDim)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Header
            HStack {
                Text(DateHelpers.formatDate(date))
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.bgPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

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
                                        .font(AppFont.medium(13))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(sub.category)
                                        .font(AppFont.regular(10))
                                        .foregroundColor(Theme.textSecondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CurrencyFormatter.formatShort(sub.amount, currency: sub.currency))
                                        .font(AppFont.medium(13))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(sub.cycle.shortLabel)
                                        .font(AppFont.regular(10))
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
            .frame(maxHeight: min(CGFloat(subscriptions.count) * 52 + 8, 280))
        }
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onClose()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}
