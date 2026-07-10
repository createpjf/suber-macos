import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    let onEdit: (Subscription) -> Void
    /// AUDIT-v1.9.2 U-15: opens the add-subscription form — the default tab's
    /// empty state now carries the primary CTA instead of hiding it behind
    /// the Dashboard icon.
    let onAdd: () -> Void

    @State private var currentMonth = Date()
    @State private var selectedDate: Date?
    @State private var slideDirection: SlideDirection = .forward

    private enum SlideDirection {
        case forward, backward
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    // AUDIT-v1.9.2 U-02/U-03: [LocalizedStringKey] (was [String]) — Text(day)
    // rendered the raw String verbatim, so the weekday strip could never
    // localize. The English literals stay the catalog keys.
    private let weekdays: [LocalizedStringKey] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

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
        // AUDIT-v1.9.2 C-39: zero-param onChange — single-param form is
        // deprecated on macOS 14 and the values aren't used.
        .onChange(of: currentMonth) { recomputeCache() }
        .onChange(of: subscriptionStore.subscriptions) { recomputeCache() }
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
                    // AUDIT-v1.9.2 U-10: icon-only month nav — label the
                    // function for VoiceOver + tooltip.
                    .accessibilityLabel(Text("Previous month"))
                    .help("Previous month")

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 22, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Next month"))
                    .help("Next month")
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
            // LocalizedStringKey isn't Hashable — iterate by index.
            ForEach(weekdays.indices, id: \.self) { i in
                Text(weekdays[i])
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

            // AUDIT-v1.9.2 U-15: first-run empty state on the default tab was
            // one gray line ("Tap + …" — desktop app, no tapping) while the
            // real Add CTA hid behind the unlabeled Dashboard icon. Reuse the
            // Dashboard empty state's capsule CTA here.
            if subscriptionStore.subscriptions.isEmpty {
                VStack(spacing: 10) {
                    Text("No subscriptions yet")
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                    Button(action: onAdd) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add subscription")
                                .font(AppFont.medium(12))
                        }
                        .foregroundColor(Theme.bgPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.textPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("or press ⌘N")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textDim)
                }
                .padding(.vertical, 12)
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
        // AUDIT-v1.9.2 U-05: convert every sub into the primary currency (same
        // math as DashboardViewModel.update) instead of silently dropping
        // non-primary-currency subs — the two tabs disagreed on "monthly spend".
        // "~" marks the total as FX-estimated.
        let total = activeSubs.reduce(0.0) { sum, sub in
            let equiv = BillingCalculator.getMonthlyEquivalent(sub)
            return sum + ExchangeRateService.shared.convert(equiv, from: sub.currency, to: primaryCurrency)
        }
        let formatted = CurrencyFormatter.formatShort(total, currency: primaryCurrency)
        cachedMonthlySpend = hasMultipleCurrencies ? "~\(formatted)" : formatted
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
