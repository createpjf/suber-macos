import Foundation

/// 支付宝账单 CSV 格式适配器。
///
/// 支付宝 app → 我的 → 账单 → 右上角 "..." → 开具交易流水证明 → 邮箱收到 CSV。
/// 常见列:
///   交易创建时间 | 付款时间 | 最近修改时间 | 交易来源地 | 类型 |
///   交易对方 | 商品名称 | 金额(元) | 收/支 | 交易状态 | ...
///
/// 我们只要:交易创建时间(或付款时间)、交易对方、金额、收/支。
struct AlipayFormat: StatementFormat {
    let displayName = "支付宝 (Alipay)"
    let subtitle = "从支付宝 App 导出的 CSV 账单"

    func parse(rows: [[String]]) throws -> [StatementTransaction] {
        // Find header row — Alipay exports often have 5-10 rows of metadata
        // (title, date range, name, account number, etc.) BEFORE the real header.
        guard let headerIdx = findHeaderRow(in: rows) else {
            throw StatementFormatError.unrecognizedFormat
        }
        let header = rows[headerIdx]

        guard let dateCol = StatementFieldParser.columnIndex(
            in: header, matching: ["交易创建时间", "付款时间", "交易时间"]
        ) else { throw StatementFormatError.missingColumn("交易时间") }

        guard let merchantCol = StatementFieldParser.columnIndex(
            in: header, matching: ["交易对方", "对方"]
        ) else { throw StatementFormatError.missingColumn("交易对方") }

        guard let amountCol = StatementFieldParser.columnIndex(
            in: header, matching: ["金额", "金额(元)"]
        ) else { throw StatementFormatError.missingColumn("金额") }

        // 收/支 column is optional — if missing, we'll fallback to sign-based filter.
        let directionCol = StatementFieldParser.columnIndex(
            in: header, matching: ["收/支", "收支"]
        )

        var transactions: [StatementTransaction] = []
        for row in rows[(headerIdx + 1)...] where row.count > max(dateCol, merchantCol, amountCol) {
            let dateRaw = row[dateCol]
            let merchant = row[merchantCol].trimmingCharacters(in: .whitespaces)
            let amountRaw = row[amountCol]

            guard let date = StatementFieldParser.parseDate(dateRaw),
                  let amount = StatementFieldParser.parseAmount(amountRaw),
                  !merchant.isEmpty else { continue }

            // Filter: outgoing only.
            if let dCol = directionCol, dCol < row.count {
                let dir = row[dCol].trimmingCharacters(in: .whitespaces)
                if dir != "支出" { continue }
            } else {
                // Without direction column, treat positive-signed amounts as outflow
                // (most Alipay exports don't include the "-" sign for spends).
                if amount <= 0 { continue }
            }

            transactions.append(StatementTransaction(
                date: date,
                merchantRaw: merchant,
                amount: abs(amount),
                currency: "CNY"
            ))
        }

        if transactions.isEmpty { throw StatementFormatError.emptyFile }
        return transactions
    }

    /// Alipay exports have metadata rows before the real column header.
    /// The real header is the first row that contains both "交易" and "金额".
    private func findHeaderRow(in rows: [[String]]) -> Int? {
        for (i, row) in rows.enumerated() {
            let joined = row.joined(separator: " ")
            if joined.contains("交易") && joined.contains("金额") {
                return i
            }
        }
        return nil
    }
}
