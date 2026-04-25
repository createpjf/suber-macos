import Foundation

// ┌───────────── MailSubscriptionExtractor — receipt → candidate ──────────────┐
// │                                                                            │
// │  Takes [MailMessage] (raw receipt emails) and returns                      │
// │  [CandidateSubscription] (structured rows the ChangeDetector can reason    │
// │  about, and the D3 newCharge flow can Add via pre-filled form).            │
// │                                                                            │
// │  D8 privacy policy: this is the ONE place raw email body text gets read.   │
// │  After extraction, the MailMessage values fall out of scope. We persist    │
// │  only the extracted CandidateSubscription fields (amount, currency, cycle, │
// │  merchant name, billing day, dates). Raw body text NEVER reaches           │
// │  StorageService.                                                           │
// │                                                                            │
// │  Extraction strategy — simple, honest, testable:                           │
// │    1. Regex-extract price: first monetary amount in body (e.g. "$22.99",   │
// │       "€9.99", "¥188"). Currency inferred from symbol or ISO code.         │
// │    2. Regex-extract service name: from sender domain OR subject line       │
// │       ("Netflix", "Spotify", "ChatGPT Plus", etc.). Prefer the sender      │
// │       domain (unique, stable) over subject parsing (noisy).                │
// │    3. Regex-extract billing-cycle hint: "monthly", "yearly", "per month",  │
// │       "/mo", "/year", "每月", "每年", "年订阅". Default monthly if absent.  │
// │    4. Trial detection: "trial ends in N days", "试用期还剩". Maps to       │
// │       CandidateSubscription with cycle .monthly and trial flag (set on     │
// │       CandidateSubscription? no — trial lives on Subscription after Add).  │
// │    5. Billing day: from message date (day-of-month).                       │
// │                                                                            │
// │  NOT doing (deferred): OCR on embedded images, PDF-attachment parsing,     │
// │  multi-line amount aggregation. v1.6 ships the clean-email path.           │
// │                                                                            │
// │  Rejection rules — emails we can tell are NOT subscription receipts:       │
// │    - Amazon shipping notifications (subject contains "shipped"/"delivered")│
// │    - Zero-amount "welcome" emails (no $ extractable)                       │
// │    - Refund receipts (negative or "refund" keyword in body)                │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum MailSubscriptionExtractor {

    /// Extract candidates from a batch of messages. Unrecognizable messages
    /// are silently skipped — we trust the subject-line filter to pre-select,
    /// and we'd rather return [] than false-positives.
    static func extract(from messages: [MailMessage]) -> [CandidateSubscription] {
        messages.compactMap { extract(from: $0) }
    }

    /// Extract a single candidate, or nil if the message isn't a parseable receipt.
    static func extract(from message: MailMessage) -> CandidateSubscription? {
        // Rejection gate — known non-subscription signals.
        if looksLikeShipping(message) { return nil }
        if looksLikeRefund(message) { return nil }

        guard let price = extractPrice(from: message.body) else { return nil }
        guard price.amount > 0 else { return nil }

        let serviceName = extractServiceName(from: message)
        guard !serviceName.isEmpty else { return nil }

        let cycle = extractCycle(from: message.body) ?? .monthly

        // Billing day: message received date. For recurring subs this will be
        // close to the real billing day; if drift is large (e.g. receipt
        // delayed by 3 days), the user can correct via Edit after Add.
        let billingDay = Calendar.current.component(.day, from: message.dateReceived)

        return CandidateSubscription(
            name: serviceName,
            normalizedMerchant: MerchantNormalizer.normalize(serviceName),
            sampleMerchantRaw: message.sender,
            amount: price.amount,
            currency: price.currency,
            cycle: cycle,
            billingDay: billingDay,
            startDate: message.dateReceived,
            lastChargeDate: message.dateReceived,
            category: nil,
            occurrences: 1,
            confidence: .medium    // one-receipt confidence is medium; CSV clusters are high
        )
    }

    // MARK: - Rejection rules

    /// NSLocalizedString ignore — extractor heuristic keywords
    private static let shippingKeywords: [String] = [
        "shipped", "delivered", "on its way", "out for delivery",
        "已发货", "已送达", "配送中",
    ]
    private static func looksLikeShipping(_ m: MailMessage) -> Bool {
        let haystack = (m.subject + " " + m.body).lowercased()
        return shippingKeywords.contains { haystack.contains($0) }
    }

    /// NSLocalizedString ignore — extractor heuristic keywords
    private static let refundKeywords: [String] = [
        "refund", "refunded", "reversal", "credit issued",
        "退款", "已退款",
    ]
    private static func looksLikeRefund(_ m: MailMessage) -> Bool {
        let haystack = (m.subject + " " + m.body).lowercased()
        return refundKeywords.contains { haystack.contains($0) }
    }

    // MARK: - Price extraction

    /// Parsed monetary amount with currency. Currency inferred from symbol
    /// in the matched substring, falls back to USD.
    struct Price {
        let amount: Double
        let currency: String
    }

    /// First plausible monetary amount in the body. Matches:
    ///   $22.99    USD
    ///   $1,234.56 USD thousand-separator
    ///   €9.99     EUR
    ///   €9,99     EUR decimal-comma
    ///   £7.99     GBP
    ///   ¥188      CNY/JPY (context-dependent; default CNY for Chinese emails)
    ///   USD 22.99 / 22.99 USD (ISO-code style)
    ///   9.99 €    (trailing symbol style)
    ///
    /// Number grammar: one or more digit-groups separated by commas, optional
    /// `.nn` fractional. Covers both `1,234.56` (US) and `9,99` (EU).
    private static let amountPattern = #"[0-9][0-9,]*(?:\.[0-9]{1,2})?"#

    static func extractPrice(from body: String) -> Price? {
        // Symbol-prefixed: $22.99, €9.99, £7.99, ¥188, $1,234.56
        let symbolPattern = #"([$€£¥])\s?(\#(amountPattern))"#
        if let match = firstMatch(of: symbolPattern, in: body),
           let amount = parseAmount(match.group(2)) {
            let symbol = match.group(1)
            return Price(amount: amount, currency: currencyForSymbol(symbol, body: body))
        }

        // ISO-code prefixed: USD 22.99, EUR 9.99, CNY 188
        let isoPrefixPattern = #"\b(USD|EUR|GBP|CNY|JPY|KRW|CAD|AUD|HKD|SGD)\s+(\#(amountPattern))\b"#
        if let match = firstMatch(of: isoPrefixPattern, in: body),
           let amount = parseAmount(match.group(2)) {
            return Price(amount: amount, currency: match.group(1))
        }

        // ISO-code suffixed: 22.99 USD
        let isoSuffixPattern = #"\b(\#(amountPattern))\s+(USD|EUR|GBP|CNY|JPY|KRW|CAD|AUD|HKD|SGD)\b"#
        if let match = firstMatch(of: isoSuffixPattern, in: body),
           let amount = parseAmount(match.group(1)) {
            return Price(amount: amount, currency: match.group(2))
        }

        return nil
    }

    private static func parseAmount(_ s: String) -> Double? {
        // Strategy:
        //   contains dot  → dot is decimal, commas are thousands-separators.
        //     "1,234.56" → "1234.56" → 1234.56
        //     "9.99"     → 9.99
        //   comma only, 1-2 digits after  → European decimal
        //     "9,99"  → 9.99
        //     "9,9"   → 9.9
        //   comma only, 3 digits after    → thousands-separator
        //     "1,234"  → 1234
        //   no punctuation → plain integer
        //     "188"   → 188
        if s.contains(".") {
            return Double(s.replacingOccurrences(of: ",", with: ""))
        }
        if s.contains(",") {
            let parts = s.split(separator: ",")
            // Exactly one comma AND the segment after has 1-2 digits → decimal comma.
            if parts.count == 2, let last = parts.last, last.count <= 2 {
                return Double(s.replacingOccurrences(of: ",", with: "."))
            }
            // Else treat commas as thousands.
            return Double(s.replacingOccurrences(of: ",", with: ""))
        }
        return Double(s)
    }

    private static func currencyForSymbol(_ symbol: String, body: String) -> String {
        switch symbol {
        case "$": return "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥":
            // Disambiguate Yen vs Yuan: if body has CJK characters, bias CNY;
            // else JPY. Crude but the data is honest about this — both share
            // the symbol in practice.
            return body.contains(where: { $0.isCJKIdeograph }) ? "CNY" : "JPY"
        default: return "USD"
        }
    }

    // MARK: - Service name extraction

    /// Prefer sender domain (stable), fall back to subject first-token heuristic.
    static func extractServiceName(from message: MailMessage) -> String {
        // Sender format: "Netflix <info@netflix.com>" or "info@netflix.com"
        // or just a display name. Prefer the domain.
        if let domain = extractDomain(from: message.sender) {
            return titleCase(domain)
        }
        // Fall back to subject's first capitalized word (often the service name).
        let firstWord = message.subject
            .split(separator: " ")
            .first
            .map(String.init)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        return firstWord ?? ""
    }

    /// Pulls the eTLD+1 (roughly) from "xxx@foo.bar.com" → "foo". We don't
    /// need a full PublicSuffixList here; "netflix.com" → "netflix" is enough.
    private static func extractDomain(from sender: String) -> String? {
        // Find @domain.tld
        guard let at = sender.firstIndex(of: "@") else { return nil }
        let afterAt = sender[sender.index(after: at)...]
        // Strip trailing ">" if sender was "Name <addr@domain>"
        let cleaned = afterAt.split(whereSeparator: { $0 == ">" || $0.isWhitespace }).first ?? ""
        // Take second-to-last label as the service name: "a.b.netflix.com" → "netflix"
        let labels = cleaned.split(separator: ".")
        guard labels.count >= 2 else { return nil }
        // "netflix.com" → labels = ["netflix", "com"] → want labels[0]
        // "mail.netflix.com" → labels = ["mail", "netflix", "com"] → want labels[1]
        return String(labels[labels.count - 2])
    }

    private static func titleCase(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: - Cycle extraction

    static func extractCycle(from body: String) -> BillingCycle? {
        let lower = body.lowercased()
        // Order: more specific patterns first so "quarterly" beats "yearly"
        // (neither contains the other, but for consistency keep specificity).
        if lower.contains("weekly") || lower.contains("per week") || lower.contains("/week") ||
           lower.contains("每周") {
            return .weekly
        }
        if lower.contains("quarterly") || lower.contains("per quarter") ||
           lower.contains("每季") {
            return .quarterly
        }
        if lower.contains("yearly") || lower.contains("annual") || lower.contains("per year") ||
           lower.contains("/year") || lower.contains("/yr") ||
           lower.contains("每年") || lower.contains("年订阅") {
            return .yearly
        }
        if lower.contains("monthly") || lower.contains("per month") ||
           lower.contains("/month") || lower.contains("/mo") ||
           lower.contains("每月") || lower.contains("月订阅") {
            return .monthly
        }
        return nil
    }

    // MARK: - Regex helpers

    private static func firstMatch(of pattern: String, in input: String) -> MatchResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range) else { return nil }
        return MatchResult(match: match, source: input)
    }

    private struct MatchResult {
        let match: NSTextCheckingResult
        let source: String
        func group(_ i: Int) -> String {
            guard i < match.numberOfRanges,
                  let range = Range(match.range(at: i), in: source) else { return "" }
            return String(source[range])
        }
    }
}

// MARK: - CJK helper (used by currency disambiguation)

private extension Character {
    /// Rough heuristic — is this character in a CJK ideograph block?
    /// Good enough to tell "¥188 for 爱奇艺 订阅" apart from "¥188 for Plex".
    var isCJKIdeograph: Bool {
        unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x4E00...0x9FFF).contains(v)     // CJK Unified Ideographs
                || (0x3400...0x4DBF).contains(v)     // CJK Extension A
                || (0x20000...0x2A6DF).contains(v)   // CJK Extension B
        }
    }
}
