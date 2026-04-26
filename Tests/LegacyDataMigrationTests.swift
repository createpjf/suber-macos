import XCTest
@testable import Suber

/// 单测覆盖 v1.8.0 LegacyDataMigration：
///   - 老 plist 不存在 → no-op
///   - 老 plist 存在 → 三个 key 都迁到 AppGroupStore
///   - AppGroupStore 已有数据 → 不覆盖（保护 iCloud sync 已经拉过来的更新版本）
///   - 一次性标志位 → 第二次跑 no-op，即使老 plist 后来才出现
final class LegacyDataMigrationTests: XCTestCase {

    /// 测试用临时 plist 路径（每个 case 一个 UUID 隔离）。
    var fixturePlistURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        // 清一次性标志，让每个 case 都从干净状态起步
        LegacyDataMigration.resetForTests()
        // 清掉真实 AppGroupStore 里的迁移目标 key（防止上次测试残留）
        AppGroupStore.removeObject(forKey: "suber-subscriptions")
        AppGroupStore.removeObject(forKey: "suber-settings")
        AppGroupStore.removeObject(forKey: "suber-changes")
        // 每个 case 一个独立 plist 路径
        fixturePlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-migration-test-\(UUID().uuidString).plist")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fixturePlistURL)
        AppGroupStore.removeObject(forKey: "suber-subscriptions")
        AppGroupStore.removeObject(forKey: "suber-settings")
        AppGroupStore.removeObject(forKey: "suber-changes")
        try await super.tearDown()
    }

    func testNoOpWhenLegacyPlistMissing() {
        // fixturePlistURL 还没写过文件 — 模拟 fresh install / 已清理过的机器
        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)
        XCTAssertNil(AppGroupStore.data(forKey: "suber-subscriptions"),
                     "No legacy plist → no migration → AppGroupStore 应该仍空")
    }

    func testMigratesKeysFromFixturePlist() throws {
        // 写一份 fixture plist，模拟 v1.6.0/v1.6.1 留下的数据
        let payload: [String: Any] = [
            "suber-subscriptions": Data("[fake-subs-json]".utf8),
            "suber-settings": Data("[fake-settings-json]".utf8),
            "suber-changes": Data("[fake-changes-json]".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fixturePlistURL)

        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)

        XCTAssertEqual(AppGroupStore.data(forKey: "suber-subscriptions"),
                       Data("[fake-subs-json]".utf8))
        XCTAssertEqual(AppGroupStore.data(forKey: "suber-settings"),
                       Data("[fake-settings-json]".utf8))
        XCTAssertEqual(AppGroupStore.data(forKey: "suber-changes"),
                       Data("[fake-changes-json]".utf8))
    }

    func testDoesNotOverwriteExistingAppGroupStoreData() throws {
        // 模拟 iCloud sync 已经把更新版本拉到 AppGroupStore
        AppGroupStore.set(Data("NEW-from-iCloud".utf8), forKey: "suber-subscriptions")

        // 老 plist 里有更老的数据
        let payload: [String: Any] = [
            "suber-subscriptions": Data("OLD-from-plist".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fixturePlistURL)

        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)

        // 新数据应该保留，不被老 plist 覆盖
        XCTAssertEqual(AppGroupStore.data(forKey: "suber-subscriptions"),
                       Data("NEW-from-iCloud".utf8),
                       "AppGroupStore 已有数据时迁移不应覆盖")
    }

    func testRunsOnlyOnce() throws {
        // 第一次跑（plist 不存在 → no-op，但标志位置 true）
        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)

        // 之后 plist 突然出现（不应该发生，但防御性测试）
        let payload: [String: Any] = [
            "suber-subscriptions": Data("LATE-arrival".utf8),
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0)
        try plistData.write(to: fixturePlistURL)

        // 第二次跑应该被一次性标志拦下，不再迁
        LegacyDataMigration.runIfNeeded(legacyURLOverride: fixturePlistURL)
        XCTAssertNil(AppGroupStore.data(forKey: "suber-subscriptions"),
                     "已跑过迁移的标志位应该让第二次 runIfNeeded no-op")
    }
}
