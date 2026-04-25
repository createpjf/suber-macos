import XCTest
@testable import Suber

/// Tests the `composeChangesBody` template. This is the notification copy users
/// see on their lock screen — it needs to be accurate, grouped, and honest.
/// Plan Pass 1 + Pass 4: specific verbs, no "things", Oxford-comma grouping.
final class NotificationServiceGroupingTests: XCTestCase {

    func testSingleChangePriceRise() {
        var form = SubscriptionFormData()
        form.name = "Netflix"
        let change = SubscriptionChange(
            subscriptionID: UUID(), type: .priceChange,
            detectedAt: Date(),
            previousValue: "15.99 USD", newValue: "22.99 USD",
            source: .mailWatchdog,
            pendingSubscriptionData: form,   // hydrated so name is resolvable
            previousBaseAmount: 15.99, newBaseAmount: 22.99
        )
        let (title, body) = NotificationService.composeChangesBody(from: [change])
        XCTAssertEqual(title, "Suber found 1 change")
        XCTAssertTrue(body.contains("Netflix raised to 22.99 USD"),
                      "Body should spell out the service and new amount; got: \(body)")
        XCTAssertTrue(body.contains("+44%"), "Body should include the percent delta; got: \(body)")
    }

    func testSingleNewCharge() {
        var form = SubscriptionFormData()
        form.name = "Spotify"
        let change = SubscriptionChange(
            subscriptionID: nil, type: .newCharge,
            detectedAt: Date(),
            previousValue: nil, newValue: "9.99 USD",
            source: .mailWatchdog,
            pendingSubscriptionData: form,
            newBaseAmount: 9.99
        )
        let (title, body) = NotificationService.composeChangesBody(from: [change])
        XCTAssertEqual(title, "Suber found 1 change")
        XCTAssertEqual(body, "Spotify — new subscription detected")
    }

    func testSingleDuplicate() {
        let change = SubscriptionChange(
            subscriptionID: nil, type: .duplicate,
            detectedAt: Date(),
            previousValue: nil, newValue: "2 charges of 9.99 USD on 2026-03-14",
            source: .csvImport,
            newBaseAmount: 19.98
        )
        let (title, body) = NotificationService.composeChangesBody(from: [change])
        XCTAssertEqual(title, "Suber found 1 change")
        XCTAssertEqual(body, "2 charges of 9.99 USD on 2026-03-14")
    }

    // MARK: - Grouping (2–5)

    func testTwoPriceChanges() {
        var netflixForm = SubscriptionFormData(); netflixForm.name = "Netflix"
        var spotifyForm = SubscriptionFormData(); spotifyForm.name = "Spotify"
        let changes = [
            SubscriptionChange(subscriptionID: UUID(), type: .priceChange,
                               detectedAt: Date(),
                               previousValue: "15.99 USD", newValue: "22.99 USD",
                               source: .mailWatchdog,
                               pendingSubscriptionData: netflixForm,
                               previousBaseAmount: 15.99, newBaseAmount: 22.99),
            SubscriptionChange(subscriptionID: UUID(), type: .priceChange,
                               detectedAt: Date(),
                               previousValue: "9.99 USD", newValue: "11.99 USD",
                               source: .mailWatchdog,
                               pendingSubscriptionData: spotifyForm,
                               previousBaseAmount: 9.99, newBaseAmount: 11.99),
        ]
        let (title, body) = NotificationService.composeChangesBody(from: changes)
        XCTAssertEqual(title, "Suber found 2 changes")
        XCTAssertTrue(body.contains("Netflix") && body.contains("Spotify") && body.contains("raised prices"),
                      "Both names + grouped verb; got: \(body)")
    }

