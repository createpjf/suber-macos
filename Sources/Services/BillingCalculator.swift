import Foundation

enum BillingCalculator {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }

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
            let next = calendar.date(byAdding: .month, value: 1, to: date)!
            return clampDay(next, day: billingDay)
        case .yearly:
            let next = calendar.date(byAdding: .year, value: 1, to: date)!
            return clampDay(next, day: billingDay)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)!
        case .quarterly:
            let next = calendar.date(byAdding: .month, value: 3, to: date)!
            return clampDay(next, day: billingDay)
        case .oneTime:
            return date
        }
    }

    // MARK: - Public API

    /// Returns the next billing date on or after today.
    static func getNextBillingDate(_ sub: Subscription) -> Date {
        let today = startOfDay(Date())
        let start = startOfDay(sub.startDate)
        var next = sub.cycle == .weekly ? start : clampDay(start, day: sub.billingDay)

        if sub.cycle == .oneTime {
            return next
        }

        while next < today {
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

    /// Returns all weekly billing dates in a given month.
    static func getWeeklyBillingDatesInMonth(_ sub: Subscription, year: Int, month: Int) -> [Date] {
        guard sub.cycle == .weekly else { return [] }

        var dates: [Date] = []
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

        var current = start
        while current < monthStart {
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }

        while current <= monthEnd {
            let currentMonth = calendar.component(.month, from: current)
            if currentMonth == month {
                dates.append(current)
            }
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }

        return dates
    }

    /// Total amount spent from start date until today.
    static func getTotalSpent(_ sub: Subscription) -> Double {
        let today = startOfDay(Date())
        let start = startOfDay(sub.startDate)

        if today < start { return 0 }
        if sub.cycle == .oneTime { return sub.amount }

        let components = calendar.dateComponents([.weekOfYear, .month, .year], from: start, to: today)

        let count: Int
        switch sub.cycle {
        case .weekly:
            count = components.weekOfYear ?? 0
        case .monthly:
            count = components.month ?? 0
        case .quarterly:
            count = (components.month ?? 0) / 3
        case .yearly:
            count = components.year ?? 0
        case .oneTime:
            return sub.amount
        }

        return Double(max(0, count)) * sub.amount
    }

    /// Days from today to next billing date.
    static func getDaysUntilBilling(_ sub: Subscription) -> Int {
        let next = getNextBillingDate(sub)
        let today = startOfDay(Date())
        let diff = next.timeIntervalSince(today)
        return Int(ceil(diff / 86400))
    }

    /// Normalize subscription cost to a monthly equivalent.
    static func getMonthlyEquivalent(_ sub: Subscription) -> Double {
        switch sub.cycle {
        case .yearly: return sub.amount / 12.0
        case .weekly: return sub.amount * 4.33
        case .quarterly: return sub.amount / 3.0
        case .oneTime: return 0
        case .monthly: return sub.amount
        }
    }
}
