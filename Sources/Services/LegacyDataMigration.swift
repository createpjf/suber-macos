import Foundation

// ┌───────────── LegacyDataMigration — v1.6.x → v1.7.x+ 数据救援 ─────────────┐
// │                                                                            │
// │  v1.6.0 / v1.6.1 / v1.7.0 把 subscriptions + settings + 变更日志写到       │
// │  `UserDefaults(suiteName: "group.com.suber.app")`。v1.6.2 起迁到文件        │
// │  AppGroupStore（绕开 macOS 26.4 cfprefsd 故障，详见 AppGroupStore.swift   │
// │  的 header）。                                                             │
// │                                                                            │
// │  跳过 v1.6.2 直接升 v1.7.x 的用户看到空状态：v1.7.x 只读新路径            │
// │  (`Library/Preferences/Suber/{key}.json`)，从没看过老 plist。              │
// │  CHANGELOG 里写过这个 trade-off，但实际是 UX 回归。                        │
// │                                                                            │
// │  本类的工作：v1.8.0 第一次启动时**直接读老 plist 文件**                    │
// │  （`PropertyListSerialization`，不走 cfprefsd → 不触发 TCC），             │
// │  decode 后写到 AppGroupStore。一次性，UserDefaults.standard 标志位防重跑。 │
// │                                                                            │
// │  老 plist 不存在就 no-op（fresh install 或已被 macOS 清理）。             │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum LegacyDataMigration {
    private static let migrationDoneKey = "suber.legacyMigration.v180.done"
    private static let groupID = "group.com.suber.app"

    /// 只迁这些 key — settings / subscriptions / changes 是 AppGroupStore 关心的。
    /// ExchangeRateService 缓存不迁（refresh 一下就有，不值得多写代码）。
    private static let migrationKeys = [
        "suber-subscriptions",
        "suber-settings",
        "suber-changes",
    ]

    /// 在 SubscriptionStore 第一次读 AppGroupStore 之前调一次。Idempotent —
    /// UserDefaults.standard 上的标志位防止重复跑。
    ///
    /// `legacyURLOverride` 用于测试注入临时 plist 路径；生产路径走真实
    /// group container 下的 `<groupID>.plist` 文件。
    static func runIfNeeded(legacyURLOverride: URL? = nil) {
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: migrationDoneKey) else { return }
        defer { standard.set(true, forKey: migrationDoneKey) }

        guard let url = legacyURLOverride ?? defaultLegacyPlistURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            // 没 plist — fresh install 或已迁移用户。No-op。
            return
        }

        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else {
            NSLog("Suber: legacy plist 存在但解码失败 — 跳过迁移")
            return
        }

        var migrated: [String] = []
        for key in migrationKeys {
            // 已有新数据时不覆盖（保留更新版本，比如 iCloud KVS sync 已经
            // 把数据拉过来了 / v1.6.2 用户已经在 AppGroupStore 里有数据）。
            if AppGroupStore.data(forKey: key) != nil { continue }
            guard let value = plist[key] as? Data else { continue }
            AppGroupStore.set(value, forKey: key)
            migrated.append(key)
        }

        if !migrated.isEmpty {
            NSLog("Suber: 从 legacy plist 恢复了 \(migrated.joined(separator: ", "))")
        }
    }

    private static func defaultLegacyPlistURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("\(groupID).plist")
    }

    /// 测试逃生通道：清除一次性标志，让下一次 runIfNeeded 重新跑。
    static func resetForTests() {
        UserDefaults.standard.removeObject(forKey: migrationDoneKey)
    }
}
