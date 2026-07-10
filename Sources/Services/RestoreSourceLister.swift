import Foundation

// ┌────────── RestoreSourceLister — enumerate available recovery sources ──────┐
// │                                                                            │
// │  v1.9.0 — replaces the dangerous automatic LegacyDataMigration with an     │
// │  explicit user-driven Restore UI. This service is the data source for     │
// │  Settings → Data → Restore from Backup; it scans all known places we      │
// │  might find a recoverable subscription list and returns one uniform list  │
// │  of `BackupSource` rows.                                                   │
// │                                                                            │
// │  Sources scanned:                                                          │
// │    1. .localRotating  — `DataBackupManager.listBackups("suber-…")`         │
// │       (10 most-recent timestamped snapshots in Backups/)                  │
// │    2. .iCloudKVS      — `CloudSyncService.shared.pullSubscriptions()`     │
// │       (only when `enableCloudSync == true`; otherwise skipped)            │
// │    3. .legacyPlist    — `<container>/Library/Preferences/                 │
// │       group.com.suber.app.plist`. The v1.6.0–v1.6.1 cfprefsd-era file.    │
// │       Read via `PropertyListSerialization` to bypass cfprefsd entirely    │
// │       (same approach the now-disabled LegacyDataMigration used).          │
// │                                                                            │
// │  This service NEVER mutates state. Listing is read-only; the actual      │
// │  restore (write back to AppGroupStore + reload SubscriptionStore) lives  │
// │  in DataRestoreView.                                                      │
// │                                                                            │
// │  Decode errors are tolerated — a corrupt backup shouldn't make the        │
// │  whole list disappear. We surface what we can and skip what we can't,    │
// │  logging via NSLog so a developer can investigate. The UI shows what's    │
// │  listable; if everything is corrupt the list is empty and the view tells │
// │  the user "no backups found" rather than crashing.                        │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// One restore-eligible blob. Identified by `id` so SwiftUI lists can diff.
struct BackupSource: Identifiable, Equatable {
    enum Kind: Equatable {
        case localRotating       // DataBackupManager Backups/ dir
        case iCloudKVS           // remote KVS pull
        case legacyPlist         // pre-v1.6.2 group plist
    }

    let id: String
    let kind: Kind
    /// When the snapshot was created. For local rotating: file mtime.
    /// For iCloud KVS: best-effort `Date()` (KVS doesn't expose mtimes).
    /// For legacy plist: the plist file's mtime.
    let timestamp: Date
    /// Number of subscriptions decoded from this snapshot. Decode failures
    /// surface as 0 here but the source is still listed so the user can
    /// Preview and see the raw byte count.
    let subscriptionCount: Int
    /// Raw bytes of the subscriptions JSON. The actual restore writes this
    /// back to AppGroupStore exactly as-is, so we don't need to round-trip
    /// through Subscription decoding for the restore path itself.
    let subscriptionsData: Data
    /// Optional bytes for the settings + changes payloads in the same source.
    /// Local rotating + legacy plist often have all three; KVS provides them
    /// independently.
    let settingsData: Data?
    let changesData: Data?
    /// Human-readable label rendered in the row ("Local backup · 12 min ago",
    /// "iCloud · 2026-04-25 14:32", "Legacy data (v1.6.x)"). Localized since
    /// the v1.9.2 U-02 backfill (String(localized:) at every build site).
    let label: String
}

enum RestoreSourceLister {
    /// Returns all currently listable backup sources, newest-first.
    /// Pass `iCloudSyncEnabled: false` to skip the KVS pull (the toggle in
    /// Settings is the source of truth — we don't second-guess it here).
    static func listAvailableSources(iCloudSyncEnabled: Bool) -> [BackupSource] {
        var out: [BackupSource] = []
        out.append(contentsOf: localRotatingSources())
        if iCloudSyncEnabled, let icloud = iCloudKVSSource() {
            out.append(icloud)
        }
        if let legacy = legacyPlistSource() {
            out.append(legacy)
        }
        return out.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - 1. Local rotating snapshots

    /// Pair each `suber-subscriptions-*.json` snapshot with the closest-in-time
    /// settings/changes snapshot. The Backups/ directory writes all three keys
    /// independently, so we don't expect exact-time matches; "within 5s" is
    /// generous enough to capture a single SubscriptionStore.persist() pulse.
    private static func localRotatingSources() -> [BackupSource] {
        let subURLs = DataBackupManager.listBackups(key: "suber-subscriptions")
        let settingsURLs = DataBackupManager.listBackups(key: "suber-settings")
        let changesURLs = DataBackupManager.listBackups(key: "suber-changes")

        return subURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? Date()
            let count = decodeSubscriptionCount(from: data)
            let settings = pickClosest(to: mtime, in: settingsURLs)
            let changes = pickClosest(to: mtime, in: changesURLs)
            return BackupSource(
                id: "local-\(url.lastPathComponent)",
                kind: .localRotating,
                timestamp: mtime,
                subscriptionCount: count,
                subscriptionsData: data,
                settingsData: settings,
                changesData: changes,
                label: String(localized: "Local backup · \(relativeTime(mtime))")
            )
        }
    }