    func testMixedTypesInGroup() {
        var netflixForm = SubscriptionFormData(); netflixForm.name = "Netflix"
        var newForm = SubscriptionFormData(); newForm.name = "NewSvc"
        let changes = [
            SubscriptionChange(subscriptionID: UUID(), type: .priceChange,
                               detectedAt: Date(),
                               previousValue: "15.99 USD", newValue: "22.99 USD",
                               source: .mailWatchdog,
                               pendingSubscriptionData: netflixForm,
                               previousBaseAmount: 15.99, newBaseAmount: 22.99),
            SubscriptionChange(subscriptionID: nil, type: .newCharge,
                               detectedAt: Date(),
                               previousValue: nil, newValue: "9.99 USD",
                               source: .mailWatchdog,
                               pendingSubscriptionData: newForm,
                               newBaseAmount: 9.99),
            SubscriptionChange(subscriptionID: nil, type: .duplicate,
                               detectedAt: Date(),
                               previousValue: nil, newValue: "2 charges",
                               source: .csvImport,
                               newBaseAmount: 20),
        ]
        let (title, body) = NotificationService.composeChangesBody(from: changes)
        XCTAssertEqual(title, "Suber found 3 changes")
        XCTAssertTrue(body.contains("raised prices"), "Body should describe price change group")
        XCTAssertTrue(body.contains("new sub"), "Body should describe new charge count")
        XCTAssertTrue(body.contains("duplicate"), "Body should describe duplicate count")
    }

    // MARK: - >5 compact summary

    func testManyChangesCompactSummary() {
        var forms: [SubscriptionChange] = []
        var form = SubscriptionFormData(); form.name = "svc"
        // 3 priceChange + 2 newCharge + 1 duplicate = 6 total
        for _ in 0..<3 {
            forms.append(SubscriptionChange(
                subscriptionID: UUID(), type: .priceChange,
                detectedAt: Date(),
                previousValue: "10 USD", newValue: "12 USD",
                source: .mailWatchdog,
                pendingSubscriptionData: form,
                previousBaseAmount: 10, newBaseAmount: 12
            ))
        }
        for _ in 0..<2 {
            forms.append(SubscriptionChange(
                subscriptionID: nil, type: .newCharge,
                detectedAt: Date(),
                previousValue: nil, newValue: "9.99 USD",
                source: .mailWatchdog,
                pendingSubscriptionData: form,
                newBaseAmount: 9.99
            ))
        }
        forms.append(SubscriptionChange(
            subscriptionID: nil, type: .duplicate,
            detectedAt: Date(),
            previousValue: nil, newValue: "2 charges",
            source: .csvImport, newBaseAmount: 20
        ))
        let (title, body) = NotificationService.composeChangesBody(from: forms)
        XCTAssertEqual(title, "Suber found 6 changes")
        XCTAssertTrue(body.contains("3 price changes"),
                      "Compact summary for >5; got: \(body)")
        XCTAssertTrue(body.contains("2 new subs"))
        XCTAssertTrue(body.contains("1 duplicate"))
    }

    // MARK: - URL scheme routing

    func testURLSchemeParsesChanges() {
        let url = URL(string: "suber://changes")!
        let action = URLSchemeHandler.parseAction(url)
        XCTAssertEqual(action, .openChanges)
    }

    func testURLSchemeParsesAddStillWorks() {
        let url = URL(string: "suber://add?name=Netflix&amount=15.99&currency=USD")!
        let action = URLSchemeHandler.parseAction(url)
        switch action {
        case .add(let form):
            XCTAssertEqual(form.name, "Netflix")
            XCTAssertEqual(form.amount, "15.99")
            XCTAssertEqual(form.currency, "USD")
        default:
            XCTFail("Expected .add action")
        }
    }

    func testURLSchemeUnknownHostReturnsNil() {
        let url = URL(string: "suber://wat")!
        XCTAssertNil(URLSchemeHandler.parseAction(url))
    }

    func testURLSchemeWrongSchemeReturnsNil() {
        let url = URL(string: "https://changes")!
        XCTAssertNil(URLSchemeHandler.parseAction(url))
    }
}
