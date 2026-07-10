# Changelog

All notable changes to Suber. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); semver per release.

## [1.10.0] — 2026-07-10 — 第二轮独立审计：删除墓碑、IMAP 崩溃面、本地化补全

v1.9.2 自称"audit hardening"，但一次新的独立复审（6 个领域并行深读 + 每条 finding 对抗验证，完整报告见 `docs/AUDIT-v1.9.2.md`）又挖出 58 个问题，其中最讽刺的一个是审计本身教会我们的：**跑测试套件会删除开发机上的真实订阅数据**——测试的 setUp/tearDown 直接读写真实 App Group 容器，而发布流程恰恰要求每次发版前跑测试。没有任何"零缺陷"的审计，只有下一双眼睛还没看过的代码；这次的结论是把"对抗验证"做成常态，而不是信任第一遍通过。

6 条高危中另外 5 条是真实的数据完整性缺口：云同步删除从不跨设备传播、且已删订阅会在别的设备"复活"；Siri/快捷指令加的订阅会被 App 下一次保存静默覆盖；Changes 窗口接受涨价从不落盘；金额为 ∞ 时永久打死后续所有保存；取消验证在年付订阅续费月之前就被误判为"成功"。本版把这些全部收口，并顺带把本地化从 99 个 key 补到 417 个——绝大多数中文用户此前看到的其实是中英混排界面。

58 个发现全部修复（6 高危 / 24 警告 / 28 建议），**274/274 测试全绿**（233 baseline + 41 新增回归测试）。

### Added

- **删除墓碑（deletion tombstones）**——`CloudSyncMerger` 新增独立 iCloud KVS key（`suber-deleted-ids`），删除操作记录墓碑并双向传播；合并逻辑在既有三规则前先按墓碑过滤本地和远端两侧。跨版本安全：`[Subscription]` 线格式完全未动，旧版本客户端永远不会因为新 key 而崩溃解码，只是暂时看不到这次的墓碑机制。
- Settings 页新增汇率新鲜度提示（刷新失败静默、兜底汇率可能已过期数月都无提示）与 iCloud 同步状态展示（合并/冲突事件此前只进 NSLog，界面永远是静态文案）。
- 两个 Widget 加 `widgetURL` 深链（`suber://changes`）——此前点按 LSUIElement 应用没有任何可见反应。
- IMAP 账号删除、"Mark as cancelled"（右键菜单 + 日详情两处）新增确认弹窗——此前无确认直接改数据，IMAP 删除还会同步销毁 Keychain 里的 App 密码且不可恢复。

### Fixed

- **测试沙箱化**：6 个测试文件的 setUp/tearDown 之前直接读写真实 App Group 容器、跑一次测试就刷穿真实 Backups/ 轮换环——现在全部指向一次性临时目录。副作用：全量测试套件从 73 秒降到 1.6 秒。
- **IMAP/Mail**：osascript 输出超过 64KB 内核管道缓冲区必然死锁（改并发排水）；IMAP literal 长度接受负数导致 Range 崩溃（钳制到 0…16M）；connect() 超时闭包无条件 cancel 连接，会杀掉刚握手成功、仍在自身预算内的健康会话。
- **金额/日期正确性**：`getTotalSpent` 用多单位 `dateComponents` 层级分解，超过一年的月付/周付/季付订阅累计消费严重算错，改为逐周期计数；`getDaysUntilBilling` 用 `ceil(秒差/86400)`，DST 回拨日多算一天，改日历日差；周付年化 Dashboard 用 4.33×12、AnnualCost 用 52，同一订阅两处显示不同年费，统一为 52/12；date-only 字符串按 UTC 午夜解析，UTC 以西时区导入日期全部提前一天。
- **解析器**：欧式小数逗号（"1.234,56"）被当千分位剥掉导致金额放大 100 倍；OCR 金额正则截断千分位（"¥1,299" 曾预填成 1.29）；多订阅解析价格行扩展越界导致 Range 崩溃；Vision 识别失败路径 continuation 双重 resume 导致崩溃；大 CSV 导入曾在主线程做 O(n²) 扫描冻结 UI。
- **视觉/无障碍**：状态色浅色模式对比度仅 1.67–2.54:1（低于 WCAG 底线），主流程图标按钮全部无 accessibility 标注——两者均已修复；圆角/间距/图表配色散落各视图硬编码，收进 `Theme`。

### Cleanup

- 本地化目录 `Localizable.xcstrings`：99 → 417 key，全部补齐 zh-Hans 翻译；修掉 14 处"死翻译通道"（组件的 String 类型参数导致目录里的翻译永远无法生效）；修掉 5 处字符串拼接 bug 和 7 处仅英文有效的复数后缀 hack。
- Widget target 此前资源列表不含本地化目录，Widget 内文案回退英文——已加入 `project.yml` 的 SuberWidget 资源并验证 417 个 key 全部编译进 `.appex`。

### Notes

- 已知遗留：Swift 6 严格并发迁移未启动（多个修复点标注了未来 `Sendable` 需求）；`clearAll`/整表替换路径不记删除墓碑（云端可合法地在 Clear All 后重新水合数据，这是预期行为而非 bug）。
- 本版**未**执行 `docs/RELEASE-PROCESS.md` Rule 3 要求的人工 QA 项（Mail/IMAP 真实收发、Sparkle 升级路径、iCloud 多设备收敛、强杀进程）——本轮审计范围从一开始就限定为静态代码审查 + 自动化构建/测试，这些场景请在使用中留意并反馈。
- 7-day feature freeze clock 重置为 2026-07-10。

---

## [1.9.2] — 2026-06-09 — Audit hardening：补全数据完整性缺口

v1.9.1 之后做了一次完整代码审计（SwiftUI 崩溃预防 + UX/功能两个 lens）。崩溃面干净：0 个 `try!`/`as!`，所有数组 force-unwrap 都被 `switch count` 证明性守卫，所有 ObservableObject 都正确标 `@MainActor`。本版修掉审计发现的 7 个数据完整性/正确性缺口，外加实现过程中发现的 1 个潜在数据丢失 bug，无新功能 —— 属 `docs/RELEASE-PROCESS.md` 的 P0 数据安全例外，7-day freeze clock 重置。

每个修复都走了 implementer → spec review → code-quality review 三道关，并做了一次跨任务的 final integration review。**233/233 测试全绿**（228 baseline + 5 新增）。

### Added

- **W4 — `SubscriptionStore.replaceAll(_:reason:)` 破坏性整表替换的唯一 chokepoint。** 带显式 `reason`（`userImport`/`userRestore`/`cloudMerge`/`clearAll`）：替换前把旧列表快照到 Backups/、记录 count 变化日志、`cloudMerge` 路径若缩小则触发 tripwire 警告。`clearAll` 与 3 个调用点（CloudSync merge / JSON import / Restore）全部改走它，`importSubscriptions` 移除。这是「自动路径静默清空订阅」这一类 bug（v1.8.4 / v1.9.0）的架构级收口。新增 `SubscriptionReplaceTests`（3 个测试，含 Backups/ 可恢复性断言）。

