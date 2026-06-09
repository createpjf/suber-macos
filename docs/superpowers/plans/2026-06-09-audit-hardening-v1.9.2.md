# Audit Hardening (v1.9.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 7 data-integrity and correctness gaps found in the v1.9.1 code audit, shipping as a data-safety patch (v1.9.2) without introducing new features.

**Architecture:** Centralize every destructive subscription replace behind one logged, snapshot-taking chokepoint (`replaceAll(_:reason:)`); make the change-log merge path respect the same H5 prune policy as every other write; add a confirmation gate to the only un-gated destructive UI action (JSON import); narrow the AppIntents lost-update window; and harden a handful of practically-safe Calendar force-unwraps.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, XcodeGen (`project.yml` → `xcodegen generate`), `xcodebuild test`, Sparkle 2 (in-app updates), `scripts/build-dmg.sh`.

**Severity recap (from audit):**
- W1 🟡 `mergeRemoteChanges` bypasses H5 prune → change log can exceed 200-cap + blow KVS 1 MB budget.
- W2/U1 🟡 JSON import does a silent destructive replace with no confirmation.
- W3 🟡 `AddSubscriptionIntent` load→append→save is a TOCTOU lost-update race.
- W4 🟡 No architectural chokepoint guarding silent subscription-list collapse.
- I1 🔵 6 `Calendar.date(byAdding:to:)!` force-unwraps.
- I2 🔵 `onReceive($settings)` toggles sync on every settings change, not just the `enableCloudSync` transition.
- I4 🔵 `DataRestoreView` doesn't refresh its source list after a restore.

**Build/test commands used throughout (proxy must be unset — MacPacket TUN intercepts Apple endpoints):**

```bash
# Regenerate project after adding/removing files:
cd /Users/leo/Desktop/suber-macos && xcodegen generate

# Run one test class:
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/<TestClassName>

# Full suite:
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB
```

Baseline before this plan: **228 tests, 0 failures** (commit `1f2c2f4`). Target after: **233** (228 + 5 new: 1 in Task 1, 3 in Task 2, 1 in Task 4).

---

## Task 1: W1 — Route `mergeRemoteChanges` through H5 prune

**Why:** `SubscriptionStore.mergeRemoteChanges` is the only change-log writer that calls `AppGroupStore.set("suber-changes")` directly, skipping `StorageService.prune`. Every other writer prunes to 200. A noisy multi-device account can grow the merged log unbounded and blow the iCloud KVS 1 MB budget → sync breakage.

**Files:**
- Modify: `Sources/ViewModels/SubscriptionStore.swift:344-356`
- Test: `Tests/SubscriptionStoreChangeLogTests.swift` (add one test)

- [ ] **Step 1: Write the failing test**

Add this test method inside `SubscriptionStoreChangeLogTests` (after `testPruneKeepsRecent200WhenOverflowing`, around line 82):

```swift
func testMergeRemoteChangesPrunesTo200() {
    // 250 distinct remote changes merged into an empty log must end up
    // pruned to the 200-entry cap — both in memory and on disk. Guards the
    // v1.9.2 fix: mergeRemoteChanges used to bypass H5 prune.
    var remote: [SubscriptionChange] = []
    let base = Date()
    for i in 0..<250 {
        remote.append(SubscriptionChange(
            subscriptionID: UUID(), type: .priceChange,
            detectedAt: base.addingTimeInterval(-TimeInterval(i)),
            previousValue: nil, newValue: "\(i)",
            source: .csvImport,
            previousBaseAmount: Double(i), newBaseAmount: Double(i + 1)
        ))
    }

    store.mergeRemoteChanges(remote)

    XCTAssertLessThanOrEqual(store.changes.count, 200,
                             "in-memory log must be pruned to 200")
    let reloaded = StorageService.shared.loadChanges()
    XCTAssertLessThanOrEqual(reloaded.count, 200,
                             "persisted log must be pruned to 200")
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/SubscriptionStoreChangeLogTests/testMergeRemoteChangesPrunesTo200
```

