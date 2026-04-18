import XCTest
@testable import Suber

final class MerchantNormalizerTests: XCTestCase {

    func test_alipay_star_prefix_stripped() {
        XCTAssertEqual(MerchantNormalizer.normalize("ALIPAY*NETFLIX*SUB"), "netflix sub")
    }

    func test_paypal_prefix_stripped() {
        XCTAssertEqual(MerchantNormalizer.normalize("PAYPAL *SPOTIFY"), "spotify")
    }

    func test_trailing_location_stripped() {
        XCTAssertEqual(MerchantNormalizer.normalize("NETFLIX NEW YORK NY US"), "netflix")
    }

    func test_trailing_phone_number_stripped() {
        XCTAssertEqual(MerchantNormalizer.normalize("Netflix.com 866-123-4567"), "netflix")
    }

    func test_order_number_stripped() {
        XCTAssertEqual(MerchantNormalizer.normalize("Spotify #123456"), "spotify")
    }

    func test_cjk_preserved() {
        XCTAssertEqual(MerchantNormalizer.normalize("爱奇艺"), "爱奇艺")
        XCTAssertEqual(MerchantNormalizer.normalize("网易云音乐"), "网易云音乐")
    }

    func test_whitespace_collapsed() {
        XCTAssertEqual(MerchantNormalizer.normalize("  Netflix   Premium  "), "netflix premium")
    }

    func test_empty_input_safe() {
        XCTAssertEqual(MerchantNormalizer.normalize(""), "")
        XCTAssertEqual(MerchantNormalizer.normalize("   "), "")
    }

    func test_display_name_title_cases_latin() {
        XCTAssertEqual(MerchantNormalizer.displayName(from: "netflix premium"), "Netflix Premium")
    }

    func test_display_name_preserves_cjk() {
        XCTAssertEqual(MerchantNormalizer.displayName(from: "爱奇艺"), "爱奇艺")
    }

    func test_display_name_unknown_fallback() {
        XCTAssertEqual(MerchantNormalizer.displayName(from: ""), "Unknown")
    }
}
