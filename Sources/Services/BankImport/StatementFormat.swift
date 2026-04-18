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
        switch self {
        case .missingColumn(let name):
            return "Couldn't find column \"\(name)\" in the CSV."
        case .emptyFile:
            return "The CSV has no data rows."
        case .unrecognizedFormat:
            return "Couldn't detect columns automatically. Try the format-specific option, or pick a different CSV."
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

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MM-dd-yyyy",
        ]
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
        s = s.replacingOccurrences(of: ",", with: "")
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
