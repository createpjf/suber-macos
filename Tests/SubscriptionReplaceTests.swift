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