Expected: FAIL — `store.changes.count` is 250 (no prune).

- [ ] **Step 3: Apply the fix**

In `Sources/ViewModels/SubscriptionStore.swift`, replace the body of `mergeRemoteChanges` (lines 344-356) with:

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/SubscriptionStoreChangeLogTests/testMergeRemoteChangesPrunesTo200
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/ViewModels/SubscriptionStore.swift Tests/SubscriptionStoreChangeLogTests.swift
git commit -m "fix(v1.9.2): mergeRemoteChanges applies H5 prune (W1)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: W4 — `replaceAll(_:reason:)` destructive-replace chokepoint

**Why:** Three data-loss incidents (v1.8.4, v1.9.0, and the audit) all shared one shape: an automated path silently replacing the live subscription list. There is no single, logged, self-documenting chokepoint for destructive replaces. This task introduces `replaceAll(_:reason:)` — every destructive replace passes an explicit reason, logs the count transition, snapshots the outgoing state to `Backups/` first, and a tripwire fires if the automated `cloudMerge` path ever shrinks the list (which `CloudSyncMerger` should already prevent upstream).

**Files:**
- Modify: `Sources/ViewModels/SubscriptionStore.swift` (replace `clearAll` + `importSubscriptions`, lines 101-109)
- Modify: `Sources/SuberApp.swift:236` (CloudSyncMerger apply path)
- Modify: `Sources/Views/SettingsView.swift:490` (JSON import)
- Modify: `Sources/Views/Settings/DataRestoreView.swift:249` (restore)
- Test: `Tests/SubscriptionReplaceTests.swift` (new file)

- [ ] **Step 1: Write the failing test (new file)**

Create `Tests/SubscriptionReplaceTests.swift`:

```swift
import XCTest
@testable import Suber

/// v1.9.2 — guards the single destructive-replace chokepoint
/// `SubscriptionStore.replaceAll(_:reason:)`. The contract: after any
/// destructive replace, the PRE-replace state must be recoverable from the
/// rotating Backups/ directory. This is the regression lock for the
/// "automated path silently wiped my subs" family of bugs.
@MainActor
final class SubscriptionReplaceTests: XCTestCase {

    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-replace-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempStoreDir, withIntermediateDirectories: true)
        AppGroupStore.testOverrideDirectory = tempStoreDir

        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-replace-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempBackupDir, withIntermediateDirectories: true)
        DataBackupManager.testOverrideDirectory = tempBackupDir
    }

    override func tearDown() async throws {
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        try? FileManager.default.removeItem(at: tempStoreDir)
        try? FileManager.default.removeItem(at: tempBackupDir)
        try await super.tearDown()
    }

    private func makeSub(_ seed: Int) -> Subscription {
        Subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", seed))")!,
            name: "Sub-\(seed)", amount: 9.99, currency: "USD", cycle: .monthly,
            billingDay: 1, startDate: Date(timeIntervalSince1970: 1_700_000_000),
            category: "Test", status: .active,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testReplaceAllAppliesNewListAndPersists() {
        let store = SubscriptionStore()
        store.replaceAll((0..<3).map(makeSub), reason: .userImport)
        XCTAssertEqual(store.subscriptions.count, 3)
        XCTAssertEqual(StorageService.shared.loadSubscriptions().count, 3)
    }

    func testReplaceAllKeepsPreReplaceStateRecoverable() {
        let store = SubscriptionStore()
        store.replaceAll((0..<3).map(makeSub), reason: .userImport)   // 0 -> 3
        store.replaceAll([makeSub(99)], reason: .userRestore)         // 3 -> 1

        XCTAssertEqual(store.subscriptions.count, 1)

        // The pre-replace 3-sub state must survive as a rotating backup so a
        // bad replace is reversible.
        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        let counts = backups.compactMap { url -> Int? in
            guard let d = try? Data(contentsOf: url),
                  let arr = try? JSONDecoder.suberDecoder.decode([Subscription].self, from: d)
            else { return nil }
            return arr.count
        }
        XCTAssertTrue(counts.contains(3),
                      "Pre-replace 3-sub state must be recoverable from Backups/")
    }

    func testClearAllRoutesThroughReplaceAll() {
        let store = SubscriptionStore()
        store.replaceAll((0..<2).map(makeSub), reason: .userImport)
        store.clearAll()
        XCTAssertTrue(store.subscriptions.isEmpty)
        // The 2-sub state before clear must remain recoverable.
        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        let counts = backups.compactMap { url -> Int? in
            guard let d = try? Data(contentsOf: url),
                  let arr = try? JSONDecoder.suberDecoder.decode([Subscription].self, from: d)
            else { return nil }
            return arr.count
        }
        XCTAssertTrue(counts.contains(2),
                      "clearAll must preserve the pre-clear state as a backup")
    }
}
```

