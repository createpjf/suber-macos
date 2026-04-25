import XCTest
@testable import Suber

/// Plan Section 3 spec: 5-8 email fixtures covering Netflix EN, Spotify family,
/// 爱奇艺 续费, Stripe invoice, Amazon shipping (reject).
final class MailSubscriptionExtractorTests: XCTestCase {

    // MARK: - Happy-path fixtures

    func testNetflixRenewalReceipt() {
        let msg = MailMessage(
            id: "<netflix-1@email.netflix.com>",
            account: "Gmail",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),   // 2024-03-09
            subject: "Your Netflix subscription was renewed",
            sender: "info@email.netflix.com",
            body: "Your Netflix Premium subscription was renewed. You'll be charged $22.99 USD monthly."
        )
        let candidate = MailSubscriptionExtractor.extract(from: msg)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.amount, 22.99)
        XCTAssertEqual(candidate?.currency, "USD")
        XCTAssertEqual(candidate?.cycle, .monthly)
        // Domain-derived name: "netflix"
        XCTAssertEqual(candidate?.name.lowercased(), "netflix")
    }

    func testSpotifyFamilyShareMonthlyReceipt() {
        let msg = MailMessage(
            id: "<spotify-family-1@spotify.com>",
            account: "iCloud",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "Receipt from Spotify",
            sender: "no-reply@spotify.com",
            body: "Spotify Family • $16.99 per month • Next billing: April 9"
        )
        let candidate = MailSubscriptionExtractor.extract(from: msg)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.amount, 16.99)
        XCTAssertEqual(candidate?.currency, "USD")
        XCTAssertEqual(candidate?.cycle, .monthly)
    }

    func testIQiyiChineseRenewal() {
        // ¥188/yr CNY, mixed English+Chinese body
        let msg = MailMessage(
            id: "<iqiyi-1@iqiyi.com>",
            account: "QQ Mail",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "爱奇艺VIP 续费成功",
            sender: "service@iqiyi.com",
            body: "尊敬的用户, 您的爱奇艺VIP已成功续费 ¥188 年订阅"
        )
        let candidate = MailSubscriptionExtractor.extract(from: msg)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.amount, 188)
        XCTAssertEqual(candidate?.currency, "CNY",
                       "¥ + CJK body → CNY (not JPY)")
        XCTAssertEqual(candidate?.cycle, .yearly)
    }

    func testStripeInvoiceUSD() {
        let msg = MailMessage(
            id: "<stripe-abc@stripe.com>",
            account: "Gmail",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "Your receipt from ChatGPT Plus",
            sender: "receipts@stripe.com",
            body: "Invoice for ChatGPT Plus - Amount charged: USD 20.00 monthly. Thank you."
        )
        let candidate = MailSubscriptionExtractor.extract(from: msg)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.amount, 20.00)
        XCTAssertEqual(candidate?.currency, "USD")
        XCTAssertEqual(candidate?.cycle, .monthly)
    }

    func testEuroYearlyReceipt() {
        let msg = MailMessage(
            id: "<proton-1@proton.me>",
            account: "Personal",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "Proton subscription renewed",
            sender: "billing@proton.me",
            body: "Your yearly Proton subscription renewed: €71.88"
        )
        let candidate = MailSubscriptionExtractor.extract(from: msg)
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.amount, 71.88)
        XCTAssertEqual(candidate?.currency, "EUR")
        XCTAssertEqual(candidate?.cycle, .yearly)
    }

    // MARK: - Rejection fixtures

    func testAmazonShippingEmailRejected() {
        // This is the plan's canonical "NOT a subscription receipt" email.
        let msg = MailMessage(
            id: "<amzn-ship-1@amazon.com>",
            account: "Gmail",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "Your Amazon.com order has shipped",
            sender: "ship-confirm@amazon.com",
            body: "Your order of $29.99 has shipped and will arrive Thursday."
        )
        XCTAssertNil(MailSubscriptionExtractor.extract(from: msg),
                     "Shipping notifications must NOT be treated as subscriptions")
    }

    func testRefundReceiptRejected() {
        let msg = MailMessage(
            id: "<refund-1@vendor.com>",
            account: "Gmail",
            dateReceived: Date(timeIntervalSince1970: 1_710_000_000),
            subject: "Your refund from VendorX",
            sender: "billing@vendor.com",
            body: "We've issued a refund of $9.99 to your card. Processing takes 5-10 days."
        )
        XCTAssertNil(MailSubscriptionExtractor.extract(from: msg),
                     "Refund receipts must NOT become subscription candidates")
    }

    func testZeroAmountWelcomeEmailRejected() {
        let msg = MailMessage(
            id: "<welcome-1@service.com>",
            account: "Gmail",
            dateReceived: Date(),
            subject: "Welcome to Our Subscription Service!",
            sender: "hello@service.com",
            body: "Thanks for signing up! Your free trial starts today."
        )
        // No price → nil. (Even though subject contains "Subscription".)
        XCTAssertNil(MailSubscriptionExtractor.extract(from: msg))
    }

    // MARK: - Price parsing corner cases

    func testEuropeanDecimalCommaParses() {
        XCTAssertEqual(MailSubscriptionExtractor.extractPrice(from: "€9,99/month")?.amount, 9.99)
    }

    func testUSThousandSeparatorStrips() {
        XCTAssertEqual(MailSubscriptionExtractor.extractPrice(from: "$1,234.56 annual")?.amount, 1234.56)
    }

    // MARK: - Cycle hints

    func testCycleRecognizesSlashYr() {
        XCTAssertEqual(MailSubscriptionExtractor.extractCycle(from: "Charged $99/yr"), .yearly)
    }

    func testCycleRecognizesChinesePerMonth() {
        XCTAssertEqual(MailSubscriptionExtractor.extractCycle(from: "每月自动续费"), .monthly)
    }

    func testCycleDefaultsToNilWhenAbsent() {
        XCTAssertNil(MailSubscriptionExtractor.extractCycle(from: "No cycle info here."))
    }

    // MARK: - Batch

    func testBatchReturnsOnlyRecognizedMessages() {
        let messages = [
            MailMessage(id: "<1>", account: "a", dateReceived: Date(),
                        subject: "Receipt", sender: "x@netflix.com",
                        body: "Renewed $15.99 monthly"),
            MailMessage(id: "<2>", account: "a", dateReceived: Date(),
                        subject: "shipped", sender: "x@amazon.com", body: ""),
            MailMessage(id: "<3>", account: "a", dateReceived: Date(),
                        subject: "Subscription", sender: "x@spotify.com",
                        body: "Your Spotify Premium: $9.99/month"),
        ]
        let results = MailSubscriptionExtractor.extract(from: messages)
        XCTAssertEqual(results.count, 2, "Amazon shipping excluded")
    }
}
