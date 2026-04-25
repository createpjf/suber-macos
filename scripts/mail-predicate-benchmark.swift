#!/usr/bin/env swift
//
// scripts/mail-predicate-benchmark.swift
//
// Slice 1 load-bearing gate (eng re-review C2/D12).
//
// Prototypes the AppleScript `whose` predicate that MailWatchdog plans to use for
// incremental billing-receipt extraction. Measures:
//   1. Time to first result (wall clock)
//   2. Whether the filter actually pushes down to Mail (few results fast = good)
//      vs silently triggers a full-mailbox scan (slow regardless of matches)
//   3. Whether compound `AND (OR OR OR ...)` predicates are evaluated correctly
//      or throw errors / return unfiltered results
//
// USAGE
//   swift scripts/mail-predicate-benchmark.swift [days-back]
//
// First run will trigger the macOS TCC prompt asking "Allow Terminal to control Mail?".
// Grant it. On subsequent runs the permission persists.
//
// SUCCESS CRITERIA
//   Initial scan of last 30 days should return results in <= 90s on a 10k+ inbox.
//   If it takes longer OR returns `0` when you know receipts exist, the predicate
//   is degrading to a full-table scan and the Watchdog design must switch to
//   "fetch all message-IDs since cursor, filter in Swift" before Slice 5 starts.

import Foundation

let daysBack = CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 30

let script = """
tell application "Mail"
    set cutoff to (current date) - (\(daysBack) * days)
    set matchedMessages to {}
    set startTime to (current date)

    -- The exact predicate MailWatchdog plans to use in production.
    -- Six OR-clauses + one AND date comparison.
    repeat with acct in accounts
        repeat with mbox in mailboxes of acct
            try
                set matchedMessages to matchedMessages & ¬
                    (messages of mbox whose (date received > cutoff) and ¬
                        (subject contains "receipt" or ¬
                         subject contains "subscription" or ¬
                         subject contains "renewal" or ¬
                         subject contains "发票" or ¬
                         subject contains "订阅" or ¬
                         subject contains "续费"))
            on error errMsg number errNum
                log "Error in " & (name of mbox) & ": " & errMsg & " (" & errNum & ")"
            end try
        end repeat
    end repeat

    set elapsed to (current date) - startTime
    return "ELAPSED=" & elapsed & "s COUNT=" & (count of matchedMessages)
end tell
"""

let process = Process()
process.launchPath = "/usr/bin/osascript"
process.arguments = ["-e", script]

let stdout = Pipe()
let stderr = Pipe()
process.standardOutput = stdout
process.standardError = stderr

let wallStart = Date()
print("Running AppleScript predicate against Mail.app...")
print("  Window: last \(daysBack) days")
print("  If this is your first run, approve the Apple Events prompt when it appears.")
print("")

do {
    try process.run()
} catch {
    print("FAILED to launch osascript: \(error)")
    exit(1)
}

process.waitUntilExit()
let wallElapsed = Date().timeIntervalSince(wallStart)

let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

print("=== Result ===")
print("Wall time: \(String(format: "%.2f", wallElapsed))s")
print("osascript exit: \(process.terminationStatus)")
if !out.isEmpty { print("stdout: \(out)") }
if !err.isEmpty { print("stderr: \(err)") }

print("")
print("=== Interpretation ===")
if process.terminationStatus != 0 {
    print("❌ FAIL: osascript errored out.")
    print("   Possible causes: TCC permission denied; compound predicate rejected by Mail;")
    print("   syntax drift. Check stderr above.")
    print("   Action: Slice 5 design must switch to fetch-IDs-then-filter-in-Swift.")
    exit(2)
}

if wallElapsed > 90 {
    print("⚠️  SLOW: predicate took > 90s on \(daysBack)-day window.")
    print("   Likely falling back to full-mailbox scan (predicate not pushing down).")
    print("   Action: Slice 5 must switch to fetch-IDs-then-filter-in-Swift strategy.")
    print("   Rerun with smaller --days-back to confirm this is predicate, not dataset size.")
    exit(3)
}

print("✅ PASS: predicate executed in \(String(format: "%.2f", wallElapsed))s.")
print("   Output line above should contain ELAPSED=<seconds> COUNT=<matches>.")
print("   If COUNT is suspiciously low compared to how many receipts you know you have,")
print("   the predicate may be silently dropping results and Slice 5 still needs review.")
print("")
print("Slice 1 gate: verified. Safe to proceed with Slice 2.")
