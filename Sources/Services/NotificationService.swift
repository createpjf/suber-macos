import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    /// Tracks the latest set of expected notification IDs across calls,
    /// so the async cleanup callback always uses the most recent set.
    private var latestExpectedIDs: Set<String> = []
    private let lock = NSLock()

    /// v1.6 Autopilot: category for grouped "Suber found N changes" alerts.
    /// Tapping routes via userInfo["deeplink"] → suber://changes → opens
    /// the Changes Window via SuberApp's onOpenURL handler.
    static let autopilotCategoryID = "com.suber.autopilot.changes"

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

    // MARK: - v1.6 Autopilot: immediate grouped notifications (Slice 4a)

    /// Fires a single notification RIGHT NOW (no trigger). Used by the Change
    /// Sentinel loop: one notification per scan run, body listing all changes
    /// found in that run. Rate limit is implicit via "one call per scan."
    ///
    /// Tap → opens Changes Window via `suber://changes` URL scheme
    /// (registered in Info.plist + SuberApp.onOpenURL handler).
    ///
    /// Permission: silently fails if the user hasn't granted authorization —
    /// the menu-bar badge still updates, so the Sentinel loop still works.
    /// Never nag users about notifications.
    func scheduleImmediate(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.autopilotCategoryID
        content.userInfo = ["deeplink": "suber://changes"]

        // Unique ID per call so rapid back-to-back scans don't collapse.
        let id = "autopilot-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                // Silent fail — badge still updates per requestPermission contract.
                print("Suber: scheduleImmediate failed: \(error.localizedDescription)")
            }
        }
    }

    /// Compose the Changes notification body from a batch of detected changes.
    /// Template lives HERE so the notification copy stays consistent with the
    /// Changes Window rows (don't let two surfaces drift on the same events).
    ///
    /// Design review Pass 1 (obvious-fix): type-grouped summary ordered by
    /// severity. Truncation at 5+ changes.
    static func composeChangesBody(from changes: [SubscriptionChange]) -> (title: String, body: String) {
        let count = changes.count
        let title = count == 1 ? "Suber found 1 change" : "Suber found \(count) changes"

        // Single change: spell out what happened.
        if count == 1, let c = changes.first {
            return (title, describe(single: c))
        }

        // Multiple same-type: "Netflix and Spotify raised prices"
        let priceChanges = changes.filter { $0.type == .priceChange }
        let newCharges = changes.filter { $0.type == .newCharge }
        let duplicates = changes.filter { $0.type == .duplicate }
        let trials = changes.filter { $0.type == .trialExpiring }

        // >5 changes: compact summary.
        if count > 5 {
            var parts: [String] = []
            if !priceChanges.isEmpty { parts.append("\(priceChanges.count) price change\(priceChanges.count == 1 ? "" : "s")") }
            if !newCharges.isEmpty   { parts.append("\(newCharges.count) new sub\(newCharges.count == 1 ? "" : "s")") }
            if !duplicates.isEmpty   { parts.append("\(duplicates.count) duplicate\(duplicates.count == 1 ? "" : "s")") }
            if !trials.isEmpty       { parts.append("\(trials.count) trial ending") }
            return (title, parts.joined(separator: ", "))
        }

        // 2–5: natural-language list, type-grouped.
        var fragments: [String] = []
        if !priceChanges.isEmpty {
            if priceChanges.count == 1 {
                fragments.append("\(nameOrFallback(priceChanges[0])) raised prices")
            } else {
                let names = priceChanges.prefix(2).map { nameOrFallback($0) }
                fragments.append(oxford(names) + " raised prices")
            }
        }
        if !newCharges.isEmpty {
            fragments.append("\(newCharges.count) new sub\(newCharges.count == 1 ? "" : "s")")
        }
        if !duplicates.isEmpty {
            fragments.append("\(duplicates.count) duplicate")
        }
        if !trials.isEmpty {
            fragments.append("\(trials.count) trial ending")
        }
        return (title, fragments.joined(separator: ", "))
    }

    // MARK: - Body template helpers (private)

    /// Single-change body. Named helpers keep composeChangesBody scannable.
    private static func describe(single change: SubscriptionChange) -> String {
        switch change.type {
        case .priceChange:
            let delta = priceDeltaPercent(change)
            let sign = delta >= 0 ? "+" : ""
            if let name = nameFromChange(change) {
                return "\(name) raised to \(change.newValue ?? "?") (\(sign)\(delta)%)"
            }
            return "Price changed to \(change.newValue ?? "?") (\(sign)\(delta)%)"
        case .newCharge:
            if let name = change.pendingSubscriptionData?.name {
                return "\(name) — new subscription detected"
            }
            return "New subscription detected"
        case .duplicate:
            return change.newValue ?? "Duplicate charge detected"
        case .trialExpiring:
            if let name = nameFromChange(change) {
                return "\(name) trial ends soon"
            }
            return "Trial ending soon"
        case .cancellationConfirmed:
            if let name = nameFromChange(change) {
                return "\(name) cancelled — confirmed by Suber"
            }
            return "Cancellation confirmed"
        case .cancellationFailed:
            if let name = nameFromChange(change) {
                return "\(name) didn't cancel — still active"
            }
            return "A cancellation didn't take effect"
        }
    }

    private static func nameFromChange(_ change: SubscriptionChange) -> String? {
        // Pull from hydrated form if .newCharge, else nil (caller should
        // look up via subscriptionID at the call site).
        change.pendingSubscriptionData?.name
    }

    private static func nameOrFallback(_ change: SubscriptionChange) -> String {
        nameFromChange(change) ?? "A subscription"
    }

    private static func priceDeltaPercent(_ change: SubscriptionChange) -> Int {
        guard let prev = Double(change.previousValue?.split(separator: " ").first.map(String.init) ?? ""),
              let curr = Double(change.newValue?.split(separator: " ").first.map(String.init) ?? ""),
              prev > 0 else { return 0 }
        return Int(((curr - prev) / prev * 100).rounded())
    }

    /// Oxford-style list: "A", "A and B", "A, B, and C"
    private static func oxford(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head), and \(items.last!)"
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

        // Store the latest expected IDs (thread-safe) so the async callback
        // always checks against the most recent call's set.
        lock.lock()
        latestExpectedIDs = expectedIDs
        lock.unlock()

        // Remove only stale notifications (ones no longer expected)
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self = self else { return }
            self.lock.lock()
            let currentExpected = self.latestExpectedIDs
            self.lock.unlock()

            let staleIDs = pending.map(\.identifier).filter { !currentExpected.contains($0) }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
        }
    }
}