### Fixed

- **W1** `mergeRemoteChanges` 之前直接 `AppGroupStore.set` 绕过了 H5 prune —— 跨设备合并后 change log 可超过 200 条上限、撑爆 KVS 1 MB 预算。现在走 `StorageService.prune`，in-memory + 持久化都裁剪（仍不回推 KVS，避免 ping-pong）。+1 回归测试。
- **W5（bonus，实现 W4 时发现）** `DataBackupManager.snapshot` 的文件名是毫秒级时间戳。`replaceAll` 先快照旧列表、`save()` 微秒后快照新列表 —— 同一毫秒内两次写会撞同名，第二次 `.atomic` 写**静默覆盖**第一次，丢掉 pre-replace 恢复点。加数字后缀消歧（`-1`/`-2`），两份都保留。这是真实数据安全 bug，不只是测试假象。
- **W2/U1** JSON Import 之前是静默破坏性替换。现在弹 confirmation：「将用 X 条替换当前 Y 条订阅」，只有点 Replace 才执行。
- **W3** `AddSubscriptionIntent` 的 load→append→save 跨两次调用、中间夹着对象构造，存在 lost-update 窗口。集中到 `StorageService.appendSubscription` 单次调用收窄窗口。**诚实标注残余风险**：这不修跨进程/app↔Intent 的根本竞态 —— 运行中的 app 持有启动时载入的内存快照，每次 `save()` 整份回写，所以 Intent 写盘后被 app 后续 save 覆盖仍可能发生（任意时刻，不只竞态窗口）。彻底修需要 app reconcile-on-save，列为后续。+1 测试。
- **I1** 6 处 `Calendar.date(byAdding:to:)!` force-unwrap 改 `?? fallback`（widget 用 `?? Date().addingTimeInterval(7200)`）。
- **I2** `onReceive($settings)` 之前每次任意设置变更都调 start/stopSync，现在只在 `enableCloudSync` 真翻转时调。
- **I4** Restore 成功后没刷新备份源列表，二次 restore 显示旧列表 —— 现在 restore 后 `reload()`。

### Cleanup

- 移除死代码 `StorageService.clearAll()`（无调用者，且做的是**不带快照**的 `removeObject` 删除 —— 对未来调用者是个 loaded gun）。live clear 路径是 `SubscriptionStore.clearAll()` → `replaceAll([])`，始终先快照。
- 修正 `DataRestoreView` 里引用已删除 `importSubscriptions` 的过期注释。

### Notes

- v1.9.1 用户应用内一键升级（Settings → Updates → Check for updates → Install）。
- 已知后续（不在本补丁）：app↔Intent reconcile-on-save（W3 根因）；`StorageService.prune` 的 `now:` 参数与文档描述漂移（pre-existing，change-log prune 语义，与本版订阅路径无关）。
- 7-day feature freeze clock 重置为 2026-06-09。

---

## [1.9.1] — 2026-04-28 — 紧急 hotfix：iCloud KVS 不再无条件覆盖本地数据

**🚨 CRITICAL — 所有 v1.9.0 用户应**立即升级**。**

### 真凶定位（v1.9.0 ship 后 90 分钟实测中触发）

v1.9.0 ship 完用户走第一次 onboarding 流程，点了 "Enable iCloud Sync"，然后**9 条订阅又被覆盖成 1 条 stale Netflix Premium**。

跟 v1.8.4 LegacyDataMigration 是**同一个反模式从不同方向触发**：

| 路径 | v1.8.4 (LegacyDataMigration) | v1.9.0 (CloudSync onRemoteChange) |
|---|---|---|
| 来源 | `<container>/.../group.com.suber.app.plist` | `NSUbiquitousKeyValueStore` (iCloud KVS) |
| 写入 | `AppGroupStore.set(staleData)` | `subscriptionStore.importSubscriptions(staleSubs)` |
| 守卫 | "已有数据则不写"（在 macOS Tahoe 上失效） | **完全没有守卫** |
| 后果 | 9 → 1 | 9 → 1 |

`SuberApp.setupCloudSync.onRemoteChange` 一直直接调 `subscriptionStore.importSubscriptions(remote)`，**任何**远端推送都无条件 replace 本地。架构上 iCloud KVS 还残留之前测试用的 stale Netflix snapshot，用户开 sync 那一刻就被它覆盖。

v1.9.0 的 4 层数据保护把本地持久层修了，但**完全没碰这个 cloud-sync 路径**。这是计划的盲点。

### Fixed

- **新增 `Sources/Services/CloudSyncMerger.swift`** — 纯函数 + 3 条 merge 规则：
  1. local 空 + remote 非空 → REPLACE（合法的 fresh-device hydration）
  2. remote.count < local.count（且 local 非空）→ **REJECT** + NSLog；本地不动
  3. 否则 → 按 `Subscription.id` merge，按 `updatedAt` last-write-wins，保留 local-only 条目
- **`SuberApp.handleRemoteSubscriptions`** — 替换原 `importSubscriptions(subs)` 为走 merger。还在 merge 之前对当前 local 数据**强制 snapshot 一份**到 `DataBackupManager`，即使 merger 逻辑写错了也能 Restore UI 一键回滚。
- **`SuberApp.handleRemoteSettings`** — 同样不再无条件 `update { $0 = settings }`。`CloudSyncMerger.mergeSettings` 只在本地仍是 factory default 时接受 remote；用户改过任何字段 → local wins。防止跨设备同步时静默回退用户偏好（货币、语言、Autopilot toggle 等）。

### Tests

- 新增 `Tests/CloudSyncMergerTests.swift` — 9 个测试覆盖 3 条规则 + 边界 + settings merger。其中 `testRule2_rejectsStaleRemoteAgainstLargerLocal_TheBugThatPromptedV191` 是 v1.9.0 的精准 regression：local 9 + remote 1 → 必须 REJECT。任何人将来弱化这个守卫，这个测试就会变红。
- **228/228 全绿**（219 + 9 new）。

### Notes

- v1.9.0 用户**应用内一键升级**（Settings → Updates → Check for updates → Install）。升级后 iCloud sync 仍是关闭状态（v1.9.0 onboarding 时若你开过会被这次 hotfix 自动保留，因为我们改的是 sync 触发后的 merge 行为，不是 sync 开关本身）。
- **如果 v1.9.0 已经用 iCloud KVS 覆盖了你的真实数据：** Settings → Data → Restore from backup… 选择本地 rotating backups 里时间戳最早的（merge 前的版本）→ Restore。或者 Tab 上能看到 `Legacy data (v1.6.x)` → Restore。
- **架构反思**：v1.9.0 的 4-layer 计划只看本地持久层，没看远端 → 本地的 merge 路径，是非常典型的"计划盲点"。v1.9.1 把同样的"挽救/同步机制不能无条件覆盖"原则扩展到所有 inbound write 路径。下次再做 sync-related 设计，需要 explicit checklist：每个 inbound write path（远端 KVS / 老 plist / import 文件）都过 merger 决策点，不直接进 store。
- 7-day feature freeze clock **重置为 2026-04-28 起的 7 天**（按 `docs/RELEASE-PROCESS.md` rule "P0 数据安全 exception → reset clock"）。

