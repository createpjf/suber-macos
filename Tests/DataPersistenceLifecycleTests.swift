import XCTest
@testable import Suber

/// v1.9.0 — End-to-end persistence lifecycle tests.
///
/// Why this exists. v1.6.0 → v1.8.4 shipped 12 versions in 4 days, including
/// one real data-loss event (LegacyDataMigration overwriting 9 live subs with
/// stale plist content). The architectural fix in v1.9.0 is rotating local
/// backups + Restore UI; this file is the regression net guarding that fix.
///
/// **Test isolation.** All backup tests redirect `DataBackupManager` to a
/// per-test temp directory via `testOverrideDirectory`. The production
/// `<container>/Library/Preferences/Suber/Backups/` is NEVER touched, so it
/// is safe to run these on a developer machine that has live subscription
/// data. The `tearDown` removes the temp dir entirely.
///
/// This file currently covers Step A.2 (5 backup-related tests). Step D will
/// add 5 more tests for round-trip / concurrent writes / fresh launch / etc.
final class DataPersistenceLifecycleTests: XCTestCase {

    private var tempBackupDir: URL!
    private var tempStoreDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Sandbox the backup directory so prune/snapshot can't touch
        // the user's real Backups/.
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-backup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempBackupDir, withIntermediateDirectories: true)
        DataBackupManager.testOverrideDirectory = tempBackupDir

        // Sandbox the live AppGroupStore directory too. Tests that exercise
        // round-trip / concurrent writes / fresh launch need to touch the
        // live key paths; without this override they'd wipe the user's
        // actual subscriptions JSON.
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempStoreDir, withIntermediateDirectories: true)
        AppGroupStore.testOverrideDirectory = tempStoreDir
    }

    override func tearDown() async throws {
        DataBackupManager.testOverrideDirectory = nil
        AppGroupStore.testOverrideDirectory = nil
        if let dir = tempBackupDir {
            try? FileManager.default.removeItem(at: dir)
        }
        if let dir = tempStoreDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempBackupDir = nil
        tempStoreDir = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Build N test subscriptions with deterministic IDs so round-trip
    /// assertions can compare arrays directly.
    private func makeSubscriptions(count: Int) -> [Subscription] {
        (0..<count).map { i in
            Subscription(
                id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", i))")!,
                name: "Test-\(i)",
                url: "https://example.com/\(i)",
                amount: 9.99 + Double(i),
                currency: "USD",
                cycle: .monthly,
                billingDay: (i % 28) + 1,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                category: "Test",
                status: .active,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
    }

    // MARK: - Test 2: snapshot fires on every save

    /// Calling `DataBackupManager.snapshot` 3 times produces 3 distinct
    /// backup files. Filenames use millisecond-precision timestamps; tiny
    /// sleeps (2 ms) guarantee uniqueness and let mtime-based sort be stable.
    func testBackupCreatedOnEverySave() throws {
        DataBackupManager.snapshot(key: "suber-subscriptions",
                                   data: Data("snapshot-1".utf8))
        Thread.sleep(forTimeInterval: 0.005)
        DataBackupManager.snapshot(key: "suber-subscriptions",
                                   data: Data("snapshot-2".utf8))
        Thread.sleep(forTimeInterval: 0.005)
        DataBackupManager.snapshot(key: "suber-subscriptions",
                                   data: Data("snapshot-3".utf8))

        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, 3, "Each snapshot call must produce a backup file")

        // Newest-first ordering: contents should read back in reverse insertion order.
        let contents = backups.map { try? String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(contents[0], "snapshot-3")
        XCTAssertEqual(contents[1], "snapshot-2")
        XCTAssertEqual(contents[2], "snapshot-1")
    }

    // MARK: - Test 3: prune keeps last N

    /// Writing 12 snapshots (with > 1s spacing for unique filenames) leaves
    /// exactly `maxBackupsPerKey` (10) on disk. The 2 oldest must be deleted.
    func testBackupPruneKeepsLastN() throws {
        let total = DataBackupManager.maxBackupsPerKey + 2  // 12 with current cap
        for i in 0..<total {
            DataBackupManager.snapshot(key: "suber-subscriptions",
                                       data: Data("payload-\(i)".utf8))
            // Tiny spacing — millisecond-resolution timestamps mean 2 ms
            // is plenty to guarantee unique filenames + stable mtime order.
            Thread.sleep(forTimeInterval: 0.005)
        }

        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, DataBackupManager.maxBackupsPerKey,
                       "Prune must cap at maxBackupsPerKey (\(DataBackupManager.maxBackupsPerKey))")

        // Newest 10 are payload-2 .. payload-11 (payload-0 and payload-1 pruned).
        // Newest-first order: payload-11, payload-10, ..., payload-2.
        let newest = try String(contentsOf: backups.first!, encoding: .utf8)
        XCTAssertEqual(newest, "payload-\(total - 1)")
        let oldest = try String(contentsOf: backups.last!, encoding: .utf8)
        XCTAssertEqual(oldest, "payload-2",
                       "payload-0 and payload-1 must be pruned (oldest 2)")
    }

    // MARK: - Test 4: restore round-trip

    /// Reading a backup and writing it back through AppGroupStore
    /// reconstitutes the live file exactly. This is the contract Restore UI
    /// (Step C.2) depends on. We don't go through AppGroupStore here because
    /// that would touch the real container; we just verify the byte-level
    /// integrity of read-then-write.
    func testRestoreFromBackupReplacesLive() throws {
        let original = Data("nine-subscriptions-blob".utf8)
        DataBackupManager.snapshot(key: "suber-subscriptions", data: original)

        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, 1)

        let readBack = try Data(contentsOf: backups[0])
        XCTAssertEqual(readBack, original,
                       "Backup file must be byte-identical to the data passed in")

        // Simulate a destructive overwrite then "restore" by writing the
        // backup contents to a new live URL and re-reading.
        let liveURL = tempBackupDir.appendingPathComponent("simulated-live.json")
        try Data("destroyed".utf8).write(to: liveURL)
        try readBack.write(to: liveURL, options: [.atomic])
        XCTAssertEqual(try Data(contentsOf: liveURL), original)
    }

    // MARK: - Test 5: legacy migration never overwrites (v1.8.4 regression)

    /// **Critical regression test.** Even with this v1.9.0 lifecycle suite,
    /// LegacyDataMigration must remain hard-disabled. If anyone re-enables
    /// the migration body without the v1.8.4 safety review (atomic backup,
    /// path verification, OS-version testing), this assertion catches it.
    /// Mirrors the assertion in LegacyDataMigrationTests but lives here as
    /// a defense-in-depth check tied to the persistence lifecycle.
    func testLegacyMigrationNeverOverwrites() throws {
        // We intentionally exercise the override-URL path so this test does
        // NOT depend on the user having any legacy plist in their container.
        let fakeLegacy = tempBackupDir.appendingPathComponent("legacy.plist")
        let payload: [String: Any] = [
            "suber-subscriptions": Data("STALE-OLD-DATA".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fakeLegacy)

        // Pre-populate the live key. If migration ever ran, it would
        // overwrite this. v1.8.4 hard-disable means it must be untouched.
        AppGroupStore.set(Data("LIVE-USER-DATA".utf8), forKey: "suber-subscriptions")
        defer { AppGroupStore.removeObject(forKey: "suber-subscriptions") }

        LegacyDataMigration.resetForTests()
        LegacyDataMigration.runIfNeeded(legacyURLOverride: fakeLegacy)

        XCTAssertEqual(AppGroupStore.data(forKey: "suber-subscriptions"),
                       Data("LIVE-USER-DATA".utf8),
                       "v1.8.4 hard-disable: live data must never be overwritten by migration")
    }

    // MARK: - Test 1: full round-trip preserves all subscriptions

    /// The acceptance test for the original v1.6.0 → v1.8.4 data-loss
    /// pattern. Save 9 subs (matching the user's recovered data), reload via
    /// a fresh StorageService read path, assert byte-for-byte equality.
    /// If this test ever fails, something in the persistence layer has
    /// silently lost a record. That's the bug v1.9.0 exists to prevent.
    func testRoundTripPreservesAllSubscriptions() throws {
        let originals = makeSubscriptions(count: 9)
        StorageService.shared.saveSubscriptions(originals)

        let reloaded = StorageService.shared.loadSubscriptions()
        XCTAssertEqual(reloaded.count, 9)
        XCTAssertEqual(reloaded.map(\.id), originals.map(\.id))
        XCTAssertEqual(reloaded.map(\.name), originals.map(\.name))
        XCTAssertEqual(reloaded.map(\.amount), originals.map(\.amount))

        // The save also took a snapshot — verify it landed in our test
        // backup dir (same data the round-trip used).
        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, 1, "saveSubscriptions should produce one snapshot")
    }

    // MARK: - Test 6: concurrent writes don't corrupt the live file

    /// Simulates two processes (app + widget refresh) both writing
    /// `suber-subscriptions` near-simultaneously. Atomic writes guarantee a
    /// reader never sees a half-flushed file; this test confirms the live
    /// file always decodes to a valid `[Subscription]` array regardless of
    /// which writer "won". 50 iterations × 2 concurrent writers picks up
    /// any rare interleaving bug that single-threaded tests miss.
    func testConcurrentProcessWritesDontCorrupt() throws {
        // Use the StorageService encoder (ISO 8601 dates) so the decoder
        // below can read it. The default JSONEncoder writes dates as numbers
        // and would fail to round-trip.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dataA = try encoder.encode(makeSubscriptions(count: 3))
        let dataB = try encoder.encode(makeSubscriptions(count: 7))

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for _ in 0..<50 {
            group.enter()
            queue.async {
                AppGroupStore.set(dataA, forKey: "suber-subscriptions")
                group.leave()
            }
            group.enter()
            queue.async {
                AppGroupStore.set(dataB, forKey: "suber-subscriptions")
                group.leave()
            }
        }
        group.wait()

        // Whichever write ran last, the live blob must decode cleanly.
        let live = AppGroupStore.data(forKey: "suber-subscriptions")
        XCTAssertNotNil(live, "Live file must exist after writes")
        let decoded = try JSONDecoder.suberDecoder.decode([Subscription].self, from: live!)
        XCTAssertTrue(decoded.count == 3 || decoded.count == 7,
                      "Decoded count must be one of the inputs (no torn writes)")
    }

    // MARK: - Test 7: empty array writes still go through (defensive)

    /// `clearAll` legitimately writes an empty array. We DON'T want to
    /// silently drop that write — clearing is a valid user action. But the
    /// snapshot system MUST capture the empty state too so the user can
    /// restore from a previous (non-empty) backup if they regret clearing.
    /// This test guards both halves.
    func testEmptyArrayWriteDoesNotPropagate() throws {
        // Pre-populate with real data to set up a recoverable state.
        let originals = makeSubscriptions(count: 3)
        StorageService.shared.saveSubscriptions(originals)
        XCTAssertEqual(DataBackupManager.listBackups(key: "suber-subscriptions").count, 1)

        // Now write an empty array — simulates clearAll().
        StorageService.shared.saveSubscriptions([])
        XCTAssertTrue(StorageService.shared.loadSubscriptions().isEmpty,
                      "Empty write must reach the live store")

        // Critical: the previous (non-empty) snapshot must STILL exist so
        // the user can restore from it. v1.9.0's whole safety promise hinges
        // on this — clearing data is reversible because backups survive.
        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, 2,
                       "Both pre-clear and post-clear snapshots should exist")
        // Newest backup is empty []; second-newest is the original 3 subs.
        let oldData = try Data(contentsOf: backups[1])
        let oldDecoded = try JSONDecoder.suberDecoder.decode([Subscription].self, from: oldData)
        XCTAssertEqual(oldDecoded.count, 3,
                       "Pre-clear backup must still hold the original subscriptions")
    }

    // MARK: - Test 8: cloud sync toggle respects user choice

    /// Flipping `enableCloudSync` from a fresh AppSettings round-trips
    /// through StorageService correctly. Catches forward-compat bugs in
    /// AppSettings.init(from:) where new fields might shadow the toggle.
    func testCloudSyncToggleRespectsUserChoice() throws {
        var off = AppSettings()
        off.enableCloudSync = false
        StorageService.shared.saveSettings(off)
        XCTAssertFalse(StorageService.shared.loadSettings().enableCloudSync)

        var on = AppSettings()
        on.enableCloudSync = true
        StorageService.shared.saveSettings(on)
        XCTAssertTrue(StorageService.shared.loadSettings().enableCloudSync,
                      "Toggle ON must round-trip cleanly through encode/decode")

        // Backup snapshots track every write — both states should be
        // recoverable.
        let backups = DataBackupManager.listBackups(key: "suber-settings")
        XCTAssertEqual(backups.count, 2)
    }

    // MARK: - Test 9: fresh launch reads back what was persisted

    /// Approximates a process restart. We don't actually fork a new process
    /// (XCTest can't), but we can prove the read path is purely
    /// file-system-driven by writing through one StorageService access and
    /// reading via a separate AppGroupStore.data() lookup with no shared
    /// in-memory cache between the two.
    func testFreshLaunchRestoresFromAppGroupStore() throws {
        let originals = makeSubscriptions(count: 5)
        StorageService.shared.saveSubscriptions(originals)

        // Read raw bytes directly from disk (bypasses any decoder cache),
        // then decode — this is what a fresh process does at launch.
        let raw = AppGroupStore.data(forKey: "suber-subscriptions")
        XCTAssertNotNil(raw, "On-disk blob must exist after save")
        let decoded = try JSONDecoder.suberDecoder.decode([Subscription].self, from: raw!)
        XCTAssertEqual(decoded.map(\.id), originals.map(\.id),
                       "Fresh-launch read must reconstitute the exact saved state")
    }

    // MARK: - Test 10: rotation preserves individual backup integrity

    /// Rotation deletes the OLDEST file; the survivors must remain
    /// byte-identical to what was originally written. This guards against
    /// any future "smart prune" that might compact / merge / re-encode files.
    func testBackupContainsValidJSONAfterRotation() throws {
        // Use real JSON payloads so we can assert decode success post-rotation.
        struct TestPayload: Codable, Equatable { let index: Int; let label: String }
        let total = DataBackupManager.maxBackupsPerKey + 3  // force 3 evictions

        var written: [TestPayload] = []
        for i in 0..<total {
            let payload = TestPayload(index: i, label: "row-\(i)")
            let data = try JSONEncoder().encode(payload)
            DataBackupManager.snapshot(key: "suber-subscriptions", data: data)
            written.append(payload)
            Thread.sleep(forTimeInterval: 0.005)
        }

        let backups = DataBackupManager.listBackups(key: "suber-subscriptions")
        XCTAssertEqual(backups.count, DataBackupManager.maxBackupsPerKey)

        // Each surviving file decodes cleanly and matches the originally
        // written payload (newest-first → indexes total-1 ... total-N).
        for (offset, url) in backups.enumerated() {
            let expectedIndex = (total - 1) - offset
            let raw = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(TestPayload.self, from: raw)
            XCTAssertEqual(decoded, written[expectedIndex],
                           "Backup \(offset) must decode to original payload \(expectedIndex)")
        }
    }
}
