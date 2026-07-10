import Foundation

// ┌──────────── CloudSyncMerger — safe iCloud KVS → local merge (v1.9.1) ──────┐
// │                                                                            │
// │  Why this exists. v1.9.0 shipped with a destructive cloud-sync callback:   │
// │  `onRemoteChange` unconditionally called `subscriptionStore.import-        │
// │  Subscriptions(remote)` — replacing the user's local list with whatever    │
// │  iCloud KVS happened to hold. On a fresh v1.9.0 install where the user     │
// │  enabled sync via the new onboarding sheet, an old stale 1-sub snapshot    │
// │  in KVS overwrote the user's 9 live subs at first launch.                  │
// │                                                                            │
// │  This is the **same destructive overwrite pattern** as the v1.8.4          │
// │  LegacyDataMigration bug, just from a different source. The fix is the     │
// │  same architectural lesson: rescue/sync mechanisms must NEVER replace      │
// │  live user data without a sanity check.                                    │
// │                                                                            │
// │  Three-rule merge (subscriptions):                                         │
// │   1. Local empty + remote non-empty           → REPLACE (new device).      │
// │   2. Remote count < local count, and local    → REJECT. Log + flag for    │
// │      non-empty (suspected stale remote)         user review via Restore UI.│
// │   3. Otherwise                                → MERGE by `id`,             │
// │                                                  keep the higher           │
// │                                                  `updatedAt` per row;      │
// │                                                  preserve local-only       │
// │                                                  entries (additive).       │
// │                                                                            │
// │  Settings: never unconditionally replaced. Cloud-merged only when          │
// │  local equals factory defaults (i.e. user hasn't customised yet).         │
// │  Otherwise, the remote settings are logged + dropped — the user's local   │
// │  preferences win. They can re-import via Restore UI if they really want.  │
// │                                                                            │
// │  Pre-merge backup. Before applying ANY accepted merge, we take a fresh    │
// │  `DataBackupManager.snapshot` of the current local blob. So even if the   │
// │  merger logic is wrong, the pre-merge state is recoverable from           │
// │  Backups/. This is the architectural safety net the v1.9.0 plan called   │
// │  for but didn't extend to the cloud-sync path.                            │
// │                                                                            │
// │  Reading order: rule decision → pre-merge snapshot → merge → save.        │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

// MARK: - Deletion tombstones (AUDIT-v1.9.2 C-02)

/// One deliberate delete. `deletedAt` exists so the set can be pruned —
/// without it tombstones would accumulate forever against the 1 MB KVS budget.
struct DeletionTombstone: Codable, Equatable {
    let id: UUID
    let deletedAt: Date
}

/// AUDIT-v1.9.2 C-02 — deletion tombstones. Without them the three-rule merge
/// can never propagate a delete (Rule 2 rejects the now-smaller remote list)
/// and Rule 3's union-by-id resurrects a locally deleted sub the next time a
/// peer pushes — silently re-inflating monthly totals.
///
/// Storage: JSON `[DeletionTombstone]` in AppGroupStore + mirrored to the
/// iCloud KVS key `suber-deleted-ids`. Cross-version safety by construction:
/// the tombstone set is a NEW, separate payload — the `[Subscription]` wire
/// format is untouched, and pre-tombstone app versions never read this key,
/// so they decode nothing new (they just keep the old no-propagation behavior).
///
/// Threading: record/mergeRemote/removeMatching are called from the main
/// thread only (store mutations + the main-hopped onRemoteChange callback).
enum DeletionTombstones {
    static let storageKey = "suber-deleted-ids"
    /// Keep a tombstone long enough for every device to sync past the delete.
    static let maxAge: TimeInterval = 90 * 86_400
    /// KVS-budget hard cap (newest-first) — same storage-safety-first stance
    /// as StorageService.changeLogMaxEntries.
    static let maxEntries = 500

    /// Record a deliberate local delete. Persists locally and pushes the set
    /// to iCloud KVS so peers apply the delete instead of re-pushing the sub.
    static func record(_ id: UUID, now: Date = Date()) {
        let merged = prune(load() + [DeletionTombstone(id: id, deletedAt: now)], now: now)
        persist(merged, pushToCloud: true)
    }

    /// Drop tombstones for ids the user deliberately brought back via
    /// Restore/Import — otherwise the next cloud merge would silently
    /// re-delete the restored subs.
    static func removeMatching(_ ids: Set<UUID>) {
        let current = load()
        let kept = current.filter { !ids.contains($0.id) }
        guard kept.count != current.count else { return }
        persist(kept, pushToCloud: true)
    }

