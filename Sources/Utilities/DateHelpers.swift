import Foundation

enum DateHelpers {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return cal
    }

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

    /// Builds a map of "yyyy-MM-dd" → [Subscription] for a given month.
    static func subscriptionsByDate(month: Date, subscriptions: [Subscription]) -> [String: [Subscription]] {
        let cal = calendar
        let year = cal.component(.year, from: month)
        let monthNum = cal.component(.month, from: month)

        var result: [String: [Subscription]] = [:]

        let activeSubs = subscriptions.filter { $0.status != .cancelled }

        for sub in activeSubs {
            if sub.cycle == .weekly {
                let dates = BillingCalculator.getWeeklyBillingDatesInMonth(sub, year: year, month: monthNum)
                for date in dates {
                    let key = formatDayKey(date)
                    result[key, default: []].append(sub)
                }
            } else {
                if let date = BillingCalculator.getBillingDateInMonth(sub, year: year, month: monthNum) {
                    let key = formatDayKey(date)
                    result[key, default: []].append(sub)
                }
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

    /// Format date as "MMMM yyyy" for month header display.
    static func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Format date as "MMM d, yyyy" for general display.
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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
