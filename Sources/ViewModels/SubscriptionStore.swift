import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published var subscriptions: [Subscription] = []

    // MARK: - v1.6 Change log (Sentinel)
    //
    // The log drives:
    //   - Changes Window (.reviewChanges mode)
    //   - Menu-bar badge (unreadChangeCount — count of unacknowledged changes
    //     within the last 14 days)
    //   - SinceYouWereAwayBanner (same count + once-per-day gate)
    //   - FirstCatchBanner (gated by AutopilotFlags.hasSeenFirstCatch)
    //   - CancellationSuccessBanner (reads cancellationConfirmed entries)
    //
    // Write path: recordAndPersist(changes:) is the one entry point. It
    // dedups against the existing log via SubscriptionChange.dedupHash,
    // appends new ones, and calls StorageService.saveChanges (which applies
    // H5 prune-on-write before persisting + syncing to iCloud).
    @Published var changes: [SubscriptionChange] = []

    /// Menu-bar badge source of truth. Count of unacknowledged changes within
    /// the last 14 days. Older unacknowledged changes remain in `changes` for
    /// historical review but don't count toward the badge.
    ///
    /// Computed, not stored, so it stays in sync with any mutation to
    /// `changes` without manual bookkeeping. @Published via `objectWillChange`
    /// propagation from the `changes` setter.
    var unreadChangeCount: Int {
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        return changes.filter { !$0.acknowledged && $0.detectedAt >= threshold }.count
    }

    init() {
        subscriptions = StorageService.shared.loadSubscriptions()
        changes = StorageService.shared.loadChanges()
    }

    func add(_ data: SubscriptionFormData) {
        guard let amount = data.parsedAmount else { return }

        let sub = Subscription(
            id: UUID(),
            name: data.name.trimmingCharacters(in: .whitespaces),
            url: data.url.isEmpty ? nil : data.url,
            logo: data.logo,
            amount: amount,
            currency: data.currency,
            cycle: data.cycle,
            billingDay: data.billingDay,
            startDate: data.startDate,
            trialEndDate: data.status == .trial ? data.trialEndDate : nil,
            category: data.category,
            status: data.status,
            notes: data.notes.isEmpty ? nil : data.notes,
            splitCount: data.splitCount,
            createdAt: Date(),
            updatedAt: Date()
        )

        subscriptions.append(sub)
        save()
    }

    func update(id: UUID, with data: SubscriptionFormData) {
        guard let amount = data.parsedAmount,
              let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }

        subscriptions[index].name = data.name.trimmingCharacters(in: .whitespaces)
        subscriptions[index].url = data.url.isEmpty ? nil : data.url
        subscriptions[index].logo = data.logo
        subscriptions[index].amount = amount
        subscriptions[index].currency = data.currency
        subscriptions[index].cycle = data.cycle
        subscriptions[index].billingDay = data.billingDay
        subscriptions[index].startDate = data.startDate
        subscriptions[index].trialEndDate = data.status == .trial ? data.trialEndDate : nil
        subscriptions[index].category = data.category
        subscriptions[index].status = data.status
        subscriptions[index].notes = data.notes.isEmpty ? nil : data.notes
        subscriptions[index].splitCount = data.splitCount
        subscriptions[index].updatedAt = Date()
        save()
    }

    func delete(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        save()
    }

    func togglePause(id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].status = subscriptions[index].status == .active ? .paused : .active
        subscriptions[index].updatedAt = Date()
        save()
    }

    func clearAll() {
        // v1.9.2: route through the single destructive-replace chokepoint so
        // the pre-clear state is snapshotted + logged like every other replace.
        replaceAll([], reason: .clearAll)
    }

    /// **The one destructive-replace chokepoint (v1.9.2).** Every wholesale
    /// replacement of the subscription list passes through here with an
    /// explicit `reason`. It (1) snapshots the OUTGOING state to Backups/
    /// before overwriting, (2) logs the count transition for diagnostics, and
    /// (3) fires a tripwire if the automated `cloudMerge` path ever shrinks the
    /// list — which `CloudSyncMerger` should already prevent upstream.
    ///
    /// User-initiated reasons (`userImport`, `userRestore`, `clearAll`) may
    /// legitimately reduce the count; only `cloudMerge` shrinking is suspicious.
    func replaceAll(_ subs: [Subscription], reason: SubscriptionReplaceReason) {
        let oldCount = subscriptions.count
        let newCount = subs.count

        // Belt-and-suspenders: snapshot the outgoing state before overwrite,
        // independent of AppGroupStore.set's own post-write hook. Guarantees
        // the pre-replace list is in Backups/ for one-click recovery.
        if oldCount > 0, let outgoing = try? JSONEncoder.suberEncoder.encode(subscriptions) {
            DataBackupManager.snapshot(key: "suber-subscriptions", data: outgoing)
        }

        if reason == .cloudMerge && newCount < oldCount {
            NSLog("Suber ⚠️ replaceAll TRIPWIRE: cloudMerge shrank \(oldCount) → \(newCount). CloudSyncMerger should have rejected this — investigate.")
        } else {
            NSLog("Suber replaceAll: \(oldCount) → \(newCount) (reason=\(reason.rawValue))")
        }

        subscriptions = subs
        save()
    }

    private func save() {
        StorageService.shared.saveSubscriptions(subscriptions)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Change log (v1.6 Sentinel)

    /// Append new changes to the log, dedup'd by `SubscriptionChange.dedupHash`.
    /// Persists via StorageService (which applies H5 prune-on-write) and syncs
    /// to iCloud.
    ///
    /// Same-day re-scans produce identical hashes → silently dropped.
    /// Cross-device duplicates (detected on Mac A and Mac B same day) → also dropped.
    ///
    /// First scan completion also flips `AutopilotFlags.hasSeenFirstScan = true`
    /// so the Changes Window stops showing the first-run empty state.
    func recordAndPersist(
        changes newChanges: [SubscriptionChange],
        flags injectedFlags: AutopilotFlags? = nil
    ) {
        // Must build inside the @MainActor body; AutopilotFlags.init is
        // MainActor-isolated and can't be called as a default argument value.
        let flags = injectedFlags ?? AutopilotFlags()

        guard !newChanges.isEmpty else {
            // First scan with zero findings still flips the flag — user sees
            // "You're all caught up" instead of first-run copy next time.
            if !flags.hasSeenFirstScan { flags.hasSeenFirstScan = true }
            return
        }

        let existingHashes = Set(changes.map { $0.dedupHash })
        let fresh = newChanges.filter { !existingHashes.contains($0.dedupHash) }
        guard !fresh.isEmpty else {
            if !flags.hasSeenFirstScan { flags.hasSeenFirstScan = true }
            return
        }

        changes.append(contentsOf: fresh)
        if !flags.hasSeenFirstScan { flags.hasSeenFirstScan = true }
        StorageService.shared.saveChanges(changes)
        // Keep in-memory state in sync with what we just persisted
        // (saveChanges applies H5 prune-on-write). Otherwise UI would show
        // > 200 entries until app restart.
        changes = StorageService.prune(changes)
    }

    /// Mark a change as read. Called when the user acts on a row (Accept /
    /// Ignore / Add / Open cancel page) in the Changes Window.
    func markChangeAcknowledged(id: UUID) {
        guard let index = changes.firstIndex(where: { $0.id == id }) else { return }
        guard !changes[index].acknowledged else { return }
        changes[index].acknowledged = true
        StorageService.shared.saveChanges(changes)
    }

    /// Mark ALL changes as acknowledged. Used when the user opens the Changes
    /// Window via the menu-bar badge tap — clears the unread count.
    func markAllChangesAcknowledged() {
        var mutated = false
        for i in changes.indices where !changes[i].acknowledged {
            changes[i].acknowledged = true
            mutated = true
        }
        if mutated { StorageService.shared.saveChanges(changes) }
    }

    /// A4 manual cancel path for v1.5-style users (no data source) who've
    /// cancelled elsewhere and want to tell Suber. Transitions to `.cancelled`
    /// and logs a `cancellationConfirmed` change so the celebration banner
    /// can fire.
    func markCancelledManually(id: UUID, now: Date = Date()) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        let sub = subscriptions[index]
        guard sub.status != .cancelled else { return }

        subscriptions[index].status = .cancelled
        subscriptions[index].pendingCancellationSetAt = nil
        subscriptions[index].updatedAt = now
        save()

        let change = SubscriptionChange(
            subscriptionID: sub.id,
            type: .cancellationConfirmed,
            detectedAt: now,
            previousValue: sub.status.rawValue,
            newValue: "cancelled",
            source: .backgroundCheck,    // user action, but logged as verification
            newBaseAmount: sub.amount
        )
        recordAndPersist(changes: [change])
    }

    /// v1.6 One-Tap Cancel state transition.
    ///
    /// D5 (eng review iter-1) idempotency: if the sub is already in
    /// `.pendingCancellation`, do NOT reset `pendingCancellationSetAt` —
    /// keeps the D4 auto-transition anchor stable so re-taps of "Open cancel
    /// page" don't move the verification window.
    func markPendingCancellation(id: UUID, now: Date = Date()) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        if subscriptions[index].status == .pendingCancellation {
            // Re-tap: URL already opened from the view layer; DO NOT mutate anchor.
            return
        }
        subscriptions[index].status = .pendingCancellation
        subscriptions[index].pendingCancellationSetAt = now
        subscriptions[index].updatedAt = now
        save()
    }

    // MARK: - Auto-transition (A4 + P1)

    /// Check every `.pendingCancellation` sub against incoming transactions in
    /// its verification window. Called from:
    ///   (a) App launch (SuberApp.setupWatchdog)
    ///   (b) End of MailWatchdog.scanNow (P1: fold into scan-completion hook)
    ///   (c) End of CSV import (ImportPresenter)
    ///
    /// Logic (D4 + A4):
    ///   - For each `.pendingCancellation` sub:
    ///     - Zero matching charges in window AND window is data-source-covered
    ///       → transition to `.cancelled`, log `cancellationConfirmed`
    ///     - One or more matching charges in window
    ///       → transition back to `.active`, log `cancellationFailed`
    ///     - No data source covers the window
    ///       → stay `.pendingCancellation`, do nothing (UI nudges the user
    ///         to "Mark as cancelled manually" if they want)
    ///
    /// - Parameters:
    ///   - transactions: fresh incoming transactions from this scan/import.
    ///     Pass [] for the "no data source" case.
    ///   - dataSourceCoversWindow: true if we can be confident a charge in
    ///     the pending window would have been captured. False for manual-
    ///     only v1.5-style users.
    ///   - now: injectable for tests.
    func checkPendingCancellationTransitions(
        transactions: [StatementTransaction] = [],
        dataSourceCoversWindow: Bool,
        now: Date = Date()
    ) {
        var detectedChanges: [SubscriptionChange] = []

        for index in subscriptions.indices {
            let sub = subscriptions[index]
            guard sub.status == .pendingCancellation,
                  let setAt = sub.pendingCancellationSetAt else { continue }

            // Only evaluate once the billing day in the pending window has
            // passed — too early and we'd fire "cancellationConfirmed" before
            // the charge could even have dropped.
            let billingDue = computeBillingDue(after: setAt, billingDay: sub.billingDay)
            guard now >= billingDue else { continue }

            // A4 gate: must have a data source that covered this window.
            guard dataSourceCoversWindow else {
                // Stay pending. DayDetail surfaces the manual nudge.
                continue
            }

            // Did any incoming transaction match this sub in the window?
            let merchantKey = MerchantNormalizer.normalize(sub.name)
            let matches = transactions.contains { txn in
                txn.date >= setAt &&
                txn.date <= now &&
                MerchantNormalizer.normalize(txn.merchantRaw) == merchantKey
            }

            if matches {
                // cancellationFailed — roll back to .active.
                subscriptions[index].status = .active
                subscriptions[index].pendingCancellationSetAt = nil
                subscriptions[index].updatedAt = now

                let change = SubscriptionChange(
                    subscriptionID: sub.id,
                    type: .cancellationFailed,
                    detectedAt: now,
                    previousValue: "pending_cancellation",
                    newValue: "active",
                    source: .backgroundCheck,
                    newBaseAmount: sub.amount
                )
                detectedChanges.append(change)
            } else {
                // cancellationConfirmed — transition to .cancelled.
                subscriptions[index].status = .cancelled
                subscriptions[index].pendingCancellationSetAt = nil
                subscriptions[index].updatedAt = now

                let change = SubscriptionChange(
                    subscriptionID: sub.id,
                    type: .cancellationConfirmed,
                    detectedAt: now,
                    previousValue: "pending_cancellation",
                    newValue: "cancelled",
                    source: .backgroundCheck,
                    newBaseAmount: sub.amount
                )
                detectedChanges.append(change)
            }
        }

        if !detectedChanges.isEmpty {
            save()  // persist status mutations
            recordAndPersist(changes: detectedChanges)
        }
    }

    /// The first billing-due date at-or-after `setAt`. Used to gate the
    /// auto-transition evaluation — we only check AFTER the expected billing
    /// day has passed.
    ///
    /// Example: pending set 2026-03-10, billingDay=15 → returns 2026-03-15.
    /// Pending set 2026-03-20, billingDay=15 → returns 2026-04-15 (next month).
    private func computeBillingDue(after setAt: Date, billingDay: Int) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month], from: setAt)
        components.day = billingDay

        guard let thisMonth = cal.date(from: components) else { return setAt }

        // If billing day in the current month is already past `setAt`, use it.
        // Otherwise use next month's billing day.
        if thisMonth >= setAt {
            return thisMonth
        }
        return cal.date(byAdding: .month, value: 1, to: thisMonth) ?? setAt
    }

    /// iCloud-merge path. Called by SuberApp's CloudSync.onRemoteChange when
    /// another device pushes a newer change log. Dedups by `dedupHash` so the
    /// "same change" detected locally and remotely doesn't double-count.
    func mergeRemoteChanges(_ remote: [SubscriptionChange]) {
        let existingHashes = Set(changes.map { $0.dedupHash })
        let fresh = remote.filter { !existingHashes.contains($0.dedupHash) }
        guard !fresh.isEmpty else { return }
        changes.append(contentsOf: fresh)
        // v1.9.2: apply H5 prune-on-write (was a raw AppGroupStore.set that
        // skipped prune → the merged log could exceed the 200-entry cap and
        // blow the iCloud KVS 1 MB budget). We prune both in-memory and the
        // persisted blob, but deliberately do NOT re-push to KVS — the remote
        // already holds its own copy (avoiding a sync ping-pong). The direct
        // AppGroupStore.set still triggers DataBackupManager.snapshot.
        let pruned = StorageService.prune(changes)
        changes = pruned
        if let data = try? JSONEncoder.suberEncoder.encode(pruned) {
            AppGroupStore.set(data, forKey: "suber-changes")
        }
    }
}

/// Why a subscription list was wholesale-replaced. Used by
/// `SubscriptionStore.replaceAll(_:reason:)` for logging + the cloudMerge
/// shrink tripwire. `rawValue` strings appear in NSLog diagnostics.
enum SubscriptionReplaceReason: String {
    case userImport    // JSON import (Settings → Data → Import JSON)
    case userRestore   // Settings → Data → Restore from backup
    case cloudMerge    // CloudSyncMerger result applied from iCloud KVS
    case clearAll      // explicit "Clear all data" (count → 0 expected)
}

// MARK: - Shared Encoder (matches StorageService.encoder)

extension JSONEncoder {
    static let suberEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
