import Foundation

/// Parses raw OCR text into structured subscription form data.
enum SubscriptionTextParser {

    struct ParsedSubscription {
        var name: String?
        var url: String?
        var amount: String?
        var currency: String?
        var cycle: BillingCycle?
        var startDate: Date?
        var trialEndDate: Date?
        var category: String?
        var status: SubscriptionStatus?
    }

    // MARK: - Main Parse Entry

    static func parse(_ text: String) -> ParsedSubscription {
        var result = ParsedSubscription()

        // 1. Try known service match first
        if let service = KnownServices.findMatch(in: text) {
            result.name = service.names.first
            result.url = service.domain
            result.category = service.category
            result.cycle = service.defaultCycle
        }

        // 2. Parse amount and currency
        let (amount, currency) = parseAmount(text)
        result.amount = amount
        result.currency = currency

        // 3. Parse billing cycle (may override known service default)
        if let cycle = parseCycle(text) {
            result.cycle = cycle
        }

        // 4. Parse dates
        let dates = parseDates(text)
        if let start = dates.start { result.startDate = start }
        if let trial = dates.trialEnd { result.trialEndDate = trial }

        // 5. Parse status — only set if explicitly trial/cancelled/paused found
        let detectedStatus = parseStatus(text)
        if detectedStatus != .active {
            result.status = detectedStatus
        }

        // 6. If no known service matched, try to infer name from text
        if result.name == nil {
            result.name = inferServiceName(text)
        }

        // 7. If no category from known service, try keyword inference
        if result.category == nil {
            result.category = inferCategory(text)
        }

        return result
    }

    // MARK: - Amount Parsing

    /// Currency symbol to code mapping (reversed from AppConstants.currencySymbols)
    private static let symbolToCode: [(symbol: String, code: String)] = [
        ("HK$", "HKD"), ("NT$", "TWD"), ("A$", "AUD"), ("C$", "CAD"),
        ("S$", "SGD"), ("MX$", "MXN"), ("R$", "BRL"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "CNY"),
        ("₩", "KRW"), ("₹", "INR"), ("₽", "RUB"), ("฿", "THB"),
        ("kr", "SEK"), ("CHF", "CHF"),
    ]

    /// Currency code patterns (appear after amount or standalone)
    private static let currencyCodes = Set(AppConstants.currencies)

    static func parseAmount(_ text: String) -> (amount: String?, currency: String?) {
        var detectedCurrency: String?

        // Strategy: find all potential amounts, pick the best one.
        struct AmountCandidate {
            let value: String
            let currency: String?
            let priority: Int  // higher = better
        }
        var candidates: [AmountCandidate] = []

        // Priority keywords — amounts near these words are more likely the real price
        let priorityKeywords = ["total", "charge", "amount", "payment", "price",
                                "billed", "due", "subtotal", "cost", "fee",
                                "合计", "总计", "金额", "价格", "费用", "支付"]

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let lowerLine = line.lowercased()
            let hasPriorityKeyword = priorityKeywords.contains { lowerLine.contains($0) }
            let basePriority = hasPriorityKeyword ? 10 : 0

            // Try each symbol pattern
            for (symbol, code) in symbolToCode {
                // Pattern: symbol + optional space + number
                let escaped = NSRegularExpression.escapedPattern(for: symbol)
                let pattern = "\(escaped)\\s*(\\d{1,}(?:[.,]\\d{1,2})?)"
                if let match = firstMatch(pattern: pattern, in: line) {
                    let numStr = normalizeNumber(match)
                    candidates.append(AmountCandidate(value: numStr, currency: code, priority: basePriority + 5))
                }
            }

            // Pattern: number + optional space + currency code
            let codePattern = "(\\d{1,}(?:[.,]\\d{1,2})?)\\s*(USD|EUR|GBP|CNY|JPY|KRW|CAD|AUD|CHF|HKD|SGD|SEK|NOK|DKK|INR|BRL|MXN|TWD|THB|RUB)"
            if let regex = try? NSRegularExpression(pattern: codePattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let numRange = Range(match.range(at: 1), in: line),
                   let codeRange = Range(match.range(at: 2), in: line) {
                    let numStr = normalizeNumber(String(line[numRange]))
                    let code = String(line[codeRange]).uppercased()
                    candidates.append(AmountCandidate(value: numStr, currency: code, priority: basePriority + 5))
                }
            }

            // Fallback: standalone number near price keywords
            if hasPriorityKeyword {
                let numPattern = "(\\d{1,}[.,]\\d{2})"
                if let match = firstMatch(pattern: numPattern, in: line) {
                    let numStr = normalizeNumber(match)
                    candidates.append(AmountCandidate(value: numStr, currency: nil, priority: basePriority))
                }
            }
        }

        // Sort: highest priority first, then largest amount
        candidates.sort { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return (Double(a.value) ?? 0) > (Double(b.value) ?? 0)
        }