---

## [1.9.0] — 2026-04-25 — Stability Release · 4 层数据保护 + 完整 QA pass

### PM 反思 — 为什么是 v1.9.0 而不是继续小版本

数据：v1.6.0 → v1.8.4，**12 个版本，4 天**。其中 4 个引入新 bug、8 个修补、1 次真实数据丢失（v1.8.0 的 LegacyDataMigration 把用户的 9 条订阅覆盖成月前的 1 条 snapshot）、**0 次完整 QA pass**。

核心反思是架构问题，不是技术问题。Suber 一直只有**一层数据保护**——AppGroupStore 的"已有数据则不覆盖"守卫。那一层失效就全军覆没。LegacyDataMigration 是这个架构的副产品；只要架构是这样，下一个 destructive bug 还会来。

v1.9.0 把"防止数据丢失"从"靠开发者写对代码"升级为"架构上多层冗余"。Ship 之后**强制 7 天 feature freeze**（详见 docs/RELEASE-PROCESS.md），让稳定性在用户那里证明出来。

### Added — 4 层数据保护

1. **本地轮转备份（Local rotating backups）** — 新增 `Sources/Services/DataBackupManager.swift`。每次 `AppGroupStore.set()` 写主文件后，自动写一份带毫秒级 ISO 8601 时间戳的快照到 `<container>/Library/Preferences/Suber/Backups/`，每 key 保留最近 10 份（按 mtime prune）。仅对 3 个 critical key 启用：`suber-subscriptions` / `suber-settings` / `suber-changes`。备份写失败仅 NSLog 不阻塞业务（"备份是 bonus，不是 dependency"）。

2. **iCloud 同步默认推荐 + 首次启动 onboarding sheet** — 新增 `Sources/Views/Onboarding/CloudSyncOnboardingSheet.swift`。第一次启动通过 OverlayPresenter 弹出 consent sheet "Sync your subscriptions across Macs"，三条 trust bullet（跨 Mac 同步 / 异常时可恢复 / 私密免费），Skip 与 Enable 都把 `iCloud.onboarded` flag 翻成 true 防重弹。Settings → iCloud Sync 提到顶部独立 section，加状态指示器。永远不强制开启（隐私 / 用户主权），但默认推荐。

3. **Settings → Data → Restore from backup… UI** — 新增 `Sources/Views/Settings/DataRestoreView.swift` + `Sources/Services/RestoreSourceLister.swift`。显式列出所有可用备份源（本地轮转 / iCloud KVS / legacy plist v1.6.x），用户**主动**选择恢复。Restore 操作前 confirmation dialog 名出"将用 X 条订阅替换当前 Y 条订阅"，确认后写回 AppGroupStore——这一次写入又触发新的 backup snapshot，所以 Restore 本身也是可逆的。**这就是替代危险自动 LegacyDataMigration 的安全路径。**

4. **DataPersistenceLifecycleTests** — 新增 `Tests/DataPersistenceLifecycleTests.swift`，10 个测试覆盖：round-trip 9 subs 不丢、每次 save 都触发 snapshot、prune 保留最近 10 份、restore 字节级一致、LegacyMigration 永远不动 AppGroupStore（regression 防线）、并发写不腐化、空数组写入仍然走 backup（clearAll 可逆）、cloud sync toggle 正确传播、fresh launch 从磁盘恢复、rotation 不破坏单个 backup 文件。`AppGroupStore` + `DataBackupManager` 各加 `testOverrideDirectory` 测试逃生通道，测试全跑在 temp 目录不污染用户真实数据。**219/219 全绿**（209 + 10 new）。

### Added — 仪式

- **`docs/QA-pass-v1.9.0.md`** — v1.6.0 → v1.9.0 全部 13 项功能 QA checklist，8 项 auto-verified（测试 + 代码审查），5 项 requires-manual（Mail/IMAP/Sparkle/进程杀/同步收敛 — 用户运行已构建 app 后逐项确认）。
- **`docs/RELEASE-PROCESS.md`** — 7 天 feature freeze 仪式 + ship 后 release notes 第一段必须包含反思的硬规则（v1.9.0 起生效）。

### Changed

- **Settings 布局** — iCloud Sync 升级到顶部 section（之前埋在 General 里被忽略）；Data section 新增 "Restore from backup…" 入口；其余排序未动。
- **`TrustBullet`** 从 AutopilotConsentSheet private 提升为 internal，给 CloudSyncOnboardingSheet 复用，避免重复实现。
- **`AppGroupStore.set(_:forKey:)`** 在原子写之后追加 `DataBackupManager.snapshot(key:data:)` 调用——3 个 critical key 自动 backup，其他 key（exchange-rate cache 等）不变。

### Not changed (feature freeze)

- IMAP / MailWatchdog / Sparkle 任何代码（freeze 周期内不动）。
- LegacyDataMigration 仍然 hard-disabled（`runIfNeeded` 是单行 return，原 body 保留为 `_disabledMigrationBody` dead code）。
- iCloud KVS prune 政策（H5 已限制 SubscriptionChange 200 条，本次不动）。

### Out of scope（明确不在 v1.9.0）

Settings 独立 Window scene、IMAP OAuth2、多账号 IMAP UI、iOS 配套 app、IMAP IDLE / push notifications。这些是 v2.0 候选，不在本周冲刺范围。

### Notes for upgraders

- **v1.8.4 → v1.9.0**：通过 Settings → Updates → Check for updates → Install 在应用内一键升级（v1.8.3 的 Sparkle pipeline 已实测过一次）。第一次启动会弹 iCloud Sync onboarding sheet——**强烈推荐 Enable**，这样未来任何本地异常都能从远端恢复。
- **数据安全文档** — 见 README "Data Safety" 章节（v1.9.0 新加），完整描述 4 层防护和恢复路径。
- 219/219 tests 全绿。

---

## [1.8.4] — 2026-04-28 — 紧急 hotfix：彻底拆掉 LegacyDataMigration（数据丢失真凶）

**🚨 CRITICAL — 所有 v1.8.0 / v1.8.1 / v1.8.2 / v1.8.3 用户应**立即升级**。**

### 真凶定位

本来 v1.8.3 是想用 Sparkle 升级实验证伪/证实"升级丢数据"是不是 Sparkle 引起的。结果**实验进行中数据自己丢了一次**，调试发现：

罪魁不是 Sparkle，是 v1.8.0 加进来的 `LegacyDataMigration.runIfNeeded()`。它本来是给跳过 v1.6.2 直升 v1.7.x 的用户救数据用的，但有几个致命设计缺陷：

