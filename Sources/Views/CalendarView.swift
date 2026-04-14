import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    let onEdit: (Subscription) -> Void

    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var slideDirection: SlideDirection = .forward

    private enum SlideDirection {
        case forward, backward
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                calendarGrid
                    .id(DateHelpers.formatMonthYear(currentMonth))
                    .transition(monthTransition)
            }
            .clipped()

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
        .onAppear { recomputeCache() }
        .onChange(of: currentMonth) { _ in recomputeCache() }
        .onChange(of: subscriptionStore.subscriptions) { _ in recomputeCache() }
    }

    private var monthTransition: AnyTransition {
        switch slideDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            HStack(spacing: 4) {
                VStack(spacing: 2) {
                    Button(action: prevMonth) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 22, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 22, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text(DateHelpers.formatMonthYear(currentMonth))
                    .font(AppFont.bold(22))
                    .foregroundColor(Theme.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Monthly spend")
                    .font(AppFont.regular(10))
                    .foregroundColor(Theme.textSecondary)
                Text(monthlySpend)
                    .font(AppFont.bold(16))
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(AppFont.medium(10))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 8)

            // Empty state hint when no subscriptions
            if subscriptionStore.subscriptions.isEmpty {
                VStack(spacing: 6) {
                    Text("No subscriptions yet")
                        .font(AppFont.regular(12))
                        .foregroundColor(Theme.textSecondary)
                    Text("Tap + or ⌘N to add your first one")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textDim)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Cached Computed Data

    @State private var cachedCalendarDays: [Date] = []
    @State private var cachedSubscriptionsByDate: [String: [Subscription]] = [:]
    @State private var cachedMonthlySpend: String = ""

    private var calendarDays: [Date] { cachedCalendarDays }
    private var subscriptionsByDate: [String: [Subscription]] { cachedSubscriptionsByDate }
    private var monthlySpend: String { cachedMonthlySpend }

    private func recomputeCache() {
        cachedCalendarDays = DateHelpers.calendarDaysCompact(for: currentMonth)
        cachedSubscriptionsByDate = DateHelpers.subscriptionsByDate(month: currentMonth, subscriptions: subscriptionStore.subscriptions)

        let activeSubs = subscriptionStore.subscriptions
            .filter { $0.status == .active || $0.status == .trial }
        let primaryCurrency = settingsStore.settings.primaryCurrency
        let hasMultipleCurrencies = Set(activeSubs.map(\.currency)).count > 1
        let total = activeSubs
            .filter { !hasMultipleCurrencies || $0.currency == primaryCurrency }
            .reduce(0.0) { $0 + BillingCalculator.getMonthlyEquivalent($1) }
        let formatted = CurrencyFormatter.formatShort(total, currency: primaryCurrency)
        cachedMonthlySpend = (hasMultipleCurrencies && total > 0) ? "~\(formatted)" : formatted
    }

    // MARK: - Actions

    private func prevMonth() {
        selectedDate = nil
        slideDirection = .backward
        withAnimation(.easeInOut(duration: 0.25)) {
            currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        }
    }

    private func nextMonth() {
        selectedDate = nil
        slideDirection = .forward
        withAnimation(.easeInOut(duration: 0.25)) {
            currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
        }
    }
}
