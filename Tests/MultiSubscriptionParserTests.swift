import XCTest
@testable import Suber

final class MultiSubscriptionParserTests: XCTestCase {

    // MARK: - Positive: multi-sub screenshots

    /// Raw OCR text from an iOS Settings > Subscriptions screenshot with 4 items.
    /// Vision outputs lines in visual top-to-bottom order.
    func test_apple_subscriptions_screenshot_yields_four_blocks() {
        let text = """
        8:19
        Subscriptions
        Active Sort
        ChatGPT
        ChatGPT Plus
        Renews May 7
        $19.99
        Claude
        Claude Max 20x - Monthly
        Renews May 17
        $249.99
        Life Widget - Time Progress
        Monthly
        Renews May 15
        $0.99
        Water Tracker by WaterMinder®
        Premium Features
        Expiring January 23, 2027
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        XCTAssertEqual(results.count, 4, "Should find 4 subscription blocks")

        // First block: ChatGPT
        XCTAssertEqual(results[0].name, "ChatGPT")
        XCTAssertEqual(results[0].amount, "19.99")

        // Second block: Claude
        XCTAssertEqual(results[1].name, "Claude")
        XCTAssertEqual(results[1].amount, "249.99")

        // Third block: Life Widget (not in KnownServices — name inferred)
        XCTAssertNotNil(results[2].name)
        XCTAssertEqual(results[2].amount, "0.99")

        // Fourth block: Water Tracker (Expiring — no amount)
        XCTAssertNotNil(results[3].name)
    }

    func test_chinese_subscriptions_screenshot_splits_on_续费() {
        let text = """
        订阅
        网易云音乐
        黑胶VIP 连续包月
        下次扣款 5月7日
        ¥15
        爱奇艺
        黄金VIP会员 连续包月
        下次扣款 5月12日
        ¥19.8
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "网易云音乐")
        XCTAssertEqual(results[1].name, "爱奇艺")
    }

    func test_google_play_style_renews_on() {
        let text = """
        Subscriptions
        Spotify
        Premium Individual
        Renews on May 7
        $9.99/month
        YouTube Premium
        Family
        Renews on May 12
        $22.99/month
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "Spotify")
        XCTAssertEqual(results[1].name?.contains("YouTube") ?? false, true)
    }

    // MARK: - Fallback: single-sub content

    func test_single_subscription_email_returns_empty_so_caller_falls_back() {
        // Typical Netflix billing-email screenshot: one "auto-renews" anchor only.
        // With fewer than 2 anchors, parseMultiple returns empty — caller uses the
        // single-parse path instead. This is the no-regression guarantee.
        let text = """
        Netflix
        Thanks for your payment
        Your subscription auto-renews on May 7, 2026
        Total: $15.99
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        XCTAssertTrue(results.isEmpty, "Single-sub content should return empty array so caller falls back to single-parse")
    }

    func test_no_anchor_text_returns_empty() {
        let text = "Some random text with no subscription-like structure"
        XCTAssertTrue(MultiSubscriptionParser.parseMultiple(text).isEmpty)
    }

    func test_empty_input_is_safe() {
        XCTAssertTrue(MultiSubscriptionParser.parseMultiple("").isEmpty)
    }

    // MARK: - Quality filter

    func test_bare_section_header_renews_not_treated_as_anchor() {
        // "Renews" as a standalone section header (no date) must NOT trigger
        // block splitting — otherwise we'd slice page chrome as a fake entry.
        // A real anchor requires a digit on the same line.
        let text = """
        Subscriptions
        Renews
        Active
        Netflix
        Standard Plan
        Renews May 7
        $15.99
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        // Only one real anchor ("Renews May 7"), so parseMultiple returns empty
        // and the caller falls back to single-parse. Correct behavior.
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Anchor/price-line overlap (AUDIT-v1.9.2 C-13)

    func test_price_line_that_is_also_anchor_does_not_trap() {
        // "$14.99/renewal" matches BOTH looksLikePriceLine and the renew
        // anchor. Before the C-13 guard, the second anchor produced
        // lines[3...2] — a fatal Range trap.
        let text = """
        Namecheap Domains
        Renews Mar 3, 2027
        $14.99/renewal
        example.com
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        // The consumed anchor is skipped, leaving a single block.
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].amount, "14.99")
        XCTAssertNotNil(results[0].name)
    }

    // MARK: - Amount normalization (AUDIT-v1.9.2 C-34)

    func test_thousands_separator_amount_not_truncated() {
        // "¥1,299/年" used to be captured as "1,29" then comma→dot'd to 1.29.
        let (amount, currency) = SubscriptionTextParser.parseAmount("¥1,299/年")
        XCTAssertEqual(amount, "1299")
        XCTAssertEqual(currency, "CNY")
    }

    func test_thousands_with_decimal_amount() {
        let (amount, currency) = SubscriptionTextParser.parseAmount("Total: $1,299.00")
        XCTAssertEqual(amount, "1299.00")
        XCTAssertEqual(currency, "USD")
    }

    func test_decimal_comma_amount_still_normalized() {
        let (amount, currency) = SubscriptionTextParser.parseAmount("€9,99 per month")
        XCTAssertEqual(amount, "9.99")
        XCTAssertEqual(currency, "EUR")
    }

    func test_chrome_name_without_amount_dropped() {
        // Two real anchors but the first block's only content is page chrome
        // ("Subscriptions" as inferred name, no amount). Chrome filter drops it.
        let text = """
        Subscriptions
        Renews today May 1
        Netflix
        Standard Plan
        Renews May 7
        $15.99
        """
        let results = MultiSubscriptionParser.parseMultiple(text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Netflix")
    }
}
