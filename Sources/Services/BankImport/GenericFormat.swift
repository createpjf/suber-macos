import Foundation

/// Generic CSV adapter with header-name auto-detection.
///
/// Handles common export shapes:
///   - Chase: Transaction Date, Post Date, Description, Category, Type, Amount
///   - Amex:  Date, Description, Amount
///   - Revolut: Started Date, Completed Date, Description, Amount, Fee, Currency
///   - Mint / YNAB: Date, Description, Amount, Category
///
/// Detection is purely by header name; assumes first non-blank row is the header.
struct GenericFormat: StatementFormat {
    let displayName = "Generic CSV"
    let subtitle = "Chase · Amex · Revolut · any statement with Date / Description / Amount"

    func parse(rows: [[String]]) throws -> [StatementTransaction] {
        guard let header = rows.first, !header.isEmpty else {
            throw StatementFormatError.unrecognizedFormat
        }

        guard let dateCol = StatementFieldParser.columnIndex(
            in: header,
            matching: ["transaction date", "posted date", "started date", "date"]
        ) else { throw StatementFormatError.missingColumn("Date") }

        guard let merchantCol = StatementFieldParser.columnIndex(
            in: header,
            matching: ["description", "merchant", "payee", "name", "narrative", "details"]
        ) else { throw StatementFormatError.missingColumn("Description") }

        guard let amountCol = StatementFieldParser.columnIndex(
            in: header,
            matching: ["amount", "debit", "value"]
        ) else { throw StatementFormatError.missingColumn("Amount") }

        let currencyCol = StatementFieldParser.columnIndex(
            in: header, matching: ["currency", "ccy"]
        )

        // "Type" column lets us exclude transfers / payments / refunds on some banks.
        let typeCol = StatementFieldParser.columnIndex(
            in: header, matching: ["type", "transaction type"]
        )

        // Default currency guess: if we see "Amount (USD)" style header
        var defaultCurrency = "USD"
        if let amountHeader = header[safe: amountCol]?.lowercased() {
            if amountHeader.contains("eur") { defaultCurrency = "EUR" }
            else if amountHeader.contains("gbp") { defaultCurrency = "GBP" }
            else if amountHeader.contains("cny") || amountHeader.contains("rmb") { defaultCurrency = "CNY" }
        }

        var transactions: [StatementTransaction] = []
        for row in rows.dropFirst() where row.count > max(dateCol, merchantCol, amountCol) {
            guard let date = StatementFieldParser.parseDate(row[dateCol]),
                  let rawAmount = StatementFieldParser.parseAmount(row[amountCol]) else { continue }
            let merchant = row[merchantCol].trimmingCharacters(in: .whitespaces)
            guard !merchant.isEmpty else { continue }

            // Skip non-spend transaction types when available.
            // Careful: "card payment" / "card_payment" / "CARD PAYMENT" is a
            // purchase — we keep those. Only filter keywords that unambiguously
            // mean "not a spend": account transfers, refunds, reversals, top-ups.
            if let tCol = typeCol, tCol < row.count {
                let t = row[tCol].lowercased()
                let nonSpendKeywords = ["transfer", "refund", "reversal", "topup", "top-up", "top up", "deposit"]
                if nonSpendKeywords.contains(where: { t.contains($0) }) {
                    continue
                }
            }

            // Outgoing filter: most statements use negative amounts for spends,
            // but some (Revolut CSV) use positive amounts with a separate Type column.
            // Strategy: if any negative amounts exist in the file, treat negatives as outflow;
            // else treat all as outflow (already implicitly pre-filtered by type above).
            let isSpend = rawAmount < 0 || rowHasNoNegatives(rows: rows, amountCol: amountCol)
            guard isSpend else { continue }

            let currency: String
            if let cCol = currencyCol, cCol < row.count, !row[cCol].isEmpty {
                currency = row[cCol].trimmingCharacters(in: .whitespaces).uppercased()
            } else {
                currency = defaultCurrency
            }

            transactions.append(StatementTransaction(
                date: date,
                merchantRaw: merchant,
                amount: abs(rawAmount),
                currency: currency
            ))
        }

        if transactions.isEmpty { throw StatementFormatError.emptyFile }
        return transactions
    }

    /// Cached per-file check — if the file never uses negative amounts, the sign convention is "all positive = all spend".
    private func rowHasNoNegatives(rows: [[String]], amountCol: Int) -> Bool {
        for row in rows.dropFirst() where row.count > amountCol {
            if let amt = StatementFieldParser.parseAmount(row[amountCol]), amt < 0 {
                return false
            }
        }
        return true
    }
}

// MARK: - Collection safe-index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
