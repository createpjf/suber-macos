import Foundation

// ┌───────────── IMAPContinuationGuard — race-safe continuation wrapper ───────┐
// │                                                                            │
// │  IMAPClient runs three `withCheckedThrowingContinuation` blocks where      │
// │  multiple sources can race to resume:                                      │
// │                                                                            │
// │    connect()           — stateUpdateHandler (NWConnection queue) AND       │
// │                          asyncAfter timeout (DispatchQueue.global)         │
// │    sendCommand()       — completion callback AND asyncAfter timeout        │
// │    readMoreIntoBuffer  — receive callback AND asyncAfter timeout           │
// │                                                                            │
// │  `withCheckedThrowingContinuation` requires resume be called EXACTLY       │
// │  once. The previous `var resumed = false` flag check-and-set was NOT       │
// │  atomic — under network flapping (Wi-Fi/LTE swap, TLS handshake on the     │
// │  edge of timeout), two callbacks could race, both observe `false`, both   │
// │  call resume → Swift runtime crashes with                                  │
// │  "SWIFT TASK CONTINUATION MISUSE: tried to resume more than once".         │
// │                                                                            │
// │  This guard owns an `NSLock` so the check-and-set is atomic. Wrapped       │
// │  callers do `guarded.resume(.success(...))` instead of inline flag        │
// │  manipulation, so the lock is impossible to forget.                        │
// │                                                                            │
// │  `@unchecked Sendable` because we manually enforce thread safety via the   │
// │  lock — Swift's automatic Sendable inference doesn't see through that.     │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

/// One-shot continuation wrapper. First `resume` call wins; subsequent
/// calls are silent no-ops. Thread-safe via internal NSLock.
final class IMAPContinuationGuard<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// First caller wins. Subsequent calls are silent no-ops.
    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let isFirst = !resumed
        if isFirst { resumed = true }
        lock.unlock()
        guard isFirst else { return }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    /// Convenience for `Void`-returning continuations.
    func resumeSuccess() where T == Void { resume(.success(())) }

    /// Convenience for the failure path.
    func resume(throwing error: Error) { resume(.failure(error)) }
}