1. **存在用户数据时仍然覆盖** — `AppGroupStore.data(forKey:) != nil` 这个守卫在 macOS Tahoe 上某种条件下失效（疑似 cfprefsd 路径不一致：我们写到 `<container>/Library/Preferences/Suber/*.json`，但 `containerURL()` 在新进程里返回的根路径不同）
2. **一次性 flag 会被重置** — `suber.legacyMigration.v180.done` 标志位在某种情况下从 true 变 false（可能因 UserDefaults 缓存 / 进程并发 / Sparkle swap），让 migration 反复跑
3. **结果**：用户的 9 条真实订阅被覆盖成 1 条月前的旧 Netflix Premium snapshot

### Fixed

- **`LegacyDataMigration.runIfNeeded()` HARD DISABLED** — 一行 return，无任何路径触发迁移逻辑。原 migration body 保留为 `_disabledMigrationBody` dead code 仅供参考。
- 单测重写：增加 2 个 critical regression 测试 — `testHardDisabledEvenWhenPlistExists` 和 `testNeverOverwritesExistingAppGroupStoreData`，防止任何人未经审查重新启用迁移。
- 受影响用户的数据通过 `plutil -extract suber-subscriptions raw` 从 legacy plist `<container>/Library/Preferences/group.com.suber.app.plist` 直接 base64-decode 写回 AppGroupStore — 已用此方法手动救回过用户的 9 条订阅。

### Notes

- v1.6.0/v1.6.1 直升 v1.8.4 的用户：legacy plist 里的数据**不会自动迁了**。如有需要数据救援，运行 `plutil -extract suber-subscriptions raw ~/Library/Group\ Containers/group.com.suber.app/Library/Preferences/group.com.suber.app.plist | base64 -d > ~/Library/Group\ Containers/group.com.suber.app/Library/Preferences/Suber/suber-subscriptions.json` 即可。后续 v1.9.0 会加 "Import from legacy plist" 显式 UI 入口替代危险的自动迁移。
- 这次事件的全部 PM 反思 + 路线图修订见 v1.9.0 release notes。
- 210/210 tests 全绿。

---

## [1.8.3] — 2026-04-28 — Sparkle pipeline 数据完整性验证

**纯净对照版本，零功能变更。** 唯一目的：验证 Sparkle 自动升级 (v1.8.2 → v1.8.3) 是否会损坏 AppGroupStore 用户数据。用户在 v1.8.2 上预先记录订阅列表 SHA256，升级后比对 — 任何不匹配都证明 Sparkle 路径有 data-loss bug。

### Changed

- 仅版本号：1.8.2 → 1.8.3 / 182 → 183

### Notes

- 这是 Suber 历史上第一次**为可观测性而非功能**发版。从 v1.9.0 起恢复正常发版（功能 + 修 bug），但只有当数据持久性问题彻底证伪 / 修好 / 测全。
- v1.6.x → v1.8.2 累计 6 个 release，期间未做完整 QA pass —— 那个 PM-grade 决策见 v1.9.0 release notes。

---

## [1.8.2] — 2026-04-26 — IMAP setup 一键跳转

v1.8.1 同日小升级。setupHint 里的 URL 现在是可点击按钮，不用再手动复制到浏览器。

### Added

- **IMAP provider 设置页一键跳转按钮** — 在 setupHint 文字下加一排带 SF Symbol 的小按钮，点一下浏览器直接打开对应设置页：
  - **Gmail**: "Enable IMAP"（→ mail.google.com 的 IMAP 启用页）+ "Create App Password"（→ myaccount.google.com/apppasswords 直链）
  - **iCloud**: "Apple ID Sign-In and Security"（→ appleid.apple.com）
  - **Outlook**: "Microsoft Account Security"（→ account.microsoft.com/security）
  - **Yahoo**: "Yahoo Account Security"（→ login.yahoo.com/account/security）
  - **Fastmail**: "Fastmail App Passwords"（→ app.fastmail.com 的 App passwords 设置页）
  - **Generic**: 无（用户自填 host，无 canonical 设置页）

### Notes

- v1.8.1 用户**应用内一键升级**到 v1.8.2（Settings → Updates → Check for updates → Install）— **首次完整实测 Sparkle pipeline**。
- 210/210 tests 全绿（纯 UI 加法 + 数据扩展，零逻辑变更）。

---

## [1.8.1] — 2026-04-26 — Gmail 跑通 + consent 布局 + IMAP 错误显示

v1.8.0 同日 hotfix。修核心问题：Gmail 用户哪怕输对了 App Password 也常常连不上，加上 v1.8.0 弹窗布局漏修一处 + IMAP 错误信息被截。

### Fixed

- **AutopilotConsentSheet 写死 540pt 宽超过 popover 480pt** → "Connect Apple Mail" 按钮被裁。改成 `.frame(maxWidth: .infinity)` 自适应。`IMAPAccountSheet` 同改（之前 480pt 等于 popover 宽度但零边距，OverlayPresenter 包裹层任何 padding 都会破）。
- **IMAP 测试错误信息被 `.lineLimit(2) + .truncationMode(.tail)` 截断** → 看不到 Gmail/Outlook 服务器返回的完整 URL。重做 testRow：失败信息独立成全宽多行 selectable 块 + Copy diagnostic 按钮一键把完整响应复制到剪贴板。

### Improved (Gmail 救援)

- **Email + App Password 输入自动 trim** — 复制粘贴时常带的首尾空格、换行、看不见的 unicode 现在不会再卡住 LOGIN。
- **Gmail "abcd efgh ijkl mnop" 4-4-4-4 格式自动 strip 空格** — Google 的 App Password 页面用空格分组方便阅读，我们粘贴后自动归一化为连续 16 字符（Gmail 服务器两种都接受，归一化更稳）。
- **Gmail setupHint 加为 4 步**，把最常被忽略的"启用 IMAP"放到第 1 步：
  1. mail.google.com → Settings → Forwarding and POP/IMAP → IMAP access: Enable
  2. 启用 2-Step Verification
  3. 在 myaccount.google.com/apppasswords 创建 App Password
  4. 粘贴 16 位 App Password
- **iCloud / Yahoo / Fastmail setupHint** 全部改成同款 3-4 步多行格式（与 Outlook 一致），明确"NOT your account password"。
- **Test connection 错误智能识别 5 种常见模式**，失败信息前自动追加一句中文友好解释：
  - "App Password required" → 提示用户输的是账号密码
  - "Basic auth disabled" → Outlook 个人账号必须用 App Password
  - "IMAP is disabled" → Gmail/Workspace IMAP 没启用
  - "Web login required" → Gmail 触发安全锁，需要先在浏览器登录一次
  - "LOGINDISABLED" → 服务器禁了 IMAP 登录

### Notes

- v1.8.0 用户**直接 Sparkle 应用内一键升级**（Settings → Updates → Check for updates → Install）— 首次实测 Sparkle 升级 pipeline 是否端到端工作。
- 210/210 tests 全绿（无逻辑变更，UI/copy 调整 + 防御性 trim/normalize）。

---

## [1.8.0] — 2026-04-26 — Layout fix · Data rescue · IMAP detail · Sparkle in-app updates