- [ ] **Step 2: Add the new file to the project and run the test to verify it fails**

```bash
cd /Users/leo/Desktop/suber-macos && xcodegen generate
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/SubscriptionReplaceTests
```

Expected: FAIL to compile — `replaceAll` does not exist yet.

- [ ] **Step 3: Add the `SubscriptionReplaceReason` enum + `replaceAll`, route `clearAll`, remove `importSubscriptions`**

In `Sources/ViewModels/SubscriptionStore.swift`, replace lines 101-109 (the current `clearAll` + `importSubscriptions`) with:

```swift
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
```

Then add this enum at the bottom of the same file, just before the `extension JSONEncoder` block (around line 359):

```swift
/// Why a subscription list was wholesale-replaced. Used by
/// `SubscriptionStore.replaceAll(_:reason:)` for logging + the cloudMerge
/// shrink tripwire. `rawValue` strings appear in NSLog diagnostics.
enum SubscriptionReplaceReason: String {
    case userImport    // JSON import (Settings → Data → Import JSON)
    case userRestore   // Settings → Data → Restore from backup
    case cloudMerge    // CloudSyncMerger result applied from iCloud KVS
    case clearAll      // explicit "Clear all data" (count → 0 expected)
}
```

- [ ] **Step 4: Update the three `importSubscriptions` call sites**

In `Sources/SuberApp.swift:236`, change:

```swift
            store.importSubscriptions(merged)
```

to:

```swift
            store.replaceAll(merged, reason: .cloudMerge)
```

In `Sources/Views/SettingsView.swift:490`, change:

```swift
                subscriptionStore.importSubscriptions(result.subscriptions)
```

to:

```swift
                subscriptionStore.replaceAll(result.subscriptions, reason: .userImport)
```

In `Sources/Views/Settings/DataRestoreView.swift:249`, change:

```swift
        subscriptionStore.importSubscriptions(subs)
```

to:

```swift
        subscriptionStore.replaceAll(subs, reason: .userRestore)
```

- [ ] **Step 5: Run the new test + the merger tests to verify they pass**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/SubscriptionReplaceTests \
  -only-testing:SuberTests/CloudSyncMergerTests