    /// Best-effort: load the file in `urls` whose mtime is within ±5s of
    /// `target`. Skips if the file can't be read. Used to bundle the
    /// settings/changes snapshots that were written alongside a given
    /// subscriptions snapshot.
    private static func pickClosest(to target: Date, in urls: [URL]) -> Data? {
        let candidate = urls.first { url in
            guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { return false }
            return abs(mtime.timeIntervalSince(target)) <= 5.0
        }
        return candidate.flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: - 2. iCloud KVS

    /// Pull the current remote subscriptions blob. KVS doesn't expose
    /// per-key mtime, so we tag with `Date()` — fine because there's only
    /// ever ONE iCloud row in the list (it represents the latest sync state).
    private static func iCloudKVSSource() -> BackupSource? {
        guard let data = CloudSyncService.shared.pullSubscriptions() else { return nil }
        let count = decodeSubscriptionCount(from: data)
        let settings = CloudSyncService.shared.pullSettings()
        let changes = CloudSyncService.shared.pullChanges()
        return BackupSource(
            id: "icloud-kvs",
            kind: .iCloudKVS,
            timestamp: Date(),
            subscriptionCount: count,
            subscriptionsData: data,
            settingsData: settings,
            changesData: changes,
            label: count == 1
                ? String(localized: "iCloud · 1 subscription")
                : String(localized: "iCloud · \(count) subscriptions")
        )
    }

    // MARK: - 3. Legacy plist (v1.6.0 / v1.6.1 / early v1.7.x)

    /// Read the legacy `<container>/Library/Preferences/group.com.suber.app.plist`
    /// directly via `PropertyListSerialization` — bypasses cfprefsd to avoid
    /// the macOS Tahoe TCC prompt that v1.6.2 fixed. This is the same
    /// read-path the disabled LegacyDataMigration used; here it's safe
    /// because the user explicitly chose Restore.
    private static func legacyPlistSource() -> BackupSource? {
        guard let url = legacyPlistURL(),
              FileManager.default.fileExists(atPath: url.path),
              let raw = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: raw, options: [], format: nil
              ) as? [String: Any]
        else { return nil }

        guard let subsData = plist["suber-subscriptions"] as? Data else { return nil }
        let count = decodeSubscriptionCount(from: subsData)
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? Date(timeIntervalSince1970: 0)

        return BackupSource(
            id: "legacy-plist",
            kind: .legacyPlist,
            timestamp: mtime,
            subscriptionCount: count,
            subscriptionsData: subsData,
            settingsData: plist["suber-settings"] as? Data,
            changesData: plist["suber-changes"] as? Data,
            label: count == 1
                ? String(localized: "Legacy data (v1.6.x) · 1 subscription")
                : String(localized: "Legacy data (v1.6.x) · \(count) subscriptions")
        )
    }

    private static func legacyPlistURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupStore.groupIdentifier
        )?
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Preferences", isDirectory: true)
        .appendingPathComponent("\(AppGroupStore.groupIdentifier).plist")
    }

    // MARK: - Helpers

    /// Decode just enough to count subscriptions. Failures yield 0 (we still
    /// list the source so the user can Preview / inspect raw bytes).
    private static func decodeSubscriptionCount(from data: Data) -> Int {
        if let arr = try? JSONDecoder.suberDecoder.decode([Subscription].self, from: data) {
            return arr.count
        }
        return 0
    }

    /// "12 minutes ago" / "2 hours ago" / "Apr 24". Cheap relative format
    /// with a fall-through to absolute date for older snapshots.
    private static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "just now") }
        if interval < 3600 { return String(localized: "\(Int(interval / 60)) min ago") }
        if interval < 86_400 { return String(localized: "\(Int(interval / 3600)) hr ago") }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
