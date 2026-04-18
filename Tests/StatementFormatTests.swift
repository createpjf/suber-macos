import XCTest
@testable import Suber

final class StatementFormatTests: XCTestCase {

    // MARK: - CSVParser

    func test_csv_parser_handles_quoted_fields_with_commas() {
        let text = [
            "Date,Description,Amount",
            #"2026-01-14,"Netflix, Inc.",-15.99"#,
            #"2026-02-14,"Spotify AB",-9.99"#,
            "",
        ].joined(separator: "\n")
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][1], "Netflix, Inc.")
    }

    func test_csv_parser_handles_escaped_quotes() {
        let text = #"a,"He said ""hi""",c"# + "\n"
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows[0][1], "He said \"hi\"")
    }

    func test_csv_parser_handles_crlf() {
        let text = "a,b,c\r\n1,2,3\r\n"
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], ["1", "2", "3"])
    }

    func test_csv_parser_strips_utf8_bom() {
        let text = "\u{FEFF}a,b\n1,2\n"
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows[0], ["a", "b"])
    }

    // MARK: - AlipayFormat

    func test_alipay_format_parses_outflow() throws {
        let csv = """
        支付宝(中国)网络技术有限公司
        账单明细
        账户名:test
        ----------------交易记录明细----------------
        交易创建时间,付款时间,交易对方,商品名称,金额(元),收/支,交易状态,
        2026-01-14 10:00:00,2026-01-14 10:00:00,爱奇艺,会员服务,29.90,支出,交易成功,
        2026-02-14 10:00:00,2026-02-14 10:00:00,爱奇艺,会员服务,29.90,支出,交易成功,
        2026-02-15 12:00:00,2026-02-15 12:00:00,朋友,转账,100.00,收入,交易成功,
        """
        let rows = CSVParser.parse(csv)
        let format = AlipayFormat()
        let txs = try format.parse(rows: rows)
        XCTAssertEqual(txs.count, 2, "Should keep only 支出 rows")
        XCTAssertEqual(txs[0].merchantRaw, "爱奇艺")
        XCTAssertEqual(txs[0].amount, 29.9, accuracy: 0.01)
        XCTAssertEqual(txs[0].currency, "CNY")
    }

    // MARK: - WechatFormat

    func test_wechat_format_skips_refunds() throws {
        let csv = """
        微信支付账单明细
        ----------------以下是账单明细列表----------------
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
        2026-01-14 10:00:00,商户消费,腾讯视频,VIP,支出,¥25.00,零钱,支付成功,12345,x,
        2026-02-14 10:00:00,商户消费,腾讯视频,VIP,支出,¥25.00,零钱,支付成功,23456,x,
        2026-02-16 11:00:00,商户消费,某小店,某商品,支出,¥9.90,零钱,已退款,34567,x,
        """
        let rows = CSVParser.parse(csv)
        let format = WechatFormat()
        let txs = try format.parse(rows: rows)
        XCTAssertEqual(txs.count, 2)
        XCTAssertTrue(txs.allSatisfy { $0.merchantRaw == "腾讯视频" })
    }

    // MARK: - GenericFormat

    func test_generic_format_chase_style() throws {
        let csv = """
        Transaction Date,Post Date,Description,Category,Type,Amount
        2026-01-14,2026-01-15,NETFLIX.COM,Entertainment,Sale,-15.99
        2026-02-14,2026-02-15,NETFLIX.COM,Entertainment,Sale,-15.99
        2026-02-20,2026-02-21,AMZN Mktp US,Shopping,Sale,-42.10
        2026-02-25,2026-02-25,PAYROLL DEPOSIT,Income,Payment,2500.00
        """
        let rows = CSVParser.parse(csv)
        let format = GenericFormat()
        let txs = try format.parse(rows: rows)
        XCTAssertEqual(txs.count, 3, "Should drop payroll (positive amount / Payment type)")
        XCTAssertTrue(txs.allSatisfy { $0.currency == "USD" })
    }

    func test_generic_format_revolut_style_with_currency_column() throws {
        let csv = """
        Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance
        CARD_PAYMENT,Current,2026-01-14 10:00:00,2026-01-14 10:00:00,Netflix,-7.99,0,GBP,COMPLETED,100
        CARD_PAYMENT,Current,2026-02-14 10:00:00,2026-02-14 10:00:00,Netflix,-7.99,0,GBP,COMPLETED,92
        TOPUP,Current,2026-02-16 08:00:00,2026-02-16 08:00:00,Top-up,100,0,GBP,COMPLETED,192
        """
        let rows = CSVParser.parse(csv)
        let format = GenericFormat()
        let txs = try format.parse(rows: rows)
        XCTAssertEqual(txs.count, 2)
        XCTAssertTrue(txs.allSatisfy { $0.currency == "GBP" })
    }

    func test_generic_format_missing_required_column_throws() {
        let csv = "Foo,Bar\n1,2\n"
        let rows = CSVParser.parse(csv)
        let format = GenericFormat()
        XCTAssertThrowsError(try format.parse(rows: rows))
    }
}
