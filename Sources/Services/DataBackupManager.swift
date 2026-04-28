import Foundation

// ┌──────────── DataBackupManager — rotating local snapshots (v1.9.0) ─────────┐
// │                                                                            │
// │  Why this exists. v1.8.0 shipped LegacyDataMigration, which under          │
// │  certain macOS Tahoe (26.4) conditions destroyed the user's live data      │
// │  and had no second copy to recover from. The architectural lesson:         │
// │  ONE layer of data protection (the AppGroupStore "data already exists"     │
// │  guard) is too few. v1.9.0 adds rotating local backups so any future       │
// │  destructive bug is recoverable from disk without dev intervention.        │
// │                                                                            │
// │  Layout (`<container>` = group container):                                 │
// │    <container>/Library/Preferences/Suber/                                  │
// │      ├── suber-subscriptions.json     ← live (read by app + widget)       │
// │      ├── suber-settings.json                                               │
// │      ├── suber-changes.json                                                │
// │      └── Backups/                                                          │
// │          ├── suber-subscriptions-2026-04-25T14-32-08Z.json                │
// │          ├── suber-subscriptions-2026-04-25T14-45-12Z.json                │
// │          ├── ... (max 10 per key, oldest pruned)                           │
// │          ├── suber-settings-...                                            │
// │          └── suber-changes-...                                             │
// │                                                                            │
// │  Design rules:                                                             │
// │   1. **Backup is bonus, not dependency** — if snapshot fails, the live     │
// │      write already succeeded; we NSLog and move on. Never block the user.  │
// │   2. **3 critical keys only** — subscriptions / settings / changes.        │
// │      Exchange-rate cache and other ephemera don't justify backup churn.    │
// │   3. **Filesystem-safe timestamps** — ISO 8601 with `:` replaced by `-`,   │
// │      so `ls Backups/` sorts lexicographically == chronologically.          │
// │   4. **Atomic writes** — same `.atomic` option as live store; readers      │
// │      (Restore UI) never see a half-written backup.                         │
// │   5. **Prune on every write** — keeps disk footprint bounded; we don't     │
// │      need a separate scheduler.                                            │
// │                                                                            │
// │  This is read by RestoreSourceLister (Settings → Data → Restore) and      │
// │  hooked from AppGroupStore.set(_:forKey:).                                 │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum DataBackupManager {
    /// Hard cap per key. 10 × 3 keys ≤ ~few hundred KB even with large
    /// subscription lists; well below any reasonable disk-pressure threshold.
    static let maxBackupsPerKey = 10

    /// Keys that justify backup snapshots. Membership check is set-cheap.
    /// Adding a key here means every write triggers a snapshot+prune; review
    /// before extending.
    static let backupKeys: Set<String> = [
        "suber-subscriptions",
        "suber-settings",
        "suber-changes",
    ]

    /// Take a timestamped snapshot of `data` for `key`. Called from
    /// `AppGroupStore.set(_:forKey:)` on every successful live write.
    /// **Zero-failure mode**: any I/O error is logged, never thrown — the
    /// live write has already succeeded by the time we get here.
    static func snapshot(key: String, data: Data) {
        guard backupKeys.contains(key) else { return }
        guard let dir = backupsDirectory() else {
            NSLog("Suber DataBackup: backups directory unavailable for \(key)")
            return
        }

        let timestamp = filesystemSafeTimestamp(Date())
        let url = dir.appendingPathComponent("\(key)-\(timestamp).json")
        do {
            try data.write(to: url, options: [.atomic])
            pruneIfNeeded(key: key, dir: dir)
        } catch {
            NSLog("Suber DataBackup: snapshot failed for \(key): \(error)")
        }
    }

    /// All backup file URLs for `key`, newest first.
    /// Used by Restore UI to enumerate "Available backups".
    static func listBackups(key: String) -> [URL] {
        guard let dir = backupsDirectory() else { return [] }
        let prefix = "\(key)-"
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    /// Test/debug entry point — wipe all snapshots for `key`. Production
    /// code should never call this.
    static func removeAllBackups(key: String) {
        for url in listBackups(key: key) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Internals

    private static func pruneIfNeeded(key: String, dir: URL) {
        let backups = listBackups(key: key)
        guard backups.count > maxBackupsPerKey else { return }
        // backups[maxBackupsPerKey...] are the older ones (we sorted newest-first).
        for url in backups[maxBackupsPerKey...] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Test-only override. When non-nil, every snapshot/list/prune call uses
    /// this directory instead of the App Group container. Production code
    /// MUST NOT set this — leaving it nil keeps behavior identical to v1.8.x.
    /// Used by `DataPersistenceLifecycleTests` so tests can't trample the
    /// user's real `Backups/` directory.
    static var testOverrideDirectory: URL?

    /// Lazy-creates `<container>/Library/Preferences/Suber/Backups`.
    /// Returns nil only when the App Group entitlement is missing — at which
    /// point AppGroupStore itself is non-functional and the app has bigger
    /// problems than a missing backup directory.
    static func backupsDirectory() -> URL? {
        if let override = testOverrideDirectory {
            try? FileManager.default.createDirectory(
                at: override, withIntermediateDirectories: true)
            return override
        }
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupStore.groupIdentifier
        ) else { return nil }
        let dir = base
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("Suber", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ISO 8601 in UTC with millisecond precision, `:` replaced by `-` so
    /// the string is filesystem-safe AND lexicographic sort == chronological
    /// sort. Example: `2026-04-25T14-32-08.453Z`.
    ///
    /// Why milliseconds: two writes within the same second (e.g. SubscriptionStore
    /// saves subscriptions then saves the change log atomically) need distinct
    /// filenames, otherwise the second write would overwrite the first via
    /// `data.write(.atomic)` and we'd lose a backup point.
    static func filesystemSafeTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
