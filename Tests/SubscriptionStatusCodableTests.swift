import XCTest
@testable import Suber

/// D7 forward-compat: unknown raw `SubscriptionStatus` values decode to
/// `.active` with a warning log rather than throwing. Keeps v1.5.x clients
/// non-crashing when an iCloud sync delivers a case they don't recognize.
final class SubscriptionStatusCodableTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Round-trip known cases

    func testKnownCasesRoundTrip() throws {
        for status in SubscriptionStatus.allCases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SubscriptionStatus.self, from: data)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status.rawValue)")
        }
    }

    // MARK: - Forward-compat fallback (D7)

    func testUnknownCaseFallsBackToActive() throws {
        // Simulates an iCloud payload from a v1.7+ client that knows about a
        // case this v1.6 client doesn't.
        let json = "\"suspended_indefinitely\"".data(using: .utf8)!
        let decoded = try decoder.decode(SubscriptionStatus.self, from: json)
        XCTAssertEqual(decoded, .active,
                       "Unknown raw value should fall back to .active per D7")
    }

    func testEmptyStringFallsBackToActive() throws {
        let json = "\"\"".data(using: .utf8)!
        let decoded = try decoder.decode(SubscriptionStatus.self, from: json)
        XCTAssertEqual(decoded, .active)
    }

    func testPendingCancellationDecodesCorrectly() throws {
        // v1.6 new case — verify serialized form is "pending_cancellation"
        // (snake_case, not camelCase — the raw value we chose).
        let data = try encoder.encode(SubscriptionStatus.pendingCancellation)
        let str = String(data: data, encoding: .utf8)
        XCTAssertEqual(str, "\"pending_cancellation\"")

        let decoded = try decoder.decode(SubscriptionStatus.self, from: data)
        XCTAssertEqual(decoded, .pendingCancellation)
    }

    // MARK: - Full Subscription round-trip with pendingCancellation

    func testSubscriptionWithPendingCancellationRoundTrip() throws {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let sub = Subscription(
            id: UUID(),
            name: "Netflix",
            amount: 22.99,
            currency: "USD",
            cycle: .monthly,
            billingDay: 15,
            startDate: anchor,
            category: "Entertainment",
            status: .pendingCancellation,
            createdAt: anchor,
            updatedAt: anchor,
            cancellationURL: "https://netflix.com/cancel",
            pendingCancellationSetAt: anchor
        )
        let data = try encoder.encode(sub)
        let decoded = try decoder.decode(Subscription.self, from: data)
        XCTAssertEqual(decoded.status, .pendingCancellation)
        XCTAssertEqual(decoded.cancellationURL, "https://netflix.com/cancel")
        XCTAssertEqual(decoded.pendingCancellationSetAt, anchor)
    }

    /// v1.5 payload (no cancellationURL, no pendingCancellationSetAt) must
    /// still decode cleanly in v1.6 — the two new fields default to nil.
    func testV15PayloadDecodesWithoutNewFields() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Spotify",
          "amount": 9.99,
          "currency": "USD",
          "cycle": "monthly",
          "billingDay": 20,
          "startDate": "2024-01-01T00:00:00Z",
          "category": "Music",
          "status": "active",
          "splitCount": 1,
          "createdAt": "2024-01-01T00:00:00Z",
          "updatedAt": "2024-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(Subscription.self, from: json)
        XCTAssertNil(decoded.cancellationURL)
        XCTAssertNil(decoded.pendingCancellationSetAt)
        XCTAssertEqual(decoded.status, .active)
    }
}
