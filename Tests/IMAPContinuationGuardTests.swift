import XCTest
@testable import Suber

/// Tests for v1.7 IMAPContinuationGuard — the lock-protected one-shot
/// continuation primitive that replaces the broken `var resumed = false`
/// pattern in IMAPClient. Three scenarios exercise the contract:
///
///   1. First success wins; later success ignored (no double-resume crash).
///   2. First failure wins; later success ignored (preserves error path).
///   3. 100 racing dispatches — without the lock, this crashes Swift runtime
///      with "SWIFT TASK CONTINUATION MISUSE: tried to resume more than
///      once". With the lock, exactly one wins and the other 99 silent-noop.
///
/// The race test is the load-bearing one: it's the closest XCTest can get
/// to reproducing the real-world Wi-Fi/LTE handover race that motivated
/// IMAP-01 in the first place.
final class IMAPContinuationGuardTests: XCTestCase {

    func testFirstResumeWinsOnSuccess() async throws {
        let value = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int, Error>) in
            let guarded = IMAPContinuationGuard(c)
            guarded.resume(.success(42))
            guarded.resume(.success(99))   // ignored
            guarded.resume(throwing: MailBridgeError.permissionDenied)  // ignored
        }
        XCTAssertEqual(value, 42, "First resume value should win")
    }

    func testFirstResumeWinsOnFailure() async {
        do {
            _ = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int, Error>) in
                let guarded = IMAPContinuationGuard(c)
                guarded.resume(throwing: MailBridgeError.permissionDenied)
                guarded.resume(.success(0))    // ignored
                guarded.resume(throwing: MailBridgeError.unknown("ignored"))
            }
            XCTFail("Should have thrown the first error")
        } catch let e as MailBridgeError {
            XCTAssertEqual(e, .permissionDenied, "First-thrown error must propagate")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    /// 100 concurrent dispatches racing to resume the same continuation.
    /// Without the lock this crashes the test runner with the Swift task
    /// continuation misuse trap. With the lock, exactly one resume wins
    /// and the test completes deterministically.
    func testRaceUnderConcurrencyDoesNotCrash() async throws {
        let value = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int, Error>) in
            let guarded = IMAPContinuationGuard(c)
            for i in 0..<100 {
                DispatchQueue.global().async { guarded.resume(.success(i)) }
            }
        }
        XCTAssertTrue((0..<100).contains(value),
                      "Winning value should be one of the dispatched values")
    }

    /// Void-returning convenience helper.
    func testResumeSuccessVoidConvenience() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let guarded = IMAPContinuationGuard(c)
            guarded.resumeSuccess()
            guarded.resumeSuccess()  // ignored
        }
    }
}