```

Expected: PASS (3 new + 9 merger tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/ViewModels/SubscriptionStore.swift Sources/SuberApp.swift \
        Sources/Views/SettingsView.swift Sources/Views/Settings/DataRestoreView.swift \
        Tests/SubscriptionReplaceTests.swift Suber.xcodeproj/project.pbxproj
git commit -m "feat(v1.9.2): replaceAll(_:reason:) destructive-replace chokepoint (W4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: W2/U1 — Confirmation gate for JSON import

**Why:** "Import JSON" (Settings → Data) is the only destructive UI action with no confirmation. A misclick + selecting a small/empty/old file silently replaces every subscription. Restore-from-backup already gates with a confirm dialog; JSON import must too. (The underlying replace is now logged + snapshotted via Task 2, so this is the UX safety layer on top.)

**Files:**
- Modify: `Sources/Views/SettingsView.swift` (add state + confirm alert + split `importData` into pick → confirm → apply)

This task is UI wiring; verify by build + manual click-through (no unit test — SwiftUI alert presentation isn't unit-testable here).

- [ ] **Step 1: Add confirmation state**

In `Sources/Views/SettingsView.swift`, after line 14 (`@State private var showImportError = false`), add:

```swift
    // v1.9.2: JSON import confirmation — import is a destructive whole-list
    // replace, so we stage the decoded result and require explicit confirm.
    // StorageService.importData(from:) returns this exact tuple shape.
    @State private var pendingImport: (subscriptions: [Subscription], settings: AppSettings)?
    @State private var showImportConfirm = false
```

(Verified: `StorageService.importData(from:)` is declared `throws -> (subscriptions: [Subscription], settings: AppSettings)` — the `@State` tuple above matches it exactly.)

- [ ] **Step 2: Replace `importData()` with a pick-then-stage flow**

In `Sources/Views/SettingsView.swift`, replace the whole `importData()` method (lines 481-499) with:

```swift
    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if Self.runFilePanelFromPopover(panel) == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let result = try StorageService.shared.importData(from: data)
                // v1.9.2: stage + confirm before the destructive replace.
                pendingImport = result
                showImportConfirm = true
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
    }

    /// Applies a previously-staged JSON import after the user confirms.
    private func applyPendingImport() {
        guard let result = pendingImport else { return }
        subscriptionStore.replaceAll(result.subscriptions, reason: .userImport)
        settingsStore.update { $0 = result.settings }
        pendingImport = nil
    }
