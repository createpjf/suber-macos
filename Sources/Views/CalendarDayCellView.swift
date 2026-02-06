import SwiftUI

struct CalendarDayCellView: View {
    let date: Date
    let subscriptions: [Subscription]
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

    private let maxVisible = 3

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(DateHelpers.dayOfMonth(date))")
                    .font(AppFont.medium(12))
                    .foregroundColor(dayTextColor)

                if !subscriptions.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(subscriptions.prefix(maxVisible)) { sub in
                            LogoView(subscription: sub, size: 14)
                        }
                        if subscriptions.count > maxVisible {
                            Text("+\(subscriptions.count - maxVisible)")
                                .font(AppFont.medium(6))
                                .foregroundColor(Theme.textDim)
                                .frame(width: 14, height: 14)
                                .background(Theme.bgPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.vertical, 1)
            .padding(.horizontal, 0.5)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(cellOverlay)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentMonth)
    }

    private var dayTextColor: Color {
        if !isCurrentMonth { return Theme.textDim.opacity(0.5) }
        if isToday { return Theme.textPrimary }
        return Theme.textPrimary
    }

    private var cellBackground: Color {
        Theme.bgCell
    }

    @ViewBuilder
    private var cellOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.textPrimary.opacity(0.6), lineWidth: 1.5)
        } else if isToday {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.textPrimary.opacity(0.4), lineWidth: 1)
        } else {
            EmptyView()
        }
    }
}
