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
    static func mergeSubscriptions(local: [Subscription],
                                   remote: [Subscription]) -> CloudSyncMergeResult {
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
