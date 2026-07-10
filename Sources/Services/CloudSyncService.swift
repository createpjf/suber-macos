import Foundation

/// AUDIT-v1.9.2 U-12: minimal sync-status surface. Merge outcomes (applied /
/// rejected-as-stale conflicts) were NSLog-only and Settings showed a static
/// string — success and silent data divergence were indistinguishable in the
/// UI. SuberApp reports events here; SettingsView.iCloudSyncRow observes.
/// @MainActor: @Published backs SwiftUI directly.
@MainActor
final class CloudSyncUIStatus: ObservableObject {
    static let shared = CloudSyncUIStatus()

    @Published private(set) var lastEvent: String?
    @Published private(set) var lastEventAt: Date?
    /// true for conflict/rejection events — lets the UI color them as warnings
    /// without matching on display text.
    @Published private(set) var lastEventIsWarning = false

    func report(_ text: String, isWarning: Bool = false) {
        lastEvent = text
        lastEventAt = Date()
        lastEventIsWarning = isWarning
    }
}

/// Manages iCloud Key-Value Store sync for subscriptions and settings.
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let subscriptionsKey = "suber-subscriptions"
    private let settingsKey = "suber-settings"
    private let changesKey = "suber-changes"  // v1.6: SubscriptionChange log
    // AUDIT-v1.9.2 C-02: deletion-tombstone set. A NEW KVS key — pre-tombstone
    // app versions never read it, so the added payload is cross-version safe.
    private let tombstonesKey = DeletionTombstones.storageKey

    /// Called when remote data arrives. Passes (subscriptions Data?, settings
    /// Data?, changes Data?, tombstones Data?). C-02 added the tombstones arg.
    /// Threading contract: set and invoked on the MAIN thread only
    /// (handleRemoteChange hops to main before calling) — keep it that way,
    /// this var is deliberately unlocked.
    var onRemoteChange: ((Data?, Data?, Data?, Data?) -> Void)?

    // AUDIT-v1.9.2 C-28: `observing` is read by push* from whatever thread the
    // caller runs on (AppIntents execute off-main) while startSync/stopSync
    // write it from the main thread — an unsynchronized cross-thread access.
    // Lock the accessor so reads can't tear/stale. start/stopSync themselves
    // remain main-thread-only (NotificationCenter add/removeObserver pairing).
    private let stateLock = NSLock()
    private var _observing = false
    private var observing: Bool {
        get { stateLock.withLock { _observing } }
        set { stateLock.withLock { _observing = newValue } }
    }

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

    /// v1.6: push the SubscriptionChange log. H5 prune already applied
    /// upstream in StorageService.saveChanges.
    func pushChanges(_ data: Data) {
        guard observing else { return }
        kvStore.set(data, forKey: changesKey)
        kvStore.synchronize()
    }

    /// AUDIT-v1.9.2 C-02: push the deletion-tombstone set so peers apply the
    /// delete instead of resurrecting the sub. Prune applied upstream in
    /// DeletionTombstones.
    func pushTombstones(_ data: Data) {
        guard observing else { return }
        kvStore.set(data, forKey: tombstonesKey)
        kvStore.synchronize()
    }

    // MARK: - Read

    func pullSubscriptions() -> Data? {
        kvStore.data(forKey: subscriptionsKey)
    }

    func pullSettings() -> Data? {
        kvStore.data(forKey: settingsKey)
    }

    func pullChanges() -> Data? {
        kvStore.data(forKey: changesKey)
    }

    func pullTombstones() -> Data? {
        kvStore.data(forKey: tombstonesKey)
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
            let changesData = kvStore.data(forKey: changesKey)  // v1.6
            let tombstonesData = kvStore.data(forKey: tombstonesKey)  // C-02
            DispatchQueue.main.async { [weak self] in
                self?.onRemoteChange?(subsData, settingsData, changesData, tombstonesData)
            }
        default:
            break
        }
    }
}
