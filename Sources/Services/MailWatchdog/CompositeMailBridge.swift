import Foundation

// ┌───────────── CompositeMailBridge — fan-out to multiple sources ────────────┐
// │                                                                            │
// │  Combines N MailBridge instances behind a single MailBridge facade.        │
// │  MailWatchdog stays unchanged — it sees ONE bridge, gets unified results. │
// │                                                                            │
// │  Use case: a user with iCloud + Gmail in macOS Mail.app gets               │
// │  AppleMailBridge to handle both. A user with Mail.app for iCloud +         │
// │  GenericIMAPBridge for a separate Gmail account that's NOT in Mail.app    │
// │  gets [AppleMailBridge, GenericIMAPBridge(gmail)] composed here.           │
// │                                                                            │
// │  Error handling rule: per-bridge errors are LOGGED but don't fail the      │
// │  whole scan. If Apple Mail is fine but the IMAP server is down, the       │
// │  user still sees Apple Mail results + an error in the IMAP-specific       │
// │  state row. Better than zero results.                                      │
// │                                                                            │
// │  Exception: if ALL bridges fail with permissionDenied, that's a hard      │
// │  fail — user needs to fix at least one. Mixed errors (some succeed,        │
// │  some fail) are silent: the failure state lives on the per-source UI     │
// │  affordances (Apple Mail row, IMAP row), not on this composite bridge.    │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

final class CompositeMailBridge: MailBridge {

    let bridges: [MailBridge]

    init(bridges: [MailBridge]) {
        self.bridges = bridges
    }

    /// Sum of account counts across all bridges. If ALL bridges fail, throw —
    /// otherwise return whatever succeeded.
    func ping(timeout: TimeInterval) async throws -> Int {
        guard !bridges.isEmpty else {
            // No bridges configured at all — treat as no-op success.
            return 0
        }

        var total = 0
        var errors: [Error] = []
        for bridge in bridges {
            do {
                total += try await bridge.ping(timeout: timeout)
            } catch {
                errors.append(error)
                NSLog("Suber: bridge ping failed: \(error.localizedDescription)")
            }
        }

        // If every bridge failed, propagate the most informative error.
        if errors.count == bridges.count {
            // Prefer permissionDenied (most actionable) over generic.
            if let denied = errors.first(where: { ($0 as? MailBridgeError) == .permissionDenied }) {
                throw denied
            }
            throw errors.first ?? MailBridgeError.unknown("all bridges failed")
        }

        return total
    }

    /// Scan all bridges in parallel, merge results. Per-bridge errors don't
    /// abort other bridges' scans — the user sees whatever was found, plus
    /// per-source error UI (handled by the consumer, not here).
    func scan(since: Date,
              keywords: [String],
              timeout: TimeInterval) async throws -> [MailMessage] {
        guard !bridges.isEmpty else { return [] }

        // Parallel fan-out with TaskGroup. Each bridge gets the full timeout
        // budget; if one is slow, others can still finish before deadline.
        return try await withThrowingTaskGroup(of: [MailMessage].self) { group in
            for bridge in bridges {
                group.addTask {
                    do {
                        return try await bridge.scan(since: since,
                                                     keywords: keywords,
                                                     timeout: timeout)
                    } catch {
                        // Don't propagate single-bridge errors — log and
                        // contribute zero messages from this source. The
                        // whole-scan failure mode is "all bridges failed",
                        // which surfaces as ping() throwing on next call.
                        NSLog("Suber: bridge scan failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            var merged: [MailMessage] = []
            for try await chunk in group {
                merged.append(contentsOf: chunk)
            }

            // Dedup across sources (e.g. an iCloud-account email seen by both
            // Apple Mail's iCloud account AND a separate IMAP bridge to
            // imap.mail.me.com). Use Message-ID as the dedup key — RFC 5322
            // requires it to be globally unique.
            return dedupByMessageID(merged)
        }
    }

    private func dedupByMessageID(_ messages: [MailMessage]) -> [MailMessage] {
        var seen = Set<String>()
        var unique: [MailMessage] = []
        for msg in messages {
            // Empty IDs (rare; IMAPClient generates synthetic ones) skip dedup.
            if msg.id.isEmpty {
                unique.append(msg)
                continue
            }
            if seen.insert(msg.id).inserted {
                unique.append(msg)
            }
        }
        return unique
    }
}
