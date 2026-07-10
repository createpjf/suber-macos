import Foundation

/// Minimal RFC-4180 CSV parser.
///
/// Handles:
/// - Comma-separated fields
/// - Quoted fields (with escaped `""` inside)
/// - CRLF and LF line endings
/// - UTF-8 BOM stripping
/// - Skips blank lines
///
/// Does NOT handle: non-comma delimiters, header-row metadata.
enum CSVParser {

    enum ParseError: LocalizedError {
        case emptyFile
        case decodingFailed

        var errorDescription: String? {
            // U-02: surfaced verbatim in BankImportView's error stage.
            switch self {
            case .emptyFile: return String(localized: "File is empty.")
            case .decodingFailed: return String(localized: "Could not decode file as UTF-8.")
            }
        }
    }

    /// Parse CSV text into a 2D array of rows × columns.
    /// First non-blank row is returned as the first element — caller decides
    /// whether it's a header or data.
    static func parse(_ text: String) -> [[String]] {
        var text = text
        // Strip UTF-8 BOM if present
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        // Normalize line endings. Swift treats \r\n as a single extended-grapheme
        // cluster, which breaks character-by-character matching against "\r" or
        // "\n" literals. Collapse every variant to plain \n up-front.
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]

            if insideQuotes {
                if ch == "\"" {
                    // Lookahead: "" means literal "
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        currentField.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    insideQuotes = false
                    index = text.index(after: index)
                    continue
                }
                currentField.append(ch)
                index = text.index(after: index)
                continue
            }

            // Not inside quotes
            switch ch {
            case "\"":
                insideQuotes = true
            case ",":
                currentRow.append(currentField)
                currentField = ""
            case "\r":
                // Swallow \r; the following \n (if any) will close the row.
                currentRow.append(currentField)
                currentField = ""
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == "\n" {
                    index = next
                }
                if !currentRow.isEmpty && !(currentRow.count == 1 && currentRow[0].isEmpty) {
                    rows.append(currentRow)
                }
                currentRow = []
            case "\n":
                currentRow.append(currentField)
                currentField = ""
                if !currentRow.isEmpty && !(currentRow.count == 1 && currentRow[0].isEmpty) {
                    rows.append(currentRow)
                }
                currentRow = []
            default:
                currentField.append(ch)
            }
            index = text.index(after: index)
        }

        // Flush trailing field / row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    /// Decode a file's raw bytes into a String, trying UTF-8 first, then GBK/GB18030
    /// (common for Alipay/WeChat exports on Windows).
    static func decode(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // GB 18030 covers simplified Chinese exports
        if let gb = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
            return gb
        }
        throw ParseError.decodingFailed
    }
}
