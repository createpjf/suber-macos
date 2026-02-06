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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(dayTextColor)

                if !subscriptions.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(subscriptions.prefix(maxVisible)) { sub in
                            LogoView(subscription: sub, size: 14)
                        }
                        if subscriptions.count > maxVisible {
                            Text("+\(subscriptions.count - maxVisible)")
                                .font(.system(size: 6, weight: .medium))
                                .foregroundColor(Theme.textDim)
                                .frame(width: 14, height: 14)
                                .background(Theme.bgPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .padding(.vertical, 1)
            .padding(.horizontal, 0.5)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(cellOverlay)
        }
        .buttonStyle(.plain)
        .opacity(isCurrentMonth ? 1.0 : 0.2)
    }

    private var dayTextColor: Color {
        if isToday { return Theme.textPrimary }
        if isCurrentMonth { return Theme.textSecondary }
        return Theme.textDim
    }

    private var cellBackground: Color {
        isCurrentMonth ? Theme.bgCell : .clear
    }

    @ViewBuilder
    private var cellOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.textPrimary.opacity(0.6), lineWidth: 1)
        } else if isToday {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.textPrimary.opacity(0.4), lineWidth: 1)
        } else {
            EmptyView()
        }
    }
}
