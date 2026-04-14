import SwiftUI

struct CalendarDayCellView: View {
    let date: Date
    let subscriptions: [Subscription]
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

    private let maxVisible = 3
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("\(DateHelpers.dayOfMonth(date))")
                    .font(AppFont.medium(13))
                    .foregroundColor(dayTextColor)

                if !subscriptions.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(subscriptions.prefix(maxVisible)) { sub in
                            LogoView(subscription: sub, size: 16)
                        }
                        if subscriptions.count > maxVisible {
                            Text("+\(subscriptions.count - maxVisible)")
                                .font(AppFont.medium(7))
                                .foregroundColor(Theme.textDim)
                                .frame(width: 16, height: 16)
                                .background(Theme.bgPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .padding(.vertical, 4)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(cellOverlay)
        }
        .buttonStyle(.plain)
        .disabled(!isCurrentMonth)
        .onHover { hovering in
            if isCurrentMonth { isHovering = hovering }
        }
    }

    private var dayTextColor: Color {
        if !isCurrentMonth { return Theme.textDim.opacity(0.5) }
        if isToday { return Theme.textPrimary }
        return Theme.textPrimary
    }

    private var cellBackground: Color {
        if isHovering && isCurrentMonth { return Theme.bgSecondary }
        return Theme.bgCell
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
