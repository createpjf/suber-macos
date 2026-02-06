import XCTest
@testable import SubReminder

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    var store: SubscriptionStore!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "subreminder-subscriptions")
        store = SubscriptionStore()
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
