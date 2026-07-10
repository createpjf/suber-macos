import XCTest
@testable import Suber

final class StorageServiceTests: XCTestCase {
    private var tempStoreDir: URL!
    private var tempBackupDir: URL!

    override func setUp() {
        super.setUp()
        // AUDIT-v1.9.2 C-01: sandbox ALL file I/O into fresh per-test temp
        // dirs. The old setUp cleared the user's REAL container keys, and the
        // non-sandboxed tests below then wrote "Netflix 15.99" etc. into the
        // user's real live store + rotated real Backups/ snapshots.
        tempStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-storage-store-\(UUID().uuidString)")
        tempBackupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-storage-backup-\(UUID().uuidString)")
        AppGroupStore.testOverrideDirectory = tempStoreDir
        DataBackupManager.testOverrideDirectory = tempBackupDir
    }

    override func tearDown() {
        AppGroupStore.testOverrideDirectory = nil
        DataBackupManager.testOverrideDirectory = nil
        if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
        if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
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

    func testAppendSubscriptionPreservesExisting() {
        // Sandboxing now lives in setUp/tearDown for the whole class.
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

    // MARK: - AUDIT-v1.9.2 C-09: non-finite amounts must never parse

    func testParsedAmountRejectsNonFiniteInput() {
        var data = SubscriptionFormData()
        data.name = "Poison"

        for poison in ["inf", "infinity", "-inf", "1e999", "nan"] {
            data.amount = poison
            XCTAssertNil(data.parsedAmount,
                         "'\(poison)' parses to a non-finite Double and would make JSONEncoder throw on every future save")
            XCTAssertFalse(data.isValid, "'\(poison)' must fail validation")
        }

        data.amount = "15.99"
        XCTAssertEqual(data.parsedAmount, 15.99)
        XCTAssertTrue(data.isValid)
    }

    // MARK: - AUDIT-v1.9.2 C-10: persistence failures must surface

    private func makeSub(amount: Double) -> Subscription {
        Subscription(
            id: UUID(), name: "C10", amount: amount, currency: "USD",
            cycle: .monthly, billingDay: 1, startDate: Date(),
            category: "Test", status: .active, createdAt: Date(), updatedAt: Date())
    }

    func testSaveSubscriptionsReturnsTrueOnSuccess() {
        XCTAssertTrue(StorageService.shared.saveSubscriptions([makeSub(amount: 9.99)]))
    }

    func testSaveSubscriptionsReportsEncodeFailureAndLeavesDiskUntouched() {
        // C-09 blocks ∞ at the form, but legacy/imported data could still
        // carry it — the encoder guard must report instead of try?-swallowing.
        XCTAssertTrue(StorageService.shared.saveSubscriptions([makeSub(amount: 9.99)]))

        let poisoned = makeSub(amount: .infinity)
        XCTAssertFalse(StorageService.shared.saveSubscriptions([poisoned]),
                       "encode failure must be reported, not swallowed")

        let onDisk = StorageService.shared.loadSubscriptions()
        XCTAssertEqual(onDisk.map(\.amount), [9.99],
                       "failed encode must leave the previous on-disk state intact")
    }

    func testSaveSubscriptionsReportsDiskWriteFailure() {
        // Point the store at an impossible directory (parent is a FILE) so
        // AppGroupStore.set's write throws. The old code ignored the false
        // and pushed to iCloud KVS anyway — cloud ran ahead of disk and the
        // session's data vanished on restart.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("suber-c10-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(at: blocker) }

        AppGroupStore.testOverrideDirectory = blocker.appendingPathComponent("nope")
        defer { AppGroupStore.testOverrideDirectory = tempStoreDir }

        XCTAssertFalse(StorageService.shared.saveSubscriptions([makeSub(amount: 9.99)]),
                       "disk-write failure must be reported to the caller")
        XCTAssertFalse(StorageService.shared.saveSettings(AppSettings()),
                       "saveSettings shares the C-10 contract")
        XCTAssertFalse(StorageService.shared.saveChanges([]),
                       "saveChanges shares the C-10 contract")
    }

    func testLoadEmptyReturnsDefaults() {
        let subs = StorageService.shared.loadSubscriptions()
        XCTAssertTrue(subs.isEmpty)

        let settings = StorageService.shared.loadSettings()
        XCTAssertEqual(settings.primaryCurrency, "USD")
    }
}
