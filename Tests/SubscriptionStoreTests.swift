import XCTest
@testable import Suber

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    var store: SubscriptionStore!
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        // AUDIT-v1.9.2 C-01: sandbox ALL file I/O into fresh temp dirs.
        // The previous setUp cleared the user's REAL App Group container
        // (removeObject has no snapshot hook) and every save() here rotated
        // real Backups/ snapshots — running the suite destroyed real data.
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-store-tests-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-backup-tests-\(UUID().uuidString)")
        AppGroupStore.testOverrideDirectory = tempStoreDir
        DataBackupManager.testOverrideDirectory = tempBackupDir
        store = SubscriptionStore()
    }

    override func tearDown() {
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
        if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    func testAddSubscription() {
        var data = SubscriptionFormData()
        data.name = "Netflix"
        data.amount = "15.99"
        data.currency = "USD"
        data.cycle = .monthly
        data.billingDay = 15

        store.add(data)

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.subscriptions.first?.name, "Netflix")
        XCTAssertEqual(store.subscriptions.first?.amount, 15.99)
    }

    func testUpdateSubscription() {
        var data = SubscriptionFormData()
        data.name = "Netflix"
        data.amount = "15.99"
        store.add(data)

        let id = store.subscriptions.first!.id
        var updated = SubscriptionFormData()
        updated.name = "Netflix Premium"
        updated.amount = "22.99"

        store.update(id: id, with: updated)

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.subscriptions.first?.name, "Netflix Premium")
        XCTAssertEqual(store.subscriptions.first?.amount, 22.99)
    }

    func testDeleteSubscription() {
        var data = SubscriptionFormData()
        data.name = "Netflix"
        data.amount = "15.99"
        store.add(data)

        let id = store.subscriptions.first!.id
        store.delete(id: id)

        XCTAssertTrue(store.subscriptions.isEmpty)
    }

    func testTogglePause() {
        var data = SubscriptionFormData()
        data.name = "Netflix"
        data.amount = "15.99"
        data.status = .active
        store.add(data)

        let id = store.subscriptions.first!.id

        // Active -> Paused
        store.togglePause(id: id)
        XCTAssertEqual(store.subscriptions.first?.status, .paused)

        // Paused -> Active
        store.togglePause(id: id)
        XCTAssertEqual(store.subscriptions.first?.status, .active)
    }

    func testClearAll() {
        var data = SubscriptionFormData()
        data.name = "Netflix"
        data.amount = "15.99"
        store.add(data)

        data.name = "Spotify"
        data.amount = "9.99"
        store.add(data)

        XCTAssertEqual(store.subscriptions.count, 2)

        store.clearAll()
        XCTAssertTrue(store.subscriptions.isEmpty)
    }
}
