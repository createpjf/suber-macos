import Foundation

/// 微信支付账单 CSV 格式适配器。
///
/// 微信 → 我 → 服务 → 钱包 → 账单 → 右上角 → 账单下载 → 邮箱 CSV。
/// 常见列:
///   交易时间 | 交易类型 | 交易对方 | 商品 | 收/支 | 金额(元) | 支付方式 |
///   当前状态 | 交易单号 | 商户单号 | 备注
struct WechatFormat: StatementFormat {
    let displayName = "微信支付 (WeChat Pay)"
    let subtitle = "从微信导出的账单 CSV"

    func parse(rows: [[String]]) throws -> [StatementTransaction] {
        guard let headerIdx = findHeaderRow(in: rows) else {
            throw StatementFormatError.unrecognizedFormat
        }
        let header = rows[headerIdx]

        guard let dateCol = StatementFieldParser.columnIndex(
            in: header, matching: ["交易时间", "交易创建时间"]
        ) else { throw StatementFormatError.missingColumn("交易时间") }

        guard let merchantCol = StatementFieldParser.columnIndex(
            in: header, matching: ["交易对方", "对方"]
        ) else { throw StatementFormatError.missingColumn("交易对方") }

        guard let amountCol = StatementFieldParser.columnIndex(
            in: header, matching: ["金额(元)", "金额"]
        ) else { throw StatementFormatError.missingColumn("金额") }

        let directionCol = StatementFieldParser.columnIndex(
            in: header, matching: ["收/支", "收支"]
        )
        let statusCol = StatementFieldParser.columnIndex(
            in: header, matching: ["当前状态", "交易状态"]
        )

        var transactions: [StatementTransaction] = []
        for row in rows[(headerIdx + 1)...] where row.count > max(dateCol, merchantCol, amountCol) {
            let merchant = row[merchantCol].trimmingCharacters(in: .whitespaces)
            guard let date = StatementFieldParser.parseDate(row[dateCol]),
                  let amount = StatementFieldParser.parseAmount(row[amountCol]),
                  !merchant.isEmpty else { continue }

            // Outflow only.
            if let dCol = directionCol, dCol < row.count {
                let dir = row[dCol].trimmingCharacters(in: .whitespaces)
                if dir != "支出" { continue }
            } else {
                if amount <= 0 { continue }
            }

            // Skip refunded / cancelled transactions if status available.
            if let sCol = statusCol, sCol < row.count {
                let status = row[sCol]
                if status.contains("退款") || status.contains("已退款") || status.contains("已撤销") {
                    continue
                }
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

    /// WeChat exports also prefix the CSV with 16+ rows of metadata. The real header
    /// is the first row containing "交易时间".
    private func findHeaderRow(in rows: [[String]]) -> Int? {
        for (i, row) in rows.enumerated() where row.joined(separator: " ").contains("交易时间") {
            return i
        }
        return nil
    }
}