合集 release。修复 v1.7.1 三个紧急 bug + 加入 Sparkle 应用内自动更新。

### Added

- **In-app auto-update via Sparkle 2.** Settings → Updates 加 "Check for updates" 按钮 + "Automatically check" toggle + last-checked 时间戳。一键下载 + 验证 EdDSA 签名 + 原子替换 binary + 重启。绕开了 macOS Sequoia/Tahoe 的 App Management TCC 弹窗（Sparkle 用签名 XPC helper "Autoupdate.app"，权限 baked in）。**v1.7.x 用户最后一次手动下载 v1.8.0 DMG，之后所有 v1.8.x → v1.8.x+1 都在应用内自动升级。**
- 改进的 Outlook setupHint：三步具体指南（启用 2FA → 创建 App Password → IMAP 启用），不再笼统说"Generate App Password"。Outlook 个人账号（@outlook.com / @hotmail.com / @live.com）2024-2025 起 Microsoft 逐步禁用 Basic Auth，新提示明确告诉用户必须走 App Password 路径。

### Fixed

- **弹窗布局** — IMAPAccountSheet / Watch consent / Cancel confirmation 现在正确铺满 popover。v1.7.1 的 `.popoverOverlay` modifier 只能在 popover 根节点起作用；深嵌触发的 modal 会被 section 边界限制成 inline 错位（用户截图证实"Add IMAP account" 表单挂在 Autopilot 标题下面而不是居中弹出）。新加 `OverlayPresenter` env-object 把弹窗渲染抽到 `MenuBarView` 根 ZStack，`.frame(.infinity)` 那时才真覆盖整个 480×520 popover。
- **升级丢数据** — 新加 `LegacyDataMigration`：第一次启动 v1.8.0+ 时直接读 legacy `~/Library/Group Containers/group.com.suber.app/group.com.suber.app.plist`（`PropertyListSerialization` 走文件系统，不走 cfprefsd → 不触发 macOS Tahoe 的 TCC 弹窗）恢复 v1.6.0/v1.6.1 用户写在老 UserDefaults app-group 里的 subscriptions + settings + change log。一次性，UserDefaults.standard 标志位防重跑。已有 AppGroupStore 数据（v1.6.2+ 用户 / iCloud sync 拉过来的）不被覆盖。
- **IMAP 测试连接错误信息** — `MailBridgeError.permissionDenied` 加 `detail:` 参数，`IMAPClient.login()` 把服务器原始响应（如 `[AUTHENTICATIONFAILED] basic auth disabled`）透传过去，IMAPAccountSheet 的 "Test connection" 失败提示从笼统的 "check email and app password" 升级为 "Authentication failed. Server said: ..." — Outlook 个人账号 Basic Auth 被 Microsoft 禁用的情况下用户能直接看到原因，自助诊断。
- **IMAPAccountSheet timeout 错误信息** — 加上"Check the host and port (or local proxy/VPN settings)"提示，因为本地 VPN/proxy（Clash/Stash 等）经常拦截 imap.* 域名导致超时。

### Notes for upgraders

- **v1.7.1 → v1.8.0**：手动下载 DMG（最后一次）。安装后，未来所有 v1.8.x → v1.8.x+1 都在应用内自动升级，不用再手动下 DMG。
- **v1.6.0 / v1.6.1 → v1.8.0**（跳过 v1.6.2 / v1.7.x 直升）：自动数据迁移，无感。LegacyDataMigration 会从老 UserDefaults plist 恢复订阅 + 设置。
- **v1.6.2 → v1.8.0**：数据已在 AppGroupStore，迁移 no-op，零变化。
- **v1.7.0 → v1.8.0**：v1.7.0 的 IMAP 配置（如有保存）和 v1.7.1 修了一半的 sheet UI 都在 v1.8.0 完整工作。

### Engineering

- 210/210 tests green (+4 LegacyDataMigrationTests)
- 新依赖：Sparkle 2.9.1 通过 SwiftPM
- `scripts/build-dmg.sh` 新增 [9/9] generate_appcast 步骤（用 `~/.local/sparkle/bin/generate_appcast` — brew cask 已废弃，直接从 GitHub 下二进制）
- `MailBridgeError` enum 加自定义 `==` 实现，`detail` 字段不参与比较，老 catch 写法（`catch MailBridgeError.permissionDenied(_)`）兼容
- v1.7.1 加的 `.popoverOverlay(item:)` overload 已删除（无引用），`.popoverOverlay(isPresented:)` 保留备用

---

## [1.7.1] — 2026-04-26 — Fix sheet dismissal inside menubar popover

Same-day hotfix for v1.7.0. Reported within the hour of release: clicking the **App Password** field in "Add IMAP account" made the entire sheet vanish. Same root cause also broke the "Watch Apple Mail" consent sheet and the "Open cancel page" confirmation sheet — anywhere v1.6/v1.7 used `.sheet(...)` from inside the menubar popover.

### Root cause
Suber is a menu-bar-only app (`LSUIElement=true`, `MenuBarExtra(.window)`). When a SwiftUI `.sheet(isPresented:)` is attached to a view inside the popover, the sheet's NSWindow is a child of the popover's NSWindow. The moment the popover loses key-window status — which happens trivially when SecureField hands focus to macOS's `SecureInputServer`, when AppKit reorders for an osascript spawn, etc. — the popover auto-closes and the sheet dies with it. This is the **same architectural problem** Suber fixed in v1.5.1 for the Import flow by promoting it to a separate `Window` scene; v1.6/v1.7 reintroduced the bug for new sheets without considering popover key-loss.

### Fixed
- New `Sources/Views/PopoverOverlay.swift` — reusable `.popoverOverlay(isPresented:)` and `.popoverOverlay(item:)` modifiers that render the modal as an in-popover overlay (same view hierarchy, popover stays key) instead of as a child sheet. Lifts the existing `MenuBarView.formOverlay` pattern (battle-tested since v1.5 for the Add Subscription form) into a reusable shape.
- **`IMAPAccountSheet`** (`AutopilotSettingsSection.swift`) — `.sheet` → `.popoverOverlay`. Clicking App Password no longer dismisses the modal. SecureInputServer's focus grab is now harmless because there's no separate sheet window to lose.
- **`AutopilotConsentSheet`** — same swap. "Watch Apple Mail" toggle now reliably presents the consent panel; Confirm/Cancel work as designed.
- **`CancelConfirmationSheet`** in both `ListView` and `DayDetailView` — `.sheet(item:)` → `.popoverOverlay(item:)`. "Open cancel page" confirmation no longer disappears mid-flow.

### Notes
- `.alert(...)` and `.confirmationDialog(...)` are NOT affected — those are backed by `NSAlert`, which lives at the `.modalPanel` window level, independent of the popover. So the "Restart Suber to switch language?" alert, "Mark X as cancelled?" alert, and "Import Error" alert continue to work as before.
- Workflows that need to coexist with system dialogs (file picker, NSSavePanel, multi-step Import) still use the separate `Window("import")` scene + `WindowActivationCoordinator` — that pattern is unchanged and remains the right answer for those cases. `PopoverOverlay` is the lighter pattern for popover-internal modals.
- 206/206 tests still green (no logic changed, only the sheet→overlay modifier swap).

