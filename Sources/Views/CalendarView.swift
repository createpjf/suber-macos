import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    let onEdit: (Subscription) -> Void

    @State private var currentMonth = Date()
    @State private var selectedDate: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                calendarGrid
            }

            if let selectedDate = selectedDate,
               let subs = subscriptionsByDate[DateHelpers.formatDayKey(selectedDate)],
               !subs.isEmpty {
                DayDetailView(
                    date: selectedDate,
                    subscriptions: subs,
                    onEdit: onEdit,
                    onClose: { self.selectedDate = nil }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: selectedDate)
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Text(DateHelpers.formatMonthYear(currentMonth))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                VStack(spacing: 2) {
                    Button(action: prevMonth) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Monthly spend")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                Text(monthlySpend)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(calendarDays, id: \.self) { date in
                CalendarDayCellView(
                    date: date,
                    subscriptions: subscriptionsByDate[DateHelpers.formatDayKey(date)] ?? [],
                    isCurrentMonth: DateHelpers.isSameMonth(date, currentMonth),
                    isToday: DateHelpers.isToday(date),
                    isSelected: selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false,
                    onTap: {
                        if let subs = subscriptionsByDate[DateHelpers.formatDayKey(date)], !subs.isEmpty {
                            withAnimation {
                                selectedDate = date
                            }
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Computed

    private var calendarDays: [Date] {
        DateHelpers.calendarDays(for: currentMonth)
    }

    private var subscriptionsByDate: [String: [Subscription]] {
        DateHelpers.subscriptionsByDate(month: currentMonth, subscriptions: subscriptionStore.subscriptions)
    }

    private var monthlySpend: String {
        let total = subscriptionStore.subscriptions
            .filter { $0.status == .active || $0.status == .trial }
            .reduce(0.0) { $0 + BillingCalculator.getMonthlyEquivalent($1) }
        return CurrencyFormatter.formatShort(total, currency: settingsStore.settings.primaryCurrency)
    }

    // MARK: - Actions

    private func prevMonth() {
        selectedDate = nil
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
    }

    private func nextMonth() {
        selectedDate = nil
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
    }
}