        if let best = candidates.first {
            detectedCurrency = best.currency

            // If currency from amount is ambiguous (e.g. ¥ could be CNY or JPY), check context
            if detectedCurrency == "CNY" {
                let lowerText = text.lowercased()
                if lowerText.contains("jpy") || lowerText.contains("japan") || lowerText.contains("日本") || lowerText.contains("円") {
                    detectedCurrency = "JPY"
                }
            }
            if detectedCurrency == "SEK" {
                let lowerText = text.lowercased()
                if lowerText.contains("nok") || lowerText.contains("norway") || lowerText.contains("norsk") {
                    detectedCurrency = "NOK"
                } else if lowerText.contains("dkk") || lowerText.contains("denmark") || lowerText.contains("dansk") {
                    detectedCurrency = "DKK"
                }
            }

            return (best.value, detectedCurrency)
        }

        return (nil, nil)
    }

    // MARK: - Billing Cycle

    private static let cycleKeywords: [(keywords: [String], cycle: BillingCycle)] = [
        (["weekly", "per week", "/wk", "/week", "every week", "每周"], .weekly),
        (["monthly", "per month", "/mo", "/month", "every month", "each month", "每月", "月度", "包月"], .monthly),
        (["quarterly", "every 3 months", "per quarter", "/qtr", "每季", "季度"], .quarterly),
        (["yearly", "annual", "per year", "/yr", "/year", "annually", "every year", "年度", "包年", "每年"], .yearly),
        (["one-time", "one time", "lifetime", "once", "一次性", "终身", "买断"], .oneTime),
    ]

    static func parseCycle(_ text: String) -> BillingCycle? {
        let lower = text.lowercased()
        for entry in cycleKeywords {
            for keyword in entry.keywords {
                if lower.contains(keyword.lowercased()) {
                    return entry.cycle
                }
            }
        }
        return nil
    }

    // MARK: - Date Parsing

    struct DateResult {
        var start: Date?
        var trialEnd: Date?
    }

    private static let startKeywords = ["start", "billing", "billed", "began", "since", "开始", "生效"]
    private static let trialKeywords = ["trial end", "trial expire", "free trial", "试用到期", "试用截止", "试用结束"]
    private static let nextKeywords = ["next billing", "next payment", "renewal", "renew", "下次扣款", "续费"]

    static func parseDates(_ text: String) -> DateResult {
        var result = DateResult()
        let lines = text.components(separatedBy: .newlines)

        // Collect all dates found with their context
        struct DateCandidate {
            let date: Date
            let context: String  // the line where it was found
        }

        var candidates: [DateCandidate] = []

        for line in lines {
            if let date = extractDate(from: line) {
                candidates.append(DateCandidate(date: date, context: line.lowercased()))
            }
        }

        // Assign dates based on context keywords
        for candidate in candidates {
            let ctx = candidate.context

            if trialKeywords.contains(where: { ctx.contains($0.lowercased()) }) {
                result.trialEnd = candidate.date
            } else if startKeywords.contains(where: { ctx.contains($0.lowercased()) }) {
                result.start = candidate.date
            } else if nextKeywords.contains(where: { ctx.contains($0.lowercased()) }) {
                // Next billing date — use as start date if none found
                if result.start == nil { result.start = candidate.date }
            }
        }

        // If only one date found and no context matched, use it as start date
        if candidates.count == 1 && result.start == nil && result.trialEnd == nil {
            result.start = candidates[0].date
        }

        return result
    }

    private static func extractDate(from text: String) -> Date? {
        // Try specific patterns first

        // Chinese: 2025年1月15日
        let chinesePattern = "(\\d{4})年(\\d{1,2})月(\\d{1,2})日"
        if let match = firstMatchGroups(pattern: chinesePattern, in: text, groupCount: 3) {
            if let y = Int(match[0]), let m = Int(match[1]), let d = Int(match[2]) {
                return makeDate(year: y, month: m, day: d)
            }
        }

        // ISO / standard: yyyy-MM-dd or yyyy/MM/dd
        let isoPattern = "(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})"
        if let match = firstMatchGroups(pattern: isoPattern, in: text, groupCount: 3) {
            if let y = Int(match[0]), let m = Int(match[1]), let d = Int(match[2]),
               m >= 1 && m <= 12 && d >= 1 && d <= 31 {
                return makeDate(year: y, month: m, day: d)
            }
        }

        // English natural: January 15, 2025 / Jan 15, 2025
        let naturalPattern = "(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s*(\\d{4})"
        if let match = firstMatchGroups(pattern: naturalPattern, in: text, groupCount: 3) {
            if let m = monthNumber(match[0]), let d = Int(match[1]), let y = Int(match[2]) {
                return makeDate(year: y, month: m, day: d)
            }
        }

        // Also: 15 January 2025 / 15 Jan 2025
        let reversedPattern = "(\\d{1,2})(?:st|nd|rd|th)?\\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\s+(\\d{4})"
        if let match = firstMatchGroups(pattern: reversedPattern, in: text, groupCount: 3) {
            if let d = Int(match[0]), let m = monthNumber(match[1]), let y = Int(match[2]) {
                return makeDate(year: y, month: m, day: d)
            }
        }

        // US/EU: MM/dd/yyyy or dd/MM/yyyy — use locale to disambiguate
        let slashPattern = "(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})"
        if let match = firstMatchGroups(pattern: slashPattern, in: text, groupCount: 3) {
            if let a = Int(match[0]), let b = Int(match[1]), let y = Int(match[2]) {
                // If one part > 12, it must be the day
                if a > 12 && b <= 12 {
                    return makeDate(year: y, month: b, day: a) // dd/MM/yyyy
                } else if b > 12 && a <= 12 {
                    return makeDate(year: y, month: a, day: b) // MM/dd/yyyy
                } else if a <= 12 && b <= 31 {
                    // Ambiguous — use locale preference
                    let usesMonthFirst = Locale.current.identifier.hasPrefix("en_US")
                    if usesMonthFirst {
                        return makeDate(year: y, month: a, day: b)
                    } else {
                        return makeDate(year: y, month: b, day: a)
                    }
                }
            }
        }

        // Fallback: NSDataDetector
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range), let date = match.date {
                return date
            }
        }

        return nil
    }

    // MARK: - Status

    static func parseStatus(_ text: String) -> SubscriptionStatus {
        let lower = text.lowercased()
        if lower.contains("trial") || lower.contains("free trial") || lower.contains("试用") {
            return .trial
        }
        if lower.contains("cancel") || lower.contains("已取消") || lower.contains("取消") {
            return .cancelled
        }
        if lower.contains("pause") || lower.contains("暂停") {
            return .paused
        }
        return .active
    }

    // MARK: - Service Name Inference

    /// If no known service matched, try to pick the most prominent text as service name.
    static func inferServiceName(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip lines that look like dates, amounts, or generic words
        let skipPatterns = ["receipt", "invoice", "order", "payment", "confirmation",
                            "thank you", "thanks", "dear", "hello", "hi ",
                            "total", "subtotal", "tax", "收据", "发票", "订单", "确认"]

        for line in lines.prefix(5) {
            let lower = line.lowercased()
            // Skip if line is too long (probably a sentence, not a service name)
            if line.count > 40 { continue }
            // Skip if it contains price patterns
            if line.contains("$") || line.contains("€") || line.contains("£") || line.contains("¥") { continue }
            // Skip generic words
            if skipPatterns.contains(where: { lower.contains($0) }) { continue }
            // Skip pure numbers or dates
            if Double(line) != nil { continue }

            return line
        }
        return nil
    }

    // MARK: - Category Inference

    static func inferCategory(_ text: String) -> String? {
        let lower = text.lowercased()
        let categoryKeywords: [(keywords: [String], category: String)] = [
            (["stream", "video", "movie", "film", "watch", "视频", "影视"], "Streaming"),
            (["music", "song", "audio", "podcast", "音乐", "歌曲"], "Music"),
            (["cloud", "storage", "backup", "云存储", "网盘", "云盘"], "Cloud Storage"),
            (["ai", "artificial intelligence", "machine learning", "人工智能"], "AI"),
            (["game", "gaming", "play", "游戏"], "Gaming"),
            (["fitness", "workout", "health", "gym", "exercise", "健身", "运动"], "Fitness"),
            (["news", "journal", "newspaper", "press", "新闻", "报纸"], "News"),
            (["learn", "course", "education", "study", "学习", "课程", "教育"], "Education"),
            (["invest", "stock", "trade", "bank", "finance", "投资", "理财", "金融"], "Finance"),
            (["design", "photo", "edit", "creative", "设计", "创意"], "Software"),
            (["vpn", "security", "privacy", "安全", "隐私"], "Software"),
            (["code", "develop", "programming", "git", "编程", "开发"], "Software"),
            (["project", "task", "team", "collaborate", "项目", "协作"], "Productivity"),
        ]

        for (keywords, category) in categoryKeywords {
            if keywords.contains(where: { lower.contains($0) }) {
                return category
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let groupRange = Range(match.range(at: 1), in: text) {
            return String(text[groupRange])
        }
        if let fullRange = Range(match.range, in: text) {
            return String(text[fullRange])
        }
        return nil
    }

    private static func firstMatchGroups(pattern: String, in text: String, groupCount: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard match.numberOfRanges > groupCount else { return nil }

        var groups: [String] = []
        for i in 1...groupCount {
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            groups.append(String(text[r]))
        }
        return groups
    }

    private static func normalizeNumber(_ str: String) -> String {
        // Convert comma decimals to period: "9,99" -> "9.99"
        str.replacingOccurrences(of: ",", with: ".")
    }

    private static func monthNumber(_ name: String) -> Int? {
        let lower = name.lowercased()
        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
        let prefix = String(lower.prefix(3))
        return months[prefix]
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }
}