### Notes for v1.7.0 upgraders
- v1.7.0 IMAP direct connection feature was effectively unusable due to the SecureField bug. v1.7.1 makes it work as documented.
- No data migration. Existing Settings, IMAP account (if any was saved before the bug), subscriptions, change log all carry forward.

---

## [1.7.0] — 2026-04-26 — **IMAP direct connection**

v1.6 Mail Watchdog only saw what Apple Mail.app saw. If you route Gmail through web/mobile and never set it up in Mail.app, those receipts were invisible to Suber. v1.7 adds an IMAP bridge that talks to imap.gmail.com (and Outlook, iCloud, Yahoo, Fastmail, Generic) directly, in parallel with AppleMailBridge — results merge and dedup by RFC 5322 Message-ID.

### Added

#### 📧 IMAP direct connection (Settings → Other email accounts)
- Provider presets: Gmail / Outlook / iCloud / Yahoo / Fastmail / Generic. Each preset auto-fills host + port (993 TLS) + scan mailbox + per-provider App Password setup hint copy.
- App Password authentication (no OAuth — avoids 6-8 week Google security review). All five major providers + most self-hosted IMAP servers support App Passwords.
- "Test connection" button before save: lightweight `LOGIN` + `LOGOUT` round-trip in 1-2s tells you whether host/port/credentials are valid before you commit anything to Settings.
- Hand-rolled ~500-line IMAP4rev1 client (`actor IMAPClient` over `NWConnection` + TLS). Implements just the subset Suber needs: `LOGIN` / `SELECT` / `UID SEARCH` / `UID FETCH` / `LOGOUT`. Chosen over MailCore2 to avoid Obj-C++ dependencies and notarization complexity.
- `CompositeMailBridge`: parallel scan via `withThrowingTaskGroup`; per-bridge errors logged but don't abort siblings. Apple Mail can be down while IMAP keeps working (and vice versa).
- App Password lives in **local Keychain** with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable by background Watchdog scans but **never synced via iCloud Keychain** (per-device only).
- Dynamic bridge composition: adding/removing an IMAP account in Settings rebuilds the bridge stack live without an app restart (`MailWatchdog.setBridge()` swap).

#### 🌍 In-app language toggle (Settings → Language)
- System default / English / 简体中文 — was previously locked to macOS system locale.
- "Restart" prompt → relaunch with new locale via shell helper that waits for our PID then `open`s the bundle.
- Existing per-app locale honored: macOS auto-selects from CFBundleLocalizations declared in Info.plist (zh-Hans + en).

### Changed
- `MailBridge` protocol gains `func ping(timeout:) async throws -> Int` — lightweight liveness probe (used by "Watch Apple Mail" toggle and "Test connection" button) separate from the heavyweight scan path.
- `AutopilotSettings.imapAccount: IMAPAccount?` field added with forward-compat decoder so v1.6.x payloads decode cleanly.
- `MailWatchdog.connectAppleMail()` switched from a heavy probe-scan (10s timeout) to the new lightweight `ping(timeout: 60)` — fixes the "TCC dialog killed osascript" v1.6 user-reported bug where the macOS permission prompt blocked osascript longer than the probe budget.

### Fixed (audit polish, not user-visible)
- **IMAP continuation safety** (3 sites in IMAPClient): `withCheckedThrowingContinuation` + `var resumed = false` flag check-and-set was non-atomic. Network flapping (Wi-Fi/LTE swap, TLS handshake on the timeout edge) could race two callbacks both calling `continuation.resume` → Swift runtime crash with `SWIFT TASK CONTINUATION MISUSE`. Replaced with `IMAPContinuationGuard` (NSLock-backed one-shot wrapper). Stress-tested with 100 concurrent dispatches.
- **`IMAPClient.sendCommand` wall-clock timeout**: a half-open or blackholed TCP connection would leave the wrapping Task suspended forever. Added `asyncAfter` timeout matching the read-loop budget.
- **`NWConnection` cleanup on timeout**: timeout branches now `conn.cancel()` so a stuck TLS handshake doesn't leave a zombie socket.
- **`stateUpdateHandler` cleared on success**: prevents the captured closure from outliving the `connect()` call.
- **`LanguageOverride.relaunch()`** now uses `NSApp.terminate(nil)` instead of `exit(0)` so AppKit drains pending Scene saves and CloudSync's in-flight `kvStore.synchronize()` finishes before exit. Was a rare edge case where a settings flip made just before language switch could be lost when iCloud re-synced from another device.
- 4 force unwraps converted to `guard let` / nil-coalesce. All were guarded-safe in current code; the rewrite makes the safety self-document and survives future refactors. (DateHelpers calendar grid, ListView sort comparator, RecurringChargeDetector first/last txn date.)

### Engineering
- **206 tests across 15 suites** (+22 new for IMAP + 4 for IMAPContinuationGuard).
- Plan reviewed via `/swiftui-code-audit` (8/10 → 10/10 post-fix). Audit found 0 🔴, 4 🟡, 3 🔵 — all addressed in this release.
- Build pipeline (`scripts/build-dmg.sh`) hardened in v1.6.1/v1.6.2 (archive + exportArchive, defensive runtime check) — same pipeline ships v1.7.

### Notes for upgraders
- v1.6.2 → v1.7.0: zero data migration. AppGroupStore (file-based shared container, introduced in v1.6.2) is unchanged — v1.7.0 reads/writes the same JSON files. Settings, subscriptions, change log all carry forward cleanly.
- v1.6.0 / v1.6.1 users who never upgraded to v1.6.2: Mac data may live in the old UserDefaults app-group store; iCloud sync (if enabled) repopulates on first launch. Without iCloud sync, expect a one-time empty state. (Same migration story as v1.6.2 — the fix path is unchanged.)

---

## [1.6.2] — 2026-04-25 — Fix the actual launch-time permission prompt on macOS Tahoe

v1.6.1 misdiagnosed the macOS 26.4 (Tahoe) "Suber.app would like to access data from other apps" prompt as the Apple Events temporary-exception entitlement. Removing that was correct cleanup but not the root cause — the prompt still fires on v1.6.1.

Real root cause, found by reading the live system log on a stuck v1.6.1 install:

```
[User Defaults] Couldn't read values in CFPrefsPlistSource
  (Domain: group.com.suber.app, User: kCFPreferencesAnyUser, ...):
  Using kCFPreferencesAnyUser with a container is only allowed for
  System Containers, detaching from cfprefsd
[TCC] AUTHREQ_PROMPTING: service=kTCCServiceSystemPolicyAppData,
  subject=com.suber.app
```

macOS 26.4 tightened cfprefsd: `UserDefaults(suiteName: "group.com.suber.app")` can no longer use `kCFPreferencesAnyUser` for non-system containers. cfprefsd detaches, UserDefaults falls back to a path the OS classifies as "cross-app data access," and `kTCCServiceSystemPolicyAppData` fires — that's the prompt. Combined with the menu-bar popover sitting on top of the system dialog, the UI looks frozen because the user can't reach the Allow / Don't Allow buttons.

