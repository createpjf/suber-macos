import Foundation

enum BillingCalculator {
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    // MARK: - Private Helpers

    private static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func daysInMonth(_ date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    private static func clampDay(_ date: Date, day: Int) -> Date {
        let maxDay = daysInMonth(date)
        let clampedDay = min(day, maxDay)
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = clampedDay
        return calendar.date(from: comps) ?? date
    }

    private static func advanceByOneCycle(_ date: Date, cycle: BillingCycle, billingDay: Int) -> Date {
        switch cycle {
        case .monthly:
            guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { return date }
            return clampDay(next, day: billingDay)
        case .yearly:
            guard let next = calendar.date(byAdding: .year, value: 1, to: date) else { return date }
            return clampDay(next, day: billingDay)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .quarterly:
            guard let next = calendar.date(byAdding: .month, value: 3, to: date) else { return date }
            return clampDay(next, day: billingDay)
        case .oneTime:
            return date
        }
    }

    // MARK: - Public API

    /// Returns the next billing date on or after today.
    static func getNextBillingDate(_ sub: Subscription) -> Date {
        getNextBillingDate(sub, onOrAfter: Date())
    }

    /// Returns the next billing date on or after `reference` (cycle-aware,
    /// day-clamped).
    static func getNextBillingDate(_ sub: Subscription, onOrAfter reference: Date) -> Date {
        let ref = startOfDay(reference)
        let start = startOfDay(sub.startDate)
        // oneTime (like weekly) anchors to startDate, never billingDay — the
        // form hides billingDay for one-time purchases, so clamping produced a
        // date the user never picked and disagreed with the calendar's
        // getBillingDateInMonth oneTime branch (AUDIT-v1.9.2 C-35).
        var next = (sub.cycle == .weekly || sub.cycle == .oneTime)
            ? start
            : clampDay(start, day: sub.billingDay)

        if sub.cycle == .oneTime {
            return next
        }

        // Safety: limit iterations to prevent infinite loop from unexpected data
        var iterations = 0
        while next < ref && iterations < 2000 {
            next = advanceByOneCycle(next, cycle: sub.cycle, billingDay: sub.billingDay)
            iterations += 1
        }

        return next
    }

    /// First billing date strictly after `reference`'s calendar day
    /// (cycle-aware, day-clamped). The pending-cancellation gate uses this so
    /// (a) a yearly sub verifies at its actual anniversary instead of a
    /// synthetic monthly date, (b) Feb-31-style overflow clamps to Feb 28
    /// rather than sliding into March, and (c) a cancel tapped ON a billing
    /// day waits a full cycle — that day's charge is ambiguous relative to
    /// the tap, and day-granular statement data can't order the two
    /// (AUDIT-v1.9.2 C-05).
    static func getNextBillingDate(_ sub: Subscription, strictlyAfter reference: Date) -> Date {
        let ref = startOfDay(reference)
        var next = getNextBillingDate(sub, onOrAfter: reference)
        if next <= ref && sub.cycle != .oneTime {
            next = advanceByOneCycle(next, cycle: sub.cycle, billingDay: sub.billingDay)
        }
        return next
    }

    /// Returns the billing date for a specific year/month, or nil if not applicable.
    static func getBillingDateInMonth(_ sub: Subscription, year: Int, month: Int) -> Date? {
        // one-time: only in the start month
        if sub.cycle == .oneTime {
            let startComps = calendar.dateComponents([.year, .month], from: sub.startDate)
            if startComps.year == year && startComps.month == month {
                return startOfDay(sub.startDate)
            }
            return nil
        }

        // weekly: handled separately
        if sub.cycle == .weekly {
            return nil
        }

        // Build target date
        var targetComps = DateComponents()
        targetComps.year = year
        targetComps.month = month
        targetComps.day = 1
        guard let target = calendar.date(from: targetComps) else { return nil }

        let maxDay = daysInMonth(target)
        let day = min(sub.billingDay, maxDay)

        var billingComps = DateComponents()
        billingComps.year = year
        billingComps.month = month
        billingComps.day = day
        guard let billingDate = calendar.date(from: billingComps) else { return nil }

        let startDate = startOfDay(sub.startDate)
        if billingDate < startDate {
            return nil
        }

        // Yearly: only show in the anniversary month
        if sub.cycle == .yearly {
            let startMonth = calendar.component(.month, from: startDate)
            if startMonth != month {
                return nil
            }
        }

        // Quarterly: only show every 3 months from start month
        if sub.cycle == .quarterly {
            let startYear = calendar.component(.year, from: startDate)
            let startMonth = calendar.component(.month, from: startDate)
            let monthDiff = (year - startYear) * 12 + (month - startMonth)
            if monthDiff < 0 || monthDiff % 3 != 0 {
                return nil
            }
        }

        return billingDate
    }

    /// Returns all billing dates for a subscription that fall within the given year/month.
    /// Unifies weekly / monthly / quarterly / yearly / oneTime handling so callers don't
    /// need to branch on cycle themselves.
    static func getBillingDatesInMonth(_ sub: Subscription, year: Int, month: Int) -> [Date] {
        if sub.cycle == .weekly {
            return getWeeklyBillingDatesInMonth(sub, year: year, month: month)
        }
        if let date = getBillingDateInMonth(sub, year: year, month: month) {
            return [date]
        }
        return []
    }

    /// Returns all weekly billing dates in a given month.
    /// Optimized: jumps directly to the target month instead of iterating week-by-week from startDate.
    static func getWeeklyBillingDatesInMonth(_ sub: Subscription, year: Int, month: Int) -> [Date] {
        guard sub.cycle == .weekly else { return [] }

        let start = startOfDay(sub.startDate)

        var monthStartComps = DateComponents()
        monthStartComps.year = year
        monthStartComps.month = month
        monthStartComps.day = 1
        guard let monthStart = calendar.date(from: monthStartComps) else { return [] }

        var monthEndComps = DateComponents()
        monthEndComps.year = year
        monthEndComps.month = month + 1
        monthEndComps.day = 0
        guard let monthEnd = calendar.date(from: monthEndComps) else { return [] }

        // Jump: calculate weeks from start to monthStart, then align
        var current: Date
        if start >= monthStart {
            current = start
        } else {
            let daysBetween = calendar.dateComponents([.day], from: start, to: monthStart).day ?? 0
            let weeksToSkip = daysBetween / 7
            guard let jumped = calendar.date(byAdding: .weekOfYear, value: weeksToSkip, to: start) else { return [] }
            current = jumped
            // Advance one more week if we landed before monthStart
            if current < monthStart {
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { return [] }
                current = next
            }
        }

        var dates: [Date] = []
        while current <= monthEnd {
            let currentMonth = calendar.component(.month, from: current)
            if currentMonth == month {
                dates.append(current)
            }
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    /// Total amount spent from start date until today.
    /// Counts charges by advancing cycle-by-cycle with the same logic as
    /// getNextBillingDate. Multi-unit dateComponents([.weekOfYear,.month,.year])
    /// hierarchically decomposes the span (29 months → month remainder 5), and
    /// the old count also skipped the initial charge (AUDIT-v1.9.2 C-17).
    static func getTotalSpent(_ sub: Subscription) -> Double {
        let today = startOfDay(Date())
        let start = startOfDay(sub.startDate)

        if today < start { return 0 }
        if sub.cycle == .oneTime { return sub.amount }

        var chargeDate = sub.cycle == .weekly ? start : clampDay(start, day: sub.billingDay)
        if chargeDate < start { // billingDay precedes actual start day → first charge rolls one cycle
            chargeDate = advanceByOneCycle(chargeDate, cycle: sub.cycle, billingDay: sub.billingDay)
        }
        var count = 0
        // Safety: limit iterations to prevent infinite loop from unexpected data
        var iterations = 0
        while chargeDate <= today && iterations < 2000 {
            count += 1
            chargeDate = advanceByOneCycle(chargeDate, cycle: sub.cycle, billingDay: sub.billingDay)
            iterations += 1
        }
        return Double(count) * sub.amount
    }

    /// Days from today to next billing date.
    /// Calendar-aware day difference between two local midnights — the old
    /// ceil(seconds/86400) counted the DST fall-back's extra hour as a whole
    /// phantom day for every countdown crossing the transition
    /// (AUDIT-v1.9.2 C-21).
    static func getDaysUntilBilling(_ sub: Subscription) -> Int {
        let next = getNextBillingDate(sub)
        let today = startOfDay(Date())
        return daysBetween(from: today, to: next, calendar: calendar)
    }

    /// DST-safe day count between two midnights. Internal (not private) so the
    /// fall-back regression test can drive it with a fixed-TimeZone calendar.
    static func daysBetween(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Normalize subscription cost to a monthly equivalent, using effective (split-adjusted) amount.
    static func getMonthlyEquivalent(_ sub: Subscription) -> Double {
        let amt = sub.effectiveAmount
        switch sub.cycle {
        case .yearly: return amt / 12.0
        // 52/12 ≈ 4.3333, same 52-weeks/year basis as BillingCycle.annualAmount —
        // the old 4.33 made Dashboard's yearly figure (×12 = 51.96 weeks) disagree
        // with ChangeRowView/CancellationSuccessBanner (AUDIT-v1.9.2 C-36).
        case .weekly: return amt * 52.0 / 12.0
        case .quarterly: return amt / 3.0
        case .oneTime: return 0
        case .monthly: return amt
        }
    }
}
