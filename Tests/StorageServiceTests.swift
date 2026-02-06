import XCTest
@testable import SubReminder

final class StorageServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear test data
        UserDefaults.standard.removeObject(forKey: "subreminder-subscriptions")
        UserDefaults.standard.removeObject(forKey: "subreminder-settings")
    }

    func testSaveAndLoadSubscriptions() {
        let sub = Subscription(
            id: UUID(),
            name: "Netflix",
            url: "https://netflix.com",
            amount: 15.99,
            currency: "USD",
            cycle: .monthly,
            billingDay: 15,
            startDate: Date(),
            category: "Streaming",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )

        StorageService.shared.saveSubscriptions([sub])
        let loaded = StorageService.shared.loadSubscriptions()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Netflix")
        XCTAssertEqual(loaded.first?.amount, 15.99)
        XCTAssertEqual(loaded.first?.cycle, .monthly)
    }

    func testSaveAndLoadSettings() {
        var settings = AppSettings()
        settings.primaryCurrency = "EUR"
        settings.reminderDaysBefore = [1, 5, 7]

        StorageService.shared.saveSettings(settings)
        let loaded = StorageService.shared.loadSettings()

        XCTAssertEqual(loaded.primaryCurrency, "EUR")
        XCTAssertEqual(loaded.reminderDaysBefore, [1, 5, 7])
    }

    func testExportImportRoundTrip() throws {
        let sub = Subscription(
            id: UUID(),
            name: "Spotify",
            url: "https://spotify.com",
            amount: 9.99,
            currency: "USD",
            cycle: .monthly,
            billingDay: 1,
            startDate: Date(),
            category: "Music",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )

        var settings = AppSettings()
        settings.primaryCurrency = "GBP"

        let data = StorageService.shared.exportData(subscriptions: [sub], settings: settings)
        XCTAssertNotNil(data)

        let result = try StorageService.shared.importData(from: data!)
        XCTAssertEqual(result.subscriptions.count, 1)
        XCTAssertEqual(result.subscriptions.first?.name, "Spotify")
        XCTAssertEqual(result.settings.primaryCurrency, "GBP")
    }

    func testImportChromeExtensionJSON() throws {
        let chromeJSON = """
        {
          "subscriptions": [
            {
              "name": "Claude",
              "url": "https://claude.ai/",
              "logo": "https://www.google.com/s2/favicons?domain=claude.ai&sz=64",
              "amount": 124.99,
              "currency": "USD",
              "cycle": "monthly",
              "billingDay": 30,
              "startDate": "2026-01-31",
              "trialEndDate": null,
              "category": "AI",
              "status": "active",
              "notes": null,
              "id": "a650dd20-011d-4e25-b95f-9db1ad648b17",
              "createdAt": "2026-02-06T08:10:11.226Z",
              "updatedAt": "2026-02-06T08:23:55.399Z"
            },
            {
              "name": "iCloud",
              "url": "https://www.icloud.com/",
              "logo": null,
              "amount": 21,
              "currency": "CNY",
              "cycle": "monthly",
              "billingDay": 30,
              "startDate": "2026-02-01",
              "trialEndDate": null,
              "category": "Other",
              "status": "active",
              "notes": "test note",
              "id": "780fcf58-305b-4f84-92e4-985fc3a99b4e",
              "createdAt": "2026-02-06T08:25:24.124Z",
              "updatedAt": "2026-02-06T08:25:24.124Z"
            }
          ],
          "settings": {
            "primaryCurrency": "USD",
            "theme": "light",
            "reminderDaysBefore": [1, 3],
            "enableNotifications": true,
            "enableUsageTracking": true,
            "enableCloudSync": false,
            "language": "en"
          }
        }
        """
        let data = chromeJSON.data(using: .utf8)!
        let result = try StorageService.shared.importData(from: data)

        XCTAssertEqual(result.subscriptions.count, 2)
        XCTAssertEqual(result.subscriptions[0].name, "Claude")
        XCTAssertEqual(result.subscriptions[0].amount, 124.99)
        XCTAssertEqual(result.subscriptions[0].currency, "USD")
        XCTAssertEqual(result.subscriptions[0].cycle, .monthly)
        XCTAssertNil(result.subscriptions[0].notes)
        XCTAssertEqual(result.subscriptions[1].name, "iCloud")
        XCTAssertEqual(result.subscriptions[1].notes, "test note")
        XCTAssertEqual(result.settings.primaryCurrency, "USD")
        XCTAssertEqual(result.settings.reminderDaysBefore, [1, 3])
        XCTAssertEqual(result.settings.enableNotifications, true)
    }

    func testLoadEmptyReturnsDefaults() {
        let subs = StorageService.shared.loadSubscriptions()
        XCTAssertTrue(subs.isEmpty)

        let settings = StorageService.shared.loadSettings()
        XCTAssertEqual(settings.primaryCurrency, "USD")
    }
}
