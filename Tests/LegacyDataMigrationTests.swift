import XCTest
@testable import Suber

/// v1.8.4: LegacyDataMigration is now HARD-DISABLED (see runIfNeeded
/// header for the data-loss bug it caused). These tests now verify the
/// disabled behavior — runIfNeeded must NEVER touch AppGroupStore,
/// regardless of input.
///
/// This is a deliberately defensive test surface: if anyone ever re-
/// enables the migration body without also fixing the existing-data
/// guard + path verification + atomic backup, these tests catch it.
final class LegacyDataMigrationTests: XCTestCase {

    var fixturePlistURL: URL!
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        LegacyDataMigration.resetForTests()
        // AUDIT-v1.9.2 C-01: sandbox AppGroupStore into a fresh temp dir.
        // The old setUp/tearDown cleared the user's REAL live keys, and
        // testNeverOverwritesExistingAppGroupStoreData wrote fixture bytes
        // into the user's real `suber-subscriptions`.
        // DataBackupManager must be sandboxed too: AppGroupStore.set's
        // post-write hook snapshots the 3 critical keys, so the fixture
        // write would otherwise rotate into the user's real Backups/.
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-migration-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-migration-backup-\(UUID().uuidString)")
        AppGroupStore.testOverrideDirectory = tempStoreDir
        DataBackupManager.testOverrideDirectory = tempBackupDir
        fixturePlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-migration-test-\(UUID().uuidString).plist")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixturePlistURL)
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
        if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
        try await super.tearDown()
    }

    /// runIfNeeded must be a no-op when no plist exists (already true before;
    /// confirm v1.8.4 hard-disable doesn't regress this).
    func testNoOpWhenLegacyPlistMissing() {
        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)
        XCTAssertNil(AppGroupStore.data(forKey: "suber-subscriptions"))
    }

    /// **Critical regression test (v1.8.4)** — even when a legacy plist
    /// exists with valid data, runIfNeeded MUST NOT migrate. The function
    /// is permanently disabled to prevent the data-loss bug observed in
    /// v1.8.0–v1.8.3.
    func testHardDisabledEvenWhenPlistExists() throws {
        let payload: [String: Any] = [
            "suber-subscriptions": Data("[would-have-migrated]".utf8),
            "suber-settings": Data("[would-have-migrated]".utf8),
            "suber-changes": Data("[would-have-migrated]".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fixturePlistURL)

        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)

        XCTAssertNil(AppGroupStore.data(forKey: "suber-subscriptions"),
                     "v1.8.4: migration is hard-disabled — must NOT migrate even when plist exists")
        XCTAssertNil(AppGroupStore.data(forKey: "suber-settings"))
        XCTAssertNil(AppGroupStore.data(forKey: "suber-changes"))
    }

    /// **Critical regression test (v1.8.4)** — existing AppGroupStore data
    /// must be preserved no matter what. This is the bug user hit:
    /// 9 real subs got overwritten with stale plist content.
    func testNeverOverwritesExistingAppGroupStoreData() throws {
        // Pre-populate AppGroupStore with user's real data
        AppGroupStore.set(Data("USER-REAL-DATA-9-SUBS".utf8), forKey: "suber-subscriptions")

        // Drop a legacy plist with stale data that WOULD have caused overwrite
        let payload: [String: Any] = [
            "suber-subscriptions": Data("STALE-OLD-PLIST-DATA".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fixturePlistURL)

        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)

        // User's real data must still be there, untouched
        XCTAssertEqual(AppGroupStore.data(forKey: "suber-subscriptions"),
                       Data("USER-REAL-DATA-9-SUBS".utf8),
                       "Real user data must NEVER be overwritten — this was the v1.8.0 bug")
    }
}
