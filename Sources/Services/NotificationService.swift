import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            if granted {
                print("Notification permission granted")
            }
        }
    }

    func scheduleReminders(for subscriptions: [Subscription], daysBefore: [Int]) {
        let center = UNUserNotificationCenter.current()

        let activeSubs = subscriptions.filter { $0.status == .active || $0.status == .trial }

        // Build the set of notification IDs we expect
        var expectedIDs: Set<String> = []

        for sub in activeSubs {
            let nextBilling = BillingCalculator.getNextBillingDate(sub)

            for days in daysBefore {
                guard let reminderDate = Calendar.current.date(byAdding: .day, value: -days, to: nextBilling) else {
                    continue
                }

                // Only schedule future reminders
                if reminderDate <= Date() { continue }

                let id = "\(sub.id.uuidString)-\(days)d"
                expectedIDs.insert(id)

                let content = UNMutableNotificationContent()
                content.title = "Subscription Reminder"
                if days == 0 {
                    content.body = "\(sub.name) is billing today - \(CurrencyFormatter.format(sub.amount, currency: sub.currency))"
                } else if days == 1 {
                    content.body = "\(sub.name) is billing tomorrow - \(CurrencyFormatter.format(sub.amount, currency: sub.currency))"
                } else {
                    content.body = "\(sub.name) is billing in \(days) days - \(CurrencyFormatter.format(sub.amount, currency: sub.currency))"
                }
                content.sound = .default

                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request)
            }
        }

        // Remove only stale notifications (ones no longer expected)
        center.getPendingNotificationRequests { pending in
            let staleIDs = pending.map(\.identifier).filter { !expectedIDs.contains($0) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
        }
    }
}