### Fixed
- New `Sources/Services/AppGroupStore.swift` — file-based read/write to the app-group container via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`. Bypasses cfprefsd entirely, so the kCFPreferencesAnyUser regression no longer applies and `kTCCServiceSystemPolicyAppData` is never requested.
- All 5 main-app call sites of `UserDefaults(suiteName: "group.com.suber.app")` migrated:
  - `StorageService` (subscriptions, settings, change log) → `AppGroupStore`
  - `ExchangeRateService` (rates cache, last-updated timestamp) → `AppGroupStore`
  - `SubscriptionStore.mergeRemoteChanges` (iCloud sync write-back) → `AppGroupStore`
  - `MailWatchdog` (scan cursors, lastScanDate) → `UserDefaults.standard` (own-bundle prefs; widget doesn't read these)
  - `AutopilotFlags` (UI state flags) → `UserDefaults.standard` (widget doesn't read these)
- `SuberWidget/WidgetDataProvider` migrated to read via the same `AppGroupStore` (file added to `SuberWidget` target via `project.yml`). Widget continues to display upcoming subscriptions and monthly spend; the read path just changes from cfprefsd to filesystem.
- Test fixtures updated to clear both `AppGroupStore` and legacy `UserDefaults(suiteName:)` between tests.

### Notes
- **Settings, subscriptions, and change-log data on existing v1.6.0/v1.6.1 installs:** persisted to the UserDefaults app-group store. v1.6.2 reads from `AppGroupStore` (file path) and won't see the old data on first launch. iCloud sync (NSUbiquitousKeyValueStore) re-populates subscriptions and settings on first launch if the user has sync enabled. Users without iCloud sync will see an empty state and need to re-enter (one-time). Trade-off accepted to ship the fix immediately on macOS Tahoe.
- The `com.apple.security.application-groups` entitlement stays — it's still required for the widget to share container data with the main app. The OS-level prompt was never about the entitlement itself; it was about the access pattern UserDefaults(suiteName:) used.

### Engineering
- 184/184 tests green after migration.

---

## [1.6.1] — 2026-04-25 — Fix launch-time permission prompt on macOS Sequoia/Tahoe (incomplete fix)

Same-day patch for v1.6.0. Users on macOS 15+ saw an unexpected "Suber.app would like to access data from other apps" system prompt the first time they opened the app — even before they'd toggled Watch Apple Mail on. The popover-vs-system-dialog z-order made it look like the app was stuck.

**This release misdiagnosed the trigger.** The Apple Events entitlement removal was correct cleanup but not the root cause; v1.6.2 has the real fix. v1.6.1 users will still see the prompt on macOS 26.4.

### Fixed
- Removed the `com.apple.security.temporary-exception.apple-events` entitlement scoped to `com.apple.mail`. This entitlement is sandbox-only — it lets a sandboxed app bypass its sandbox to send Apple Events to a specific target. Suber is **not** sandboxed (Developer ID, no `com.apple.security.app-sandbox` entitlement), so it was dead weight that did nothing functionally. macOS Sequoia / Tahoe added a proactive "this app declares Apple Events control" launch-time prompt that fires for every app declaring this entitlement, regardless of whether the entitlement actually does anything for that app. Removing it eliminates the bonus prompt.
- The standard "Suber wants to control Mail" TCC permission flow is unchanged. It still fires the first time the user toggles Watch Apple Mail ON, gated by `NSAppleEventsUsageDescription` in Info.plist. No regression in Mail Watchdog functionality.

### Notes for v1.6.0 upgraders
- If you'd already clicked Allow on the v1.6.0 launch-time prompt, your TCC permissions carry forward. Watchdog continues to work without re-prompting.
- If you'd clicked Don't Allow, install v1.6.1 and the prompt simply won't return on launch. The standard Mail-control prompt will fire normally when you turn Watch Apple Mail on.

---

## [1.6.0] — 2026-04-25 — **Autopilot**

The first release where Suber works in the background. Three features ship together as **Autopilot — Watch · Sense · Act**, plus the app speaks 简体中文 alongside English from this version on.

### Added

#### 📬 Watch — Mail Watchdog
- Reads billing receipts (renewals, invoices, trial endings) from Apple Mail via osascript bridge, gated by macOS TCC Apple Events permission.
- Daily background scan via `NSBackgroundActivityScheduler` — power-aware, respects App Nap, ±2h tolerance.
- Per-account incremental scan cursors persisted in UserDefaults; 60s hard cap per scan with resume token on timeout.
- **Privacy guarantee (D8 policy):** raw email body text never reaches `StorageService`. Only extracted amounts, dates, and merchant names persist.
- First-run consent modal before the macOS TCC prompt — explains what's read, what's saved (amounts + dates only), how to revoke.
- Settings → Autopilot section: Watch toggle, Scan-now button, last-scan stamp with progress, permission-denied banner with deep-link to System Settings → Privacy → Automation.

#### 🔔 Sense — Change Sentinel
- Detects price changes (5% AND $1 thresholds, AND rule, post-FX-conversion), new subscriptions, duplicate charges, trial expirations.
- `SubscriptionChange` log with SHA256 dedup hash over USD-canonical amounts (so flipping display currency doesn't re-insert the same change).
- Menu-bar icon badge — red capsule with unread count, 14-day window. NSImage fallback path for template-mode rendering edge cases.
- Three banners share a 56pt rhythm and a single-slot priority renderer (`BannerCoordinator`):
  - **"Since you were away"** — number-first daily re-engagement banner with verb-led [Review] action.
  - **"Suber caught your first change"** — once-forever first-detection banner.
  - **"Netflix cancelled. You'll save $215/year."** — earned celebration with concrete annual savings (rounded down to whole dollars).
- Grouped notifications (1 per scan run) with `suber://changes` deep-link routing.
- Changes Window with decision-prompt rows (hero amount, delta %, annual impact, inline primary action) — type-specific for priceChange / newCharge / duplicate / trialExpiring / cancellationConfirmed / cancellationFailed.
- Two empty states — first-run vs returning-user.

#### ✂️ Act — One-Tap Cancel
- Built-in cancel-URL map for 40+ services across Streaming / Music / AI / Cloud / Productivity / News / Gaming / Fitness / Finance / VPN / Dev tools / Design / Communication categories.
- Apple-billed subscriptions (iCloud+, Apple TV+, Apple Music, Apple Arcade, Bear, Telegram Premium, …) deep-link to the App Store Subscriptions screen via `itms-apps://`.
- Resolution priority: per-sub override → KnownServices → DuckDuckGo search fallback (`https://duckduckgo.com/?q=how+to+cancel+...`).
- Confirmation sheet sets the right mental model: "Suber will open Netflix's cancellation page in your browser. You'll cancel there. Suber will check next month and confirm when the charges stop." Adapts when no data source is available ("Suber can't verify automatically — tap Mark as cancelled when you're done").
- Tertiary "Already cancelled?" link with two-step alert confirm for users who cancelled outside Suber.
- `.pendingCancellation` visual state across 4 view contexts — dashed orange border + size-appropriate countdown:
  - Calendar tile (~40pt): dashed border + tiny "Nd" badge
  - List row (~64pt): dashed border + "Pending cancel · Xd" inline label
  - SubCardView card (~100pt): dashed border + corner badge
  - DayDetail (~300pt): full inline banner with due-date + days-left
