import Foundation

/// Strips payment-processor noise so that variations like
/// "ALIPAY*NETFLIX*SUB", "Netflix.com 866-123-4567", and "NETFLIX NEW YORK US"
/// all reduce to the same key ("netflix") for grouping.
enum MerchantNormalizer {

    /// Returns a lowercase, trimmed, noise-stripped version of `raw`.
    /// Empty output means "no usable merchant token" — caller should skip.
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()

        // Drop common payment-processor prefixes that precede the real merchant
        let processorPrefixes = [
            "alipay*", "alipay ", "alipay-",
            "wechatpay*", "wechat pay*", "wechatpay ", "wechat pay ",
            "paypal*", "paypal ", "pypl*",
            "sq *", "sq*",           // Square
            "tst*", "tst *",          // Toast
            "google *", "google*",
            "apple.com/bill",
        ]
        for prefix in processorPrefixes {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
            }
        }

        // Collapse `*` separators to spaces — "NETFLIX*SUB*123" -> "netflix sub 123"
        s = s.replacingOccurrences(of: "*", with: " ")

        // Strip trailing numeric IDs (order numbers, reference codes, phone numbers)
        // Examples: "Netflix.com 866-123-4567" -> "Netflix.com", "Spotify USA 1234567"
        // Do this BEFORE tail-noise so the TLD / location suffix becomes the tail.

        // Phone: NNN-NNN-NNNN or NNN NNN NNNN
        s = s.replacingOccurrences(
            of: #"\s+\d{3}[-\s]?\d{3}[-\s]?\d{4}$"#,
            with: "",
            options: .regularExpression
        )
        // Long numeric ID run (order ref, transaction id)
        s = s.replacingOccurrences(
            of: #"\s+\d{4,}[-\s\d]*$"#,
            with: "",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\s+#\d+$"#,
            with: "",
            options: .regularExpression
        )

        // Strip trailing domain-suffix tokens glued to the merchant name:
        // "netflix.com" -> "netflix". Must come before / match inside the
        // tail-noise loop below.
        s = s.replacingOccurrences(
            of: #"\.(com|net|org|io|co|us|uk|ai|app|store)$"#,
            with: "",
            options: .regularExpression
        )

        // Drop trailing city/state/country noise patterns that banks attach
        // e.g. "NETFLIX NEW YORK NY US" -> "netflix". Run in a loop because
        // stripping " us" may expose " ny" which then also matches.
        let tailNoise = [
            " new york ny us", " new york ny", " ny us",
            " san francisco ca", " san francisco ca us",
            " los angeles ca", " seattle wa",
            " usa", " us", " uk", " ca", " de",
        ]
        var changed = true
        while changed {
            changed = false
            for noise in tailNoise where s.hasSuffix(noise) {
                s = String(s.dropLast(noise.count))
                changed = true
            }
        }

        // Collapse whitespace / non-alphanumerics (except CJK) to a single space
        s = s.replacingOccurrences(
            of: #"[\s\-_/]+"#,
            with: " ",
            options: .regularExpression
        )

        s = s.trimmingCharacters(in: .whitespaces)

        return s
    }

    /// Human-readable version of a normalized key — "netflix premium" -> "Netflix Premium".
    /// Used when no `KnownServices` match is found.
    static func displayName(from normalized: String) -> String {
        guard !normalized.isEmpty else { return "Unknown" }
        // For pure CJK strings, return as-is (capitalization doesn't apply).
        if normalized.unicodeScalars.allSatisfy({ $0.value > 0x4E00 || $0 == " " }) {
            return normalized
        }
        return normalized
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
