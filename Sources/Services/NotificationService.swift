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
        center.removeAllPendingNotificationRequests()

        let activeSubs = subscriptions.filter { $0.status == .active || $0.status == .trial }

        for sub in activeSubs {
            let nextBilling = BillingCalculator.getNextBillingDate(sub)

            for days in daysBefore {
                guard let reminderDate = Calendar.current.date(byAdding: .day, value: -days, to: nextBilling) else {
                    continue
                }

                // Only schedule future reminders
                if reminderDate <= Date() { continue }

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

                let id = "\(sub.id.uuidString)-\(days)d"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

                center.add(request)
            }
        }
    }
}
