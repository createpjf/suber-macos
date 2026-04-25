import XCTest
@testable import Suber

/// A2 (eng re-review): typed UserDefaults wrapper, compiler-enforced key
/// naming. H4 fix: Date? values TimeInterval-backed to avoid `@AppStorage`
/// compile issues with optional Date.
@MainActor
final class AutopilotFlagsTests: XCTestCase {

    var defaults: UserDefaults!
    var flags: AutopilotFlags!

    override func setUp() {
        super.setUp()
        // Isolated suite so tests don't pollute the real app group.
        // Use a unique name per test-run to avoid leakage between test cases.
        defaults = UserDefaults(suiteName: "autopilot-flags-tests-\(UUID().uuidString)")!
        flags = AutopilotFlags(defaults: defaults)
    }

    override func tearDown() {
        flags.resetForTests()
        flags = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Bool defaults

    func testFreshInstallDefaults() {
        XCTAssertFalse(flags.hasSeenFirstScan)
        XCTAssertFalse(flags.hasSeenFirstCatch)
        XCTAssertNil(flags.lastBannerShownAt)
        XCTAssertNil(flags.lastCelebrationAckedAt)
    }

    func testBoolPersistence() {
        flags.hasSeenFirstScan = true
        XCTAssertTrue(flags.hasSeenFirstScan)

        // New instance reading same suite → should still see true.
        let fresh = AutopilotFlags(defaults: defaults)
        XCTAssertTrue(fresh.hasSeenFirstScan)
    }

    // MARK: - Date? round-trip (H4 fix)

    func testDateOptionalRoundTrip() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        flags.lastBannerShownAt = anchor
        XCTAssertEqual(flags.lastBannerShownAt, anchor)

        let fresh = AutopilotFlags(defaults: defaults)
        XCTAssertEqual(fresh.lastBannerShownAt, anchor)
    }

    func testDateOptionalClearToNil() {
        flags.lastBannerShownAt = Date()
        XCTAssertNotNil(flags.lastBannerShownAt)

        flags.lastBannerShownAt = nil
        XCTAssertNil(flags.lastBannerShownAt)
    }

    func testDateOptionalNeverReadsSentinelAsDate() {
        // Direct write of the sentinel TimeInterval (0.0) to the underlying
        // key — getter must treat this as nil, not 1970-01-01 UTC.
        defaults.set(0.0, forKey: AutopilotFlags.Key.lastBannerShownAt)
        XCTAssertNil(flags.lastBannerShownAt)
    }

    // MARK: - Namespace isolation

    func testKeysAreNamespacedUnderAutopilot() {
        XCTAssertTrue(AutopilotFlags.Key.hasSeenFirstScan.hasPrefix("autopilot."))
        XCTAssertTrue(AutopilotFlags.Key.hasSeenFirstCatch.hasPrefix("autopilot."))
        XCTAssertTrue(AutopilotFlags.Key.lastBannerShownAt.hasPrefix("autopilot."))
        XCTAssertTrue(AutopilotFlags.Key.lastCelebrationAckedAt.hasPrefix("autopilot."))
    }

    func testResetForTestsClearsAll() {
        flags.hasSeenFirstScan = true
        flags.hasSeenFirstCatch = true
        flags.lastBannerShownAt = Date()
        flags.lastCelebrationAckedAt = Date()

        flags.resetForTests()

        XCTAssertFalse(flags.hasSeenFirstScan)
        XCTAssertFalse(flags.hasSeenFirstCatch)
        XCTAssertNil(flags.lastBannerShownAt)
        XCTAssertNil(flags.lastCelebrationAckedAt)
    }
}
