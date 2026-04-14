import Foundation

/// Manages iCloud Key-Value Store sync for subscriptions and settings.
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let subscriptionsKey = "subreminder-subscriptions"
    private let settingsKey = "subreminder-settings"

    /// Called when remote data arrives. Passes (subscriptions Data?, settings Data?).
    var onRemoteChange: ((Data?, Data?) -> Void)?

    private var observing = false

    private init() {}

    // MARK: - Enable / Disable

    func startSync() {
        guard !observing else { return }
        observing = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )

        // Force an initial sync
        kvStore.synchronize()
    }

    func stopSync() {
        guard observing else { return }
        observing = false

        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
    }

    // MARK: - Write

    func pushSubscriptions(_ data: Data) {
        guard observing else { return }
        kvStore.set(data, forKey: subscriptionsKey)
        kvStore.synchronize()
    }

    func pushSettings(_ data: Data) {
        guard observing else { return }
        kvStore.set(data, forKey: settingsKey)
        kvStore.synchronize()
    }

    // MARK: - Read

    func pullSubscriptions() -> Data? {
        kvStore.data(forKey: subscriptionsKey)
    }

    func pullSettings() -> Data? {
        kvStore.data(forKey: settingsKey)
    }

    // MARK: - Remote Change Handler

    @objc private func handleRemoteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        // Only handle server changes or initial sync
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            let subsData = kvStore.data(forKey: subscriptionsKey)
            let settingsData = kvStore.data(forKey: settingsKey)
            DispatchQueue.main.async { [weak self] in
                self?.onRemoteChange?(subsData, settingsData)
            }
        default:
            break
        }
    }
}
