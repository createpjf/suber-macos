import Foundation

/// Splits a blob of OCR text into per-subscription blocks, then parses each
/// block with the existing single-subscription parser.
///
/// Use case: user drops an iOS Settings > Subscriptions screenshot (or a
/// Google Play subscriptions page, or a bank app's auto-renewal list) — one
/// image, N subscriptions. The single-parse path would glue them all into
/// one wrong entry.
///
/// Strategy: scan the OCR text line-by-line. Every time we hit a line that
/// contains a **renewal anchor** ("Renews", "Expiring", "续费", "下次扣款",
/// etc.), close the current block. Each closed block is parsed independently
/// with `SubscriptionTextParser.parse(_:)`.
///
/// If zero anchors are found, callers should fall back to single-parse — this
/// parser only fires when it recognizes the multi-subscription shape.
enum MultiSubscriptionParser {

    /// Patterns that indicate the END of one subscription block in a stacked list.
    ///
    /// Anchors are intentionally narrow: they fire on phrasings that are
    /// near-exclusive to subscription status lines, not generic language in
    /// billing emails. If an anchor mistakenly fires mid-single-sub, the
    /// quality filter at the bottom drops the meaningless blocks.
    private static let anchorRegexes: [NSRegularExpression] = {
        let patterns: [String] = [
            // English
            #"\brenew(s|ed|al|ing)\b"#,                         // "Renews May 7", "Auto-renewal"
            #"\bexpir(es|ing|ed)\b"#,                            // "Expiring Jan 23"
            #"\bnext\s+(billing|bill|payment|charge|renewal)\b"#,// "Next billing May 7"
            #"\bauto[-\s]?renew"#,                               // "Auto-renew", "Auto renew"
            #"\bcancell?ed\s+\w+\s+\d"#,                         // "Canceled May 7" (Google Play)

            // Chinese
            "续费", "续订", "下次扣款", "自动续费", "到期续费", "订阅到期",
        ]
        return patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    /// Returns one `ParsedSubscription` per detected block.
    ///
    /// - Returns: Empty array if no anchors found (caller should fall back to
    ///   single-parse). Otherwise one entry per block that has at least a name
    ///   or amount.
    static func parseMultiple(_ text: String) -> [SubscriptionTextParser.ParsedSubscription] {
        let lines = text.components(separatedBy: .newlines)

        // Find indices of lines that match any anchor.
        // Require the line to ALSO contain a digit — this filters out bare
        // section headers like a column titled just "Renews" or "Active".
        var anchorLineIndices: [Int] = []
        for (i, line) in lines.enumerated() where isRealAnchor(line) {
            anchorLineIndices.append(i)
        }

        // Need at least 2 anchors to consider it a multi-sub screenshot.
        // With only 1 anchor, the single-parse path handles it fine already.
        guard anchorLineIndices.count >= 2 else {
            return []
        }

        // Split lines into blocks. Each block ends at the anchor line, BUT we
        // extend forward by one line if that next line looks like a bare price
        // — on iOS Apple Subscriptions the layout is:
        //     "Renews May 7"   ← anchor
        //     "$19.99"         ← price, belongs to THIS subscription
        //     "Claude"         ← start of next subscription
        var blocks: [[String]] = []
        var cursor = 0
        for anchorIdx in anchorLineIndices {
            // A price-line extension may have already consumed this anchor
            // (a line like "$14.99/renewal" matches BOTH looksLikePriceLine and
            // an anchor regex). Skip anchors before the cursor, otherwise
            // lines[cursor...endIdx] traps with lowerBound > upperBound.
            // (AUDIT-v1.9.2 C-13)
            guard anchorIdx >= cursor else { continue }
            var endIdx = anchorIdx
            let peekIdx = anchorIdx + 1
            if peekIdx < lines.count && looksLikePriceLine(lines[peekIdx]) {
                endIdx = peekIdx
            }
            let slice = Array(lines[cursor...endIdx])
            blocks.append(slice)
            cursor = endIdx + 1
        }
        // Trailing content after the last anchor (may be app chrome / page footer) — ignore.

        // Parse each block with the existing single-parser
        let parsed = blocks.map { blockLines in
            SubscriptionTextParser.parse(blockLines.joined(separator: "\n"))
        }

        // Quality filter: keep blocks that produced something usable AND that
        // look like actual subscription entries, not page chrome.
        return parsed.filter { p in
            // Must have at least one signal — a parsed name or an amount.
            guard (p.name?.isEmpty == false) || (p.amount?.isEmpty == false) else {
                return false
            }
            // Reject if the only signal is a name that's obvious UI chrome.
            if p.amount == nil, let name = p.name, isChromeName(name) {
                return false
            }
            return true
        }
    }

    // MARK: - Private

    private static let chromeNames: Set<String> = [
        "subscriptions", "subscription", "active", "all subscriptions",
        "inactive", "expired", "cancelled", "canceled",
        "sort", "settings", "manage",
        "订阅", "已失效", "已过期", "管理", "设置",
    ]

    /// Anchor line must match one of the renewal patterns AND contain a digit.
    /// The digit requirement filters out column headers that are just the word
    /// "Renews" / "Expired" without a date.
    private static func isRealAnchor(_ line: String) -> Bool {
        guard line.range(of: #"\d"#, options: .regularExpression) != nil else {
            return false
        }
        let range = NSRange(line.startIndex..., in: line)
        for regex in anchorRegexes {
            if regex.firstMatch(in: line, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// A line that is basically just a price (maybe with a cycle suffix like "/mo").
    /// Matches: "$19.99", "¥29.90", "$9.99/month", "USD 15.99"
    private static func looksLikePriceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^\s*(?:[\$¥€£₩₹]|USD|EUR|GBP|CNY|JPY)?\s*\d+(?:[.,]\d{1,2})?\s*(?:/\s*\w+|per\s+\w+)?\s*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isChromeName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return chromeNames.contains(lower)
    }
}
