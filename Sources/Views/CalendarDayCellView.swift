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
            .overlay(alignment: .topTrailing) {
                // v1.6: compact "Nd" countdown badge for pending-cancel
                // subs whose billing day is today or near-future. Only
                // one badge per cell — if multiple pending subs fall on
                // this day, show the soonest.
                if let d = soonestPendingCountdown {
                    PendingCancellationIndicator.tileCountdownBadge(daysLeft: d)
                        .padding(2)
                }
            }
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
        if !subscriptions.isEmpty && isCurrentMonth {
            return Theme.bgCell.opacity(0.9)
        }
        return Theme.bgCell.opacity(0.4)
    }

    @ViewBuilder
    private var cellOverlay: some View {
        // v1.6: if any sub on this day is pending-cancel, show the dashed
        // orange border. Priority: pending-cancel > selected > today.
        // Dashed pattern still communicates "this day has a pending action"
        // even when the tile is selected.
        if hasPendingCancellationSub {
            PendingCancellationIndicator.dashedBorder(tier: .tile)
        } else if isSelected {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.textPrimary.opacity(0.6), lineWidth: 1.5)
        } else if isToday {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.textPrimary.opacity(0.4), lineWidth: 1)
        } else {
            EmptyView()
        }
    }

    // MARK: - v1.6 pending-cancel derivation

    private var hasPendingCancellationSub: Bool {
        subscriptions.contains(where: { $0.status == .pendingCancellation })
    }

    /// Days until next billing for the soonest pending-cancel sub on this
    /// day. Nil if no pending-cancel sub, or if the cell date is already
    /// past the billing window (overdue — handled in DayDetail).
    private var soonestPendingCountdown: Int? {
        let pending = subscriptions.filter { $0.status == .pendingCancellation }
        guard !pending.isEmpty else { return nil }
        let now = Date()
        let daysFromNow = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        guard daysFromNow >= 0 else { return nil }  // past dates get no badge
        return daysFromNow
    }
}