    static func load() -> [DeletionTombstone] {
        guard let data = AppGroupStore.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder.suberDecoder.decode([DeletionTombstone].self, from: data)) ?? []
    }

    /// Non-expired tombstoned ids — the set the subscription merge filters by.
    static func activeIDs(now: Date = Date()) -> Set<UUID> {
        Set(prune(load(), now: now).map(\.id))
    }

    /// Merge a peer's tombstone set into ours (union by id, newest `deletedAt`
    /// wins), prune, persist. Deliberately does NOT re-push to KVS — the
    /// remote already holds its copy (same no-ping-pong stance as
    /// SubscriptionStore.mergeRemoteChanges). Returns the merged active ids
    /// for the caller's subscription merge. `nil`/undecodable remote data
    /// (e.g. a pre-tombstone peer) degrades to the local set.
    static func mergeRemote(_ remoteData: Data?, now: Date = Date()) -> Set<UUID> {
        guard let remoteData,
              let remote = try? JSONDecoder.suberDecoder.decode([DeletionTombstone].self, from: remoteData),
              !remote.isEmpty else {
            return activeIDs(now: now)
        }
        var byID: [UUID: DeletionTombstone] = [:]
        for stone in load() + remote {
            if let existing = byID[stone.id], existing.deletedAt >= stone.deletedAt { continue }
            byID[stone.id] = stone
        }
        let merged = prune(Array(byID.values), now: now)
        persist(merged, pushToCloud: false)
        return Set(merged.map(\.id))
    }

    /// Age + count prune, newest-first (deterministic order for stable encodes).
    static func prune(_ stones: [DeletionTombstone], now: Date = Date()) -> [DeletionTombstone] {
        let cutoff = now.addingTimeInterval(-maxAge)
        let kept = stones
            .filter { $0.deletedAt >= cutoff }
            .sorted { $0.deletedAt > $1.deletedAt }
        return Array(kept.prefix(maxEntries))
    }

    private static func persist(_ stones: [DeletionTombstone], pushToCloud: Bool) {
        guard let data = try? JSONEncoder.suberEncoder.encode(stones) else {
            NSLog("Suber ⚠️ DeletionTombstones: encode failed — tombstones not persisted")
            return
        }
        // C-10 contract: a failed disk write must not push to KVS.
        guard AppGroupStore.set(data, forKey: storageKey) else {
            NSLog("Suber ⚠️ DeletionTombstones: disk write failed — skipping KVS push")
            return
        }
        if pushToCloud { CloudSyncService.shared.pushTombstones(data) }
    }
}

enum CloudSyncMergeResult: Equatable {
    /// Remote was applied. `merged` is the array we're about to persist.
    case applied(merged: [Subscription])
    /// Remote was rejected because it looks stale relative to local.
    /// Caller should log + surface a banner; local state is untouched.
    case rejectedAsStale(localCount: Int, remoteCount: Int)
    /// Nothing useful happened (remote was empty AND local was empty).
    case noOp
}

enum CloudSyncMerger {

    /// **THE** decision point. Returns the new array to persist (or a
    /// rejection signal). Pure function — does NOT take backups, does NOT
    /// call AppGroupStore. Caller is responsible for the side effects.
    /// This separation makes the rule logic trivially unit-testable.
    /// `tombstones` defaults to `[]` (not `DeletionTombstones.load()`) to keep
    /// this a pure function per the contract above; the live caller
    /// (SuberApp.handleRemoteSubscriptions) passes the merged tombstone set.
    static func mergeSubscriptions(local: [Subscription],
                                   remote: [Subscription],
                                   tombstones: Set<UUID> = []) -> CloudSyncMergeResult {
        // AUDIT-v1.9.2 C-02 — filter BOTH sides by tombstone before the three
        // rules run. Filtering remote stops Rule 3's union resurrecting a
        // locally deleted sub when a peer pushes; filtering local lets a
        // peer's delete propagate here (otherwise Rule 2 sees remote < local
        // and rejects the delete forever).
        let local = local.filter { !tombstones.contains($0.id) }
        let remote = remote.filter { !tombstones.contains($0.id) }

        // Rule 1 — local empty AND remote non-empty: legitimate fresh-device
        // hydration. Apply remote as-is.
        if local.isEmpty && !remote.isEmpty {
            return .applied(merged: remote)
        }

        // Both empty: nothing to do.
        if local.isEmpty && remote.isEmpty {
            return .noOp
        }

        // Rule 2 — remote suspiciously smaller than local. The most common
        // shape of this bug is a stale 0-sub or 1-sub KVS snapshot leaking
        // into a user with N>>1 local subs. We define "suspiciously smaller"
        // as: remote has FEWER entries than local AND local has at least
        // 1 entry. We do NOT try to be smarter (e.g. percentages) — the
        // user can always go to Settings → Data → Restore to apply a
        // smaller backup intentionally.
        if remote.count < local.count {
            return .rejectedAsStale(localCount: local.count, remoteCount: remote.count)
        }

        // Rule 3 — sizes are equal-or-larger remote. Merge by `id`,
        // last-modified-wins per row, preserve local-only entries.
        // Preserves the case where two devices each added different subs:
        // Mac A has [a,b,c], Mac B pulls and now has [a,b,c,d,e,f]; both
        // converge.
        var byID: [UUID: Subscription] = [:]
        for sub in local { byID[sub.id] = sub }
        for sub in remote {
            if let existing = byID[sub.id] {
                // Last-write-wins by `updatedAt`. Tie-broken in favor of
                // remote (deterministic; doesn't matter much in practice).
                byID[sub.id] = sub.updatedAt >= existing.updatedAt ? sub : existing
            } else {
                byID[sub.id] = sub
            }
        }
        // Sort by createdAt (stable display order) — matches how
        // SubscriptionStore renders.
        let merged = byID.values.sorted { $0.createdAt < $1.createdAt }
        return .applied(merged: merged)
    }

    /// Settings merge: only accept remote when local is still factory-default.
    /// Otherwise local wins. Returns `nil` when the caller should NOT apply
    /// the remote settings.
    static func mergeSettings(local: AppSettings, remote: AppSettings) -> AppSettings? {
        // Cheap factory-default check: encode both sides and compare.
        // AppSettings is Equatable (synthesised), so we can use ==.
        let factoryDefault = AppSettings()
        if local == factoryDefault {
            return remote
        }
        // User has customised at least one field. Don't auto-overwrite —
        // log + drop. Restore UI is the explicit path if they want.
        return nil
    }
}
