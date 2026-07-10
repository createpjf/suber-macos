import Foundation

enum DateHelpers {
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    /// Returns all dates for a 6-week calendar grid starting on Monday.
    static func calendarDays(for month: Date) -> [Date] {
        let cal = calendar
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }

        let firstDayOfMonth = monthInterval.start

        // Find the Monday on or before the first day of the month
        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        // Convert to Monday-based: Mon=0, Tue=1, ..., Sun=6
        let mondayOffset = (weekday + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -mondayOffset, to: firstDayOfMonth) else {
            return []
        }

        // Generate 42 days (6 weeks)
        var days: [Date] = []
        for i in 0..<42 {
            if let date = cal.date(byAdding: .day, value: i, to: gridStart) {
                days.append(cal.startOfDay(for: date))
            }
        }
        return days
    }

    /// Returns dates for a compact calendar grid (5 or 6 weeks as needed).
    static func calendarDaysCompact(for month: Date) -> [Date] {
        let cal = calendar
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }

        let firstDayOfMonth = monthInterval.start
        // v1.7 (SAFETY-01): Calendar.date returns Optional. For a Gregorian
        // calendar + valid Date, the failure path is unreachable in practice,
        // but force-unwrapping bakes that guarantee in — guard let lets the
        // safety self-document and survives future refactors.
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: firstDayOfMonth),
              let lastDayOfMonth = cal.date(byAdding: .day, value: -1, to: nextMonth)
        else { return [] }

        // Find the Monday on or before the first day of the month
        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        let mondayOffset = (weekday + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -mondayOffset, to: firstDayOfMonth) else {
            return []
        }

        // Calculate how many weeks needed: find what row the last day falls in.
        // SAFETY-01: .day is populated when explicitly requested but nil-coalesce
        // is cheaper than future regression risk.
        let daysFromStart = (cal.dateComponents([.day], from: gridStart, to: lastDayOfMonth).day ?? 0) + 1
        let weeksNeeded = Int(ceil(Double(daysFromStart) / 7.0))
        let totalDays = weeksNeeded * 7

        var days: [Date] = []
        for i in 0..<totalDays {
            if let date = cal.date(byAdding: .day, value: i, to: gridStart) {
                days.append(cal.startOfDay(for: date))
            }
        }
        return days
    }

    /// Builds a map of "yyyy-MM-dd" → [Subscription] for a given month.
    static func subscriptionsByDate(month: Date, subscriptions: [Subscription]) -> [String: [Subscription]] {
        let cal = calendar
        let year = cal.component(.year, from: month)
        let monthNum = cal.component(.month, from: month)

        var result: [String: [Subscription]] = [:]

        let activeSubs = subscriptions.filter { $0.status != .cancelled }

        for sub in activeSubs {
            for date in BillingCalculator.getBillingDatesInMonth(sub, year: year, month: monthNum) {
                let key = formatDayKey(date)
                result[key, default: []].append(sub)
            }
        }

        return result
    }

    /// Format date as "yyyy-MM-dd" for use as dictionary key.
    static func formatDayKey(_ date: Date) -> String {
        let cal = calendar
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Cached DateFormatters

    // AUDIT-v1.9.2 U-17: locale-aware templates instead of fixed patterns.
    // A fixed "MMMM yyyy" doesn't reorder for Chinese ("七月 2026" instead of
    // "2026年7月"); setLocalizedDateFormatFromTemplate lets the locale decide
    // element order and separators.
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMM")   // en: July 2026 / zh: 2026年7月
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMd")   // en: Jul 10, 2026 / zh: 2026年7月10日
        return f
    }()

    /// Format date as a localized month + year for month header display.
    static func formatMonthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date)
    }

    /// Format date as a localized abbreviated date for general display.
    static func formatDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    /// Check if two dates are in the same month.
    static func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        let cal = calendar
        return cal.component(.year, from: a) == cal.component(.year, from: b)
            && cal.component(.month, from: a) == cal.component(.month, from: b)
    }

    /// Check if a date is today.
    static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    /// Get day of month from a date.
    static func dayOfMonth(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }
}