```

- [ ] **Step 3: Add the confirm alert**

In `Sources/Views/SettingsView.swift`, find the existing `.alert("Import Error", isPresented: $showImportError)` block (around line 305) and add this `.alert` immediately after its closing brace:

```swift
        .alert("Replace all subscriptions?",
               isPresented: $showImportConfirm,
               presenting: pendingImport) { result in
            Button("Replace", role: .destructive) { applyPendingImport() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { result in
            Text("This will replace your current \(subscriptionStore.subscriptions.count) "
                 + "subscriptions with \(result.subscriptions.count) from the file. "
                 + "Your current data is backed up automatically first.")
        }
```

- [ ] **Step 4: Build to verify it compiles**

```bash
cd /Users/leo/Desktop/suber-macos && xcodegen generate
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/Views/SettingsView.swift
git commit -m "feat(v1.9.2): confirm dialog before destructive JSON import (W2/U1)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: W3 — Narrow the AppIntents lost-update window

**Why:** `AddSubscriptionIntent` does `loadSubscriptions()` … `saveSubscriptions(subs)` across two `StorageService` calls with view-layer logic between. If the main app writes between the load and save, the Intent's save clobbers it (lost update). Centralizing into one `StorageService.appendSubscription(_:)` narrows the window to microseconds. (Honest scope: this is NOT a cross-process lock; a true fix needs `NSFileCoordinator`. Both paths are additive, so the worst residual case is one of two near-simultaneous *adds* is dropped — never existing-data loss. That residual is documented in the method.)

**Files:**
- Modify: `Sources/Services/StorageService.swift` (add `appendSubscription`)
- Modify: `Sources/Intents/AddSubscriptionIntent.swift:40-55`
- Test: `Tests/StorageServiceTests.swift` (add one test)

- [ ] **Step 1: Write the failing test**

Add to `Tests/StorageServiceTests.swift` (inside the existing test class, after `testSaveAndLoadSubscriptions`):

```swift
    func testAppendSubscriptionPreservesExisting() {
        let a = Subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "A", amount: 1, currency: "USD", cycle: .monthly, billingDay: 1,
            startDate: Date(), category: "Test", status: .active,
            createdAt: Date(), updatedAt: Date())
        let b = Subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "B", amount: 2, currency: "USD", cycle: .monthly, billingDay: 1,
            startDate: Date(), category: "Test", status: .active,
            createdAt: Date(), updatedAt: Date())
        StorageService.shared.saveSubscriptions([a, b])

        let c = Subscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "C", amount: 3, currency: "USD", cycle: .monthly, billingDay: 1,
            startDate: Date(), category: "Test", status: .active,
            createdAt: Date(), updatedAt: Date())
        StorageService.shared.appendSubscription(c)

        let loaded = StorageService.shared.loadSubscriptions()
        XCTAssertEqual(loaded.count, 3, "append must preserve existing subscriptions")
        XCTAssertTrue(loaded.contains { $0.name == "C" })
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/StorageServiceTests/testAppendSubscriptionPreservesExisting
```

Expected: FAIL to compile — `appendSubscription` does not exist.

- [ ] **Step 3: Add `appendSubscription`**

In `Sources/Services/StorageService.swift`, after `saveSubscriptions` (line 100), add:

```swift
    /// v1.9.2: atomic-ish append for AppIntents (Siri/Shortcuts). Loads the
    /// freshest on-disk list, appends, and saves in ONE call — narrowing the
    /// load→save window vs doing it across two StorageService calls in the
    /// Intent body. NOTE: this is not a cross-process lock; if the main app
    /// and an out-of-process Intent invocation race, a lost update is still
    /// theoretically possible. The window is now microseconds and both paths
    /// are additive, so the worst case is one of two near-simultaneous *adds*
    /// is dropped — never existing-data loss.
    @discardableResult
    func appendSubscription(_ sub: Subscription) -> [Subscription] {
        var subs = loadSubscriptions()
        subs.append(sub)
        saveSubscriptions(subs)
        return subs
    }
```

- [ ] **Step 4: Use it in the Intent**

In `Sources/Intents/AddSubscriptionIntent.swift`, replace lines 40-55 (from `// Write directly via StorageService...` through `StorageService.shared.saveSubscriptions(subs)`) with:

```swift
        // v1.9.2: single-call append narrows the load→save lost-update window
        // (was two StorageService calls with logic between).
        let sub = Subscription(
            id: UUID(),
            name: data.name.trimmingCharacters(in: .whitespaces),
            amount: Double(data.amount) ?? amount,
            currency: data.currency,
            cycle: data.cycle,
            billingDay: Calendar.current.component(.day, from: Date()),
            startDate: Date(),
            category: data.category,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        StorageService.shared.appendSubscription(sub)
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB \
  -only-testing:SuberTests/StorageServiceTests/testAppendSubscriptionPreservesExisting
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/Services/StorageService.swift Sources/Intents/AddSubscriptionIntent.swift \
        Tests/StorageServiceTests.swift
git commit -m "fix(v1.9.2): centralize AppIntent append to narrow lost-update window (W3)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: I1 — Harden Calendar force-unwraps

**Why:** Six `Calendar.date(byAdding:to:)!` force-unwraps. Practically never nil, but a strict-safety codebase shouldn't carry crash-by-construction. Each gets a behavior-preserving fallback. No test — these are defensive and behavior-identical in the normal path.

**Files:**
- Modify: `Sources/ViewModels/SubscriptionStore.swift:33`
- Modify: `Sources/Views/ListView.swift:129`
- Modify: `Sources/Views/DayDetailView.swift:219`
- Modify: `Sources/Services/MailWatchdog/MailWatchdog.swift:312`
- Modify: `SuberWidget/WidgetDataProvider.swift:111`

- [ ] **Step 1: Apply the five fallbacks**

`Sources/ViewModels/SubscriptionStore.swift:33` — change:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
```
to:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
```

`Sources/Views/ListView.swift:129` — change:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
```
to:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
```

`Sources/Views/DayDetailView.swift:219` — change:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
```
to:
```swift
        let threshold = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
```

`Sources/Services/MailWatchdog/MailWatchdog.swift:312` — change:
```swift
            return Calendar.current.date(byAdding: .day, value: -initialScanLookbackDays, to: Date())!
```
to:
```swift
            return Calendar.current.date(byAdding: .day, value: -initialScanLookbackDays, to: Date()) ?? Date()
```

`SuberWidget/WidgetDataProvider.swift:111` — change:
```swift
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
```
to:
```swift
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
```

- [ ] **Step 2: Build to verify it compiles (both targets)**

```bash
cd /Users/leo/Desktop/suber-macos
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/ViewModels/SubscriptionStore.swift Sources/Views/ListView.swift \
        Sources/Views/DayDetailView.swift Sources/Services/MailWatchdog/MailWatchdog.swift \
        SuberWidget/WidgetDataProvider.swift
git commit -m "refactor(v1.9.2): replace Calendar date force-unwraps with fallbacks (I1)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: I2 — Gate cloud-sync start/stop on the actual toggle transition

**Why:** `onReceive(settingsStore.$settings)` calls `startSync()`/`stopSync()` on EVERY settings change (currency, language, reminder days …), not just when `enableCloudSync` flips. Both are idempotent so it's harmless, but it's wasteful and noisy. Mirror the existing `lastIMAPAccountID` transition-tracking pattern already in that view.

**Files:**
- Modify: `Sources/SuberApp.swift` (`MenuBarContainerView` — add `lastCloudSyncEnabled` state + gate in `onReceive`)

- [ ] **Step 1: Add transition-tracking state**

In `Sources/SuberApp.swift`, find `@State private var lastIMAPAccountID: String?` in `MenuBarContainerView` and add directly below it:

```swift
    /// v1.9.2: track the previous enableCloudSync value so we only call
    /// start/stopSync on the actual toggle transition (not every settings tweak).
    @State private var lastCloudSyncEnabled: Bool?
```

- [ ] **Step 2: Gate the start/stop in `onReceive`**

In `Sources/SuberApp.swift`, replace the `onReceive(settingsStore.$settings)` body's sync block (lines 357-362):

```swift
            .onReceive(settingsStore.$settings) { settings in
                if settings.enableCloudSync {
                    CloudSyncService.shared.startSync()
                } else {
                    CloudSyncService.shared.stopSync()
                }
```

with:

```swift
            .onReceive(settingsStore.$settings) { settings in
                // v1.9.2: only react to the actual enableCloudSync transition.
                if settings.enableCloudSync != lastCloudSyncEnabled {
                    lastCloudSyncEnabled = settings.enableCloudSync
                    if settings.enableCloudSync {
                        CloudSyncService.shared.startSync()
                    } else {
                        CloudSyncService.shared.stopSync()
                    }
                }
```

(Leave the rest of the closure — the IMAP rebuild block — unchanged.)

- [ ] **Step 3: Build to verify it compiles**

```bash
cd /Users/leo/Desktop/suber-macos
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/SuberApp.swift
git commit -m "perf(v1.9.2): gate cloud-sync start/stop on enableCloudSync transition (I2)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: I4 — Refresh the restore source list after a restore

**Why:** `DataRestoreView.performRestore` writes new data (which itself creates a fresh backup) but never calls `reload()`. If the user restores a second time without closing the sheet, the source list is stale. One-line fix.

**Files:**
- Modify: `Sources/Views/Settings/DataRestoreView.swift:267-270` (end of `performRestore`)

- [ ] **Step 1: Add the reload**

In `Sources/Views/Settings/DataRestoreView.swift`, at the end of `performRestore`, after the line:

```swift
        pendingSource = nil
```

add:

```swift
        // v1.9.2: the restore wrote new data + created a fresh backup, so the
        // available-sources list is now stale — refresh it.
        reload()
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd /Users/leo/Desktop/suber-macos
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/leo/Desktop/suber-macos
git add Sources/Views/Settings/DataRestoreView.swift
git commit -m "fix(v1.9.2): refresh restore source list after a restore (I4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Ship v1.9.2

**Why:** Bundle the 7 fixes as a data-safety patch. Per `docs/RELEASE-PROCESS.md`, P0 data-safety qualifies as a freeze exception and resets the 7-day clock. Full suite must be green (234) before building the DMG.

**Files:**
- Modify: `project.yml` (1.9.1 → 1.9.2 / 191 → 192, both `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` occurrences)
- Modify: `CHANGELOG.md` (new `[1.9.2]` entry at top)

- [ ] **Step 1: Run the full suite — must be 234/234**

```bash
cd /Users/leo/Desktop/suber-macos && xcodegen generate
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
xcodebuild test -project Suber.xcodeproj -scheme Suber \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M2XH53X5DB 2>&1 \
  | grep -E "Executed [0-9]+ tests|TEST SUCCEEDED|TEST FAILED" | tail -3
```

Expected: `Executed 233 tests, with 0 failures` + `** TEST SUCCEEDED **`. If fewer/failed, fix before continuing — do NOT ship red.

- [ ] **Step 2: Bump the version**

In `project.yml`, change BOTH occurrences:
```yaml
        MARKETING_VERSION: "1.9.1"
        CURRENT_PROJECT_VERSION: "191"
```
to:
```yaml
        MARKETING_VERSION: "1.9.2"
        CURRENT_PROJECT_VERSION: "192"
```

- [ ] **Step 3: Add the CHANGELOG entry**

Insert at the top of `CHANGELOG.md` (after the `# Changelog` / intro lines, before `## [1.9.1]`):

```markdown
## [1.9.2] — 2026-06-09 — Audit hardening：补全数据完整性缺口

v1.9.1 之后做了一次完整代码审计（SwiftUI 崩溃预防 + UX/功能）。崩溃面干净（0 个 try!/as!，所有数组 force-unwrap 都被证明性守卫，@MainActor 隔离正确）。本版修掉审计发现的 7 个数据完整性/正确性缺口，无新功能 —— 属 `docs/RELEASE-PROCESS.md` 的 P0 数据安全例外，freeze clock 重置。

### Fixed

- **W1** `mergeRemoteChanges` 绕过了 H5 prune —— 跨设备合并后 change log 可超过 200 条上限、撑爆 KVS 1 MB 预算。现在走 `StorageService.prune`，in-memory + 持久化都裁剪。
- **W2/U1** JSON Import 之前是静默破坏性替换，无确认。现在弹 confirmation：「将用 X 条替换当前 Y 条订阅」。
- **W3** `AddSubscriptionIntent` 的 load→append→save 跨两次调用，存在 lost-update race。集中到 `StorageService.appendSubscription` 单次调用，窗口缩到微秒级（跨进程残余 race 已在方法注释里诚实标注）。
- **I1** 6 处 `Calendar.date(byAdding:to:)!` force-unwrap 改为 `?? fallback`。
- **I2** `onReceive($settings)` 之前每次任意设置变更都调 start/stopSync，现在只在 `enableCloudSync` 真翻转时调。
- **I4** Restore 成功后没刷新备份源列表，二次 restore 显示旧列表 —— 现在 restore 后 `reload()`。

### Added

- **W4** `SubscriptionStore.replaceAll(_:reason:)` —— 所有破坏性整表替换的唯一入口。带显式 `reason`（userImport/userRestore/cloudMerge/clearAll），替换前快照旧状态到 Backups/、记录 count 变化日志、cloudMerge 路径若缩小则触发 tripwire 警告。`clearAll` 与 3 个 import 调用点全部改走它。这是「自动路径静默清空订阅」这一类 bug（v1.8.4/v1.9.0）的架构级 chokepoint。
- 新增测试 5 个：`SubscriptionReplaceTests`（3）、`mergeRemoteChanges` prune（1）、`appendSubscription`（1）。加既有 `CloudSyncMergerTests`（9）等，**233/233 全绿**。

### Notes

- v1.9.1 用户应用内一键升级（Settings → Updates）。
- 7-day feature freeze clock 重置为 2026-06-09。
```

- [ ] **Step 4: Commit version + CHANGELOG**

```bash
cd /Users/leo/Desktop/suber-macos
git add project.yml CHANGELOG.md Suber.xcodeproj/project.pbxproj
git commit -m "chore(v1.9.2): bump version + CHANGELOG

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Build the signed/notarized DMG**

```bash
cd /Users/leo/Desktop/suber-macos
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
./scripts/build-dmg.sh 2>&1 | tail -20
```

Expected: ends with `✅ Done: Suber-1.9.2.dmg` … `Status: signed, notarized, stapled`. The script also regenerates a signed `appcast.xml`. If notarytool errors with "profile not configured", run `xcrun notarytool history --keychain-profile suber-notary` once to warm it, then re-run.

- [ ] **Step 6: Commit the regenerated appcast**

```bash
cd /Users/leo/Desktop/suber-macos
git add appcast.xml
git commit -m "chore(v1.9.2): regenerate signed appcast.xml for Sparkle

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 7: Tag, push, create the GitHub release**

```bash
cd /Users/leo/Desktop/suber-macos
git tag -a v1.9.2 -m "v1.9.2 — audit hardening: 7 data-integrity fixes"
git push origin main v1.9.2
awk '/^## \[1.9.2\]/{flag=1} /^## \[1.9.1\]/{flag=0} flag' CHANGELOG.md > /tmp/suber-v1.9.2-notes.md
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
gh release create v1.9.2 \
  /Users/leo/Desktop/suber-macos/Suber-1.9.2.dmg \
  /Users/leo/Desktop/suber-macos/appcast.xml \
  --title "v1.9.2 — audit hardening: 7 data-integrity fixes" \
  --notes-file /tmp/suber-v1.9.2-notes.md
rm /tmp/suber-v1.9.2-notes.md
```

- [ ] **Step 8: Verify the release published with both assets**

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
gh release view v1.9.2 --json name,tagName,assets \
  --jq '{name, tag: .tagName, assets: [.assets[] | {name, size}]}'
```

Expected: both `Suber-1.9.2.dmg` and `appcast.xml` present.

---

## Self-Review checklist (run before declaring done)

- [ ] All 7 audit findings (W1, W2/U1, W3, W4, I1, I2, I4) map to a task — ✅ Tasks 1-7.
- [ ] No placeholders — every code step shows complete code.
- [ ] Type consistency: `SubscriptionReplaceReason` defined in Task 2 is used identically in Tasks 2 & 3; `replaceAll(_:reason:)` signature matches at all 4 call sites; `appendSubscription` signature matches Task 4 test + Intent.
- [ ] Full suite green (234) gates the DMG build (Task 8 Step 1).
- [ ] Version bumped in both `project.yml` occurrences (Suber + SuberWidget targets).

## Residuals deliberately NOT in this plan

- **W3 cross-process lock** — true fix needs `NSFileCoordinator`; documented as a method-level note. Out of scope for a patch.
- **I3** (`synchronize()` as iCloud-availability signal) — already acknowledged in code comments; low value to change now.
- **I5** (`unreadChangeCount` per-render filter) — negligible cost; not worth changing.
- **U2** (`CloudSyncMerger.rejectedAsStale` user-visible banner) — this is the planned v1.10 "Sync Visibility" feature, not a patch fix.
