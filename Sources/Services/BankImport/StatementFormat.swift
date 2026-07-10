import Foundation

/// A strategy for converting raw CSV rows into `StatementTransaction`s.
protocol StatementFormat {
    /// Shown to the user in the format picker ("支付宝", "WeChat Pay", "Generic CSV").
    var displayName: String { get }

    /// Subtitle / hint in the format picker ("Alipay 账单导出", etc.)
    var subtitle: String { get }

    /// Turn already-parsed CSV rows (including the header row at index 0) into
    /// transactions. Non-outgoing rows (income, transfers between own accounts,
    /// refunds) are filtered out here.
    func parse(rows: [[String]]) throws -> [StatementTransaction]
}

enum StatementFormatError: LocalizedError {
    case missingColumn(String)
    case emptyFile
    case unrecognizedFormat

    var errorDescription: String? {
        // U-02: surfaced verbatim in BankImportView's error stage — localize.
        switch self {
        case .missingColumn(let name):
            return String(localized: "Couldn't find column \"\(name)\" in the CSV.")
        case .emptyFile:
            return String(localized: "The CSV has no data rows.")
        case .unrecognizedFormat:
            return String(localized: "Couldn't detect columns automatically. Try the format-specific option, or pick a different CSV.")
        }
    }
}

// MARK: - Shared parsing helpers

enum StatementFieldParser {

    /// Parse a date from common CSV date formats.
    /// Accepts: yyyy-MM-dd, yyyy/MM/dd, MM/dd/yyyy, dd/MM/yyyy, yyyy-MM-dd HH:mm:ss.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Ambiguous slash dates (AUDIT-v1.9.2 C-32): explicit dateFormat
        // matching ignores the formatter's locale, so array order is the only
        // disambiguation — "05/01/2026" is Jan 5 in the UK/EU, May 1 in the US.
        // Try the user's regional order first.
        let slashFormats: [String]
        if Locale.current.identifier.hasPrefix("en_US") {
            slashFormats = ["MM/dd/yyyy", "dd/MM/yyyy", "MM-dd-yyyy"]
        } else {
            slashFormats = ["dd/MM/yyyy", "MM/dd/yyyy", "MM-dd-yyyy"]
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
        ] + slashFormats
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: trimmed) {
                return Calendar.current.startOfDay(for: d)
            }
        }
        return nil
    }

    /// Parse a money value from an arbitrary CSV cell.
    /// Strips currency symbols, commas, surrounding quotes, and explicit signs.
    /// Returns the ABSOLUTE value (sign is communicated separately via `isOutgoing`).
    static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Strip common currency symbols
        for sym in ["$", "€", "£", "¥", "￥", "₩", "₹", "₽", "RMB", "USD", "CNY"] {
            s = s.replacingOccurrences(of: sym, with: "")
        }
        // Handle parenthesized negatives: "(9.99)" = -9.99 (US statement convention)
        var paren = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            paren = true
            s.removeFirst()
            s.removeLast()
        }
        // Decimal-separator disambiguation (AUDIT-v1.9.2 C-12): a blanket
        // comma-strip read EU decimal commas as thousands separators ("9,99" → 999).
        //   "1.234,56" (EU) → 1234.56   "9,99" (EU) → 9.99
        //   "1,234.56" (US) → 1234.56   "1,234" (US) → 1234
        if let lastComma = s.lastIndex(of: ","), let lastDot = s.lastIndex(of: "."), lastComma > lastDot {
            // EU style: dots are thousands separators, comma is the decimal point
            s = s.replacingOccurrences(of: ".", with: "")
            s = s.replacingOccurrences(of: ",", with: ".")
        } else if !s.contains("."),
                  s.filter({ $0 == "," }).count == 1,
                  let lastComma = s.lastIndex(of: ","),
                  s.distance(from: s.index(after: lastComma), to: s.endIndex) == 2 {
            // Lone comma with exactly 2 trailing digits: decimal comma ("9,99")
            s = s.replacingOccurrences(of: ",", with: ".")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard let n = Double(s) else { return nil }
        return paren ? -abs(n) : n
    }

    /// Helper: find column index whose header contains any of the given substrings
    /// (case-insensitive). Returns nil if none match.
    static func columnIndex(in header: [String], matching needles: [String]) -> Int? {
        for (i, cell) in header.enumerated() {
            let lower = cell.lowercased().trimmingCharacters(in: .whitespaces)
            for needle in needles {
                if lower.contains(needle.lowercased()) { return i }
            }
        }
        return nil
    }
}