- Auto-transition logic: after the next billing day passes, scan incoming Mail/CSV transactions in the verification window. Zero matches → `.cancelled` + log `cancellationConfirmed`. Match found → roll back to `.active` + log `cancellationFailed`.
- **Data-source gate:** for users without Mail Watchdog or recent CSV, auto-transition does NOT fire (would be a false-positive). DayDetail surfaces a manual "Mark as cancelled" nudge instead.

#### 🌍 Bilingual launch
- English + Simplified Chinese (`zh-Hans`) via Xcode 15+ String Catalog (`Localizable.xcstrings`).
- 70+ user-facing strings translated, including the trust-critical consent modal + cancel confirmation copy.
- macOS auto-selects locale based on user's Preferred Languages order.
- Pseudo-locale (`en_XA`) testing script for layout-overflow QA: `./scripts/pseudo-locale-test.sh en_XA`.
- `LocalizationCatalogTests`: zero stale keys, every English key has a `zh-Hans` translation, no `.accessibilityLabel("raw string")` regressions, MailSubscriptionExtractor keyword constants fenced out of the catalog.

#### 📐 DESIGN.md
- New `DESIGN.md` at repo root — canonical reference for visual tokens, copy voice, type ramp, SF Symbol map, banner rhythm, interaction state matrix, accessibility specs, anti-AI-slop blacklist, and i18n authoring rules. Future features calibrate against this so the app speaks with one voice.

### Changed
- Settings window: new Autopilot section between Currency and Notifications.
- Calendar day cells: pending-cancel tiles get a dashed orange border + tiny "Nd" countdown when ≤7 days from billing.
- Subscription model: + `cancellationURL`, + `pendingCancellationSetAt` fields. New `.pendingCancellation` SubscriptionStatus case.
- iCloud KVS payload now syncs the SubscriptionChange log alongside subscriptions and settings.

### Notes for upgraders from 1.5.x
- v1.5.3 clients receiving v1.6 iCloud sync data will decode `.pendingCancellation` as `.active` (D7 forward-compat fallback in `SubscriptionStatus.init(from:)`). No crash, no data loss, but pending-cancel state isn't visible until the user updates.
- Watch Apple Mail is OFF by default. Existing v1.5 workflows (manual entry, OCR, CSV import) are untouched.
- Notifications are now grouped (1 per scan run) — if you previously got per-sub reminders separately, that path is unchanged. Autopilot's grouped notifications are additive.

### Engineering
- 184 tests across 14 suites (+67 new tests for v1.6).
- Plan reviewed via `/plan-ceo-review` (SELECTIVE EXPANSION), `/plan-eng-review` ×2 iterations, `/plan-design-review` (5/10 → 9/10), with single-model outside-voice subagent at each step.
- 9 atomic per-slice commits — `git bisect` lands on the specific Slice that introduced any future regression.

---

## [1.5.3] — 2026-04-22 — Fix import window invisible after paste

Quick follow-up to v1.5.2. v1.5.2 correctly moved import flows out of the menubar popover into a dedicated `Window` so system dialogs (TCC, file picker) could stack above them. But because Suber is a menubar-only app (`LSUIElement=true`, activation policy `.accessory`), `openWindow` silently created the window BEHIND whatever real app was frontmost. Users saw nothing.

### Fixed
- New `WindowActivationCoordinator` flips `NSApp.activationPolicy` from `.accessory` to `.regular` and calls `NSApp.activate()` right before opening the import window. When the window closes, policy reverts to `.accessory` and the Dock icon disappears.

---

## [1.5.2] — 2026-04-22 — Fix popover blocking system dialogs

Multi-subscription OCR review and bank-CSV import flows became unusable when system dialogs (TCC permission prompt, file picker) couldn't render above the menubar popover.

### Changed
- Import flows extracted from `MenuBarExtra` popover into a dedicated `Window("import")` scene. Popover layer (101) was higher than `modalPanel` (8), causing system dialogs to be occluded; a regular `Window` scene lets macOS sort z-order correctly.

---

## [1.5.1] — 2026-04-22 — Multi-subscription screenshot OCR

OCR on a single-sub screenshot already worked; this release adds multi-sub screenshot parsing.

### Added
- `MultiSubscriptionParser` — anchor-split heuristic that recognizes `renews / expires / 续费 / 到期` patterns and splits one screenshot into multiple subscription candidates.
- Review window for multi-candidate batches before committing.

---

## [1.5.0] — 2026-04-18 — Import from bank statement

Suber can now discover the subscriptions you forgot about, from a bank or pay-platform statement.

### Added
- Drop a CSV → recurring-charge detection runs locally; Suber proposes which lines to add.
- Supported formats: 支付宝 (Alipay) official CSV, 微信支付 (WeChat Pay) bill export, generic CSV (best-effort column mapping).
- `MerchantNormalizer` strips `ALIPAY*` / `PAYPAL*` prefixes, phone numbers, TLDs to collapse merchant variants.
- `RecurringChargeDetector` median-interval grouping with amount-CV gate.

---

## [1.4.1] — 2026-04-16 — Polish + bilingual README

### Added
- `README.zh.md` — Simplified Chinese counterpart to the main README, with EN/中文 toggle in both files' headers.

### Fixed
- Currency-correct trend chart (was summing in display currency without per-sub conversion).
- Cleaner keyboard shortcuts.
- Shared billing helper consolidated across views.

---

## [1.4.0] — 2026-04-14 — First Developer-ID notarized release

### Added
- 8 features across two tiers (Tier 1: Calendar polish, Dashboard reshape, multi-currency Settings; Tier 2: app intents, widgets, image OCR, JSON export/import, hotkey).
- Apple Developer ID + notarization pipeline established.

### Changed
- Distributable DMG — Gatekeeper accepts directly, no right-click workaround.

[1.6.0]: https://github.com/createpjf/suber-macos/releases/tag/v1.6.0
[1.5.3]: https://github.com/createpjf/suber-macos/releases/tag/v1.5.3
[1.5.2]: https://github.com/createpjf/suber-macos/releases/tag/v1.5.2
[1.5.1]: https://github.com/createpjf/suber-macos/releases/tag/v1.5.1
[1.5.0]: https://github.com/createpjf/suber-macos/releases/tag/v1.5.0
[1.4.1]: https://github.com/createpjf/suber-macos/releases/tag/v1.4.1
[1.4.0]: https://github.com/createpjf/suber-macos/releases/tag/v1.4.0
