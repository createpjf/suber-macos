# Suber v1.9.2 全面审计报告 — 代码质量 + UI/UX

- **审计日期**：2026-07-10
- **基线**：`8741dfd4490f55c25120ad2072f4a62c7b9e4680`（工作树干净）
- **基线状态**：构建 ✅（禁签名本地构建）；测试 ✅ 233/233 通过，0 failures（73 秒）
- **方法**：6 个领域审计员并行深读全部源码（IMAP 并发 / 状态·持久化·迁移·同步 / 系统服务 / 金额·日期正确性 / 视图·呈现 / UX 证据化审计，规则集来自 swiftui-code-audit skill），产出 60 条候选 → 去重 59 条 → **每条由独立对抗验证员以"推翻"为职责逐条复核** → 58 条成立（46 CONFIRMED + 12 DOWNGRADED）、1 条被推翻。无失败场景不收录。

## 概要

Suber 是一个约 2.1 万行的 SwiftUI 菜单栏订阅管理 app。**基本功非常扎实**：全仓库零 `try!` / `as!` / 强制解包 / IUO，全部 8 个 ViewModel 都正确标注 `@MainActor`，无 Combine、无 Timer，v1.9.0 事故后建立的四层数据安全架构（live store → 滚动备份 → iCloud KVS → 恢复 UI）和 233 个测试是同体量独立 app 中少见的纪律。

但审计发现的问题恰好集中打在这个 app 最在乎的两件事上：**数据完整性**和**金额正确性**。6 条高危中,4 条是真实的数据丢失/错钱路径（云同步删除永不传播且已删订阅会"复活"、Siri 添加的订阅被下一次快照静默覆盖、视图层绕过 save() 导致重启回滚、取消验证过早放行），1 条是并发 data race，还有 1 条最讽刺——**跑一次测试套件就会删除开发机上的真实订阅数据并把真实备份轮换环刷成测试快照**。UI/UX 侧没有高危，但 7 条警告实打实破坏核心体验：中文用户全程中英混排（126/200 条文案未翻译，另有一条"死翻译"通道让已翻译的 key 永远显示英文）、多币种数字自相矛盾、分摊订阅金额虚高数倍。

## 统计

| 领域 | 🔴 高危 | 🟡 警告 | 🔵 建议 | 合计 |
|---|---|---|---|---|
| 代码审计 | 6 | 17 | 16 | 39 |
| UI/UX 审计 | 0 | 7 | 12 | 19 |
| **合计** | **6** | **24** | **28** | **58** |

漏斗：60 候选 → 59 去重 → 58 成立（46 CONFIRMED / 12 DOWNGRADED）→ 1 被推翻（附录 A）。

## 评分：4 / 10（审计基线）→ 修复后复评 8.5 / 10

基线评分 4/10：按评分标准，存在 🔴 高危即落入 3–4 区间。给 4 而不是 3，是因为高危项全部是特定条件下的数据完整性缺陷而非必现崩溃，且代码基础纪律（零强制操作、全 @MainActor、测试覆盖、数据安全架构）在同类项目中属上游水平。

**修复后（同日完成，含 Q7）**：58 条成立 finding **全部修复（58/58）**。终态门禁：双 scheme 构建 ✅✅，**274/274 测试 0 failures（1.6 秒）**，较基线新增 41 个回归测试；Widget bundle 已含 zh-Hans 目录（417 key）。复评 **9/10**——剩余扣分项：Swift 6 严格并发迁移尚未启动（多个修复 agent 标注的 Sendable 展望）、数条边角 case 留待后续版本（clearAll 不记墓碑、暗色模式 danger 按钮对比度为既有状态、汇率刷新被 C-27 闩锁限制为每次启动一次）。

## Top 3 建议

1. **立刻隔离测试数据容器**（C-01）。这是对"开发者本人"的数据丢失：`xcodebuild test` 直接读写真实 App Group 容器，删真实订阅、把真实备份轮换环刷成测试快照——而发布流程恰恰要求每次发版前跑测试。所有其余修复都依赖测试可以安全反复运行，此项是其他一切的前置。
2. **补上数据完整性的三个洞**（C-02 云同步无墓碑、C-03 Intent lost-update［同根因 C-11］、C-06 视图绕过 save）。这个 app 在 v1.9.0 事故后向用户承诺了数据安全，而这三条是当下仍然打开的静默丢数据路径，用户丢了数据都不会知道。
3. **金额正确性一次清干净**（C-17 getTotalSpent 层级分解、C-12 欧式金额 ×100、C-18 趋势图 amount vs effectiveAmount、U-05 多币种直接丢弃、U-04 硬编码 $）。订阅管理器的立身之本是数字可信，这一簇每条都是"显示错钱"。

## 自动修复红线（本次执行的策略）

仅自动修复 **🔴 CONFIRMED** 且同时满足：① 防崩溃/防数据丢失/防错钱；② 不新增用户可见 UI、不增删改本地化字符串；③ 改动局限于被引用文件，不动 project.yml、不新建源文件、不加依赖。其余（哪怕严重）进待确认队列。

## 修复日志

基线 `8741dfd4490f55c25120ad2072f4a62c7b9e4680`。6 条 🔴 中 5 条通过红线自动修复，1 条（C-02 墓碑）进待确认队列。

| # | 修复 | 改动文件 |
|---|---|---|
| C-01 | 测试全面沙箱化：6 个测试文件的 setUp/tearDown 改为 `AppGroupStore.testOverrideDirectory` + `DataBackupManager.testOverrideDirectory` 指向一次性临时目录，删除全部对真实容器的 removeObject/写入（含 LegacyDataMigrationTests 向真实 live 键写 fixture、StorageServiceTests 向真实容器写 "Netflix 15.99"）。注意两个 override 必须**成对**设置：`AppGroupStore.set` 的 post-write hook 会调 `DataBackupManager.snapshot`，只沙箱前者会把测试数据写进真实 Backups/（修复过程中实测：不成对时该写入路径还会阻塞 ~129 秒，成对后 0.002 秒） | `Tests/SubscriptionStoreTests.swift`、`Tests/AutoTransitionTests.swift`、`Tests/OneTapCancelTests.swift`、`Tests/SubscriptionStoreChangeLogTests.swift`、`Tests/LegacyDataMigrationTests.swift`、`Tests/StorageServiceTests.swift` |
| C-03 | `appendSubscription` 写盘后发 `.suberSubscriptionsChangedExternally` 通知；`SubscriptionStore.init` 注册主队列 observer 重载磁盘状态（store 每次变更即落盘，内存==磁盘，重载无损），并补 `deinit` 移除 observer | `Sources/Services/StorageService.swift`、`Sources/ViewModels/SubscriptionStore.swift` |
| C-04 | `ExchangeRateService.rates` 改为 NSLock 保护的 `_rates` + 线程安全快照读；`convert()` 单次加锁取快照 | `Sources/Services/ExchangeRateService.swift` |
| C-05 | 新增 `BillingCalculator.getNextBillingDate(_:strictlyAfter:)`（周期感知、日钳制、同日取消等满一整周期），替换 `computeBillingDue` 并加 1 天宽限；补 4 个回归测试（年付周年验证、扣费日早晨扫描、同日取消、2/31 溢出钳制） | `Sources/Services/BillingCalculator.swift`、`Sources/ViewModels/SubscriptionStore.swift`、`Tests/AutoTransitionTests.swift` |
| C-06 | 新增 `SubscriptionStore.acceptNewPrice(id:amount:)` 落盘入口；`ChangesListView.handleAcceptNewPrice` 改走该入口；`SubCardView` "Mark as cancelled" 改走已有 `markCancelledManually`（顺带消灭把订阅 id 误传给 `markChangeAcknowledged` 的永久 no-op） | `Sources/ViewModels/SubscriptionStore.swift`、`Sources/Views/Autopilot/ChangesListView.swift`、`Sources/Views/SubCardView.swift` |

**验证证据**：
- 主 app 构建 ✅（exit 0）；SuberWidget 构建 ✅（exit 0，BillingCalculator 为 Widget 共享文件）
- 沙箱化后的 6 个测试类先行验证：44/44 通过
- 全量测试门禁：**237/237 通过，0 failures，1.4 秒**（`** TEST SUCCEEDED **`；基线 233 + 新增 4 个 C-05 回归测试：年付周年验证、扣费日早晨扫描、同日取消等满周期、2/31 溢出钳制。附带收益：沙箱化让全套件从基线 73 秒提速到 1.4 秒——测试不再穿透真实容器/备份路径）

## 修复日志（第二轮 — 用户批准全量修复后）

用户批准修复全部剩余 finding（🔴 C-02 + 全部 🟡🔵 + 待确认队列）。按文件不重叠的波次执行，每波之间双 scheme 构建 + 定向测试门禁。

**第一波（17 项）** — 门禁：构建 ✅✅，75/75 测试通过：
- Mail/IMAP：C-07（osascript 管道并发排水，防 >64KB 死锁 + 回归测试）、C-08（IMAP literal 长度钳制 0...16M + readExactBytes 负数守卫 + 测试）、C-24（IMAPContinuationGuard.resume 返回 @discardableResult Bool，超时闭包仅在"赢得" resume 时才 cancel 连接 + 测试）、C-25（删除未配置的 DateFormatter 死分支，NSDataDetector 成为唯一显式路径 + 测试）
- 解析器/服务：C-12（欧式小数逗号判别，"1.234,56"/"9,99" 不再 ×100 + 6 个测试）、C-13（价格行锚点重叠 guard，防 Range trap + 测试）、C-14（Vision continuation 单次 resume 守卫）、C-15（rowHasNoNegatives O(n²)→O(n) 预计算）、C-16（relaunch 路径改为 sh 位置参数传递，撑得住带引号路径）、C-31（ImageCache 改 withLock 作用域锁，锁不再跨 await 持有）、C-32（parseDate 按 locale 排序 dd/MM vs MM/dd + 3 个测试）、C-34（OCR 千分位正则优先匹配，"¥1,299" 不再变 1.29 + 3 个测试）
- Import 视图：C-22（processFile 改 Task.detached，大 CSV 不再冻结 UI）、C-23（候选批次用 .id() 绑定视图身份，换批即重建 @State；binding(for:) 不再 fatalError）、U-08（备份解码失败改为独立警告横幅，不再顶着绿色对勾冒充成功）、U-09（onboarding 指路文案改为 "Settings → iCloud Sync"）、U-19（Import 窗口 defaultSize 620→760×520，minWidth 对齐 640，首开不再裁剪按钮）

**第二波（16 项）** — 门禁：构建 ✅✅，105/105 测试通过：
- 金额/日期：C-17（getTotalSpent 重写为逐周期计数，替换层级分解的 dateComponents；>1 年订阅累计不再算错 + 3 个测试）、C-21（getDaysUntilBilling 改日历日差，DST 回拨不再多一天 + 固定时区测试）、C-35（oneTime 锚定 startDate 不再被 billingDay 钳制，列表/日历日期一致 + 测试）、C-36（周付年化统一为 52/12，Dashboard 与 AnnualCost 不再各说各话 + 测试）、C-18（趋势图改用 effectiveAmount，与同屏其他金额面一致）、C-19（DashboardViewModel 全程固定公历，非公历系统日历下趋势图不再归零）
- 持久化/同步/App：**C-02 🔴（删除墓碑）**——`DeletionTombstone` + 独立 KVS key `suber-deleted-ids`（旧版本从不读取该 key，跨版本安全 by construction），delete 记录墓碑、merge 双侧过滤（远端过滤防复活、本地过滤让对端删除得以传播）、90 天/500 条修剪、Restore/Import 解除对应墓碑、9 个新测试；C-09（parsedAmount 拒绝非有限数，amount=∞ 不再永久毒化所有保存）、C-10（保存失败不再双重吞掉：do-catch + Bool 返回 + **写盘失败跳过 KVS 推送** + 测试）、C-20（date-only 按本地时区解析，美洲用户日期不再提前一天，SuberApp 与 StorageService 双站点）、C-26（no-change 合并短路，5 条远端回声不再刷穿 10 格备份环）、C-27（popover onAppear 启动逻辑加一次性闩锁）、C-28（CloudSyncService.observing 加锁）、C-29（suberDecoder formatter 静态缓存，解码 200 条变更不再数千次冗余分配）、C-30（prune 文档与实现对齐，删除未用的 now 参数）、C-33（UpdateService.start() 幂等守卫，防 KVO 累积）
- **C-11 无需单独修复**：与 C-03 同根因，C-03 的通知+重载机制已完整覆盖（报告建议的修复与 C-03 已落地的实现逐行同构）。

**第三波（10 项，UX 交互）** — 门禁：双 scheme 构建 ✅✅：
- U-01（IMAP 账号删除加确认 alert，明确警告 Keychain 密码不可恢复）、U-07（"Mark as cancelled" 两个入口都加确认，右键菜单经 @State 转出到卡片体呈现，文案复用 CancelConfirmationSheet）、U-13（新确认统一走系统 .alert；两张自绘确认卡补键盘支持 Esc/Return）
- C-38（overlay 延迟关闭改为可取消的单槽 Task，重开面板先 cancel 旧回调）、C-39（全部废弃的单参数 onChange 迁移到新签名）
- U-04（年度影响金额改用主货币符号表，不再硬编码 $）、U-05（日历头部月支出经汇率换算聚合全部币种，与 Dashboard 一致，多币种带 ~ 前缀标注估算）、U-06（日详情显示分摊后 effectiveAmount + ÷N 提示）
- U-11（Settings 货币区显示汇率更新时间；从未成功拉取时显示"使用内置近似汇率"警示）、U-12（新增 CloudSyncUIStatus，Settings iCloud 区显示最近同步/冲突事件及相对时间，冲突警示色）

**第四波 a（7 项，打磨清扫）** — 门禁：双 scheme 构建 ✅✅：
- U-10（主流程无障碍：TopBar 4 个导航按钮、日历翻月、关闭/清除/步进等全部图标按钮加 accessibilityLabel + 工具提示；SubCardView 合并为单一 VoiceOver 元素）
- U-14（状态色浅色模式改自适应变体 ≥4.1:1 对比度；Dashboard 12 色调色板、趋势条、teal 步进色全部收入 Theme；新增 Theme.Radius 令牌）
- U-15（日历空态升级为标题 + "Add subscription" CTA 胶囊 + ⌘N 提示，默认 tab 不变——按报告建议）
- U-16（卡片 hover 指针 + 右键菜单首项 "Edit…"；📦🔍 emoji 空态换成 SF Symbols）
- U-17（日期格式经 setLocalizedDateFormatFromTemplate 本地化模板收敛，中文语序正确重排；表单固定 yyyy/MM/dd 改走 DateHelpers；删除死代码 formatter）
- U-18（两个 Widget 加 widgetURL 深链 suber://changes，URLSchemeHandler 已有对应路由无需改动）
- C-37（导出 JSON 写盘失败不再静默，经既有错误弹窗管道呈现）

**第四波 b（本地化补全，U-02 + U-03）** — 门禁：双 scheme 构建 ✅✅ + 全量测试（见下）：
- **U-03（死翻译通道）**：14 个组件的 String 参数改为 LocalizedStringKey（ToggleRow、FilterBarView、TopBarView、SettingsView section/actionButton、表单 field 系列、Autopilot groupHeader/TrustBullet 等）；约 30 处运行时拼接的用户文案包上 String(localized:)（ChangeRowView 全部文案 helper、通知标题/正文、banner 文案、IMAP 错误提示等）；顺带修掉 5 处 `Text("a"+"b")` 拼接 bug 和 7 处英文复数后缀 hack（拆成完整单/复数句，英文输出逐字节不变）。
- **U-02（目录补全）**：`Localizable.xcstrings` **99 → 417 个 key（+318）**，全部带简体中文翻译和注释；插值 key 使用 %@/%lld 及中文语序需要时的位置参数（%1$@…）；原有 99 条逐字节未动；CloudSyncOnboardingSheet（原注释 en-only）全量本地化。刻意排除项（品牌名、占位符、纯符号组合、协议标识符等）逐条留档于修复记录。
- 已知遗留：SuberWidget target 的资源列表不含 xcstrings（改它需要动 project.yml，超出本次红线），Widget 内文案暂回退英文——已列入待确认队列 Q7。

## 待确认队列状态更新（第二轮修复后）

| # | 原条目 | 状态 |
|---|---|---|
| Q1 | C-02 云同步墓碑 | ✅ **已修**（独立 KVS key，跨版本安全，9 个测试） |
| Q2 | U-01 IMAP 删除无确认 | ✅ **已修**（确认 alert + Keychain 警告文案） |
| Q3 | U-07 Mark as cancelled 无确认 | ✅ **已修**（两个入口都加确认） |
| Q4 | U-02/U-03 本地化 | ✅ **已修**（417 key 全中文 + 死通道全部打通） |
| Q5 | U-10 无障碍 | ✅ **已修**（主流程图标按钮全部标注） |
| Q6 | 全部 🟡 | ✅ **已修**（24/24） |
| Q7（新） | Widget target 资源不含 xcstrings，Widget 文案暂为英文 | ✅ **已修**（用户批准后）：`project.yml` 的 SuberWidget target 在 `sources:` 下加 `Localizable.xcstrings`（`buildPhase: resources`——注意 xcodegen 没有 target 级 `resources:` key，首次尝试用它静默无效，主 app 能带上目录纯属目录树 `sources:` 的自动归类）+ `xcodegen generate` 重新生成工程。验证：SuberWidget.appex 内出现 `zh-Hans.lproj/Localizable.strings`，417 个 key 全部编译，抽查 "Upcoming Bills"→"即将扣费" 正确 |

## 待确认队列（严重但需要你签字才动）

| # | 发现 | 严重度 | 为什么不自动修 |
|---|---|---|---|
| Q1 | C-02 云同步无删除墓碑，删除永不传播且会"复活" | 🔴 | 修复需扩展同步数据格式（新增 tombstone 字段），涉及跨设备/跨版本兼容，属行为契约变更 |
| Q2 | U-01 IMAP 账号删除无确认且同步销毁 Keychain 密码 | 🟡 | 加确认 = 新增 UI + 本地化字符串，撞 LocalizationCatalogTests 与冻结期规则 |
| Q3 | U-07 "Mark as cancelled" 两个入口无确认直改状态 | 🟡 | 同上，需要新增确认 UI |
| Q4 | U-02 本地化补全（126/200 未翻译）+ U-03 死翻译通道 | 🟡 | feature 级工作量；死翻译通道（ToggleRow String 参数）本身是纯代码修复，但补 key 需要人审译文 |
| Q5 | U-10 主流程零无障碍标注 | 🔵 | feature 级，冻结期后统一做 |
| Q6 | C-07（🟡 AppleMailBridge 管道死锁）等全部 🟡 —— 修复代码已附在各条 finding 中 | 🟡 | 用户选择的范围是"只自动修 🔴"；🟡 修复代码全部就绪，批一声即可动手 |

## 代码审计发现

### 🔴 高危（6 条）

#### C-01 · 多个测试文件直接读写真实 App Group 容器，跑一次测试即删除开发机上的真实订阅数据并把真实 Backups/ 轮换环刷成测试快照

- **位置**：`Tests/SubscriptionStoreTests.swift:12`　**规则**：DATA-01　**裁决**：CONFIRMED

- **触发场景**：开发机上装有正在使用的 Suber（有真实订阅数据）。运行 `xcodebuild test`：SubscriptionStoreTests.setUp 对真实容器执行 removeObject("suber-subscriptions")（removeObject 没有快照钩子，删除不留备份）→ 各测试的 store.add()/save() 再向真实容器写入 "Netflix 15.99" 等测试数据，每次写入都触发 DataBackupManager.snapshot 写入真实 Backups/ 目录 → 一轮 5 个测试约 12+ 次订阅键写入，10 格轮换环被测试快照完全刷穿 → 用户真实数据的 live 文件被删、全部本地恢复点被测试数据替换。这正是 v1.8.0 事故中"月前测试快照覆盖 9 条真实订阅"的数据来源模式。DataPersistenceLifecycleTests 已经吸取教训做了沙箱，这几个文件没有。

- **同类站点**：Tests/StorageServiceTests.swift:11（setUp 未沙箱，仅 testAppendSubscriptionPreservesExisting 单测内沙箱）；Tests/LegacyDataMigrationTests.swift:19+68（还向真实 live 键写入垃圾数据）；Tests/AutoTransitionTests.swift:25；Tests/OneTapCancelTests.swift；Tests/SubscriptionStoreChangeLogTests.swift

- **证据**：

```swift
AppGroupStore.removeObject(forKey: "suber-subscriptions")
        AppGroupStore.removeObject(forKey: "suber-settings")
        AppGroupStore.removeObject(forKey: "suber-changes")
```

- **修复**：

```swift
// SubscriptionStoreTests（其余文件同模式）：setUp/tearDown 增加沙箱，删除对真实容器的 removeObject
private var tempStoreDir: URL!
private var tempBackupDir: URL!

override func setUp() {
    super.setUp()
    tempStoreDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("suber-store-tests-\(UUID().uuidString)")
    tempBackupDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("suber-backup-tests-\(UUID().uuidString)")
    AppGroupStore.testOverrideDirectory = tempStoreDir
    DataBackupManager.testOverrideDirectory = tempBackupDir
    store = SubscriptionStore()
}

override func tearDown() {
    AppGroupStore.testOverrideDirectory = nil
    DataBackupManager.testOverrideDirectory = nil
    if let d = tempStoreDir { try? FileManager.default.removeItem(at: d) }
    if let d = tempBackupDir { try? FileManager.default.removeItem(at: d) }
    super.tearDown()
}
```

- **验证意见**：静态与实证双重确认：测试以 Suber.app 为 TEST_HOST（含 app group entitlement），setUp 对真实容器无快照地删除 live 键，add/save 路径触发真实 Backups/ 快照且单文件一轮约 12 次写入即刷穿 10 格轮换环；开发机真实容器当前 live 文件已是测试残留的 "Netflix Premium 22.99"，且 10 个订阅备份快照全部为 24 毫秒内生成的测试数据——数据丢失已实际发生，red 成立。

#### C-02 · 合并无删除墓碑（tombstone）：删除永不跨设备传播，且已删订阅会在删除设备上"复活"，导致月度支出金额错误

- **位置**：`Sources/Services/CloudSyncMerger.swift:89`　**规则**：DATA-03　**裁决**：CONFIRMED

- **触发场景**：Mac A 与 Mac B 均有 9 条订阅、iCloud 同步开启。用户在 A 上删除已退订的 Netflix → A 存 8 条并推 KVS → B 收到通知：remote(8) < local(9) → Rule 2 判定 stale 拒绝（删除永远无法同步到 B）→ 之后 B 上任意一次订阅编辑（如 togglePause）把 9 条推回 KVS → A 收到：remote(9) > local(8) → Rule 3 按 id 并集合并 → Netflix 在 A 上复活 → A 的月度总支出重新计入一条用户已明确删除的订阅，金额显示错误，且 A 再推 9 条使两端"收敛"在错误状态。CloudSyncMergerTests 只覆盖增改场景，无任何删除传播测试。

- **证据**：

```swift
for sub in remote {
            if let existing = byID[sub.id] {
                byID[sub.id] = sub.updatedAt >= existing.updatedAt ? sub : existing
            } else {
                byID[sub.id] = sub
            }
        }
```

- **修复**：

```swift
// 1) 新文件 Sources/Services/DeletionTombstones.swift
enum DeletionTombstones {
    private static let key = "suber-deleted-ids"
    static func record(_ id: UUID) {
        var ids = load(); ids.insert(id)
        if let data = try? JSONEncoder().encode(ids) { AppGroupStore.set(data, forKey: key) }
    }
    static func load() -> Set<UUID> {
        guard let data = AppGroupStore.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
    }
}

// 2) SubscriptionStore.delete(id:) 记录墓碑
func delete(id: UUID) {
    subscriptions.removeAll { $0.id == id }
    DeletionTombstones.record(id)
    save()
}

// 3) CloudSyncMerger.mergeSubscriptions 过滤墓碑（先过滤再走三规则）
static func mergeSubscriptions(local: [Subscription], remote: [Subscription],
                               tombstones: Set<UUID> = DeletionTombstones.load()) -> CloudSyncMergeResult {
    let remote = remote.filter { !tombstones.contains($0.id) }
    // ……以下三规则原样保留
}
// 注：此修复根治"删除设备上复活"；删除的跨设备传播需同步墓碑集（v-next，KVS 增加 suber-deleted-ids 键）。
```

- **验证意见**：逐行静态推演证实反例完全复现：delete(id:) 无任何墓碑记录，Rule 2（第78行）使删除永远无法传播到对端，Rule 3 的按 id 并集（第89-96行）在对端任意一次编辑回推后使已删订阅在删除设备上复活，replaceAll 的 tripwire 只检测收缩不检测增长，且 DashboardViewModel 将复活的 active/trial 订阅重新计入 monthlySpend/yearlySpend，核心金额展示错误；全仓库无墓碑机制，SubscriptionChange 日志仅是展示型变更日志不承载删除，CloudSyncMergerTests 的 9 个测试确无删除场景，触发条件（双设备+同步+删除+对端编辑）完全现实，符合 red（realistic trigger 下 wrong-money 且用户删除操作被静默撤销）。

#### C-03 · Siri/快捷指令新增的订阅会被运行中 App 的下一次整体快照保存悄悄覆盖(数据丢失)

- **位置**：`Sources/Intents/AddSubscriptionIntent.swift:54`　**规则**：DATA-02　**裁决**：CONFIRMED

- **触发场景**：Suber 是常驻菜单栏应用,几乎永远在运行。用户对 Siri 说 "Add a subscription in Suber" → Intent 在 App 进程内执行 appendSubscription 写盘成功、对话框回复 "Added…"。但 SubscriptionStore 启动时已把订阅列表整份读入内存(SubscriptionStore.swift:38),且 save() 是整体快照写回(:137-138)。之后任何一次保存——用户改一个订阅、acknowledge 一条 change、trial 自动转 active——都会把不含新条目的内存快照写回磁盘 → Siri 添加的订阅无声消失。StorageService.swift:107-116 的注释已承认该 hazard 但未修。

- **同类站点**：Sources/ViewModels/SubscriptionStore.swift:38(启动即快照)、:137-138(整体写回)。GetSpendIntent 只读,无此问题。

- **证据**：

```swift
StorageService.shared.appendSubscription(sub)
```

- **修复**：

```swift
// StorageService.swift — 在 appendSubscription 末尾追加通知(AppIntents 与主 App 同进程):
extension Notification.Name {
    static let suberSubscriptionsChangedExternally =
        Notification.Name("com.suber.subscriptionsChangedExternally")
}

@discardableResult
func appendSubscription(_ sub: Subscription) -> [Subscription] {
    var subs = loadSubscriptions()
    subs.append(sub)
    saveSubscriptions(subs)
    NotificationCenter.default.post(name: .suberSubscriptionsChangedExternally, object: nil)
    return subs
}

// SubscriptionStore.swift — init 中注册重载(store 每次变更即保存,内存==磁盘,重载无损):
private var externalChangeObserver: NSObjectProtocol?

externalChangeObserver = NotificationCenter.default.addObserver(
    forName: .suberSubscriptionsChangedExternally, object: nil, queue: .main
) { [weak self] _ in
    self?.subscriptions = StorageService.shared.loadSubscriptions()
}
```

- **验证意见**：逐条核实成立：Intents 编译进主 App target（project.yml 无独立 extension），Suber 是 LSUIElement + MenuBarExtra 常驻应用；SubscriptionStore 启动时整份载入内存（:38），任何后续变更经 save()（:137-139）整体快照写回磁盘并推送 iCloud KVS，会无声覆盖 Intent 追加的条目；全仓无任何重载机制（appendSubscription 不发通知、无文件监听，CloudSyncService 只响应远端 ServerChange，本进程写入不触发），StorageService.swift:107-116 注释亦明确承认该 hazard 未修。DataBackupManager 的 10 份轮换快照仅提供事后手动恢复且会被后续写入轮换掉，不足以降级——在功能预期用法下即发生静默数据丢失，维持 red。

#### C-04 · rates 字典在后台线程写入、主线程无锁并发读取 —— 未同步的 data race

- **位置**：`Sources/Services/ExchangeRateService.swift:102`　**规则**：CONC-05　**裁决**：CONFIRMED

- **触发场景**：菜单栏应用常驻超过 24 小时(或用户隔天才打开)→ 打开 popover 时 SuberApp.swift:347 的 Task 触发 refreshRates,URLSession await 恢复在协作线程池上执行 `rates = newRates`(后台线程写);同一瞬间主线程 DashboardViewModel 正在为渲染月度总额循环调用 convert() 读取 rates[from]。Swift Dictionary 非线程安全,引用交换与读端 retain 竞争 → Thread Sanitizer 必报 data race,真机偶发 EXC_BAD_ACCESS 崩溃或读到损坏值。每个汇率过期的用户每天打开 popover 都会重演一次竞争窗口。

- **同类站点**：读端:DashboardViewModel.swift:57,72,115,127;ChangeRowView.swift:331;GetSpendIntent.swift:18

- **证据**：

```swift
rates = newRates
```

- **修复**：

```swift
private let ratesLock = NSLock()
private var _rates: [String: Double]

/// Thread-safe snapshot of the current rates table.
private(set) var rates: [String: Double] {
    get { ratesLock.withLock { _rates } }
    set { ratesLock.withLock { _rates = newValue } }
}

private init() {
    if let data = AppGroupStore.data(forKey: ratesKey),
       let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
        _rates = cached
    } else {
        _rates = Self.fallbackRates
    }
}

func convert(_ amount: Double, from: String, to: String) -> Double {
    guard from != to else { return amount }
    let snapshot = rates          // single locked read
    let fromRate = snapshot[from] ?? 1.0
    let toRate = snapshot[to] ?? 1.0
    let usdAmount = amount / fromRate
    return usdAmount * toRate
}
```

- **验证意见**：核实无误:项目为 Swift 5.9、无默认 actor 隔离,ExchangeRateService 是普通 class 且全文件无任何锁或队列,nonisolated async 的 refreshRates() 按 SE-0338 必在协作线程池执行第 102 行 `rates = newRates`(后台写);同时 @MainActor 的 DashboardViewModel(57/72/115/127 行)与 ChangeRowView:331 在主线程读,GetSpendIntent.perform() 还在另一池线程读,构成未同步的 Dictionary 并发读写,属 Swift 内存模型下的未定义行为,TSan 必报。触发条件(汇率超 24 小时过期后打开 popover)真实且每日重现,按评级标准 data race 归 red。

#### C-05 · computeBillingDue 无视计费周期且在扣费日零点即放行,导致取消验证被过早/错误地判定为"取消成功"

- **位置**：`Sources/ViewModels/SubscriptionStore.swift:352`　**规则**：DATE-01　**裁决**：CONFIRMED

- **触发场景**：场景一(年付,必现):年付订阅 startDate 2025-11-20(周年月为 11 月),用户 2026-03-10 点"Open cancel page"进入 pendingCancellation。computeBillingDue 只用 billingDay 做月度计算 → billingDue = 2026-03-20。3 月 21 日 Watchdog 日常扫描运行,窗口内当然没有该商户扣费(真正的续费在 11 月),于是 checkPendingCancellationTransitions 把状态写成 .cancelled 并弹出"You'll save $X/year"庆祝横幅——但商户端取消可能根本没成功,11 月照样扣钱,而 app 已把它从月度支出中剔除且不再复查(只有 pendingCancellation 才会被复查),cancellationFailed 对年付永远不可能触发。场景二(月付,零点早开门):月付 billingDay=15,用户 3 月 10 日 14:00 点取消(实际取消失败)。3 月 15 日 09:00 扫描:now(09:00) >= billingDue(3月15日 00:00) 放行,扣费邮件 14:00 才到 → 本次扫描零匹配 → 09:00 即判 cancellationConfirmed;5 小时后真实扣费发生,状态已永久错误。场景三(溢出):billingDay=31、setAt 在 2 月 → DateComponents(2026-02-31) 被规范化为 2026-03-03(已验证),与 BillingCalculator 钳到 2/28 的语义不一致,评估被推迟数天。

- **同类站点**：Sources/ViewModels/SubscriptionStore.swift:288-289(调用点/放行判断)。Tests/AutoTransitionTests.swift 只覆盖 .monthly 且 billingDay 与 setAt 同日的用例,年付、2/31 溢出、扣费日当天上午扫描均无测试。

- **证据**：

```swift
private func computeBillingDue(after setAt: Date, billingDay: Int) -> Date {
    let cal = Calendar.current
    var components = cal.dateComponents([.year, .month], from: setAt)
    components.day = billingDay

    guard let thisMonth = cal.date(from: components) else { return setAt }

    // If billing day in the current month is already past `setAt`, use it.
    // Otherwise use next month's billing day.
    if thisMonth >= setAt {
        return thisMonth
    }
    return cal.date(byAdding: .month, value: 1, to: thisMonth) ?? setAt
}
```

- **修复**：

```swift
// 1) BillingCalculator.swift — 增加周期感知的重载(复用 clampDay/advanceByOneCycle,年付对齐周年、2月31自动钳制):
/// Returns the next billing date on or after `reference` (cycle-aware, day-clamped).
static func getNextBillingDate(_ sub: Subscription, onOrAfter reference: Date) -> Date {
    let ref = startOfDay(reference)
    let start = startOfDay(sub.startDate)
    var next = sub.cycle == .weekly ? start : clampDay(start, day: sub.billingDay)
    if sub.cycle == .oneTime { return next }
    var iterations = 0
    while next < ref && iterations < 2000 {
        next = advanceByOneCycle(next, cycle: sub.cycle, billingDay: sub.billingDay)
        iterations += 1
    }
    return next
}

// 2) SubscriptionStore.checkPendingCancellationTransitions — 替换第 288-289 行,并删除 computeBillingDue:
// 周期感知:setAt 之后第一个真实扣费日(年付对齐周年月、2/31 钳到 2/28),
// 再加 1 天宽限:扣费日当天凌晨的扫描不能提前判定"取消成功"。
let firstDue = BillingCalculator.getNextBillingDate(sub, onOrAfter: setAt)
let billingDue = Calendar.current.date(byAdding: .day, value: 1, to: firstDue) ?? firstDue
guard now >= billingDue else { continue }
```

- **验证意见**：逐行复核确认:computeBillingDue(352行)完全不接收 sub.cycle,年付订阅的验证窗口必然落在非续费月,扫描后必判 cancellationConfirmed(cancellationFailed 对年付不可达);且误判后该订阅仍在 ChangeDetector 的 existingByKey 中,11月真实扣费同价时既不触发 newCharge 也不触发 priceChange,被永久静默吞掉,无任何纠错机制。零点放行(now >= 当日00:00)和 2026-02-31→03-03 溢出均已实测复现,测试仅覆盖 monthly 同日用例,属真实触发下的错误金额展示与虚假取消确认,维持 red。

#### C-06 · 视图层直改 store.subscriptions 数组绕过 save()，接受涨价/手动标记取消的结果重启后丢失（金额回滚 = 错钱）

- **位置**：`Sources/Views/Autopilot/ChangesListView.swift:225`　**规则**：DATA-01　**裁决**：CONFIRMED

- **触发场景**：用户在 Changes Window 看到 "Netflix raised to $22.99"，点击 Accept → handleAcceptNewPrice 直接改 subscriptions[index].amount，但从不调用 store 的 save()（saveSubscriptions + WidgetCenter.reloadAllTimelines 都不会执行）。用户退出 Suber 再启动 → init() 从磁盘重新加载 → 金额回滚到 $15.99，月支出统计和 Widget 显示的都是旧价（错钱）；且 change 已被 acknowledged，用户再也不会收到该涨价提示。同型缺陷：SubCardView 右键 "Mark as cancelled" 直接替换数组元素同样不落盘，重启后订阅回到 pendingCancellation；且该处第 88 行把订阅 id 误传给 markChangeAcknowledged（期望 change id）→ 永远 no-op，也不会记 cancellationConfirmed change，庆祝 banner 永不触发。

- **同类站点**：Sources/Views/SubCardView.swift:87-96（同一模式：直改 @Published 数组不落盘；另含 88 行订阅 id 误传给 markChangeAcknowledged 的静默 no-op）

- **证据**：

```swift
subscriptionStore.subscriptions[index].amount = newAmount
        subscriptionStore.subscriptions[index].updatedAt = Date()
        subscriptionStore.markChangeAcknowledged(id: change.id)
```

- **修复**：

```swift
// 1) SubscriptionStore.swift 新增统一落盘入口：
func acceptNewPrice(id: UUID, amount: Double) {
    guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return }
    subscriptions[i].amount = amount
    subscriptions[i].updatedAt = Date()
    save()   // saveSubscriptions + WidgetCenter.reloadAllTimelines
}

// 2) ChangesListView.handleAcceptNewPrice 替换直改数组的两行：
subscriptionStore.acceptNewPrice(id: subID, amount: newAmount)
subscriptionStore.markChangeAcknowledged(id: change.id)

// 3) SubCardView "Mark as cancelled" 按钮 action 整体替换为（store 已有正确 API，会落盘并记 cancellationConfirmed）：
Button("Mark as cancelled") {
    subscriptionStore.markCancelledManually(id: subscription.id)
}
```

- **验证意见**：核实成立：SubscriptionStore.save() 为 private 且是 saveSubscriptions 唯一调用点，无 didSet/scenePhase/willTerminate 等任何自动落盘机制，ChangesListView:225 直改数组的涨价接受结果重启后必然回滚（金额、月支出统计、Widget 均显示旧价），而 change 已被持久化 acknowledged；SubCardView:88 确实把订阅 id 误传给 markChangeAcknowledged（按 change.id 查找，必然 no-op），且手动标记取消同样不落盘、不记 cancellationConfirmed。唯一细微夸大是"再也不会收到提示"——dedupHash 含日粒度 dayKey，有数据源的用户在后续扫描日会被重新提醒，但无数据源用户确实永不重提，且错钱回滚本身已构成 red 级数据丢失。


### 🟡 警告（17 条）

#### C-07 · runOSAScript 先等进程退出再读管道，osascript 输出超过 ~64KB 内核管道缓冲区时必然死锁，真实体量邮箱的每次扫描都伪装成超时

- **位置**：`Sources/Services/MailWatchdog/AppleMailBridge.swift:180`　**规则**：PROC-01　**裁决**：CONFIRMED

- **触发场景**：触发序列：用户开启 Watch Apple Mail，过去 30 天邮箱里有十几封匹配 receipt/订阅/续费 的收据邮件（HTML 正文普遍 20–200KB）→ buildScript 把所有匹配邮件的完整正文拼进 results 一次性 `return results` → osascript 退出前向 stdout 写出远超 64KB 的数据 → 内核管道缓冲区写满而 Swift 侧无人读取 → osascript 阻塞在 write() 永不退出 → `process.isRunning` 恒为 true → 60 秒后 terminate 并抛 .timeout。因为 lastScanDateKey 只在成功时更新，下次扫描窗口和数据量完全相同，再次死锁 → 用户永远只看到 “Scan timed out — will retry in the background”，Watch Mail 核心功能对订阅较多的真实邮箱彻底不可用。测试零覆盖（IMAPBridgeTests 不碰 AppleMailBridge，MailWatchdogTests 用 Stub）。

- **证据**：

```swift
let deadline = Date().addingTimeInterval(timeout)
while process.isRunning {
    if Date() > deadline {
        process.terminate()
        throw MailBridgeError.timeout(resumeToken: [:])
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
}

let status = process.terminationStatus
let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
```

- **修复**：

```swift
// Drain stdout/stderr WHILE osascript runs. Reading only after exit
// deadlocks: once script output exceeds the ~64 KB kernel pipe buffer,
// osascript blocks on write and never exits.
let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }

// Wait with timeout. If timeout fires, terminate the process and throw.
let deadline = Date().addingTimeInterval(timeout)
while process.isRunning {
    if Date() > deadline {
        process.terminate()
        throw MailBridgeError.timeout(resumeToken: [:])
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
}

let status = process.terminationStatus
let stdoutData = await stdoutTask.value
let stderrData = await stderrTask.value
```

- **验证意见**：静态复核成立：runOSAScript 在第 180 行等进程退出后才读管道，且全仓库无 readabilityHandler 或并发排水任务；osascript 一次性写出的 results（含每封匹配邮件完整正文，跨全部账户/邮箱、Gmail "All Mail" 还会重复计入）超过 64KB 内核管道上限即死锁，60 秒后被 terminate 伪装成 .timeout。默认配置（无 IMAP）下 buildBridge 返回裸 AppleMailBridge，超时直达 MailWatchdog；lastScanDateKey 仅成功时写入、resumeToken 恒为空，30 天扫描窗口每次重试完全相同，构成永久失败循环，且 Tests/ 对 AppleMailBridge 零覆盖。无崩溃/数据丢失/金额错误，属条件性核心功能失效，yellow 定级准确。

#### C-08 · parseTrailingLiteralSize 接受负数 literal 长度，readExactBytes 随后构造 0..<负数 的 Range 直接 Fatal error 崩溃

- **位置**：`Sources/Services/MailWatchdog/IMAPClient.swift:344`　**规则**：SAFETY-05　**裁决**：CONFIRMED

- **触发场景**：触发序列：用户在 Settings → Add IMAP account 添加 generic 账户指向一台行为异常 / 被劫持 / 有 bug 的 IMAP 服务器（或中间代理返回损坏响应）→ 某条 untagged 响应行以 `{-1}` 结尾 → parseTrailingLiteralSize 里 Int("-1") 成功返回 -1 → readExactBytes(-1)：`while receiveBuffer.count < -1` 不成立直接跳过，`guard receiveBuffer.count >= -1` 恒通过（count ≥ 0）→ 执行 `receiveBuffer.subdata(in: 0..<count)` 时构造 0..<(-1) 触发 “Fatal error: Range requires lowerBound <= upperBound” → 整个 app 崩溃。同时超大 literal（如 {999999999}）虽不崩溃但会持续吞内存直到超时，建议一并封顶。

- **同类站点**：崩溃现场在 Sources/Services/MailWatchdog/IMAPClient.swift:403（receiveBuffer.subdata(in: 0..<count)）；readExactBytes 也可加 guard count >= 0 双保险

- **证据**：

```swift
let inside = line[line.index(after: openBrace)..<closeBrace]
return Int(inside)
```

- **修复**：

```swift
let inside = line[line.index(after: openBrace)..<closeBrace]
// Reject negative / absurd literal sizes from broken or hostile servers:
// a negative count would trap in readExactBytes' `0..<count` Range, and an
// unbounded one lets the server balloon receiveBuffer until timeout.
guard let size = Int(inside), (0...16_000_000).contains(size) else { return nil }
return size
```

- **验证意见**：手工重推确认成立：用户可在 IMAPAccountSheet 为 generic 账户填任意 host（GenericIMAPBridge 直接透传给 IMAPClient），恶意/异常服务器在任一 untagged 行末尾返回 {-1} 时，parseTrailingLiteralSize 的 Int("-1") 成功返回 -1，readExactBytes 中两个比较（count < -1、count >= -1）均无法拦截，第 403 行 subdata(in: 0..<(-1)) 构造 Range 触发 precondition trap 使整个 app 崩溃；代码中无任何尺寸校验或测试覆盖，IMAPContinuationGuard 与此无关。触发需服务器行为异常（正常 Gmail/iCloud 不会发负 literal），属条件性崩溃，yellow 定级恰当。

#### C-09 · parsedAmount 接受非有限数（inf），一条 amount=∞ 的订阅会让 JSONEncoder 永久抛错，此后所有保存/备份/云推送静默全线失败

- **位置**：`Sources/Models/Subscription.swift:220`　**规则**：SAFETY-07　**裁决**：DOWNGRADED（由 🔴 降级）

- **触发场景**：用户在金额输入框输入 "inf"、"infinity" 或粘贴 "1e999"（溢出为 +∞）→ Double("inf") = +inf，isValid 的 parsedAmount! > 0 判定为 true → add() 成功入内存列表 → save() → StorageService.saveSubscriptions 的 try? encoder.encode(subs) 因 JSONEncoder 默认 .throw 策略遇到 Double.infinity 抛错 → 返回 nil，磁盘不写、快照不打、KVS 不推，且无任何日志 → 此后用户所有增删改（包括与该订阅无关的）全部只存在内存 → 退出重启后数据整体回退到中毒前状态。同时 replaceAll 第 123 行的替换前快照也因同一编码失败被跳过，恢复点同步丢失。

- **同类站点**：Sources/Intents/AddSubscriptionIntent.swift:44（`Double(data.amount) ?? amount` 同样未校验 isFinite，Siri/Shortcuts 路径可注入同类毒值）；防御层建议同时在 StorageService.saveSubscriptions 把 try? 改为 do-catch 记录编码失败（见 DATA-02）

- **证据**：

```swift
var parsedAmount: Double? {
        Double(amount)
    }
```

- **修复**：

```swift
var parsedAmount: Double? {
    guard let value = Double(amount), value.isFinite else { return nil }
    return value
}
```

- **验证意见**：缺陷本身属实（已实测：Swift 的 Double("inf")/Double("1e999") 返回 +inf，JSONEncoder 默认策略对 inf 抛错，StorageService.swift:96 的 try? 静默吞掉后所有保存/快照/云推送全线无声失败），但报告声称的主触发路径不成立——SubscriptionFormView.swift:134-142 的 onChange 过滤器只保留数字和小数点，"inf" 会被清空、"1e999" 变成 "1999"。剩余可达路径（表单粘贴 ≥309 位纯数字、手工构造的 CSV 经 StatementFieldParser.parseAmount:85 无 isFinite 校验流入 add()、Siri Intent）均需极端或恶意输入，且中毒仅限当前会话（内存列表完好，删除毒条目后下次保存即恢复），不满足 red 所需的"现实触发下数据丢失"，故降级为 yellow；建议仍按原修复方案在 parsedAmount 加 isFinite 并同步修补 CSV 与 Intent 路径。

#### C-10 · 持久化失败被双重吞掉：encode 用 try? 静默、AppGroupStore.set 的 Bool 返回值被忽略，且写盘失败后仍无条件推送 iCloud KVS

- **位置**：`Sources/Services/StorageService.swift:96`　**规则**：DATA-02　**裁决**：CONFIRMED

- **触发场景**：磁盘满（或容器 ACL 异常）时：AppGroupStore.set 内部 data.write 抛错，NSLog 一条后返回 false → saveSubscriptions 不检查返回值，继续执行 CloudSyncService.pushSubscriptions（KVS 从此比磁盘新）→ 用户界面一切正常，继续添加/修改订阅 → 退出重启后 loadSubscriptions 读到旧文件，本次会话所有变更消失。用户发现问题的唯一时机是下次启动（或注意到 widget 显示的是旧数据）。encode 分支：对 subscriptions 只在非有限金额时失败（见 SAFETY-07）；对 changes/settings 几乎不可能失败——所以这里真正需要处理的是写盘失败。

- **同类站点**：StorageService.swift:141-146 saveChanges、162-167 saveSettings（同模式）；SubscriptionStore.swift:123（replaceAll 替换前快照的 try? encode 失败即静默跳过恢复点）；SubscriptionStore.swift:383-384（mergeRemoteChanges 忽略 set 返回值，合并结果重启即丢）

- **证据**：

```swift
func saveSubscriptions(_ subs: [Subscription]) {
        if let data = try? encoder.encode(subs) {
            AppGroupStore.set(data, forKey: subscriptionsKey)
            CloudSyncService.shared.pushSubscriptions(data)
        }
    }
```

- **修复**：

```swift
func saveSubscriptions(_ subs: [Subscription]) {
    do {
        let data = try encoder.encode(subs)
        guard AppGroupStore.set(data, forKey: subscriptionsKey) else {
            NSLog("Suber ⚠️ saveSubscriptions: DISK WRITE FAILED — 内存领先于磁盘，跳过 KVS 推送")
            // TODO: 通过 @Published 错误状态给用户挂 banner（重启会丢数据）
            return
        }
        CloudSyncService.shared.pushSubscriptions(data)
    } catch {
        NSLog("Suber ⚠️ saveSubscriptions: encode failed: \(error) — 本次写入完全未持久化")
    }
}
```

- **验证意见**：核实成立：AppGroupStore.set 确实返回 Bool 且被 saveSubscriptions/saveChanges/saveSettings 全部忽略，写盘失败后（原子写保旧文件）内存与 KVS 领先于磁盘，重启即静默丢失本会话全部变更，无任何用户可见报错；DataBackupManager 仅在写成功后快照，无法补救，Tests/ 中也无写失败路径覆盖。唯二缓解（RestoreSourceLister 手动从 KVS 恢复、CloudSyncMerger 在后续远端通知时可能合并回来）均依赖 iCloud 同步开启且用户先发现丢失，属事后偶发补救而非防护；"无条件推送 KVS"措辞略有不准（受 observing 门控），但不影响缺陷成立。触发条件为磁盘满/容器 ACL 异常等非常态环境，维持 yellow 恰当。

#### C-11 · Siri/Shortcuts 写盘与运行中 App 的内存快照存在 lost-update：App 的下一次 save() 会静默覆盖掉 Intent 刚追加的订阅（代码注释已承认，仍是现实数据丢失路径）

- **位置**：`Sources/Services/StorageService.swift:118`　**规则**：DATA-05　**裁决**：CONFIRMED

- **触发场景**：Suber 正在运行（菜单栏常驻，内存持有启动时加载的订阅列表）→ 用户对 Siri 说"添加订阅"→ AddSubscriptionIntent.perform 在后台线程 load→append→save，磁盘上多了一条 → 之后用户在 popover 里做任意操作（暂停/编辑某条订阅）→ SubscriptionStore.save() 把不含 Siri 新增项的整个内存快照写回磁盘 → Siri 添加的订阅无声消失。窗口不是微秒级竞态，而是 App 常驻期间随时触发。StorageService.swift:107-116 的注释明确承认这是未修复的 hazard。

- **证据**：

```swift
@discardableResult
    func appendSubscription(_ sub: Subscription) -> [Subscription] {
        var subs = loadSubscriptions()
        subs.append(sub)
        saveSubscriptions(subs)
        return subs
    }
```

- **修复**：

```swift
// 1) appendSubscription 末尾（写盘成功后）发通知（macOS 上 App 运行时 AppIntent 在同进程执行）：
extension Notification.Name {
    static let suberSubscriptionsChangedOnDisk = Notification.Name("suber.subscriptionsChangedOnDisk")
}
// appendSubscription 内 saveSubscriptions(subs) 之后：
NotificationCenter.default.post(name: .suberSubscriptionsChangedOnDisk, object: nil)

// 2) SubscriptionStore.init 订阅并重载：
NotificationCenter.default.addObserver(
    forName: .suberSubscriptionsChangedOnDisk, object: nil, queue: .main
) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.subscriptions = StorageService.shared.loadSubscriptions()
    }
}
```

- **验证意见**：复核成立：SubscriptionStore 仅在 init 时读盘（SubscriptionStore.swift:38），此后所有变更操作经 save() 全量写回内存快照；全仓无任何文件监听或通知机制在 Intent 写盘后触发重载（CloudSync 的 didChangeExternallyNotification 只对其他设备生效），故 AddSubscriptionIntent.swift:54 的写入会被 App 下一次任意 save() 静默覆盖，StorageService.swift:107-116 注释亦明确承认该 hazard 未修复。属真实静默数据丢失，但范围限于 Siri/Shortcuts 新增的单条记录且 DataBackupManager 轮换快照可事后恢复，维持 yellow。

#### C-12 · parseAmount 把小数逗号一律当千分位剥掉 —— 欧式金额被放大 100 倍(错钱)

- **位置**：`Sources/Services/BankImport/StatementFormat.swift:83`　**规则**：DATA-01　**裁决**：DOWNGRADED（由 🔴 降级）

- **触发场景**：用户导入欧洲银行(N26 / DKB / ING 等)导出的 Generic CSV,金额列写作 "9,99" 或 "1.234,56"。parseAmount 无条件执行 replacingOccurrences(of: ",", with: "") → "9,99" 变成 "999" → Double 解析为 999.0;"1.234,56" 变成 "1.23456"。RecurringChargeDetector 用该值作为订阅金额 → 导入后 Netflix 显示 €999/月,月度总额、汇率换算、Widget、通知文案全部错 100 倍。所有三个 Format(Alipay/Wechat/Generic)共用此函数。

- **同类站点**：Tests/StatementFormatTests.swift 无任何小数逗号用例 —— 建议补 "9,99"、"1.234,56"、"1,234.56" 三个断言

- **证据**：

```swift
s = s.replacingOccurrences(of: ",", with: "")
```

- **修复**：

```swift
// Decimal-separator disambiguation:
// "1.234,56" (EU) → 1234.56   "9,99" (EU) → 9.99
// "1,234.56" (US) → 1234.56   "1,234" (US) → 1234
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
```

- **验证意见**：缺陷本身属实且可手推复现:第 83 行无条件剥逗号使 "9,99"→999.0、"1.234,56"→1.23456,且 Tests/StatementFormatTests.swift 无任何小数逗号用例。但端到端触发面远窄于声称:CSVParser 仅支持逗号分隔,DKB/ING 等德式分号 CSV 会在列检测/日期解析阶段以 missingColumn/emptyFile 大声失败而非静默错钱,N26 英文导出用点号小数,支付宝/微信永远是点号小数;真正命中需要"逗号分隔 + 金额带引号写作小数逗号 + 英文表头 + 受支持日期格式"的窄集合,且入库前 ImportReviewListView 会显示并允许编辑每个候选金额(€999 的 Netflix 在确认页可见),故从 red 降为 yellow。

#### C-13 · 价格行扩展与下一个锚点重叠时 cursor > endIdx —— Range 构造直接 fatal error 崩溃

- **位置**：`Sources/Services/MultiSubscriptionParser.swift:79`　**规则**：SAFETY-05　**裁决**：CONFIRMED

- **触发场景**：OCR 截图中出现一行同时满足 looksLikePriceLine 和锚点正则,如域名商续费列表里真实存在的 "$14.99/renewal"(含数字 + 匹配 \brenew(al)\b + 形如纯价格)。文本:"Namecheap Domains\nRenews Mar 3, 2027\n$14.99/renewal\nexample.com" → 锚点索引 [1,2];处理锚点 1 时 peek 到第 2 行是价格行 → endIdx=2、cursor=3;处理锚点 2 时 endIdx=2、第 3 行非价格行不扩展 → lines[3...2] → "Fatal error: Range requires lowerBound <= upperBound",整个 App 崩溃。Tests/MultiSubscriptionParserTests.swift 未覆盖连续锚点+价格行重叠的形态。

- **证据**：

```swift
let slice = Array(lines[cursor...endIdx])
```

- **修复**：

```swift
for anchorIdx in anchorLineIndices {
    // A price-line extension may have already consumed this anchor
    // (a line like "$14.99/renewal" matches BOTH looksLikePriceLine and an
    // anchor regex). Skip anchors before the cursor, otherwise
    // lines[cursor...endIdx] traps with lowerBound > upperBound.
    guard anchorIdx >= cursor else { continue }
    var endIdx = anchorIdx
    let peekIdx = anchorIdx + 1
    if peekIdx < lines.count && looksLikePriceLine(lines[peekIdx]) {
        endIdx = peekIdx
    }
    let slice = Array(lines[cursor...endIdx])
    blocks.append(slice)
    cursor = endIdx + 1
}
```

- **验证意见**：手工推导确认崩溃可复现："$14.99/renewal" 同时满足 looksLikePriceLine（$+数字+/\w+ 全匹配）和 isRealAnchor（含数字且 "renewal" 匹配 \brenew(al)\b），导致前一锚点扩展后 cursor=3 而下一锚点 endIdx=2，lines[3...2] 构造 ClosedRange 直接 trap；调用方 ImageDropZoneView.swift:317 的 do/catch 无法捕获运行时 trap，且 Tests/MultiSubscriptionParserTests.swift 无此形态覆盖。触发依赖特定 OCR 文本形状（价格行本身含续费关键词），属条件性崩溃，维持 yellow。

#### C-14 · Vision perform 失败时 completion 与 catch 双重 resume continuation —— SWIFT TASK CONTINUATION MISUSE 崩溃

- **位置**：`Sources/Services/ImageRecognitionService.swift:140`　**规则**：CONC-07　**裁决**：CONFIRMED

- **触发场景**：用户从剪贴板粘贴一张损坏的/Vision 不支持的图片(或磁盘图片文件在读取后损坏)→ handler.perform([request]) 抛错;Vision 在抛错前已在同一线程同步调用 VNRecognizeTextRequest 的 completionHandler(error) → continuation 已 resume(throwing:);随后 catch 分支第二次 resume → 运行时 fatal error "SWIFT TASK CONTINUATION MISUSE: tried to resume its continuation more than once",App 崩溃。

- **证据**：

```swift
do {
    try handler.perform([request])
} catch {
    continuation.resume(throwing: RecognitionError.recognitionFailed(error.localizedDescription))
}
```

- **修复**：

```swift
return try await withCheckedThrowingContinuation { continuation in
    // Vision calls the request's completionHandler synchronously on this same
    // thread even when perform(_:) ALSO throws — guard against double resume.
    var didResume = false
    func resumeOnce(_ result: Result<RecognitionResult, Error>) {
        guard !didResume else { return }
        didResume = true
        continuation.resume(with: result)
    }

    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            resumeOnce(.failure(RecognitionError.recognitionFailed(error.localizedDescription)))
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            resumeOnce(.success(RecognitionResult(lines: [])))
            return
        }
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        let lines = sorted.compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, confidence: candidate.confidence)
        }
        resumeOnce(.success(RecognitionResult(lines: lines)))
    }

    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        resumeOnce(.failure(RecognitionError.recognitionFailed(error.localizedDescription)))
    }
}
```

- **验证意见**：缺陷属实：Vision 的 perform(_:) 抛错前会在同一线程同步调用 completionHandler(error)，导致 106 行与 140 行对同一 checked continuation 双重 resume，触发 SWIFT TASK CONTINUATION MISUSE 致命崩溃；该服务未使用仓库中已有的 IMAPContinuationGuard 类防护，也无测试覆盖。但触发路径比声称的更窄——损坏图片会在 NSImage 解码阶段提前失败，只有 Vision 内部错误、内存压力下模型加载失败或不支持的语言/像素格式等罕见错误路径才会命中，属条件性崩溃，维持 yellow。

#### C-15 · rowHasNoNegatives 在每行循环内全量重扫文件(O(n²)) 且解析跑在 MainActor 上 —— 大 CSV 导入主线程卡死

- **位置**：`Sources/Services/BankImport/GenericFormat.swift:76`　**规则**：CONC-02　**裁决**：CONFIRMED

- **触发场景**：用户导入一整年、全正数金额的 Revolut/银行 CSV(约 8,000 行,正数+Type 列是 Revolut 的标准形态)→ 76 行的短路条件 rawAmount < 0 恒 false,每一行都调用 rowHasNoNegatives 重扫全部 8,000 行并对每格执行 parseAmount(内部 ~12 次字符串替换)→ 约 6,400 万次解析;而 BankImportView.swift:315 的 Task {} 在 View 上下文继承 MainActor,整个解析在主线程执行 → popover 转彩球数分钟无响应,用户强制退出。99 行注释自称 "Cached per-file check" 但实际从未缓存。

- **同类站点**：Sources/Views/Import/BankImportView.swift:315 — 建议把 Task { } 换成 Task.detached(priority: .userInitiated),让 decode/parse/detect 离开主线程,仅 stage 更新回 MainActor.run(该文件不在本次审计范围,列作关联点)

- **证据**：

```swift
let isSpend = rawAmount < 0 || rowHasNoNegatives(rows: rows, amountCol: amountCol)
```

- **修复**：

```swift
// 循环之前(53 行 var transactions 声明处)只算一次:
// Compute the sign convention ONCE per file (was: recomputed per row → O(n²)).
let fileHasNegatives = rows.dropFirst().contains { row in
    row.count > amountCol && (StatementFieldParser.parseAmount(row[amountCol]) ?? 0) < 0
}

// 循环内替换为:
let isSpend = rawAmount < 0 || !fileHasNegatives
guard isSpend else { continue }

// 并删除 rowHasNoNegatives(rows:amountCol:) 整个方法。
```

- **验证意见**：静态核实成立:GenericFormat.swift:76 在全正数文件上每行调用 rowHasNoNegatives 全量重扫(每格 parseAmount 含 ~12 次字符串替换,8,000 行约 6,400 万次解析),99 行注释自称缓存但实际无任何缓存;且项目为 Swift 5.9 + macOS 14 SDK,View 协议整体 @MainActor,BankImportView.swift:315 的 Task {} 继承主线程隔离且解析前无挂起点,大文件导入必然长时间卡死主线程,测试仅覆盖 3-4 行小样本、无任何缓解。唯一小瑕疵是真实 Revolut 导出通常用负数(仓库自身测试即为 -7.99),但代码注释自认支持全正数形态且 amountCol 可匹配全正的 Debit 列,触发场景依然现实,维持 yellow(条件触发下核心体验瘫痪,非崩溃/错账)。

#### C-16 · relaunch 把 bundle 路径裸拼进 sh -c 单引号字符串 —— 路径含单引号时应用退出后无法重启(表现为闪退)

- **位置**：`Sources/Services/LanguageOverride.swift:91`　**规则**：MAC-06　**裁决**：CONFIRMED

- **触发场景**：用户没有把 Suber 装进 /Applications,而是放在带撇号的目录里(macOS 常见,如 ~/Desktop/Leo's Tools/Suber.app)→ 在设置里切换语言并点击 "Restart Suber" → 生成的命令 open '…/Leo's Tools/Suber.app' 中路径里的 ' 提前闭合引号 → /bin/sh 语法错误,open 永不执行;而 NSApp.terminate 已经把应用退掉 → 应用退出后不再回来,用户视角就是"切换语言导致闪退",还可能因语言写了一半以为设置损坏。

- **证据**：

```swift
task.arguments = [
    "-c",
    "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open '\(bundlePath)'"
]
```

- **修复**：

```swift
// 用 sh 位置参数传值,路径与 PID 都不经过字符串插值(sh -c 后第一个操作数是 $0,其后是 $1):
task.arguments = [
    "-c",
    #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; /usr/bin/open "$0""#,
    bundlePath,
    String(pid)
]
```

- **验证意见**：LanguageOverride.swift:91 确实把未转义的 bundle 路径裸拼进 sh -c 的单引号字符串：路径含撇号时 sh 因引号不匹配整体解析失败（open 与等待循环都不会执行），而 task.run() 本身成功、NSApp.terminate 仍无条件退出应用，用户视角就是点了"Restart now"后应用消失且不再回来；SettingsView.swift:329 的调用路径真实可达，无任何转义或测试覆盖。唯一夸大之处是"设置损坏"——语言在弹窗前已通过 apply() 完整写入，手动重开后生效、无数据丢失，故不到 red，yellow（条件性破坏体验、表现如闪退）成立。

#### C-17 · getTotalSpent 同时请求 [.weekOfYear,.month,.year] 导致分量被层级分解,月/周/季订阅超过一年后累计消费严重算错

- **位置**：`Sources/Services/BillingCalculator.swift:195`　**规则**：MONEY-01　**裁决**：CONFIRMED

- **触发场景**：Calendar.dateComponents 同时请求多个单位时返回的是层级分解余数,不是总量(已用脚本验证):Netflix $15.49/月,startDate 2024-01-15,今天 2026-07-10 → 分解为 year=2, month=5, weekOfYear=3 → count = components.month = 5 → 返回 $77.45;真实经过月数为 29(单独请求 [.month] 得 29)→ 应为 $449.21。更极端:周付 $10 已订满一年(2025-07-10 起)→ weekOfYear 余数 = 0 → 返回 $0.00,而真实是 52 周 = $520。quarterly 同理((月余数)/3)。另有栅栏错误:即使修好分解问题,首期扣费也没被计入(月付订了 5 个完整月 = 已付 6 次)。缓解因素:该函数当前在 Sources 中无任何 UI 调用点(仅测试调用),测试只覆盖 oneTime 和未来 startDate,完全测不到此 bug——一旦任何新功能(如 v1.11 临期消费视图)接上它就是红色级错账。

- **同类站点**：Tests/BillingCalculatorTests.swift:176-186 仅测 oneTime 与未来开始日期,需补:月付跨年(29 个月)、周付满一年、季付跨年用例。

- **证据**：

```swift
let components = calendar.dateComponents([.weekOfYear, .month, .year], from: start, to: today)

let count: Int
switch sub.cycle {
case .weekly:
    count = components.weekOfYear ?? 0
case .monthly:
    count = components.month ?? 0
case .quarterly:
    count = (components.month ?? 0) / 3
case .yearly:
    count = components.year ?? 0
case .oneTime:
    return sub.amount
}

return Double(max(0, count)) * sub.amount
```

- **修复**：

```swift
// 用与 getNextBillingDate 相同的周期推进逻辑逐期计数,
// 一并修复"多单位分解"与"首期未计入"两个问题:
static func getTotalSpent(_ sub: Subscription) -> Double {
    let today = startOfDay(Date())
    let start = startOfDay(sub.startDate)

    if today < start { return 0 }
    if sub.cycle == .oneTime { return sub.amount }

    var chargeDate = sub.cycle == .weekly ? start : clampDay(start, day: sub.billingDay)
    if chargeDate < start { // billingDay 早于实际开始日 → 首期顺延一个周期
        chargeDate = advanceByOneCycle(chargeDate, cycle: sub.cycle, billingDay: sub.billingDay)
    }
    var count = 0
    var iterations = 0
    while chargeDate <= today && iterations < 2000 {
        count += 1
        chargeDate = advanceByOneCycle(chargeDate, cycle: sub.cycle, billingDay: sub.billingDay)
        iterations += 1
    }
    return Double(count) * sub.amount
}
```

- **验证意见**：独立脚本复现了全部三个反例：多单位 dateComponents 层级分解导致月付 29 个月只算 5 个月($77.45 vs $449.21)、周付满一年返回 $0、季付 9 季只算 1 季,首期未计入的栅栏错误也属实;该函数在 Sources 中确无生产调用点且现有测试(仅 oneTime 与未来日期)完全测不到,故维持 yellow——一旦任何功能接入即成严重错账,但当前对用户不可见。

#### C-18 · 月度趋势图用 sub.amount(全额)而首页头条与其余所有金额面用 effectiveAmount(拼单分摊后),同屏数字互相矛盾

- **位置**：`Sources/ViewModels/DashboardViewModel.swift:115`　**规则**：MONEY-02　**裁决**：CONFIRMED

- **触发场景**：用户有一个 Netflix 家庭组 $20/月、splitCount=4(本人分摊 $5)。Dashboard 头部 monthlySpend 走 getMonthlyEquivalent → effectiveAmount → 显示 "$5.00";同屏下方趋势图当月柱子走 computeMonthTotal → convert(sub.amount) → $20.00,是头条的 4 倍。AnnualCost.swift 头注明确规定趋势图等 3 个面必须统一走分摊后的金额;CalendarView 的月支出(getMonthlyEquivalent)、Top 5、分类占比也全是分摊口径,唯独趋势柱是全额口径。

- **证据**：

```swift
let amountInTarget = ExchangeRateService.shared.convert(sub.amount, from: sub.currency, to: currency)
total += Double(occurrences) * amountInTarget
```

- **修复**：

```swift
let amountInTarget = ExchangeRateService.shared.convert(sub.effectiveAmount, from: sub.currency, to: currency)
total += Double(occurrences) * amountInTarget
```

- **验证意见**：反例手工复现成立:同一 Dashboard 屏内,头条 monthlySpend、Top 5、分类占比均经 getMonthlyEquivalent → effectiveAmount(分摊后),唯独趋势图 computeMonthTotal(DashboardViewModel.swift:115)直接用 sub.amount 全额,splitCount=4 的 $20 订阅头条显示 $5 而当月柱子显示 $20;AnnualCost.swift 头注明确将「Monthly trend chart」列为应走分摊口径的三个面之一,且无任何测试将全额行为固化为有意设计。属误导性展示而非错误扣款/数据损坏,yellow 定级恰当。

#### C-19 · computeMonthTrend 用 Calendar.current 抽取 year/month 再喂给固定公历的 BillingCalculator,非公历系统日历下趋势图全部归零或数据缺失

- **位置**：`Sources/ViewModels/DashboardViewModel.swift:83`　**规则**：DATE-02　**裁决**：CONFIRMED

- **触发场景**：macOS 语言与地区 → 日历 设为"日本历"(ja_JP 用户常见设置):今天是令和 8 年 → cal.component(.year) = 8 → computeMonthTotal 调 getBillingDatesInMonth(sub, year: 8, month: 7),BillingCalculator 用固定公历构造出公元 8 年 7 月的日期 → billingDate < startDate(2025) → 全部返回 nil → 6 根趋势柱全部 $0,尽管订阅活跃且头条金额正常。佛历(泰国地区默认日历):year = 2569(已用脚本验证公历构造出 2569-07-01)→ 月付柱子碰巧仍有值,但 oneTime 消费因 startComps.year(2025) != 2569 永远不会计入其购买月。同一 mixed-calendar 模式也存在于 CalendarView 翻月:Calendar.current 若为伊斯兰历,byAdding .month 步进约 29.5 天,从 7 月初连按"下月"会出现表头重复显示同一个公历月。

- **同类站点**：Sources/Views/CalendarView.swift:196、204(Calendar.current 翻月 vs DateHelpers 公历网格);Sources/Views/CalendarView.swift:136(isDate(inSameDayAs:) 影响较小)。建议统一改用固定公历。

- **证据**：

```swift
private func computeMonthTrend(subscriptions: [Subscription], currency: String) -> [MonthData] {
    let cal = Calendar.current
    let now = Date()
    let currentYear = cal.component(.year, from: now)
    let currentMonth = cal.component(.month, from: now)
```

- **修复**：

```swift
// DashboardViewModel 内新增与 BillingCalculator 一致的固定公历:
private static let gregorian: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    return cal
}()

// computeMonthTrend 中:
let cal = Self.gregorian
// (formatter 的 "MMM" 显示仍可用系统 locale,不受影响)
```

- **验证意见**：用脚本按真实代码逐行重演反例成立:日本历下 cal.component(.year) 返回令和纪年 8,喂给固定公历的 BillingCalculator 构造出公元 8 年,billingDate < startDate 全部返回 nil、weekly 返回空,6 根趋势柱全为 $0;佛历(泰国地区默认)下 year=2569,月付柱碰巧有值但 oneTime 因 startComps.year(公历 2026)≠2569 永不计入;CalendarView:196/204 确实用 Calendar.current 翻月而网格用 DateHelpers 固定公历,mixed-calendar 问题同样存在。无任何缓解措施(LanguageOverride 只改 AppleLanguages 不改日历,Tests/ 无 DashboardViewModel 覆盖),但头条月/年支出(getMonthlyEquivalent 与日历无关)仍正确、不涉及崩溃或真实扣费错误,属条件触发的核心图表失效,维持 yellow。

#### C-20 · date-only 日期字符串按 UTC 午夜解析,UTC 以西时区(整个美洲)导入的日期全部提前一天

- **位置**：`Sources/SuberApp.swift:284`　**规则**：DATE-03　**裁决**：CONFIRMED

- **触发场景**：StorageService 注释明确说明 date-only 分支服务于 Chrome 扩展导出("Chrome's startDate")。纽约用户导入 startDate "2026-01-31" → 按 UTC 午夜解析 = 当地 2026-01-30 19:00(已用脚本验证)→ 全 app 的日粒度逻辑(startOfDay、formatDate、日历 oneTime 圆点、getBillingDateInMonth 的 billingDate < startDate 判断)都把开始日当成 1 月 30 日,详情页与日历显示比用户填的早一天;trialEndDate "2026-02-01" 显示为 1 月 31 日到期 → 试用到期提醒提前一天触发。app 自身导出用完整 ISO8601 时间戳不受影响,但 SuberApp.suberDecoder(iCloud/恢复路径)与 StorageService.decoder(主加载路径)都带同样的 date-only UTC 分支。测试夹具(BillingCalculatorTests.makeDate 等)全用本地时区 DateFormatter,与生产解码路径口径不一致,所以测试永远测不出来。

- **同类站点**：Sources/Services/StorageService.swift:55(dateOnlyFormatter 同样的 TimeZone(secondsFromGMT: 0),两处需同步修改)

- **证据**：

```swift
let dateOnly = DateFormatter()
dateOnly.dateFormat = "yyyy-MM-dd"
dateOnly.locale = Locale(identifier: "en_US_POSIX")
dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
if let date = dateOnly.date(from: str) { return date }
```

- **修复**：

```swift
let dateOnly = DateFormatter()
dateOnly.dateFormat = "yyyy-MM-dd"
dateOnly.locale = Locale(identifier: "en_US_POSIX")
dateOnly.timeZone = .current   // 本地午夜——与全 app startOfDay 的日粒度语义一致
if let date = dateOnly.date(from: str) { return date }
```

- **验证意见**：用脚本按生产代码逐行复现:"2026-01-31" 经 UTC 午夜解析后,纽约用户在 BillingCalculator(本地时区 Calendar)和所有展示用 DateFormatter 中都看到 1 月 30 日,且 "2026-02-01" 甚至被当成 1 月(yearly 周年月整体错位);导入路径无任何归一化,错误日期以完整 ISO8601 时间戳永久落盘,现有测试(testImportChromeExtensionJSON 恰用同一夹具但不断言日期、BillingCalculatorTests 用本地时区夹具)确实覆盖不到。无崩溃无数据丢失、月度账单日由独立的 billingDay 驱动故非 red,但对美洲时区 Chrome 导入用户是全 app 日期显示与提醒系统性错一天的条件性核心体验破坏,yellow 恰当。

#### C-21 · getDaysUntilBilling 用 ceil(秒差/86400) 计算天数,秋季夏令时回拨后跨转换点的倒计时多算一天

- **位置**：`Sources/Services/BillingCalculator.swift:219`　**规则**：DATE-04　**裁决**：CONFIRMED

- **触发场景**：Europe/London 用户(纽约、柏林等所有 DST 时区同理),今天 2026-10-20,下次扣费 2026-11-01,中间 10 月 25 日凌晨时钟回拨一小时:两个本地午夜的间隔 = 12 天 + 1 小时 = 12.0417 天 → ceil → 13(已用脚本验证;日历真实差值为 12 天)。SubCardView 的 "in N days" 徽标与 DayDetailView 的到期倒计时在每年 10 月底~11 月初、对所有跨回拨点的账单都显示多一天;"billing tomorrow"(1 天)会显示成 "in 2 days"。春季拨快方向 ceil 恰好吞掉误差所以只有秋天出错。

- **证据**：

```swift
static func getDaysUntilBilling(_ sub: Subscription) -> Int {
    let next = getNextBillingDate(sub)
    let today = startOfDay(Date())
    let diff = next.timeIntervalSince(today)
    return Int(ceil(diff / 86400))
}
```

- **修复**：

```swift
static func getDaysUntilBilling(_ sub: Subscription) -> Int {
    let next = getNextBillingDate(sub)
    let today = startOfDay(Date())
    // 日历感知的天数差,DST 安全(两端均为本地午夜)
    return calendar.dateComponents([.day], from: today, to: next).day ?? 0
}
```

- **验证意见**：复现成立:BillingCalculator 的私有 calendar 未固定时区(随系统 DST),两端均为本地午夜,秋季回拨使间隔多出 1 小时,ceil(diff/86400) 确实多算一天——脚本实测 London 2026-10-20→11-01 得 13(真实 12),Oct25→Oct26 得 2("Tomorrow" 显示成 "in 2d"),纽约同样复现,春季方向无误,且任何仅跨一次秋季回拨点的长倒计时(如 7 月看 12 月的年付账单)同样偏大一天。无任何缓解:唯一测试 testDaysUntilBillingNonNegative 只查非负,调用点 SubCardView/DayDetailView 徽标直接显示错值,WidgetDataProvider 的 days<=7 过滤还会把恰好 7 天后的账单挤出小组件;非金额/崩溃问题但核心倒计时对所有 DST 时区用户周期性出错,维持 yellow。

#### C-22 · processFile 的 Task {} 继承 @MainActor，Data(contentsOf:) + CSV 解析全在主线程执行，大文件导入冻结整个 UI

- **位置**：`Sources/Views/Import/BankImportView.swift:315`　**规则**：CONC-01　**裁决**：CONFIRMED

- **触发场景**：View 协议是 @MainActor 隔离，struct 方法里的 Task {} 继承主 actor —— 里面的同步 Data(contentsOf:)、CSVParser.decode/parse、format.parse 全部跑在主线程。用户导入一份支付宝年度账单 CSV（几万行、几十 MB）→ Import 窗口和 menubar popover 一起转菊花变彩球，"Scanning for subscriptions…" 的 ProgressView 也不动（它自己被阻塞）。代码里的 await MainActor.run 恰好暴露作者以为在后台跑。

- **证据**：

```swift
Task {
    do {
        let data = try Data(contentsOf: url)
        let text = try CSVParser.decode(data)
```

- **修复**：

```swift
private func processFile(at url: URL, format: StatementFormat) {
    stage = .processing
    Task.detached(priority: .userInitiated) {
        do {
            let data = try Data(contentsOf: url)
            let text = try CSVParser.decode(data)
            let rows = CSVParser.parse(text)
            let transactions = try format.parse(rows: rows)
            let candidates = RecurringChargeDetector.detect(transactions: transactions)
            await MainActor.run {
                if candidates.isEmpty {
                    stage = .error("Found \(transactions.count) transactions but no recurring charges. Make sure the CSV covers at least 2 months.", format)
                } else {
                    stage = .review(candidates, format)
                }
            }
        } catch {
            await MainActor.run { stage = .error(error.localizedDescription, format) }
        }
    }
}
```

- **验证意见**：项目用 Xcode 26.6（macOS 26 SDK）构建，View 协议整体标注 @MainActor，processFile 被推断为主 actor 隔离，非 detached 的 Task {} 继承该隔离且首个 await 之前无挂起点，Data(contentsOf:) + 逐字符 CSV 解析 + 每行新建 DateFormatter 全部同步阻塞主线程；无任何文件大小防护或后台队列缓解，导入大账单时整个 menubar 应用彩球、ProgressView 冻结。无崩溃/数据丢失，属于条件性核心体验损坏，yellow 恰当。

#### C-23 · @State rows 只在视图身份首次创建时初始化，Import 窗口未关时换一批候选，界面仍显示并提交上一批的旧数据

- **位置**：`Sources/Views/Import/ImportReviewListView.swift:14`　**规则**：STATE-08　**裁决**：CONFIRMED

- **触发场景**：用户 OCR 截图 A（3 条候选）→ Import 窗口打开 .reviewCandidates 分支，@State rows 由 A 初始化。窗口不关，回到 popover 再 OCR 截图 B（5 条）→ showCandidates(B) + openWindow 聚焦同一窗口 → switch 仍是同一分支、视图身份不变 → SwiftUI 忽略新的 State(initialValue:)，列表还是 A 的 3 行，而 summaryBar 用 props 显示 "Found 5 possible subscriptions"（计数与行数对不上）。点 Add → commit() 提交的是 A 的旧候选，B 的 5 条被丢弃 → 加错/漏加订阅。附带隐患：binding(for:) 对找不到的 id 直接 fatalError，一旦此类身份错位演化成行集不一致就是必崩点。

- **同类站点**：Sources/Views/Import/ImportWindowView.swift:63-74（渲染点，修复落点）；ImportReviewListView.swift:152-157（binding(for:) 的 fatalError 埋雷）

- **证据**：

```swift
/// Per-candidate UI state (user can toggle selection + tweak name / category).
@State private var rows: [ReviewRow]
```

- **修复**：

```swift
// ImportWindowView.swift 的 .reviewCandidates 分支给视图键上数据身份，批次变化即重建 @State：
case .reviewCandidates(let candidates):
    ImportReviewListView(
        candidates: candidates,
        existingSubscriptions: subscriptionStore.subscriptions,
        onAdd: { forms in
            for data in forms { subscriptionStore.add(data) }
            closeWindow()
        },
        onCancel: closeWindow
    )
    .id(candidates.map(\.id))   // [UUID] 是 Hashable

// 顺手加固 ImportReviewListView.binding(for:)，去掉 fatalError：
private func binding(for id: UUID) -> Binding<ReviewRow>? {
    guard let idx = rows.firstIndex(where: { $0.id == id }) else { return nil }
    return $rows[idx]
}
// ForEach 内： if let b = binding(for: row.id) { RowView(row: b, onSelect: { toggle(row.id) }) }
```

- **验证意见**：复核成立：Window(id:"import") 是单实例场景，mode 从 .reviewCandidates(A) 变为 .reviewCandidates(B) 时仍处于 ImportWindowView 同一 switch 分支，视图身份不变，@State rows 保留旧批次初值，而 summaryBar 用新 props 计数，commit() 提交的确是旧批次数据且新批次被丢弃；渲染点无 .id()、无 onChange 重同步、无测试覆盖。触发需要窗口未关时二次 OCR，属条件性破坏核心导入流程但不崩溃、不损坏已有数据，维持 yellow。


### 🔵 建议（16 条）

#### C-24 · connect() 的超时闭包无条件 cancel 连接——连接成功后定时器照样在 t=timeout 触发，可能击杀仍在自身预算内健康使用的会话

- **位置**：`Sources/Services/MailWatchdog/IMAPClient.swift:109`　**规则**：TIMEOUT-01　**裁决**：CONFIRMED

- **触发场景**：触发序列：IMAPAccountSheet “Test connection” 调 GenericIMAPBridge.ping(timeout: 30)（connectAppleMail 路径为 60s）→ connect 在 1 秒内成功、continuation 已 resume → login 于 t≈1s 开始并自带 30s 预算（到 t≈31s）→ 服务器 LOGIN 响应迟缓时，t=30s connect 遗留的 asyncAfter 仍执行 conn?.cancel()，把还在 login 自身预算内的健康连接杀掉 → login 的 read 抛 “recv: …cancelled” 映射成 generic .unknown 错误而非干净的 .timeout。guarded.resume 有一次性保护，但 cancel 这个副作用没有。当前各调用方预算基本对齐，实际危害窗口窄（约 1s），属埋雷式缺陷：任何未来 “connect 短超时 + 会话长使用”（如 IDLE / keep-alive）的调用方都会被定时器掐断活连接。

- **证据**：

```swift
DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak conn] in
    conn?.cancel()                       // IMAP-03
    guarded.resume(throwing: MailBridgeError.timeout(resumeToken: [:]))
}
```

- **修复**：

```swift
// IMAPContinuationGuard.swift — 让调用方能观察到自己是否是第一个 resume：
@discardableResult
func resume(_ result: Result<T, Error>) -> Bool {
    lock.lock()
    let isFirst = !resumed
    if isFirst { resumed = true }
    lock.unlock()
    guard isFirst else { return false }
    switch result {
    case .success(let value): continuation.resume(returning: value)
    case .failure(let error): continuation.resume(throwing: error)
    }
    return true
}

@discardableResult
func resume(throwing error: Error) -> Bool { resume(.failure(error)) }

// IMAPClient.connect() — 只有超时真正“赢了”才 cancel：
DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak conn] in
    if guarded.resume(throwing: MailBridgeError.timeout(resumeToken: [:])) {
        conn?.cancel()                   // IMAP-03: timeout won → kill the zombie socket
    }
}
```

- **验证意见**：代码核实无误：connect() 的 asyncAfter 定时器无法取消，且 conn 虽为 weak 捕获但被 actor 的 connection 属性强持有，会话存活期间 t=timeout 时 cancel() 必然击中活连接；IMAPContinuationGuard 只保护 resume 不保护 cancel 副作用，ping 路径（30s/60s 两处调用方均已核实）login 预算确实超出 connect 定时器约一个 connect 时长，被杀后经 readMoreIntoBuffer 第 423 行映射为 .unknown 而非 .timeout。无崩溃、无数据丢失、危害窗口极窄且失败时点近似调用方总预算，属埋雷式错误分类缺陷，blue 定级恰当。

#### C-25 · parseOutput 的 DateFormatter 未设置任何 dateFormat/dateStyle，注释宣称的 “ISO parser first” 分支永远失效，日期解析全部静默依赖 NSDataDetector 兜底

- **位置**：`Sources/Services/MailWatchdog/AppleMailBridge.swift:207`　**规则**：LOGIC-01　**裁决**：CONFIRMED

- **触发场景**：触发序列：Mail.app 的 `date received as string` 返回系统 locale 格式的日期串（如 zh-CN 的 “2026年3月16日 星期一 22:24:33”）→ dateFormatter 没配置格式，date(from:) 恒为 nil → 全部流量落到 NSDataDetector；一旦 detector 对某个 locale/格式解析失败，该邮件被 `return nil` 静默丢弃 → 对应订阅收据漏检、cursor 不推进，用户无任何提示。当前非崩溃且 detector 覆盖面较广，故列 blue：应删除死分支（或真正配置 en_US_POSIX 格式），使代码与注释一致、丢弃路径可被有意识地监控。

- **证据**：

```swift
let dateFormatter = DateFormatter()
// ...
let date: Date
if let parsed = dateFormatter.date(from: dateStr) {
    date = parsed
} else if let match = detector?.firstMatch(
```

- **修复**：

```swift
删除死代码分支：去掉 `let dateFormatter = DateFormatter()`（207 行）以及 `if let parsed = dateFormatter.date(from: dateStr) { date = parsed } else` 分支（226–227 行），让 NSDataDetector 成为唯一且显式的解析路径：

let date: Date
if let match = detector?.firstMatch(
    in: dateStr,
    range: NSRange(dateStr.startIndex..., in: dateStr)
), let d = match.date {
    date = d
} else {
    // Can't parse date → skip (we can't tell if it's in scan window).
    return nil
}
```

- **验证意见**：实测证实：未配置 dateFormat/dateStyle 的 DateFormatter 对 ISO、en-US、zh-CN 等所有真实日期串均返回 nil（仅空字符串会异常地解析成 2000-01-01 参考日期，比声称的"死分支"更糟），注释宣称的 "ISO parser first" 与代码不符，全部解析实际依赖 NSDataDetector；因 detector 实测覆盖各常见 locale、无现实崩溃或数据丢失触发路径，且 Tests/ 中无 parseOutput 任何覆盖，blue（死代码清理/注释一致性）定级恰当。

#### C-26 · cloudMerge 合并结果与本地相同（no-change）时仍走 replaceAll：每条远端通知产生 2 个快照 + 1 次 KVS 回推，5 条通知即刷穿 10 格备份环，掏空 v1.9.0 的恢复保证

- **位置**：`Sources/SuberApp.swift:234`　**规则**：DATA-04　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：双 Mac 同步开启。用户在 Mac B 上连续编辑 5 次（改金额、改分类……），每次 push KVS → Mac A 收到 5 条 didChangeExternally 通知，每条都合并出与本地完全相同的列表 → 仍进入 .applied → replaceAll 先快照 outgoing（1 个文件）→ save() → AppGroupStore.set 再快照新列表（第 2 个文件）→ 5 条通知 = 10 个内容几乎相同的当前态快照 → Mac A 的 10 格订阅备份环被完全轮换，昨天误操作前的旧恢复点全部被 prune。这直接回答了"损坏的 live store 能否滚进所有备份"：单次坏写进不去，但配合这个 no-change 放大器，坏状态落地后只需对端几次保存就能把所有好副本挤出。

- **同类站点**：建议配套：DataBackupManager 增加按天 pinned 快照层（每 key 每天首个快照不参与 10 格轮换），使高频写入场景仍保留跨天恢复点

- **证据**：

```swift
case .applied(let merged):
            NSLog("Suber CloudSync: merge applied (local=\(local.count) remote=\(remote.count) → merged=\(merged.count))")
            store.replaceAll(merged, reason: .cloudMerge)
```

- **修复**：

```swift
case .applied(let merged):
    guard merged != local else { break }   // no-change：不写盘、不烧备份槽、不回推 KVS（同时掐断双端 ping-pong）
    NSLog("Suber CloudSync: merge applied (local=\(local.count) remote=\(remote.count) → merged=\(merged.count))")
    store.replaceAll(merged, reason: .cloudMerge)
```

- **验证意见**：机制属实：CloudSyncMerger 对 merged==local 无短路（.noOp 仅限双空）、handleRemoteSubscriptions 无 no-change guard，每次 applied 合并确实产生 2 个快照 + 1 次 KVS 回推，且无测试覆盖。但所述场景不成立为 no-change 放大器——Mac B 的 5 次编辑到达 Mac A 时每条都携带新内容，属合法合并，其 10 格轮换由 v1.9.2 有意保留的双快照设计（belt-and-suspenders）造成，提议的 guard 无法阻止该场景；真正的 no-change 路径仅是回推 echo，受确定性编码与 KVS 值收敛约束、实践中有界，不会无限 ping-pong。后果是备份环多样性加速消耗（防御层退化），无崩溃、无直接数据丢失，属值得做的加固/效率优化而非破坏核心体验。

#### C-27 · MenuBarExtra(.window) 的 onAppear 每次打开 popover 都执行 setup（注释误以为每次启动一次），scheduleDailyScan 被反复 cancel+重建，24h 倒计时不断重置，每日 Mail 扫描可能永远不触发

- **位置**：`Sources/SuberApp.swift:343`　**规则**：STATE-05　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：用户开启 Watch Apple Mail 后，作为菜单栏应用每天打开 popover 查看几次订阅 → 每次打开触发 onAppear → setupWatchdog() → scheduleDailyScan() 先 cancelDailyScan() 使前一个 NSBackgroundActivityScheduler 失效，再注册新的 24h 间隔活动 → 只要两次打开间隔小于系统调度点，倒计时被重置 → Sentinel 每日扫描被无限推迟，价格上涨/新扣费永远检测不到，用户以为 Autopilot 在工作。setupWatchdog 头注释写"Called from MenuBarContainerView.onAppear (once per app launch)"，与 MenuBarExtra window 风格的实际行为（每次显示都触发 onAppear）不符。

- **同类站点**：Sources/Services/MailWatchdog/MailWatchdog.swift scheduleDailyScan()（cancel+重建即倒计时重置的根因）

- **证据**：

```swift
.onAppear {
                setupCloudSync()
                setupWatchdog()
```

- **修复**：

```swift
// MenuBarContainerView 增加一次性门闩（MenuBarExtra 的视图层级常驻，@State 跨开合存活）
@State private var didRunLaunchSetup = false

.onAppear {
    guard !didRunLaunchSetup else { return }
    didRunLaunchSetup = true
    setupCloudSync()
    setupWatchdog()
    lastIMAPAccountID = settingsStore.settings.autopilot.imapAccount?.id
    Task { await ExchangeRateService.shared.refreshIfNeeded() }
    UpdateService.shared.start()
    presentICloudOnboardingIfNeeded()
}
// 并在 MailWatchdog.scheduleDailyScan 顶部加幂等保护：
// guard scheduler == nil else { return }
```

- **验证意见**：onAppear 确实每次打开 popover 都执行、注释"once per app launch"有误，这部分属实；但核心危害不成立：NSBackgroundActivityScheduler 基于 XPC Activity 按 identifier（"com.suber.mailwatchdog.daily"）跨注册/跨启动持久跟踪上次运行时间（这正是文档要求 identifier 恒定的设计目的，否则每次启动重新注册都会重置），cancel+重建并不会把 24h 倒计时清零；且重复型活动在区间窗口内由系统择时触发而非固定 T+24h，加上手动 Scan now 与开关初扫兜底，"每日扫描永远不触发"不可复现。剩余问题仅为注释误导与每次开合的冗余重建，属代码卫生级别。

#### C-28 · CloudSyncService 可变状态（observing / onRemoteChange）无同步保护，push* 可被 AppIntent 后台线程调用——Swift 6 严格并发下将无法编译

- **位置**：`Sources/Services/CloudSyncService.swift:17`　**规则**：CONC-05　**裁决**：CONFIRMED

- **触发场景**：用户在 Settings 关闭 iCloud 同步（主线程 stopSync 写 observing=false）的同一时刻，Siri 快捷指令在后台线程执行 appendSubscription → pushSubscriptions 读 observing → 非同步的跨线程读写（TSan 会标红；Swift 6 strict mode 编译报错）。最坏行为是读到过期的 true，用户刚关闭同步后仍有一次数据被推上 iCloud KVS。当前所有 UI 路径都在主线程，didChangeExternally 处理也通过唯一一次 DispatchQueue.main.async 跳主线程，故实际风险窗口极窄——列为前瞻性修复。

- **证据**：

```swift
var onRemoteChange: ((Data?, Data?, Data?) -> Void)?

    private var observing = false
```

- **修复**：

```swift
// 用锁把 observing 变成线程安全（onRemoteChange 仅主线程读写，可维持现状并加注释约定）
private let stateLock = NSLock()
private var _observing = false
private var observing: Bool {
    get { stateLock.withLock { _observing } }
    set { stateLock.withLock { _observing = newValue } }
}
```

- **验证意见**：核实成立：observing 为无任何同步保护的普通 var，主线程 SwiftUI onReceive 调 stopSync 写入，而 AddSubscriptionIntent.perform()（无 @MainActor，编入主 app target）经 StorageService.appendSubscription → pushSubscriptions 在后台线程读取，构成真实的跨线程非同步访问且无任何现有缓解。项目当前为 Swift 5.9，"Swift 6 编译报错"仅是前瞻性论断，最坏后果只是关闭同步后多推送一次数据，无崩溃或数据丢失，blue（最佳实践/前瞻修复）定级恰当。

#### C-29 · JSONDecoder.suberDecoder 在每个日期值的解析闭包内新建最多 3 个 formatter（ISO8601DateFormatter 构造昂贵），云同步回调在主线程解码 200 条变更日志时产生数千次冗余分配

- **位置**：`Sources/SuberApp.swift:273`　**规则**：PERF-01　**裁决**：CONFIRMED

- **触发场景**：iCloud 通知到达 → 主线程解码 remote changes（最多 200 条，每条含 detectedAt/startDate 等多个日期字段）→ 每个日期字段解析都 alloc 1-3 个 formatter → 数千次昂贵对象构造集中在主线程一次回调里，popover 交互出现可感知卡顿。StorageService 已用 static 缓存解决同一问题，suberDecoder 是遗漏的孪生实现。恶意/畸形日期字符串不会崩溃：三段解析全失败即抛 DecodingError，所有调用点均 try? 吞掉。

- **证据**：

```swift
let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: str) { return date }
```

- **修复**：

```swift
extension JSONDecoder {
    private static let suberISOFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let suberISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let suberDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static let suberDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = suberISOFractional.date(from: str) { return date }
            if let date = suberISO.date(from: str) { return date }
            if let date = suberDateOnly.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return d
    }()
}
```

- **验证意见**：事实全部成立：suberDecoder 的 .custom 闭包（SuberApp.swift:273-285）确实在每个日期值解析时新建 formatter，且 CloudSyncService.swift:100 经 DispatchQueue.main.async 把解码放在主线程；由于 StorageService 编码器用不带小数秒的 .iso8601，首个 fractional formatter 必然失败，实际每个日期值分配 2 个 ISO8601DateFormatter，200 条变更日志（StorageService.changeLogMaxEntries=200，含嵌套 pendingSubscriptionData 日期）加同回调内的订阅数组可达上千次分配，StorageService.swift:39-57 已有静态缓存的孪生修复而此处遗漏。无崩溃或数据风险（try? 吞掉 DecodingError），总耗时约毫秒级，blue（最佳实践/打磨）定级恰当。

#### C-30 · saveChanges 的文档声称"保留 14 天内 OR 最近 200 条"，但 prune 实现是纯 200 条硬上限；now 参数未使用

- **位置**：`Sources/Services/StorageService.swift:150`　**规则**：DOC-01　**裁决**：CONFIRMED

- **触发场景**：收件箱嘈杂的用户 14 天内积累 250 条变更 → 按 saveChanges 第 137-139 行文档预期这 250 条都保留（都在 14 天内）→ 实际 prune 丢掉最旧 50 条。行为与 H5 头注释（第 20-23 行"HARD CAP regardless of age"）一致、是有意为之，但 saveChanges 的 docstring 会误导下一个维护者；未使用的 now: Date 参数暗示 14 天逻辑曾计划实现于此，属于陷阱式残留。

- **证据**：

```swift
/// Prune rule: keep any entry that is (within the last 14 days OR among
    /// the 200 most-recent). Sorted newest-first so the view doesn't need
    /// to re-sort on every render.
    ...
    static func prune(_ changes: [SubscriptionChange], now: Date = Date()) -> [SubscriptionChange] {
        let sorted = changes.sorted { $0.detectedAt > $1.detectedAt }
        return Array(sorted.prefix(changeLogMaxEntries))
    }
```

- **修复**：

```swift
/// Persist the change log, applying H5 prune-on-write BEFORE save.
///
/// Prune rule: HARD CAP — keep only the 200 most-recent entries by
/// detectedAt, regardless of age (KVS 1 MB budget first; the 14-day
/// window is purely the badge policy in SubscriptionStore.unreadChangeCount).
func saveChanges(_ changes: [SubscriptionChange]) { ... }

/// Exposed for unit tests of the prune policy. Hard cap: 200 most-recent.
static func prune(_ changes: [SubscriptionChange]) -> [SubscriptionChange] {
    let sorted = changes.sorted { $0.detectedAt > $1.detectedAt }
    return Array(sorted.prefix(changeLogMaxEntries))
}
```

- **验证意见**：saveChanges 第 137-139 行文档确实声称"14 天内 OR 最近 200 条"的并集规则，而 prune 实现（150-153 行）是纯 prefix(200) 硬上限，now 参数在函数体内确实未被使用；反例（250 条全在 14 天内 → 丢最旧 50 条）手工推演成立。行为与 H5 头注释及 SubscriptionStore.unreadChangeCount 的 14 天徽章策略一致、属有意设计，故仅为误导性文档问题，blue 级别恰当。注意：提议的修复若删除 now 参数会导致 Tests/SubscriptionStoreChangeLogTests.swift:147 编译失败，需同步更新该测试。

#### C-31 · async 上下文中裸用 NSLock.lock()/unlock() —— Swift 6 模式下直接编译失败,且一处重构即死锁

- **位置**：`Sources/Services/ImageCache.swift:68`　**规则**：CONC-08　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：编译器证据(68-108 行 "unavailable from asynchronous contexts")核实结论:当前代码所有 await(71 行 existing.value、103 行 task.value)都发生在 unlock 之后,临界区内没有挂起点,所以【今天不会死锁】,竞争时只会短暂阻塞一条协作线程(临界区仅字典操作,饥饿风险可忽略)。真实风险:(1) 开启 Swift 6 language mode 时此文件直接编译报错,阻塞迁移;(2) 该模式极脆弱——未来任何人把一个 await 挪进 lock/unlock 之间(例如把 106-108 行清理挪到 await 之前的 defer 里),持锁线程挂起后恢复到另一条线程 unlock,NSLock 非同线程解锁为未定义行为,且协作线程池(核数上限)被持锁阻塞可整体饿死。正确修法:保持同步 API 不变,用闭包式 withLock 使临界区在构造上无法包含 await(actor 化是过度修复——cachedImage/cacheKey 被 SwiftUI body 同步调用,会被迫全链路 await)。

- **同类站点**：同文件 :100-101、:106-108 的 lock()/unlock() 对一并被此重写消除。NotificationService.swift:223,230 的 NSLock 用在同步函数里,无需改动。

- **证据**：

```swift
taskLock.lock()
if let existing = inFlightTasks[key] {
    taskLock.unlock()
    return await existing.value
}
```

- **修复**：

```swift
func loadImage(for key: String, url: URL) async -> NSImage? {
    if let cached = cachedImage(for: key) {
        return cached
    }

    // Dedup under the lock, but never suspend while holding it.
    // withLock is async-safe: the critical section is synchronous by construction.
    let (task, isCreator): (Task<NSImage?, Never>, Bool) = taskLock.withLock {
        if let existing = inFlightTasks[key] {
            return (existing, false)
        }
        let task = Task<NSImage?, Never> {
            do {
                let (data, response) = try await self.session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      data.count > 100,
                      let image = NSImage(data: data) else {
                    return nil
                }
                self.memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                let diskPath = self.diskCachePath(for: key)
                self.diskQueue.async {
                    try? data.write(to: diskPath, options: .atomic)
                }
                return image
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task
        return (task, true)
    }

    let result = await task.value
    if isCreator {
        taskLock.withLock { _ = inFlightTasks.removeValue(forKey: key) }
    }
    return result
}
```

- **验证意见**：事实核实成立:SDK 头文件确认 NSLocking.lock()/unlock() 带 NS_SWIFT_UNAVAILABLE_FROM_ASYNC 标注,且 68/70/101/106/108 行确实直接位于 async 函数体内;但项目当前为 SWIFT_VERSION=5.9(仅产生警告,Swift 6 模式才报错),且审计自己也承认所有 await 都在 unlock 之后、今天不会死锁。两项风险(Swift 6 迁移受阻、未来重构引入挂起点)均为前瞻性/可维护性问题,现有代码无条件性崩溃或体验破坏,按标准应降为 blue(最佳实践级);建议的 withLock 修法在 macOS 14.0 部署目标下可行,值得采纳。

#### C-32 · parseDate 固定先试 MM/dd/yyyy —— 英/欧 dd/MM 账单日期被系统性错读,漏检订阅或 billingDay 错误

- **位置**：`Sources/Services/BankImport/StatementFormat.swift:51`　**规则**：DATA-03　**裁决**：CONFIRMED

- **触发场景**：英国银行 CSV 中 "05/01/2026"(1 月 5 日)被格式数组里排前面的 MM/dd/yyyy 先命中 → 解析成 5 月 1 日。当日号 ≤ 12 时整个文件的日期都被月日互换 → 连续月扣间隔算错(如 05/01 与 05/02 两笔月费被算成 5/1 与 5/2 间隔 1 天)→ RecurringChargeDetector 判非周期,"no recurring charges" 漏检;即便检出,billingDay/startDate 也是错的。DateFormatter 的 dateFormat 匹配不受 locale 影响,现有 en_US_POSIX 设置救不了这条。

- **证据**：

```swift
"MM/dd/yyyy",
"dd/MM/yyyy",
```

- **修复**：

```swift
// 按用户区域决定歧义日期的优先顺序(仅调换两个格式的次序):
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
// 更彻底的修法(后续):先全文件扫描一遍,若任何行首段 >12 则整文件按 dd/MM 解析。
```

- **验证意见**：反例逐行复核成立：DateFormatter 显式 dateFormat 下 en_US_POSIX 不影响数字字段顺序，非 lenient 模式接受 "05/01/2026" 为 5 月 1 日且不再回退到 dd/MM;英/欧账单账单日 ≤ 12 时整月序列被解析成连续天,cycleFor(1) 返回 nil 导致整组静默丢弃,且代码库和测试中均无任何区域/日期序缓解措施(GenericFormat 还明示支持 Revolut 等英国银行)。无崩溃、金额正确、结果仅是导入辅助功能在特定区域子集下漏检或 billingDay 错误,维持 blue 严重级。

#### C-33 · start() 无幂等保护,MenuBarExtra 每次打开 popover 都重跑 —— KVO 订阅无限累积

- **位置**：`Sources/Services/UpdateService.swift:69`　**规则**：MEM-03　**裁决**：CONFIRMED

- **触发场景**：MenuBarContainerView 的 .onAppear(SuberApp.swift:343-352)在每次打开菜单栏 popover 时都会触发(MenuBarExtra 的 content 每次开合都重建),于是 start() 反复执行:startUpdater() 被 Sparkle 拒绝并打 error log;更重要的是两条 publisher(for:).assign(to: &$…) 链每次新建 2 个 KVO 订阅,而 assign(to: &$published) 的生命周期绑定在单例的 @Published 上永不释放 → 常驻数月、每天开合几十次后累积上千个活跃 KVO 观察者,内存缓慢增长且每次 Sparkle 状态变化触发上千次重复写入。

- **同类站点**：Sources/SuberApp.swift:352 调用点

- **证据**：

```swift
updaterController.updater.publisher(for: \.canCheckForUpdates)
    .receive(on: DispatchQueue.main)
    .assign(to: &$canCheckForUpdates)
```

- **修复**：

```swift
private var started = false

/// Start the Sparkle background updater. Idempotent — MenuBarExtra re-fires
/// onAppear on every popover open.
func start() {
    guard !started else { return }
    started = true
    updaterController.startUpdater()
    updaterController.updater.publisher(for: \.canCheckForUpdates)
        .receive(on: DispatchQueue.main)
        .assign(to: &$canCheckForUpdates)
    updaterController.updater.publisher(for: \.lastUpdateCheckDate)
        .receive(on: DispatchQueue.main)
        .assign(to: &$lastCheckedAt)
}
```

- **验证意见**：核心机制成立：MenuBarExtra(.window) 的 content onAppear 每次开合都触发，同一 onAppear 块里其他调用全都有幂等保护（如 CloudSyncService.startSync 的 guard !observing），唯独 UpdateService.start() 没有，两条 assign(to: &$published) 链每次新增 2 个永不释放的 KVO 订阅，累积属实。唯一需修正的子论断：Sparkle 2.9.1 的 startUpdater 本身幂等（_startedUpdater 直接 return YES），重复调用不会打 error log；但这不影响 KVO 泄漏主体，blue 级别恰当，建议的 guard 修法正确。

#### C-34 · OCR 金额正则截断千分位 + normalizeNumber 逗号一律转小数点 —— "¥1,299" 预填成 1.29

- **位置**：`Sources/Services/SubscriptionTextParser.swift:431`　**规则**：DATA-04　**裁决**：CONFIRMED

- **触发场景**：用户 OCR 一张年费账单 "¥1,299/年" → 金额正则 (\d{1,}(?:[.,]\d{1,2})?) 只能捕获 "1,29"(小数组最多 2 位、无行尾锚)→ normalizeNumber 把逗号转成点 → 表单预填 ¥1.29。用户若不细看直接保存,年度支出统计低 1000 倍。(缓解:OCR 结果进入表单供用户确认,不直接入库,故定级 blue。)

- **同类站点**：同文件 :107(符号+数字)、:115(数字+币种代码)、:128(关键词行裸数字)三处正则同型

- **证据**：

```swift
str.replacingOccurrences(of: ",", with: ".")
```

- **修复**：

```swift
// 1) 三处金额正则(107、115、128 行)把数字组改成优先匹配千分位形态:
//    (\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?|\\d+(?:[.,]\\d{1,2})?)
// 2) normalizeNumber 区分两种逗号:
private static func normalizeNumber(_ str: String) -> String {
    // "1,299" / "1,299.00" → thousands separators; "9,99" → decimal comma
    if str.range(of: #"^\d{1,3}(,\d{3})+(\.\d{1,2})?$"#, options: .regularExpression) != nil {
        return str.replacingOccurrences(of: ",", with: "")
    }
    return str.replacingOccurrences(of: ",", with: ".")
}
```

- **验证意见**：实际用 NSRegularExpression 复现:"¥1,299/年"经 107 行正则捕获 "1,29",normalizeNumber(431 行)转成 "1.29",与指控完全一致,且 115/128 行同型正则同病;无任何测试或下游修正。但解析结果仅预填 SubscriptionFormView 表单和 MenuBarView 候选审核 UI,均需用户确认后才入库,故维持 blue 定级成立。

#### C-35 · getNextBillingDate 对 oneTime 也按 billingDay 钳制,而表单对一次性消费隐藏了 billingDay 字段,导致列表/详情与日历显示两个不同日期

- **位置**：`Sources/Services/BillingCalculator.swift:52`　**规则**：DATE-05　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：今天 2026-07-10(SubscriptionFormData 默认 billingDay = 当天的 10)。用户添加一笔一次性消费,startDate 选 2026-06-25;由于 SubscriptionFormView.swift:175 对 .oneTime 隐藏 Billing day 选择器,billingDay 以 10 入库。getNextBillingDate → clampDay(6月25日, day:10) = 2026-06-10 → ListView 的排序日期与 DayDetailView 的到期日显示 6 月 10 日(一个什么都没发生的日子);而 CalendarView 走 getBillingDateInMonth 的 oneTime 分支正确显示 6 月 25 日。同一条数据两个界面日期互相矛盾。(MenuBarView.swift:158 的快捷添加路径恰好用 startDate 的日号回填 billingDay,所以只有完整表单路径触发。)

- **证据**：

```swift
var next = sub.cycle == .weekly ? start : clampDay(start, day: sub.billingDay)

if sub.cycle == .oneTime {
    return next
}
```

- **修复**：

```swift
// oneTime 与 weekly 一样不适用 billingDay 锚定,直接返回开始日:
var next = (sub.cycle == .weekly || sub.cycle == .oneTime)
    ? start
    : clampDay(start, day: sub.billingDay)

if sub.cycle == .oneTime {
    return next
}
```

- **验证意见**：缺陷本身属实：BillingCalculator.swift:52 对 .oneTime 也按 billingDay 钳制，且表单确实对一次性消费隐藏了 billingDay（默认值为当天日号），反例数学可复现。但所声称的"列表/详情与日历显示矛盾日期"这一核心症状并不成立——SubCardView（列表行）与 DayDetailView 均对 .oneTime 做了 nil 保护，不会向用户展示错误日期；残余影响仅剩 nextBilling 排序的隐性错序和未来日期一次性消费的通知调度偏差（且多被 reminderDate 过期检查静默吞掉），属于纯函数正确性修补而非破坏核心体验，故降级为 blue。

#### C-36 · 周付年化常数不统一:Dashboard 用 4.33×12 = 51.96 周/年,AnnualCost 用 52 周/年,同一订阅两个面显示不同年费

- **位置**：`Sources/Services/BillingCalculator.swift:227`　**规则**：MONEY-03　**裁决**：CONFIRMED

- **触发场景**：周付 $10 订阅:Dashboard 的 yearlySpend = 10 × 4.33 × 12 = $519.60;ChangeRowView / CancellationSuccessBanner 走 BillingCycle.annualAmount = 10 × 52 = $520.00。同一 app 内对"这订阅一年多少钱"给出两个数,违背 AnnualCost.swift 头注"One helper, one rounding policy, one source of truth"的设计意图。无崩溃、误差 <0.1%,属一致性打磨。

- **同类站点**：Sources/ViewModels/DashboardViewModel.swift:60(yearlySpend = monthly * 12,采用上述修正后自动对齐);Sources/Services/AnnualCost.swift:33(×52 为基准口径)

- **证据**：

```swift
case .weekly: return amt * 4.33
```

- **修复**：

```swift
case .weekly: return amt * 52.0 / 12.0   // ≈ 4.3333,与 AnnualCost 的 ×52 保持同一口径
```

- **验证意见**：两处常数确实不一致且均可复现:BillingCalculator.swift:227 用 ×4.33(经 DashboardViewModel:60 ×12 得 $519.60/年),而 AnnualCost.swift:33 用 ×52(ChangeRowView/CancellationSuccessBanner 显示 $520/年),formatShort 不做取整故差异用户可见;两侧还各有测试固化了不同口径。无崩溃、误差 <0.1%,属一致性打磨,blue 定级恰当。

#### C-37 · Export JSON 的 try? data.write 静默吞错，用户以为备份成功实际什么都没写

- **位置**：`Sources/Views/SettingsView.swift:492`　**规则**：ERR-01　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：用户点 Export JSON 选择保存到已满的磁盘 / 权限被收回的 iCloud Drive 目录 / 只读卷 → data.write(to:) 抛错被 try? 吞掉 → 面板关闭、无任何反馈。用户以为拿到了备份，之后放心执行 Clear all data 或重装 → 发现备份文件根本不存在，数据无法找回。（对比：同文件 importData 的失败路径有 alert，行为不对称。）

- **证据**：

```swift
if Self.runFilePanelFromPopover(panel) == .OK, let url = panel.url {
    try? data.write(to: url)
}
```

- **修复**：

```swift
if Self.runFilePanelFromPopover(panel) == .OK, let url = panel.url {
    do {
        try data.write(to: url)
    } catch {
        // 复用现有的 Import Error alert 管线呈现写盘失败
        importError = "Export failed: \(error.localizedDescription)"
        showImportError = true
    }
}
```

- **验证意见**：代码缺陷属实：第 492 行 try? 确实静默吞掉写盘错误，且与 importData 的报错路径不对称；但其严重性论据不成立——clearAll() 经由 replaceAll 在清空前自动快照到 App Group 容器的 Backups/（重装也不丢），并有"Restore from backup"一键恢复入口，所以"导出失败后清空数据无法找回"的数据丢失链条被现有 4 层备份架构切断。剩余问题仅是罕见写盘失败（磁盘满等）时缺少错误提示，属错误呈现/最佳实践级别，建议采纳修复但降为 blue。

#### C-38 · asyncAfter 延迟关闭 overlay 不可取消：延迟窗口内重开扫描面板会被旧回调突然关掉；popover 提前关闭时回调写入已卸载的 @State

- **位置**：`Sources/Views/SubscriptionFormView.swift:338`　**规则**：LIFE-01　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：触发序列 A：用户粘贴截图 → applyParsedData 排入 1.0s 后 showImageInput=false 的 asyncAfter → 用户在 1 秒内再次点击扫描按钮重开 ImageDropZoneView 准备扫第二张 → 旧回调到期把新打开的面板强行关闭，用户正拖图时面板消失。触发序列 B（与 WindowActivationCoordinator 交互）：EmailParseView 0.5s 延迟期间用户点击 popover 外部或多结果路径触发 surface() 抢焦点 → popover 失 key 关闭、视图树卸载 → 延迟回调对已拆除的 @State 写值（控制台 "Accessing State's value outside of being installed on a View"，写入常量绑定）。不崩溃，但属不可取消的定时器打断用户操作。

- **同类站点**：Sources/Views/SubscriptionFormView.swift:364（applyParsedData 内 1.0s 同型延迟）

- **证据**：

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    showEmailInput = false
}
```

- **修复**：

```swift
// 用可取消的 Task 替换两处 asyncAfter：
@State private var overlayDismissTask: Task<Void, Never>? = nil

private func scheduleOverlayDismiss(after seconds: Double, _ close: @escaping () -> Void) {
    overlayDismissTask?.cancel()
    overlayDismissTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        guard !Task.isCancelled else { return }
        close()
    }
}

// applyParsedData 内替换 364 行：
scheduleOverlayDismiss(after: 1.0) { showImageInput = false }
// EmailParseView onResult 内替换 338 行：
scheduleOverlayDismiss(after: 0.5) { showEmailInput = false }
// 两个打开按钮 action 补一行，防旧回调关新面板：
Button(action: { overlayDismissTask?.cancel(); showEmailInput = true }) { ... }
Button(action: { overlayDismissTask?.cancel(); showImageInput = true }) { ... }
```

- **验证意见**：代码事实完全属实：338/364 两处 asyncAfter 不可取消且无任何防护，旧回调确实会在延迟窗口内强关重开的面板。但触发需要用户在 1.0s（邮件 0.5s）内完成"关闭+重开"的极快操作，多结果路径（真正涉及 surface() 抢焦点的路径）是同步关闭、不排入延迟回调；场景 B 仅产生控制台警告写入已分离的 @State，无崩溃无数据丢失，解析数据已落入表单，一次点击即可恢复。属于应修的最佳实践问题（改用可取消 Task），而非"核心体验被破坏"，降为 blue。

#### C-39 · 使用已废弃的单参数 onChange(of:perform:)（部署目标 macOS 14，应迁移到新签名）

- **位置**：`Sources/Views/CalendarView.swift:45`　**规则**：DEPR-01　**裁决**：CONFIRMED

- **触发场景**：部署目标为 macOS 14.0，onChange(of:perform:) 自 macOS 14 起 deprecated。当前不崩不坏，但旧签名在 view update 期间取旧值的语义与新 API 不同，未来 SDK 升级会变成编译警告堆积并有移除风险。触发即编译期告警，无运行时故障。

- **同类站点**：Sources/Views/CalendarView.swift:46；Sources/Views/SubscriptionFormView.swift:134

- **证据**：

```swift
.onChange(of: currentMonth) { _ in recomputeCache() }
.onChange(of: subscriptionStore.subscriptions) { _ in recomputeCache() }
```

- **修复**：

```swift
// CalendarView.swift:45-46 —— 新值不被使用，用零参数形式：
.onChange(of: currentMonth) { recomputeCache() }
.onChange(of: subscriptionStore.subscriptions) { recomputeCache() }

// SubscriptionFormView.swift:134 —— 需要新值，用双参数形式：
.onChange(of: formData.amount) { _, newValue in
    let filtered = newValue.filter { $0.isNumber || $0 == "." }
    let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count > 2 {
        formData.amount = String(parts[0]) + "." + String(parts[1])
    } else if filtered != newValue {
        formData.amount = filtered
    }
}
```

- **验证意见**：核实无误：项目部署目标为 macOS 14.0（project.pbxproj 两处 MACOSX_DEPLOYMENT_TARGET = 14.0），CalendarView.swift:45-46 与 SubscriptionFormView.swift:134 均使用自 macOS 14 起废弃的单参数 onChange(of:perform:)，必然产生编译期废弃警告；且代码库已部分迁移（DashboardView.swift:49 用零参数新形式、IMAPAccountSheet.swift:126 用双参数新形式），说明这三处是遗留而非兼容性取舍。无运行时影响，blue（最佳实践/打磨级）定级恰当，建议的迁移方案与各调用点语义匹配。


## UI/UX 审计发现

### 🟡 警告（7 条）

#### U-01 · IMAP 账号一键删除无任何确认，Keychain 中的 App 密码被同步销毁且不可恢复

- **位置**：`Sources/Views/Autopilot/AutopilotSettingsSection.swift:198`　**规则**：UX-01　**裁决**：DOWNGRADED（由 🔴 降级）

- **触发场景**：用户在 设置→Autopilot 想点『Edit』修改 IMAP 端口，但 trash 图标紧贴在 Edit 右侧；误点一下 → IMAPCredentialStore.delete() 立即执行 SecItemDelete（IMAPAccount.swift:111），账号配置与 Keychain 密码同时消失。Google/Microsoft 的 App Password 生成后无法再次查看，用户必须去 Google 账号页重新生成一个新密码并重新配置。全程 1 次点击、无确认弹窗、无撤销；DataBackupManager 只备份订阅/设置/变更日志三个 key，不备份 Keychain。对比：清空全部数据、JSON 导入、恢复备份、删除订阅都有确认，唯独这个不可逆操作没有。

- **证据**：

```swift
Button {
    IMAPCredentialStore.delete(email: account.email)
    settingsStore.update { $0.autopilot.imapAccount = nil }
} label: {
    Image(systemName: "trash")
}
.buttonStyle(.bordered)
.controlSize(.small)
.help("Remove account and delete password from Keychain")
```

- **修复**：

```swift
// AutopilotSettingsSection: 加确认（.alert 是 NSAlert 后端，popover 内安全 — 见 PopoverOverlay.swift:27-31）
@State private var showRemoveIMAPConfirm = false

Button {
    showRemoveIMAPConfirm = true
} label: {
    Image(systemName: "trash")
}
.buttonStyle(.bordered)
.controlSize(.small)
.help("Remove account and delete password from Keychain")
.alert("Remove \(account.displayName)?", isPresented: $showRemoveIMAPConfirm) {
    Button("Cancel", role: .cancel) {}
    Button("Remove account", role: .destructive) {
        IMAPCredentialStore.delete(email: account.email)
        settingsStore.update { $0.autopilot.imapAccount = nil }
    }
} message: {
    Text("The app password will be deleted from your Keychain. Providers don't show app passwords again — you'll need to generate a new one to reconnect.")
}
```

- **验证意见**：事实全部成立：trash 按钮一次点击即执行 SecItemDelete（IMAPAccount.swift:117）且无任何确认，Keychain 密码不在 DataBackupManager 备份范围内，而应用内其他不可逆操作均有确认弹窗，修复方案（popover 内 .alert 走 NSAlert）也经 PopoverOverlay.swift:27-31 证实可行。但损失的是可在提供商处重新生成的 App Password，订阅数据、变更历史乃至 IMAP 账号配置（settings 快照/iCloud 同步）均未丢失，后果是几分钟的重新配置麻烦而非真正的不可恢复数据丢失，故按 red=数据丢失的标准降为 yellow。

#### U-02 · 126/200 条用户可见文案不在 99-key 目录中，中文用户全部主流程呈中英混排

- **位置**：`Sources/Views/CalendarView.swift:18`　**规则**：UX-02　**裁决**：CONFIRMED

- **触发场景**：中文用户（语言=简体中文）打开 Suber：默认 Calendar 页星期栏永远是 MON/TUE/WED（硬编码英文数组）、右上角 'Monthly spend'；点 + 添加订阅，整张表单 Service/Domain/Price/Interval/Billing day/Notes/Delete Subscription 全英文；设置页 iCloud Sync/Currency/Notifications/Data/Clear all data、导入窗口、恢复备份页、首启 iCloud onboarding、两个 Widget 全部英文。实测扫描：视图层共 200 条不同的用户可见字符串字面量，仅 74 条在目录中，126 条缺失（去掉纯数字插值约 117 条真实文案）。目录本身 99 key 全部有 zh 翻译，只覆盖了 Autopilot/取消流。

- **同类站点**：10 个最伤主流程的例子：CalendarView.swift:97 'Monthly spend'；SubscriptionFormView.swift:97-206 表单全部字段标签；SubscriptionFormView.swift:273 'Delete Subscription' 删除确认；SettingsView.swift:39/46/114/151/161/203 全部 section 标题；SettingsView.swift:190 'Clear all data'+261 'Clear All Data?'；SettingsView.swift:315 'Replace all subscriptions?' 导入确认；ListView.swift:3-8 SortBy rawValue ('Next Billing'…) + FilterBarView.swift:6 过滤器；DashboardView.swift:71-102 空状态与 'Add subscription' CTA 段落；DataRestoreView.swift:48/90/101 恢复流全部；SuberWidget/*.swift 'Monthly Spend'/'Upcoming Bills'/'No upcoming bills this week'。另：Subscription.swift:12-28 BillingCycle.label 与 SubscriptionStatus.label（'Monthly'/'Pending cancel'…）经模型 String 输出，同样全英文。

- **证据**：

```swift
private let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
```

- **修复**：

```swift
// 1) 星期栏改用 locale 感知符号（周一起始轮转）：
private let weekdays: [String] = {
    let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols // [日,一,二,...] 或 [S,M,T,...]
    return Array(symbols[1...]) + [symbols[0]] // rotate to Monday-first
}()
// 2) 把 126 条缺失字面量补进 Localizable.xcstrings（Xcode 构建会自动抽取 Text/Button 字面量），
//    优先级：SubscriptionFormView 全部、SettingsView 全部、CalendarView、ListView(SortBy rawValue/Filter)、
//    DashboardView、Import 三视图、DataRestoreView、CloudSyncOnboardingSheet、SuberWidget。
```

- **验证意见**：全部核实成立：CalendarView.swift:18 硬编码英文星期数组（Text(day) 为 String 变量走 verbatim 路径，加目录也不会本地化）；目录恰好 99 key 且全部只覆盖 Autopilot/取消流；SubscriptionFormView:273、SettingsView:190/261、ListView SortBy rawValue、Dashboard 空状态、Widget、BillingCycle.label 等引用点逐一复现。更关键的是应用自带"App language 强制简体中文"设置且 LocalizationCatalogTests 明文声明 v1.6 双语契约"no half-translated fallback-to-English surprises"，而主流程整体回退英文直接违反自身契约——对中文用户是核心体验层面的破损而非打磨问题，yellow 恰当（无崩溃/数据损失，不到 red）。

#### U-03 · 已翻译的目录 key 经 String 参数通道渲染，运行时永远显示英文（死翻译）

- **位置**：`Sources/Views/Components/ToggleRow.swift:9`　**规则**：UX-03　**裁决**：CONFIRMED

- **触发场景**：中文用户打开 设置→Autopilot：'Watch Apple Mail'、'Price changes'、'New subscriptions'、'Duplicate charges' 四个开关标签都在 99-key 目录里且有中文翻译，但 ToggleRow 的 label 参数是 String，Text(String) 走 StringProtocol 重载、不做 catalog 查询 → 标签显示英文，而每行下方的说明文字（字面量 Text）显示中文，同一屏中英交错。同理 groupHeader('Apple Mail'/'Other email accounts'/'Alert me about')、Text(lastScanText)（'Never scanned yet'/'Off'/'Look for the macOS permission dialog…' 均在目录中）、SubCardView Button(cancelMenuLabel)、DayDetailView Text(cancelButtonLabel(...))（'Open cancel page…' 在目录中）全部失效。LocalizationCatalogTests 只校验目录 JSON 形状，测不到这条运行时断链。

- **同类站点**：Sources/Views/Autopilot/AutopilotSettingsSection.swift:361 groupHeader(_ title: String)；AutopilotSettingsSection.swift:64 Text(lastScanText)；Sources/Views/SubCardView.swift:80 Button(cancelMenuLabel)；Sources/Views/DayDetailView.swift:163 Text(cancelButtonLabel(for: sub))；Sources/Views/SettingsView.swift:342 section(_ title: String)；Sources/Views/SubscriptionFormView.swift:407/422/470 field/dateField/menuField(_ label: String)；Sources/Views/Import/BankImportView.swift:70 Text(headerTitle)

- **证据**：

```swift
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
```

- **修复**：

```swift
struct ToggleRow: View {
    let label: LocalizedStringKey   // was String — Text(String) 不查 String Catalog
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label) // LocalizedStringKey → 正常走 Localizable.xcstrings
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Theme.textPrimary)
                .labelsHidden()
        }
    }
}
// 计算型字符串（lastScanText 等）在 return 处改用 String(localized: "Never scanned yet") 包装。
```

- **验证意见**：逐点复核全部属实：ToggleRow.swift:9 的 Text(label) 因 label 为 String 走 StringProtocol 重载不查目录，而四个开关标签及 lastScanText、groupHeader、cancelMenuLabel 等所有引用点的 key 均在 99-key 目录中且 zh-Hans 为 translated 状态；工程确实以双语上线为目标（knownRegions/CFBundleLocalizations 含 zh-Hans、内置 AppleLanguages 语言切换），相邻的字面量 Text 会正常显示中文，中英混排场景可静态复现；全 Sources 无 String(localized:) 兜底，LocalizationCatalogTests 仅校验目录 JSON 形状测不到此断链。无崩溃或资损故不升红，但对全部中文用户属无条件破坏已上线核心体验，维持 yellow。

#### U-04 · 价格变化行的年度影响硬编码 "$" 符号，非美元主货币显示错误币种

- **位置**：`Sources/Views/Autopilot/ChangeRowView.swift:274`　**规则**：UX-04　**裁决**：CONFIRMED

- **触发场景**：主货币设为 CNY 的用户收到爱奇艺涨价（¥19.8→¥25.8）：Changes 窗口辅助行显示 'was ¥19.80 · +30% · +$72/year' —— annualImpact() 已把差额换算成 CNY（第 331-334 行 convert(to: primaryCurrency)），但展示时永远拼 "$"，¥72 被标成 $72，年度影响被夸大约 7 倍。取消成功行 'saved $X/year'（第 299 行）同病。

- **同类站点**：Sources/Views/Autopilot/ChangeRowView.swift:299 confirmedHeadline 'saved $…/year'；ChangeRowView.swift:352-360 symbol(for:) 与 AppConstants.currencySymbols 重复且只覆盖 5 币种

- **证据**：

```swift
let annualStr = annualSavings >= 0 ? "+$\(annualSavings)/year" : "-$\(-annualSavings)/year"
```

- **修复**：

```swift
let sym = symbol(for: primaryCurrency)
let annualStr = annualSavings >= 0 ? "+\(sym)\(annualSavings)/year" : "-\(sym)\(-annualSavings)/year"
// confirmedHeadline (line 299) 同步改：
let savings = annual != 0 ? " · saved \(symbol(for: primaryCurrency))\(abs(annual))/year" : ""
// 顺带：symbol(for:) (line 352) 只认 5 种货币，应复用 AppConstants.currencySymbols[currency]。
```

- **验证意见**：第 274 行与第 299 行确实硬编码 "$"，而 annualImpact() 已通过 ExchangeRateService.convert 把差额换算成用户可在设置中选择的 primaryCurrency（含 CNY 等 20 种货币，ChangesListView.swift:165 直接传入 settings.primaryCurrency），手工重演爱奇艺 ¥19.8→¥25.8 场景得到 "was ¥19.80 · +30% · +$72/year"，与指控完全一致且无任何现有防护或测试覆盖；因仅是展示层错标币种、不影响存储和计算，维持 yellow 恰当。

#### U-05 · 日历头部『Monthly spend』在多币种时直接丢弃非主货币订阅，与 Dashboard 数字互相矛盾

- **位置**：`Sources/Views/CalendarView.swift:184`　**规则**：UX-05　**裁决**：CONFIRMED

- **触发场景**：用户有 3 个 USD 订阅（$30/月）+ 2 个 CNY 订阅（¥50/月），主货币 USD：Calendar 头部只把 USD 订阅求和显示 '~$30'（CNY 订阅被 filter 整个剔除，不做汇率换算）；切到 Dashboard，同一份数据经 ExchangeRateService 换算显示 ≈$37/月。同一 app 两个页签对『本月支出』给出两个数，且日历那个系统性偏低——用户以哪个做预算都可能错。

- **证据**：

```swift
let hasMultipleCurrencies = Set(activeSubs.map(\.currency)).count > 1
let total = activeSubs
    .filter { !hasMultipleCurrencies || $0.currency == primaryCurrency }
    .reduce(0.0) { $0 + BillingCalculator.getMonthlyEquivalent($1) }
```

- **修复**：

```swift
// 与 DashboardViewModel.update (DashboardViewModel.swift:55-58) 对齐：全部换算成主货币
let total = activeSubs.reduce(0.0) { sum, sub in
    let equiv = BillingCalculator.getMonthlyEquivalent(sub)
    return sum + ExchangeRateService.shared.convert(equiv, from: sub.currency, to: primaryCurrency)
}
let formatted = CurrencyFormatter.formatShort(total, currency: primaryCurrency)
cachedMonthlySpend = hasMultipleCurrencies ? "~\(formatted)" : formatted  // ~ 保留，表示含汇率估算
```

- **验证意见**：复核属实：CalendarView.swift:184 在多币种时直接过滤掉非主货币订阅且不做汇率换算，而 DashboardViewModel.swift:55-58 全部经 ExchangeRateService 换算，手工重算反例成立（Calendar ~$30 vs Dashboard ≈$37；若无主货币订阅甚至显示无波浪号的 $0）。git 历史显示该过滤写于 ExchangeRateService 引入之前，后续 Dashboard、趋势图、GetSpendIntent 均已迁移到换算逻辑，唯独日历遗留未改，且无任何测试覆盖此行为；属于展示层核心数字自相矛盾但非资金/数据损失，维持 yellow。

#### U-06 · 日历日详情显示未分摊的 amount，分摊（splitCount>1）订阅金额虚高数倍

- **位置**：`Sources/Views/DayDetailView.swift:69`　**规则**：UX-06　**裁决**：CONFIRMED

- **触发场景**：用户记录 Netflix 家庭组 $23.96/月、splitCount=4（自己实付 $5.99）：List 页卡片正确显示 '÷4 $5.99'（SubCardView 用 effectiveAmount），点日历该扣款日打开 DayDetail，同一订阅显示 $23.96 —— 4 倍于实付。BillingCalculator/AnnualCost 全部用 effectiveAmount，唯独此处用原始 amount，同一笔订阅在两个视图报两个价。

- **证据**：

```swift
Text(CurrencyFormatter.formatShort(sub.amount, currency: sub.currency))
```

- **修复**：

```swift
Text(CurrencyFormatter.formatShort(sub.effectiveAmount, currency: sub.currency))
// 可选：与 SubCardView 一致，splitCount>1 时加 '÷N' 前缀提示分摊。
```

- **验证意见**：DayDetailView.swift:69 确实用原始 sub.amount，而 SubCardView（÷N + effectiveAmount）、BillingCalculator.getMonthlyEquivalent、AnnualCost 均用分摊后的 effectiveAmount，甚至同一日历页顶部的月支出总额也是分摊口径，点开日详情却显示 4 倍原价，反例手动复现成立且无任何缓解或测试覆盖。属于 splitCount>1 条件下的显示不一致（数据与计算均正确），维持 yellow。

#### U-07 · 『Mark as cancelled』三个入口两个无确认：右键菜单与 DayDetail 一键直改状态并写入变更日志

- **位置**：`Sources/Views/SubCardView.swift:87`　**规则**：UX-09　**裁决**：CONFIRMED

- **触发场景**：订阅处于 pendingCancellation：用户右键卡片想再次点『Open cancel page…』，两项紧邻，误点下面的『Mark as cancelled』→ 立即置为 cancelled、清除 pendingCancellationSetAt、ack 变更，无确认、无撤销按钮；订阅从日历消失（DateHelpers.subscriptionsByDate 过滤 cancelled），自动验证流程被跳过。DayDetailView:197 的 borderedProminent 按钮同样一键直调 markCancelledManually（还会写入一条 cancellationConfirmed 日志并可能触发庆祝横幅）。而 CancelConfirmationSheet.swift:85 对完全相同的操作做了两步确认（注释自述 D5『防止误点』）——同一动作三处入口，防护不一致。恢复只能靠用户自己想起进编辑表单把 Status 改回来。

- **同类站点**：Sources/Views/DayDetailView.swift:197-205 pendingCancelBanner 的 'Mark as cancelled' borderedProminent 按钮，同样无确认直调 markCancelledManually

- **证据**：

```swift
Button("Mark as cancelled") {
    subscriptionStore.markChangeAcknowledged(id: subscription.id)
    var sub = subscription
    sub.status = .cancelled
```

- **修复**：

```swift
// SubCardView：与 CancelConfirmationSheet 相同的两步确认
@State private var showMarkCancelledConfirm = false
// contextMenu 内：
Button("Mark as cancelled") { showMarkCancelledConfirm = true }
// body 末尾：
.alert("Mark \(subscription.name) as cancelled?", isPresented: $showMarkCancelledConfirm) {
    Button("Cancel", role: .cancel) {}
    Button("Mark as cancelled", role: .destructive) {
        subscriptionStore.markCancelledManually(id: subscription.id) // 复用 store 逻辑，别在视图里手改数组
    }
} message: {
    Text("Suber will stop tracking charges for \(subscription.name). If you haven't actually cancelled, you'll see the next bill on your card and can undo this.")
}
```

- **验证意见**：三处入口逐一核实成立：SubCardView.swift:87 右键菜单与 DayDetailView.swift:197 的 borderedProminent 按钮均一键直改状态、无确认无撤销（全库无 UndoManager），而 CancelConfirmationSheet.swift:85 对同一动作按 D5 决议做了两步确认，注释自述就是防误点——防护不一致确凿。附带核实：DateHelpers.swift:80 确实过滤 cancelled 使订阅从日历消失，markCancelledManually 会写入 cancellationConfirmed 并可触发庆祝横幅；且 SubCardView 路径比 finding 描述的更糟——markChangeAcknowledged(id: subscription.id) 因 id 与 change.id 不匹配实为 no-op，手改数组也从不调用 save()，误点破坏核心取消追踪流程，yellow 恰当。


### 🔵 建议（12 条）

#### U-08 · 备份解码失败的错误文案复用 restoreSummary，被渲染成绿色对勾的"成功"横幅

- **位置**：`Sources/Views/Settings/DataRestoreView.swift:239`　**规则**：UX-01　**裁决**：CONFIRMED

- **触发场景**：用户在 Restore from backup 选中一个损坏/schema 漂移的备份 → performRestore 解码失败 → restoreSummary = "Couldn't read this backup — try another source." → body 里唯一的呈现路径是 successBanner()：绿色 checkmark.circle.fill + success 底色包着一条错误消息。用户瞟一眼绿勾以为恢复成功，实际什么都没恢复。

- **证据**：

```swift
guard let subs = try? JSONDecoder.suberDecoder
    .decode([Subscription].self, from: source.subscriptionsData) else {
    restoreSummary = "Couldn't read this backup — try another source."
    return
}
```

- **修复**：

```swift
// 新增独立错误态 + 警示样式横幅：
@State private var restoreError: String?

// performRestore 失败分支改为：
restoreError = "Couldn't read this backup — try another source."
return
// （成功路径开头补 restoreError = nil）

// body 的 ScrollView 内、successBanner 旁：
if let err = restoreError { errorBanner(err) }

@ViewBuilder
private func errorBanner(_ text: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(Theme.warning)
        Text(text)
            .font(AppFont.regular(12))
            .foregroundColor(Theme.textPrimary)
        Spacer()
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warning.opacity(0.15)))
}
```

- **验证意见**：属实：restoreSummary 的唯一渲染路径是 successBanner()（绿色 checkmark.circle.fill + Theme.success 底色），而 239 行解码失败分支把错误文案写入同一状态；且 RestoreSourceLister 有意列出解码失败的备份源（count=0 仍展示），该分支真实可达。无数据丢失（live store 未动）、确认弹窗会提示 "0 subscriptions"，属 UI 误导性文案问题，blue 严重度恰当。

#### U-09 · 首启 onboarding 指路『Settings → General → iCloud sync』，但该开关 v1.9.0 已搬离 General

- **位置**：`Sources/Views/Onboarding/CloudSyncOnboardingSheet.swift:94`　**规则**：UX-07　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：新用户首启看到 iCloud 同步 consent，犹豫后点 'Skip — I'll decide later'，记住了脚注说的路径；之后想开启，进 设置→General 只看到 'Launch at login' 一项（SettingsView.swift:151-156 注释明确写着 v1.9.0 把 iCloud 搬去了顶部独立 section），找不到开关的用户很可能放弃 —— 而这个开关正是 v1.9.0 数据安全故事的核心（CHANGELOG 4 层保护）。onboarding 每账号只显示一次，错过即无第二次引导。

- **证据**：

```swift
Text("You can change this any time in Settings → General → iCloud sync.")
```

- **修复**：

```swift
Text("You can change this any time in Settings → iCloud Sync.")
// 该 sheet 全部文案同时补进 Localizable.xcstrings（文件头注释自认 'Copy is en-only for v1.9.0'，v1.9.2 已过两个版本）。
```

- **验证意见**：文案确实过时（第 94 行仍写 Settings → General → iCloud sync，而 SettingsView.swift:148-156 证实 v1.9.0 后 General 只剩 Launch at login），但 Settings 是单页滚动视图而非分级导航，iCloud Sync 恰好是页面最顶部第一个 section，用户按旧路径打开 Settings 必先看到开关本身，所谓"找不到而放弃"的场景不成立。属于应按建议修正的文案陈旧问题，为 polish 级（blue）。

#### U-10 · 主流程零无障碍标注：4 个顶栏纯图标导航按钮无标签，VoiceOver 只读出『按钮』

- **位置**：`Sources/Views/TopBarView.swift:24`　**规则**：UX-08　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：VoiceOver 用户打开 popover：顶栏 +/列表切换/图表/齿轮 4 个按钮全部无 accessibilityLabel 也无 .help，逐个听到 'button, button, button, button'，无法得知哪个是添加、哪个是设置。量化：全仓 accessibility* 修饰符共 11 处，全部集中在 5 个 Autopilot 横幅/角标文件（MenuBarBadgeView 2、FirstCatchBanner 2、CancellationSuccessBanner 2、SinceYouWereAwayBanner 4、AutopilotBannerView 1）；Calendar/List/Dashboard/Settings/表单/TopBar/两个 Widget 共 0 处。其余无标签纯图标按钮：CalendarView 翻月 chevron、DayDetailView xmark、SearchBarView 清除、SubscriptionFormView xmark、DataRestoreView xmark、BankImportView 返回/关闭。

- **同类站点**：Sources/Views/CalendarView.swift:70/79 翻月按钮；Sources/Views/DayDetailView.swift:33 关闭；Sources/Views/Components/SearchBarView.swift:18 清除；Sources/Views/SubscriptionFormView.swift:79 关闭；Sources/Views/Settings/DataRestoreView.swift:52 关闭；Sources/Views/Import/BankImportView.swift:59/76 返回/关闭

- **证据**：

```swift
BarButtonView(icon: "plus.circle", action: onAdd)
    .keyboardShortcut("n", modifiers: .command)
```

- **修复**：

```swift
// BarButtonView 增加 label 并同时供 VoiceOver 与 tooltip 使用：
private struct BarButtonView: View {
    let icon: String
    let label: LocalizedStringKey
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) { /* 原图标视图不变 */ }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel(Text(label))
            .help(label)
    }
}
// 调用点：BarButtonView(icon: "plus.circle", label: "Add subscription", action: onAdd) 等。
```

- **验证意见**：事实部分全部核实无误（4 个顶栏按钮确实无 accessibilityLabel/.help，全仓 11 处 accessibility 修饰符确实全在 5 个 Autopilot 文件），但核心失败场景『VoiceOver 只读出 button×4』被平台机制缓解：SwiftUI 的 Image(systemName:) 在 macOS 上会自动为 SF Symbols 提供内置无障碍标签（plus.circle→"Add"、calendar→"Calendar" 等），按钮可以区分，并非完全不可用。剩余问题是默认标签描述图形而非功能（如 chart.bar 读作"Bar Chart"而非"Dashboard"）以及缺少 .help 工具提示的一致性问题，属最佳实践/打磨级别，降为 blue。

#### U-11 · 汇率刷新静默失败且全程无新鲜度提示，硬编码兜底汇率可无限期参与所有金额计算

- **位置**：`Sources/Services/ExchangeRateService.swift:110`　**规则**：UX-10　**裁决**：DOWNGRADED（由 🟡 降级）

- **触发场景**：公司网络屏蔽 api.frankfurter.app（或用户长期离线）：refreshRates() catch 分支注释明写 'Silently fail'，UI 无任何提示；Dashboard 月支出、ChangeRow 年度影响、Widget 总额全部基于写死的近似汇率（如 RUB 92——俄卢布 2022 年后实际波动 60-110）持续计算，用户看到精确到分的数字却不知道底层汇率可能偏差 30%+。全 app 没有『汇率更新于何时』的展示，也没有手动刷新入口；刷新只在 popover onAppear 且距上次 >24h 时静默尝试一次。

- **证据**：

```swift
} catch {
    // Silently fail — we always have cached or fallback rates
}
```

- **修复**：

```swift
// 1) ExchangeRateService 暴露新鲜度：
var lastUpdatedAt: Date? {
    let ti = AppGroupStore.double(forKey: updatedAtKey)
    return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
}
// 2) SettingsView Currency section 尾部：
if let updated = ExchangeRateService.shared.lastUpdatedAt {
    Text("Rates updated \(updated.formatted(.relative(presentation: .named)))")
        .font(AppFont.regular(11)).foregroundColor(Theme.textDim)
} else {
    Text("Using built-in approximate rates — multi-currency totals may be off.")
        .font(AppFont.regular(11)).foregroundColor(Theme.warning)
}
```

- **验证意见**：事实全部属实：catch 静默失败（第 110 行准确）、全 app 无汇率新鲜度展示和手动刷新入口、Dashboard/Widget/Intent 均依赖缓存或硬编码兜底汇率。但『只尝试一次』说法不准——updatedAt 仅在成功时写入，每次 popover 打开都会重试，瞬时网络故障可自愈；『偏差 30%+』需要最极端货币（RUB）叠加网络被永久屏蔽这一边缘场景，且离线兜底是文件头注释明示的有意设计，无崩溃、无数据丢失、非计费金额。属于透明度/打磨类改进（展示更新时间+手动刷新），降级为 blue。

#### U-12 · iCloud 同步冲突被拒仅 NSLog，设置页同步状态永远是静态文案

- **位置**：`Sources/SuberApp.swift:236`　**规则**：UX-11　**裁决**：CONFIRMED

- **触发场景**：用户在旧 Mac 上删掉 3 个订阅后开机新 Mac：新 Mac 的 CloudSyncMerger 判定远端更小、REJECT 并只打 NSLog（代码内注释自认 'Future improvement: surface a non-blocking banner'）——用户以为两台机器已同步，实际数据永远分叉且无任何 UI 告知。设置页 iCloudSyncRow 只显示写死的 'On — subscriptions sync to your iCloud account.'，没有最近同步时间、没有错误态，同步失败与成功在 UI 上不可区分。

- **证据**：

```swift
case .rejectedAsStale(let l, let r):
    NSLog("Suber CloudSync: REJECTED stale remote (local=\(l) remote=\(r)). Use Settings → Data → Restore if intentional.")
```

- **修复**：

```swift
// 新增 MainActor 单例状态，SettingsView.iCloudSyncRow 订阅显示：
@MainActor final class CloudSyncUIStatus: ObservableObject {
    static let shared = CloudSyncUIStatus()
    @Published var lastEvent: String?
    @Published var lastEventAt: Date?
    func report(_ text: String) { lastEvent = text; lastEventAt = Date() }
}
// SuberApp.handleRemoteSubscriptions 三个分支分别 report：
case .applied(let merged):
    store.replaceAll(merged, reason: .cloudMerge)
    Task { @MainActor in CloudSyncUIStatus.shared.report("Synced \(merged.count) subscriptions") }
case .rejectedAsStale(let l, let r):
    Task { @MainActor in CloudSyncUIStatus.shared.report("Sync conflict: another Mac has \(r) subs, this Mac has \(l). Kept local — use Restore to inspect.") }
// iCloudSyncRow 中在状态行下追加 lastEvent + lastEventAt。
```

- **验证意见**：SuberApp.swift 第 236 行的 .rejectedAsStale 分支确实只打 NSLog（代码注释自认应加 banner），全代码库无任何同步状态 UI；SettingsView.swift 401-421 行的 iCloudSyncRow 仅按开关显示写死文案，无最近同步时间和错误态。场景可复现：旧 Mac 删 3 个订阅后 remote count 更小被 merger 规则 2 无条件拒绝，且后续反向推送会让删除项复活，用户全程无感知。属于 UX 打磨类问题（拒绝本身是防数据丢失的刻意设计），blue 定级恰当。

#### U-13 · 两套确认 UI 并存：自绘 dimmed 卡片 vs 系统 NSAlert，自绘卡无键盘支持

- **位置**：`Sources/Views/SettingsView.swift:249`　**规则**：UX-12　**裁决**：CONFIRMED

- **触发场景**：同一个设置页里：点『Clear all data』弹出自绘黑遮罩卡片（按 Esc/回车无效，Esc 反而可能整只 popover 收起、丢失上下文）；点『Import JSON』弹系统 NSAlert（自带 Esc=Cancel、回车=默认键）。完整清单——自绘 dimmed 卡：SettingsView 清空确认(249-308)、SubscriptionFormView 删除确认(266-312)；NSAlert .alert：SettingsView Import Error(310)/Replace all subscriptions?(315)/Restart(326)、DataRestoreView Restore this backup?(90)、CancelConfirmationSheet Mark cancelled(85)；第三种全屏 overlay sheet：CancelConfirmationSheet/AutopilotConsentSheet/IMAPAccountSheet/CloudSyncOnboardingSheet。PopoverOverlay.swift:27-31 已论证 .alert 在 popover 内是安全的，自绘卡没有存在必要。

- **同类站点**：Sources/Views/SubscriptionFormView.swift:266-312 自绘删除确认卡（同样无 Esc/回车）

- **证据**：

```swift
if showClearConfirm {
    // Full-screen dimmed backdrop
    Color.black.opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture { showClearConfirm = false }
```

- **修复**：

```swift
// 清空确认迁到 NSAlert 后端（键盘/焦点/样式免费获得，与 Import/Restore 一致）：
.alert("Clear All Data?", isPresented: $showClearConfirm) {
    Button("Cancel", role: .cancel) {}
    Button("Clear", role: .destructive) {
        subscriptionStore.clearAll()
        settingsStore.reset()
    }
} message: {
    Text("This will permanently delete all subscriptions and reset settings. Your current data is backed up automatically first.")
}
// SubscriptionFormView 删除确认同理迁移。
```

- **验证意见**：逐一核实全部成立：SettingsView.swift:249-308 自绘清空确认卡与同文件 310/315/326 的 NSAlert .alert 并存，自绘卡无任何 keyboardShortcut/键盘监听；SubscriptionFormView.swift:266-312 同样，且其注释"replaces .alert to stay within menu bar popover"的理由已被 PopoverOverlay.swift:26-31 自家文档推翻（NSAlert 在 popover 内安全）；其余自绘 sheet（CancelConfirmationSheet 等）都配了 .cancelAction/.defaultAction，唯独这两张卡缺失。无数据丢失或崩溃路径，属一致性/键盘可达性打磨问题，blue 恰当。

#### U-14 · 视觉系统漂移：15 处 hex 色绕过 Theme、11 种圆角值、77 处系统字号绕过 AppFont，状态色浅色模式对比度 1.67–2.54:1

- **位置**：`Sources/Views/DashboardView.swift:12`　**规则**：UX-13　**裁决**：CONFIRMED

- **触发场景**：量化盘点——① Theme 外硬编码 Color(hex:)：DashboardView 12 色图表盘 + 第 205 行趋势条 '6366f1' + SubscriptionFormView 两处步进按钮 '38b2ac'（teal，全 app 唯一一处，与黑白灰主题割裂）；② cornerRadius 分布：8(×33)、6(×11)、10(×11)、12(×8)、5/3/2/4/14/16 各 1-3 处 + LogoView 的 size*0.2，共 11 种取值无 token；③ .font(.system(size:)) 主 app 64 处 + Widget 13 处绕过 AppFont（Widget 整体不用 Space Grotesk，与主 app 字体断裂）；④ 状态色白底对比度实测：active #4ade80=1.74:1、warning #fbbf24=1.67:1、trial #60a5fa=2.54:1，全部低于 WCAG 3:1 非文本下限（深色模式 #1a1a1a 底则 >9:1 通过）；danger #ff5555 作为 11pt 'Clear all data' 文字色对白底 3.07:1，低于 4.5:1 文本下限。浅色模式用户几乎看不清 6pt 状态点，Import 评审页 'High/Med' 徽章文字同样用这些色作前景。

- **同类站点**：Sources/Views/SubscriptionFormView.swift:119/149 Color(hex: "38b2ac")；Sources/Views/DashboardView.swift:205；SuberWidget/*.swift 13 处 .font(.system(size:)) 不用 AppFont

- **证据**：

```swift
private let categoryColors: [Color] = [
    Color(hex: "6366f1"),  // indigo
    Color(hex: "f59e0b"),  // amber
```

- **修复**：

```swift
// Constants.swift Theme 内集中定义并做明暗自适应：
extension Theme {
    static let chartPalette: [Color] = [/* 迁入 12 色 */]
    static let accentTeal = Color(hex: "38b2ac")
    // 状态色浅色模式换深一档（对比 ≥3:1）：
    static let success = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)   // #4ade80
            : NSColor(red: 0.09, green: 0.55, blue: 0.27, alpha: 1)   // #16893f ≈4.1:1 on white
    })
    enum Radius { static let s: CGFloat = 6; static let m: CGFloat = 8; static let l: CGFloat = 12; static let xl: CGFloat = 16 }
}
```

- **验证意见**：核心主张全部实证成立：15 处 Theme 外 hex 色、11 种圆角值均逐一数出吻合；对比度手工重算 #4ade80=1.74、#fbbf24=1.67、#60a5fa=2.54:1，且 Theme 其余颜色均明暗自适应而状态色注释明写"same in both modes"，app 未强制深色模式，浅色下 6pt 状态点、Import 页 High/Med 徽章文字（9pt 前景即状态色）和 11pt Theme.danger 'Clear all data'（≈3.0:1）确实低于 WCAG 下限。唯一夸大处：主 app 64 处 .system(size:) 中 62 处是 SF Symbol 图标尺寸（AppFont 本就不适用），仅 Widget 13 处（多为 Text 且整个 Widget 无 Space Grotesk）构成真实字体断裂；此偏差不影响 blue（打磨级）定级。

#### U-15 · IA 错位：英雄数字与 Add/Import CTA 只在无标签图标背后的 Dashboard 空状态，默认 Calendar 首屏只有一行灰字

- **位置**：`Sources/Views/MenuBarView.swift:26`　**规则**：UX-14　**裁决**：CONFIRMED

- **触发场景**：代码还原的真实首启序列：① 用户点菜单栏图标 → 480×520 popover 打开，currentView 默认 .calendar；② onAppear 同帧 presentICloudOnboardingIfNeeded 用 CloudSyncOnboardingSheet 全屏盖住内容（zIndex 2），首屏第一眼是同步 consent 而非产品；③ 关掉后是一整月空日历格，唯一引导是 11pt 灰字 'Tap + or ⌘N to add your first one'（桌面端却说 Tap）；④ 真正设计好的空状态——图标+文案+黑色 'Add subscription' 胶囊按钮+'or import a bank statement'——在 DashboardView.emptyState，但 Dashboard 藏在无标签、无 tooltip 的 chart.bar 图标后（UX-08），新用户不知道它存在。核心转化动作（加第一条订阅）与默认落地页错位。

- **证据**：

```swift
@State private var currentView: AppView = .calendar
```

- **修复**：

```swift
// CalendarView 空状态复用 Dashboard 的 CTA（CalendarView 需接收 onAdd）：
if subscriptionStore.subscriptions.isEmpty {
    VStack(spacing: 10) {
        Text("No subscriptions yet")
            .font(AppFont.medium(13)).foregroundColor(Theme.textPrimary)
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text("Add subscription").font(AppFont.medium(12))
            }
            .foregroundColor(Theme.bgPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.textPrimary).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        Text("or press ⌘N").font(AppFont.regular(11)).foregroundColor(Theme.textDim)
    }
    .padding(.vertical, 12)
}
// MenuBarView: CalendarView(onEdit:…, onAdd: { showAddForm = true })
```

- **验证意见**：逐项核实成立：currentView 默认 .calendar（MenuBarView.swift:26）；首启 onAppear 经 OverlayPresenter 以 zIndex 2 全屏呈现 CloudSyncOnboardingSheet（SuberApp.swift:356/405）；日历空状态仅为两行灰字且桌面端用 "Tap"（CalendarView.swift:151-161）；带 CTA 胶囊按钮和银行账单导入链接的完整空状态只存在于 DashboardView.emptyState（DashboardView.swift:64-114），而 Dashboard 入口是无标签、无 .help() tooltip 的 chart.bar 图标（TopBarView.swift:31-35）。顶栏有可见的 + 按钮作为兜底引导，用户不至于完全迷失，故维持 blue（打磨级 IA 问题）恰当。

#### U-16 · 卡片点击=编辑零可供性（无指针/无菜单项/无 chevron），空状态 📦🔍 emoji 与全 app SF Symbol 体系混用

- **位置**：`Sources/Views/ListView.swift:88`　**规则**：UX-15　**裁决**：CONFIRMED

- **触发场景**：List 页编辑唯一入口是整卡 onTapGesture，但卡片 hover 只变背景色、鼠标不变 pointingHand、无 chevron、右键菜单里只有『Open cancel page…』（右键反而暗示取消是唯一操作）——新用户找不到怎么改价格。同文件 67 行空状态用 32pt 的 📦/🔍 emoji，而 Dashboard 空状态(chart.bar.doc.horizontal)、Changes 窗口(checkmark.circle)、DataRestoreView(tray) 全用 SF Symbol，且 emoji 不随明暗模式与文字色调统一。

- **同类站点**：Sources/Views/ListView.swift:67 Text(subscriptionStore.subscriptions.isEmpty ? "📦" : "🔍")

- **证据**：

```swift
SubCardView(
    subscription: sub,
    onOpenCancelPage: { presentCancelConfirmation(for: sub) }
)
.environmentObject(subscriptionStore)
.onTapGesture { onEdit(sub) }
```

- **修复**：

```swift
// 1) SubCardView 增加编辑可供性（hover 指针 + 菜单项）。ListView 调用处：
SubCardView(subscription: sub, onOpenCancelPage: { presentCancelConfirmation(for: sub) })
    .environmentObject(subscriptionStore)
    .onTapGesture { onEdit(sub) }
    .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
    .contextMenu { Button("Edit…") { onEdit(sub) } } // 需把 onEdit 传入或在此外层挂 contextMenu
// 2) 空状态换 SF Symbol：
Image(systemName: subscriptionStore.subscriptions.isEmpty ? "shippingbox" : "magnifyingglass")
    .font(.system(size: 32, weight: .light))
    .foregroundColor(Theme.textDim)
```

- **验证意见**：逐项核实成立：ListView.swift:88 的整卡 onTapGesture 确是列表页唯一编辑入口，SubCardView 的 hover 仅改背景/描边色（无 NSCursor.pointingHand，全代码库无任何光标处理），右键菜单只有取消相关项无 Edit，也无 chevron 或 tooltip 提示；67 行 📦/🔍 是全 app 唯一的 emoji 空状态，Dashboard/DataRestore/ChangesList 空状态均用 SF Symbol。属可发现性与一致性打磨问题，blue 定级恰当。

#### U-17 · 10 种日期格式并存，且固定 dateFormat 模板不随中文语序重排

- **位置**：`Sources/Views/SubscriptionFormView.swift:499`　**规则**：UX-16　**裁决**：CONFIRMED

- **触发场景**：同一用户一次操作路径里遇到：表单日期 '2026/07/10'(yyyy/MM/dd)、日历头 'July 2026'(MMMM yyyy)、日详情 'Jul 10, 2026'(MMM d, yyyy)、导入评审 'Jul 10'(MMM d)、待取消横幅 dateStyle .medium、设置页 Last checked .abbreviated+.shortened、两处 RelativeDateTimeFormatter .short、导出文件名 yyyy-MM-dd、卡片/Widget 'Today/Tomorrow/in 3d'——4 种绝对格式 + 系统风格混排。且固定 pattern 在 zh 环境不重排语序：'MMMM yyyy' 输出『七月 2026』而非『2026年7月』（setLocalizedDateFormatFromTemplate 才会重排）。

- **同类站点**：Sources/Utilities/DateHelpers.swift:105 'MMMM yyyy'；DateHelpers.swift:111 'MMM d, yyyy'；Sources/Views/Import/ImportReviewListView.swift:298 'MMM d'；Sources/Views/Autopilot/PendingCancellationIndicator.swift:134 dateStyle .medium；Sources/Views/SettingsView.swift:470 .formatted(date:.abbreviated,time:.shortened)；SettingsView.swift:488 'yyyy-MM-dd'(文件名，可保留)；AutopilotSettingsSection.swift:344 与 ChangeRowView.swift:338 RelativeDateTimeFormatter；SubscriptionFormView.swift:505 'EEEE, MMM d, yyyy'（死代码）

- **证据**：

```swift
f.dateFormat = "yyyy/MM/dd"
```

- **修复**：

```swift
// DateHelpers 收敛为 locale 感知模板，各视图统一调用：
private static let monthYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("yMMMM")   // en: July 2026 / zh: 2026年7月
    return f
}()
private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("yMMMd")   // en: Jul 10, 2026 / zh: 2026年7月10日
    return f
}()
// SubscriptionFormView.formDateFormatter 改用 DateHelpers.formatDate；删除未使用的 longDateFormatter (line 503-507, 无调用点)。
```

- **验证意见**：所有引用行号逐一核实无误：UI 层确实并存约 10 种日期格式（表单 yyyy/MM/dd、日历头 MMMM yyyy、日详情 MMM d, yyyy、导入 MMM d、.medium、.abbreviated+.shortened、两处 RelativeDateTimeFormatter、Widget/卡片 Today/Tomorrow/in Nd），且这些 UI formatter 均未固定 locale 也未用 setLocalizedDateFormatFromTemplate；而应用通过 Localizable.xcstrings 和 LanguageOverride 正式支持 zh-Hans，切中文后 "MMMM yyyy" 确实输出「七月 2026」而非「2026年7月」，反例可复现。longDateFormatter (503-507) 确为死代码。属 UI 一致性/本地化打磨问题，blue 定级恰当。

#### U-18 · 两个 Widget 均无 widgetURL 深链，点按 LSUIElement 应用没有任何可见反应

- **位置**：`SuberWidget/SuberWidget.swift:10`　**规则**：UX-17　**裁决**：CONFIRMED

- **触发场景**：用户在通知中心看到 Upcoming Bills Widget 里 Netflix 'Tomorrow'，点按想去处理：Suber 是 LSUIElement 菜单栏应用、无主窗口，点按后没有窗口弹出、popover 也不会打开——看起来像点了没反应。全仓 widgetURL 检索 0 处，而 URLSchemeHandler 已支持 suber://changes（打开 Changes 窗口）与 suber://add，深链基础设施是现成的。

- **同类站点**：SuberWidget/SuberWidget.swift:26 UpcomingBillingWidget 同样缺失

- **证据**：

```swift
StaticConfiguration(kind: kind, provider: SuberTimelineProvider()) { entry in
    SmallSpendWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
}
```

- **修复**：

```swift
StaticConfiguration(kind: kind, provider: SuberTimelineProvider()) { entry in
    SmallSpendWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "suber://changes"))   // 复用现有 URLSchemeHandler.openChanges → 打开可见窗口
}
// MediumUpcomingWidget 同样加 .widgetURL。SuberApp 已 .handlesExternalEvents(matching: ["suber"]) (SuberApp.swift:59)。
```

- **验证意见**：全仓 grep 确认 widgetURL 为 0 处、两个 Widget 及其视图文件均无 Link/openURL 任何深链；Info.plist:31 确认 LSUIElement，且无 AppDelegate reopen 处理，点按 Widget 确实不会有任何可见反应。suber://changes 路由（URLSchemeHandler + SuberApp.swift:59/170-183）已被通知点击路径使用并有测试覆盖，修复方案成立；属打磨类问题，blue 定级恰当。

#### U-19 · Changes 窗口内容 minWidth 640 > Window defaultSize 620，首开即溢出裁剪行尾按钮

- **位置**：`Sources/Views/Autopilot/ChangesListView.swift:63`　**规则**：UX-18　**裁决**：CONFIRMED

- **触发场景**：用户点菜单栏红色角标（suber://changes）→ Window("import") 以 defaultSize 620×620 打开，内层 ChangesListView 要求 minWidth 640：内容比窗口宽 20pt，价格变化行右端的 'Ignore' 按钮被裁掉一截；外层 ImportWindowView 还声明 minWidth 520，用户可把窗口拖到 520 宽，裁剪加剧到 120pt。文件头注释自己写着规格 'D12 says min 640×480, default 760×520'，但 SuberApp.swift:72 实际写的是 620×620——代码与自述规格互相矛盾。

- **证据**：

```swift
.frame(minWidth: 640, minHeight: 480)
```

- **修复**：

```swift
// SuberApp.swift:72 按 D12 规格改：
.defaultSize(width: 760, height: 520)
// ImportWindowView.swift:16 外层最小宽对齐内容最大需求：
.frame(minWidth: 640, minHeight: 520)
```

- **验证意见**：静态推导成立：外层 ImportWindowView 的 frame(minWidth: 520) 截断了子视图 640 的最小宽度传播，窗口 contentMinSize 实为 520，故 defaultSize 620 不会被系统钳到 640——首开时 640 宽的 ChangesListView 在 620 窗口中居中溢出 20pt（每侧裁 10pt，主要吃掉 16pt 行内边距，滚动条压住行尾按钮），且窗口可缩到 520 使 Ignore 等行尾按钮被实裁约 44pt；文件头 D12 规格注释（min 640×480 / default 760×520）与 SuberApp.swift:72 的 620×620 确实自相矛盾。首开即"按钮被裁掉一截"略有夸大，但缺陷机制真实，blue（打磨级）定级恰当。


## 附录 A：被推翻的候选发现

- `Sources/Views/MenuBarView.swift:92` [STATE-06] 编辑表单持有已被云同步删除的订阅副本，Save 静默 no-op，用户输入无提示丢失 — 所述触发路径不可复现：云同步唯一入口是 CloudSyncMerger.mergeSubscriptions，其规则 2 会拒绝任何比本地更小的远端列表（rejectedAsStale，本地不动），规则 3 按 id 合并且显式保留本地独有条目——即删除操作根本不会经云同步传播到 Mac A，replaceAll 的 cloudMerge 收缩 tripwire 与 CloudSyncMergerTests 回归测试共同保证该不变式。update(id:) 的静默 guard 属实，但唯一能真正移除被编辑订阅的路径是用户在独立导入窗口主动执行 userImport/userRestore 整体替换（编辑覆盖层遮住 popover 内所有删除入口），属极边缘的用户自毁场景，建议的 onChange 防御仅为可选加固。

## 附录 B：各领域审计员结论笔记

### A-imap-concurrency

【强制问题逐条回答】

Q1 — IMAPClient 三个 continuation 站点逐一核查（行号按当前文件）：
① connect()（L89–113，超时闭包 L109）：IMAPContinuationGuard 已应用于全部 4 个 resume 点（.ready/.failed/.cancelled/timeout）。double-resume：不可能，NSLock 一次性 check-and-set。泄漏（永不 resume）：不可能——asyncAfter 兜底定时器从不被取消、必然触发。actor deinit 后 resume：不可能——continuation 挂起期间调用方 task 的调用帧持有 client（actor）强引用，actor 不可能先亡；resume 之后的迟到回调只触碰 guarded（no-op）和 weak conn。唯一残留缺陷：超时闭包里 conn?.cancel() 这个副作用未受 guard 保护，连接成功后定时器照样 cancel（见 finding TIMEOUT-01，blue）。
② sendCommand()（L259–271，超时闭包 L268）：send completion 与 timeout 双源均经 guard ✓。completion 永不触发（半开连接）→ asyncAfter 兜底，无泄漏；超时先胜后 completion 迟到 → no-op；回调不触碰任何 actor 状态。干净。
③ readMoreIntoBuffer()（L418–443；L421 receive 回调、L427 Task hop 内 resume、L440 超时闭包）：四条 resume 路径（error/data/isComplete/timeout）全部经 guard。data 路径先 `Task { await self?.appendToBuffer(data) }` hop 进 actor 再 resumeSuccess——即使 self 已释放，可选链 no-op 后仍会 resume，无泄漏；actor reentrancy 保证挂起中的 continuation 不阻塞 appendToBuffer，无死锁。timeout 先胜时迟到的 append 只是向仍存活（或已弱化为 nil）的 buffer 写入将被 close() 丢弃的数据，无 crash。
结论：三站点 guard 应用完整，无 double-resume、无 continuation 泄漏、无 deinit 后 resume。

Q2 — IMAPContinuationGuard 本身正确。check-and-set 在 NSLock 临界区内原子完成，continuation.resume 在锁外执行（避免持锁跨 resume）；NSLock 提供 acquire/release 内存序，`resumed` 受锁保护，`continuation` 为 let、经 GCD/NWConnection 闭包入队的 happens-before 边安全发布；CheckedContinuation 本身 Sendable，@unchecked Sendable 理由成立。测试（IMAPContinuationGuardTests）已覆盖 first-wins 语义与 100 并发竞争。两个小注（非 finding）：(a) 泛型 T 未约束 Sendable，当前仅以 Void 实例化，若未来用非 Sendable T 会静默跨线程传值，建议加 `<T: Sendable>`; (b) 若两个 resume 源都永不触发，guard deinit 时 continuation 泄漏——但每站点都有必然触发的 asyncAfter 兜底，实际不可达。

Q3 — actor 隔离干净。IMAPClient 无 nonisolated 逃逸口；host/port 为 let。NWConnection 队列回调不直接触碰 actor 状态：stateUpdateHandler / send completion 只碰 guarded 与 weak conn；receive 回调唯一的状态写入（receiveBuffer）经 Task hop 回 actor 隔离执行；connection/nextTagNumber/receiveBuffer 的所有读写都在 actor 方法内。可维护性注记：connect() 失败后 connection 残留非 nil，同一实例重调 connect() 会被 `guard connection == nil else { return }` 放行假装成功——当前 bridge 每次 scan/ping 新建 client、失败即 close()，该路径不可达，未列 finding。

Q4 — teardown 安全。close() cancel 后迟到的 receive/stateUpdate 回调捕获的都是 weak self / weak conn + guarded：resume 是 no-op，状态访问走可选链，无已释放内存访问、无 crash。超时后 caller 链上 close() 会在旧 receive 仍挂起时发起 LOGOUT 的新收发，旧回调迟到的数据只污染即将被丢弃的 client 的 buffer，无影响。反向问题（cancel 活连接）是 finding TIMEOUT-01。stateUpdateHandler 仅在 .ready 清空（RES-01），失败路径上残留的 handler 随 NWConnection 释放而释放，无保留环。

Q5 — 凭据处理干净。Keychain：update-then-add 模式、kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly（后台可读、不进 iCloud Keychain）、delete 幂等，round-trip 有测试覆盖（IMAPBridgeTests.testKeychainRoundTrip）。密码仅在 LOGIN 命令字符串中短暂存在于内存（GenericIMAPBridge 按 D8 在 scan/ping 时 resolve、用完即弃）。目录内全部 3 处日志（IMAPClient.swift:305 记录服务器返回的 unexpected line；CompositeMailBridge.swift:48/86 记录 error.localizedDescription）均不含命令原文或密码；permissionDenied(detail:) 透传的是服务器响应文本，不含凭据。无凭据进入日志 / UserDefaults / 磁盘。

【无发现的类别 · clean bill】
- SAFETY：除 finding SAFETY-05（负数 literal）外无力解包/强转/try! 风险——IMAPProvider QuickLink 的 URL(string:)! 全为硬编码常量（规则明示例外）；GenericIMAPBridge.orFoldSubjects 的 keywords.last! 有 count>=2 分支保证；IMAPClient 所有正则用 try?、group 访问有 numberOfRanges 边界检查；数组下标（select 的 parts[2]、extractDomain 的 labels[count-2]）均有 count 守卫。
- MEM：无保留环。所有逃逸闭包捕获 weak self / weak conn 或不捕获 self；MailWatchdog scheduler 闭包 [weak self]、cancelDailyScan 有 invalidate；无 Timer / Combine 订阅。
- CONC-01/03：MailWatchdog 整类 @MainActor，全部 @Published 写入在 MainActor 上 ✓。

【其他注记（未列 finding 的观察）】
1. CompositeMailBridge.scan 把非 Sendable 的 MailBridge 存在传入 TaskGroup.addTask（CONC-05）：当前两个生产实现（AppleMailBridge 无状态、GenericIMAPBridge 全 let）无实际竞态，故不构成 runtime finding；但 Swift 6 strict concurrency 会编译报错，建议 `protocol MailBridge: Sendable`。
2. MailWatchdog 逻辑注记：persistCursors 写入 mailwatchdog.cursor.* 但代码中从未读回（oldestSinceDate 只用 lastScanDateKey），注释宣称的 “filter in-proc by account cursors” 未实现，增量语义靠 “lastScan-1day + ChangeDetector 下游去重” 兜底。非崩溃、无错账（重复候选被 diff 吸收），属功能债。
3. AppleMailBridge.runOSAScript 轮询中 `try? await Task.sleep` 吞掉 CancellationError：若调用方 task 被取消，循环将 100% CPU 空转直到 deadline（最长 60s）。当前所有调用方（AutopilotSettingsSection 的按钮 Task、scheduler 的 Task）从不取消，路径不可达，故仅记 notes；若未来改用 SwiftUI .task {} 触发扫描需先修此处（catch 后 terminate + rethrow）。
4. 测试覆盖评估：IMAPContinuationGuard 的竞争语义已充分覆盖；MailWatchdog 状态机/游标/并发守卫已覆盖；IMAPClient 线协议解析（literal、ENVELOPE、FETCH）与 AppleMailBridge 的 osascript 大输出路径零覆盖——两个 yellow finding（PROC-01、SAFETY-05）都落在无测试区，建议补 parseTrailingLiteralSize 的负数/超大值单测与 parseOutput 的多 locale 日期单测。
（按要求未运行 xcodebuild，纯静态分析。）

### B-state-persistence

【指定问题回答】

Q1 — CloudSyncService 线程追踪：干净。NSUbiquitousKeyValueStore.didChangeExternallyNotification 在任意线程投递到 selector 目标 handleRemoteChange（CloudSyncService.swift:87，非 @MainActor 类，selector 目标本身非隔离——不存在 @MainActor 方法被 selector off-main 直呼的情况）。该方法在通知线程只做线程安全操作（读 userInfo、读 kvStore；三个 Data 是 Sendable 值类型），全部下游状态变更经由唯一一个 DispatchQueue.main.async（第 100 行）跳主线程。主线程侧：onRemoteChange 闭包 → SuberApp.handleRemoteSubscriptions / handleRemoteSettings（App 协议 @MainActor，成员继承隔离）→ SubscriptionStore.replaceAll / mergeRemoteChanges、SettingsStore.update（两个 store 均 @MainActor 类）。结论：每条 @Published 变更路径都已 main-hop。startSync 先于 onRemoteChange 赋值不构成竞态（通知异步投递，赋值在同一 main tick 完成）。残余瑕疵：observing/onRemoteChange 无同步保护 + push* 可被 AppIntent 后台线程调用（见 CONC-05 blue 项）；selector observer 不 removeObserver 无风险（单例永不释放）。

Q2 — try? encode 两处拆解：encode 失败与写盘失败是两类事故。(a) encode 失败：Subscription 含 Double amount，JSONEncoder 默认 .throw 策略下非有限值（用户输入 \"inf\"/\"1e999\"，见 SAFETY-07 红项）必抛——此时 SubscriptionStore.swift:123 静默跳过 replaceAll 的替换前快照（恢复点丢失，用户到需要恢复那天才发现），StorageService.saveSubscriptions 全线静默失败（所有后续变更仅存内存，重启回退）。SubscriptionChange/AppSettings 不含裸 Double（金额存为 String/dedupHash），第 383 行的 encode 实际近乎不可能失败。(b) 写盘失败（磁盘满/ACL）：AppGroupStore.set 有 NSLog 但返回值被所有调用方忽略；saveSubscriptions 还会在写盘失败后照常 push KVS（云比盘新）。丢失内容：本次会话全部变更；发现时机：下次启动列表回退，或 widget（读盘）与 App（读内存）显示不一致。第 383 行 mergeRemoteChanges 特有后果：合并结果只在内存，退出即丢，且刻意不回推 KVS，故远端也不会补救本地。修复见 DATA-02 黄项。

Q3 — 迁移 decode 失败路径：当前零风险——runIfNeeded 于 v1.8.4 硬禁用（第 60-63 行直接 return），且被 LegacyDataMigrationTests 与 DataPersistenceLifecycleTests 双重回归锁定。死代码体内审查：decode 失败 → NSLog + return，legacy plist 仅被读取、从不删除/改写 → 源数据保留；但 `defer { standard.set(true, forKey: migrationDoneKey) }` 在 decode 失败时同样置位 done 标志——若未来重新启用，一次瞬时读失败会永久烧掉唯一的迁移机会（重启用前必须把置位移到成功路径）。部分写窗口：AppGroupStore.set 与 DataBackupManager.snapshot 均用 .atomic，单文件无 torn write（DataPersistenceLifecycleTests test 6 已覆盖并发写）；跨 key（subs/settings/changes 三文件）无事务性，RestoreSourceLister 用 ±5s mtime 启发式配对，可接受。另：SuberApp.swift:6-11 的注释仍宣称迁移会\"rescue data\"，与硬禁用现实不符，建议顺手改掉。

Q4 — SuberApp 自定义 ISO 日期解析（273-291 行）遇畸形输入：三段解析（带毫秒 ISO → 标准 ISO → yyyy-MM-dd）全失败后抛 DecodingError.dataCorruptedError，不会崩溃。全部调用点均 try? 吞掉：handleRemoteSubscriptions/handleRemoteSettings → NSLog 后忽略远端更新；setupCloudSync 的 changes 解码 → 跳过合并；RestoreSourceLister.decodeSubscriptionCount → 显示 0 但源仍列出；DataRestoreView.performRestore → 提示换备份源、live 数据不动。失败模式是\"静默忽略\"而非崩溃，符合设计意图。实际缺陷是性能：闭包内每个日期值新建最多 3 个 formatter（PERF-01 blue，StorageService 已有缓存版可对齐）。无效但格式合法的日期（如 \"2026-02-30\"）被非宽松 DateFormatter 拒绝 → 同样走抛错路径，安全。

Q5 — 备份轮换能否被损坏数据刷穿：单次损坏写入不能——环深 10，且 replaceAll 在覆盖前额外快照 outgoing（clearAll/userRestore/cloudMerge 都过这个 chokepoint），CloudSyncMerger Rule 2 挡住了远端缩水覆盖。但存在两条现实的\"刷穿\"路径：(1) DATA-04 黄项：no-change cloudMerge 每条远端通知烧 2 个快照槽，对端 5 次保存即把本端 10 格环全部轮换为当前态副本——若当前态已中毒（如通过 Rule 3 混入 updatedAt 靠前的坏条目），好副本将在几分钟内被全部挤出；(2) DATA-01 红项（本次审计最高价值发现）：6 个未沙箱的测试文件直接对真实容器 removeObject + 写测试数据，一次 xcodebuild test 就把真实 Backups/ 环刷成 \"Netflix 15.99\" 测试快照并删掉 live 文件——与 v1.8.0 事故中\"月前测试快照\"的来源模式完全吻合。建议：修 DATA-04 的 no-change 短路 + 给 DataBackupManager 增加按天 pinned 快照层 + 立即沙箱化全部测试。

【干净项声明】审计范围内：无 force unwrap 风险（Subscription.swift:224 的 parsedAmount! 有前置 nil 判定）、无 as!、无 try!、无隐式解包声明；数组下标均有界（ChangeDetector group[0] 前有 count>=2 过滤，DataBackupManager backups[max...] 前有 count 守卫，buildBridge bridges[0] 恒非空）；除零已防（effectiveAmount 用 max(splitCount,1)，priceChange 的相对比较有 previousUSD>0 守卫）；STATE 规则干净（@StateObject 用法正确、Window scene 的 environmentObject 显式注入齐全、无 body 内改状态）；MEM 规则干净（onScanComplete/loadExistingSubscriptions/onRemoteChange 均 weak 捕获 store，CloudSyncService 单例的 selector observer 无悬垂风险，无未存储的 Combine sink——onReceive 由 SwiftUI 托管）。测试覆盖缺口（供参考，非缺陷）：无非有限金额输入测试、无删除跨设备传播测试、无磁盘写失败注入测试、SubscriptionStoreTests 未覆盖 recordAndPersist/mergeRemoteChanges。另记两处非崩溃 UX quirk：markChangeAcknowledged 的已读状态因 dedupHash 相同被 mergeRemoteChanges 过滤，永不跨设备同步（另一台设备徽章不清零）；DataRestoreView.performRestore 恢复 changes 时内存侧未套 prune（与 recordAndPersist 第 181 行的自我修正不一致），重启前 UI 可能短暂显示 >200 条。

### C-services-system

【指定问题回答】

Q1 NotificationService(NSLock + UN 回调)— 干净。锁的获取顺序:scheduleReminders 在 223-225 行取锁/放锁(同步路径),getPendingNotificationRequests 回调在 230-232 行取锁/放锁。全文件只有这两个不相交的临界区,均不嵌套、不在持锁状态下注册回调,不存在"回调内再取已持有的锁"的路径 → 无重入死锁可能。UNUserNotificationCenter 的 completion handler 到达于其内部后台串行队列(非主线程);回调内只读 latestExpectedIDs、调用线程安全的 removePendingNotificationRequests 和 print,不触碰任何 UI/@Published 状态 → 无 CONC-01 违规。oxford() 的 items.last! 被 switch count>=3 分支保护(SAFETY-01 例外,非 finding)。测试仅覆盖 composeChangesBody 文案(NotificationServiceGroupingTests),调度/锁路径无测试但静态审查干净。

Q2 ExchangeRateService(网络失败路径)— 失败路径本身是刻意设计:catch 静默返回,继续用缓存或硬编码 fallback(注释明示 offline-first),无过期提示是产品取舍,不算缺陷;JSON 解析全部用 JSONSerialization + 条件转型 + guard(87-97 行),另有 count>10 合理性闸(100 行),无任何强制解包 → 该项干净。真正的问题是 rates 字典的跨线程无锁读写(见红色 finding,ExchangeRateService.swift:102)。

Q3 WindowActivationCoordinator(~40 行 asyncAfter)— 无崩溃风险。闭包投递在主队列,NSApp.windows 在主线程枚举返回的是活的强引用数组;popover/窗口在 0.15s 截止前关闭时,窗口要么已从数组移除要么 isVisible==false,不存在悬垂指针或 nil 解包路径。唯一的竞态是外观级的:若用户在 0.15s 窗口期内又打开新窗口且其 NSWindow 尚未 isVisible,策略会被误flip回 .accessory,新窗口可能失去 Dock 图标/激活 —— 纯 cosmetic、低频,不构成 finding。

Q4 BankImport CSV(畸形/编码/大文件/小数)— 畸形 CSV:CSVParser 手写状态机对未闭合引号只是吞到 EOF,永不越界,不崩溃;编码错误:decode() UTF-8→GB18030 依次尝试,失败 throw ParseError.decodingFailed,BankImportView catch 后进 error stage,优雅失败;大文件:两处问题 — GenericFormat.rowHasNoNegatives O(n²)(黄色 finding)且 BankImportView 的 Task{} 继承 MainActor 导致整条解析链在主线程执行(卡死非崩溃);小数 locale:欧式小数逗号被当千分位剥除 → 金额放大 100 倍(红色 finding,三个 Format 共用);另有 MM/dd 先于 dd/MM 的日期歧义(蓝色 finding)。StatementFormatTests 覆盖了引号/CRLF/BOM/三种格式主路径,但无小数逗号、无 dd/MM、无性能用例。

Q5 Intents(进程外上下文)— App 目标的 AppIntents 在 App 自身进程内执行(未运行时由系统后台拉起),AppGroupStore 是原子文件写,GetSpendIntent 纯读安全(最坏读到略旧快照);AddSubscriptionIntent 的 appendSubscription 自身是单调用读-改-写、内部一致,但与运行中 SubscriptionStore 的"启动读一次内存、每次变更整体快照写回"模型构成 lost-update:Siri 加的订阅会被 App 下一次任何保存覆盖掉 —— 代码注释(StorageService.swift:107-116)自己承认了这个 hazard 并标注为 deferred follow-up,但对常驻菜单栏应用这几乎必然发生,按合同定级 red(数据丢失),修复代码见 finding。ExchangeRateService.shared 在 Intent 里的使用叠加了 Q2 的 rates 竞态(读端之一)。

【编译器证据裁定:ImageCache 68-108】当前代码的两个 await(71、103 行)都在 unlock 之后,临界区内无挂起点 → 今天没有真实死锁;竞争时只是短暂阻塞一条协作线程(临界区仅字典操作)。诊断的实际含义:(a) Swift 6 language mode 下是硬编译错误,阻塞迁移;(b) 模式脆弱,任何把 await 挪进临界区的重构都会造成"跨线程 unlock NSLock(未定义行为)+ 协作线程池饿死"。正确修法排序:NSLock.withLock 闭包(最小改动,保住 cachedImage/cacheKey 的同步 API,SwiftUI body 直接调用不受影响)> OSAllocatedUnfairLock(等价,macOS 13+)> actor(过度修复,强迫调用链全 await)。已给出 withLock 重写(黄色 finding)。

【干净项声明】OneTapCancelService、URLSchemeHandler、MerchantNormalizer、RecurringChargeDetector、Transaction、StatementFormat 协议层、AlipayFormat/WechatFormat(除共用的 parseAmount/parseDate 缺陷外)审查干净:无强制解包/强转/try!、下标访问均有 count 守卫(如 AlipayFormat:41 的 where row.count > max(...))、RecurringChargeDetector:104 的 first/last 用 guard 显式保护。SubscriptionTextParser 的正则全部 try? 构造、firstMatchGroups 对 range 逐个判空,无崩溃路径(仅蓝色金额质量项)。LanguageOverride 除引号注入外干净(launchPath 已弃用属 cosmetic,未列 finding)。UpdateService 逻辑干净,仅幂等/订阅累积一项(蓝色)。ImageRecognitionService 的 downsample 对 CGContext 构造失败有 nil 回退;handler.perform 是同步重活跑在协作线程上,阻塞但有界,未列 finding。ImageCache.cachedImage 会在主线程做同步小文件磁盘读(favicon 尺寸小),可接受,未列 finding。

【审计范围外但已核实的关联事实】LogoView.swift、BankImportView.swift、SubscriptionStore.swift、SuberApp.swift、StorageService.swift、AppGroupStore.swift 仅为验证调用上下文而读取,其自身问题(如 BankImportView 主线程解析)已在相应 finding 的 otherSites 中标注,未单独立项。按要求未运行 xcodebuild,全部为静态分析。

### D-billing-dates

【强制问题回答】

1) 钱是否用 Double 表示?——是,全链路 Double,无任何 Decimal:Subscription.amount: Double(Sources/Models/Subscription.swift:102)、effectiveAmount = amount / Double(splitCount)、所有 reduce 求和(DashboardViewModel、CalendarView)、汇率换算、CurrencyFormatter 的 %.2f 均为 Double。就本 app 的金额量级(<1e6)与 2 位小数显示舍入而言,浮点累积误差(<1e-9)不可见,未发现由 Double 精度直接造成的用户可见错账。两处向下取整是 ε 误差可能放大成整元差异的唯一出口:CurrencyFormatter.formatShort 的 `amount == floor(amount)` 精确比较(仅影响显示格式选择,无害)和 AnnualCost.annualSavings 的 `rounded(.down)`(方向性向下取整是注释明示的产品决策"under-promise",可接受)。迁移 Decimal 属可选打磨,非缺陷。

2) 日期比较是日粒度还是瞬时粒度?——BillingCalculator 内部一致地日粒度(所有比较两端都过 startOfDay),未发现午夜 off-by-one。SubscriptionStore 的取消验证流程是瞬时粒度但应当日粒度:`now >= billingDue`(billingDue 为扣费日 00:00 vs now 为完整时间戳,零点即放行——已列为 DATE-01 红色发现);`txn.date >= setAt` 把 CSV 午夜时间戳与点击的完整时间戳比较,同日早于点击的交易被排除——语义上属点击前的扣费,判定合理,不算缺陷。unreadChangeCount 的 14 天滚动阈值为瞬时粒度,对徽标场景可接受。

【清白声明(逐项排查过,无问题)】
- Jan 31 + 1 月链条不漂移:clampDay 每次用存储的 billingDay 重新锚定,脚本验证 2026-01-31 → 02-28 → 03-31 → 04-30 → 05-31,正确。
- 闰年 2/29 年付续费:2024-02-29 → 2025-02-28 → 2026-02-28 → 2027-02-28 → 2028-02-29,下个闰年自动恢复,正确。
- billingDay=31 在 2 月/30 天月:getBillingDateInMonth 的 min(billingDay, maxDay) 钳制正确且已有测试覆盖(testBillingDayClampingFeb)。
- 年末边界:getWeeklyBillingDatesInMonth 用 month+1/day=0 求月末,12 月时 month=13 被 Calendar 规范化为次年 1 月、day 0 回退为 12-31(脚本验证),跨年正确。
- DateHelpers 周一网格偏移:(weekday+5)%7 对周日/周一边界均正确;42 格与 compact 周数计算正确;圣保罗式"无午夜"DST 时区只影响时刻不影响日键(formatDayKey 按分量取值)。
- RecurringChargeDetector:dateComponents([.day]) 为日历感知(DST 安全);median 偶数位整除、CV 的 mean≠0 守卫、amountMedian>0 守卫均正确;年付不检测为文档化设计决策;billingDay 取末次扣费日号对月付合理。整个文件干净。
- 除零:splitCount 在 init 与 decode 双重钳制 ≥1;coefficientOfVariation 有 mean != 0 守卫;categoryBreakdown 有 grandTotal > 0 守卫。无整型除零路径。
- getBillingDatesInMonth / getBillingDateInMonth 的 yearly 周年月、quarterly 相位(monthDiff % 3,因 12≡0 mod 3 与年份无关)均正确。

【测试覆盖缺口】
- BillingCalculatorTests 的 getTotalSpent 只测 oneTime 与未来开始日 → MONEY-01(月付跨年 29 个月、周付满一年归零)完全无覆盖,现有测试给出虚假安全感。
- AutoTransitionTests 只用 .monthly 且 billingDay 与 setAt 同日 → DATE-01 的年付必现分支、2/31 溢出、扣费日当天上午扫描均无覆盖。
- 无 DST 相关测试(DATE-04)、无非公历系统日历测试(DATE-02)、无 date-only JSON 时区测试(DATE-03,测试夹具用本地时区 DateFormatter 而生产解码用 UTC,口径不一致)、无趋势图与头条 split 口径一致性测试(MONEY-02)。

【验证方法】遵守禁令未运行 xcodebuild;所有日期/日历断言用独立 swift 脚本(scratchpad/verify.swift)实际执行验证:多单位 dateComponents 分解(year=2 month=5 week=3 vs 单独 .month=29;周付满年 weekOfYear=0)、伦敦秋季回拨 ceil=13 vs 真实 12 天、2026-02-31 规范化为 03-03、UTC date-only 在纽约当地为前一日、佛历 year=2569、Jan31/Feb29 链条无漂移、month=13/day=0 归一化。

【另予备注】SuberApp.suberDecoder 每次解码一个日期都新建两个 ISO8601DateFormatter(SuberApp.swift:273-279),StorageService 已用 static 缓存,建议同样提为 static——纯性能,无错误结果,不列为 finding。BillingCalculator/DateHelpers 的 static Calendar 快照在 app 运行期间用户跨时区旅行时不会跟随系统时区更新(菜单栏 app 常驻数周),重启自愈,影响仅限"今天"高亮短暂错位,列为备注不列 finding。

### E-views-presentation

审计范围：Sources/Views/ 全部 34 个文件 + 指定 5 个 ViewModel + SuberWidget 4 个文件，全部完整读毕；相关 store/service 调用目标（SubscriptionStore、SettingsStore、SuberApp、MailWatchdog.scanNow、BillingCalculator、DateHelpers、WindowActivationCoordinator）已交叉核实。测试目录 26 个测试文件已盘点：覆盖 store/service 层，无任何视图层行为测试 —— red 发现（accept-price 不落盘）不在现有测试覆盖内。

【必答 1｜PopoverOverlay/OverlayPresenter 生命周期】overlay 可以活得比数据久：AnyView 捕获 Subscription 值拷贝，云同步 replaceAll(.cloudMerge) 删除订阅后 CancelConfirmationSheet 照常显示。但所有写回（markPendingCancellation/markCancelledManually/update/delete）均为 id 查找 + guard → 静默 no-op，无崩溃、无脏写（Subscription 是 struct，不存在悬垂 binding）。真正的数据丢失点是 MenuBarView 编辑表单的 Save 静默 no-op（黄色 finding #2）。另注意：MenuBarExtra(.window) 关闭 popover 不销毁内容视图，presenter.content 不清空 → 数天前呈现的 modal 会在下次打开 popover 时原样挂着（引用可能已删除的订阅）——stale UI，按钮全部 no-op 安全，建议在 popover 失 key 时 dismiss()（未立 finding：无损坏路径）。Dismiss 重入：dismiss() 幂等（content = nil）；present-over-present 直接替换 AnyView，无栈无断言；4 个 present 调用点（IMAPSheet/ConsentSheet/CancelSheet×2/RestoreView/CloudOnboarding）的 onConfirm/onCancel 都是先 dismiss 再改 store，顺序安全。该表现路径判定：无 crash 级缺陷。

【必答 2｜CalendarView ForEach(calendarDays, id: \.self) DST 重复】判定 CLEAN。DateHelpers.calendarDaysCompact 用 Calendar.date(byAdding: .day)（日历天算术）+ startOfDay 归一，非 86400 秒步进。已写独立 Swift 脚本逐一实测 9 个 midnight-DST 时区/月份（São Paulo 2018-11 午夜春令、2019-02 回拨；Santiago 双向；Havana 2026-11 双午夜回拨；Lord Howe；Berlin；New York）：0 重复、严格递增。对照的 naive 86400 版本在 Havana/São Paulo 各产生 1 个重复 —— 即若未来有人重写生成器为秒步进，ForEach 会得到重复 ID → LazyVGrid diff 错乱（错误单元格/漏更新）+ 快速翻月（.id(formatMonthYear) 过渡动画 + withAnimation）下可能触发 AttributeGraph precondition crash。建议给 DateHelpers 补一条 DST 时区防回归测试（现无 DateHelpers 测试文件）。次要观察（未立 finding）：翻月时 .id 立刻变化而 cachedCalendarDays 由 onChange 异步重算，理论上有单帧新旧错位，实测通常被同一事务合并。

【必答 3｜视图层 try/try? 静默吞错清单】视图层 try! 为零。raw try 全部在 do/catch 且有用户可见错误路径：BankImportView:317-320 → stage=.error（非静默，题设猜测不成立）；ImageDropZoneView:296 → errorMessage；IMAPAccountSheet:363 → testResult=.failure（并友好化 5 种服务器拒绝）；SettingsView:503-504 → importError alert。静默点：① SettingsView:492 try? data.write —— 唯一用户可见的静默丢失（黄色 finding #3，题设猜测成立）；② AutopilotSettingsSection:58 try? await watchdog.scanNow() —— 已核实 MailWatchdog.scanNow 每条抛错路径都先设 state=.error/.permissionDenied，错误经 stateBanner + lastScanText 呈现 → 非静默，CLEAN；③ DataRestoreView:254/261 settings/change-log 解码失败静默跳过 —— 注释文档化的 best-effort，主 payload(237) 失败有提示（但样式错，blue finding #8）；④ 范围外提示 A-D：SettingsStore.swift:28-30 try? SMAppService.register/unregister 静默失败会让 Launch at login 开关显示 ON 而实际未注册。Widget 的 3 处 try? 全部有 fallback（见必答 5）。

【必答 4｜SubscriptionFormView asyncAfter × WindowActivationCoordinator】两处 asyncAfter（338 的 0.5s / 364 的 1.0s）为不可取消定时器：延迟窗口内重开扫描面板会被旧回调强行关闭（黄色 finding #4，含修复）。与 WindowActivationCoordinator 的交互：onMultiResult 路径 surface() 抢焦点 → popover 失 key 自动关闭，截断进行中的 0.2s 关闭动画；此时挂起回调随后对已拆除视图的 @State 写值 —— 产生 \"Accessing State's value outside of being installed on a View\" 常量绑定告警，无崩溃。relinquishIfNoWindows 的 0.15s 延迟窗口计数均在主线程访问 NSApp.windows，静态审查未发现 crash 路径。结论：无 crash 级 race，有 UX 级 race（finding #4）。

【必答 5｜Widget】判定：decode 失败 → 占位/空态，不崩。loadSubscriptions/loadSettings/loadExchangeRates 全部 (try? decode) ?? fallback；自定义 date 解码策略内部的 throw 被外层 try? 捕获；AppGroupStore 无数据返回空。placeholder(in:) 是静态假数据。timeline 日期数学：nextUpdate 有 ?? addingTimeInterval(7200) 兜底；upcoming 过滤先排 oneTime 再 getDaysUntilBilling（getNextBillingDate 的 while 循环保证 ≥ today，无负数 \"in -3d\"）。唯一瑕疵是 getDaysUntilBilling 的 86400 除法 DST off-by-one（blue finding #9，service 文件，请与 A-D 去重）。

【必答 6｜状态包装器】@EnvironmentObject 注入链全量验证 PASS：popover 子树 5 个对象（subscriptionStore/settingsStore/importPresenter/mailWatchdog/overlayPresenter）由 MenuBarContainerView 在根部注入，DayDetailView/ListView/SettingsView/AutopilotSettingsSection 所需全覆盖；Import 窗口 scene 注入 4 个，其子树（BankImportView/ImportReviewListView/ChangesListView/ChangeRowView）只用 subscriptionStore+settingsStore+presenter，不引用 overlayPresenter ✓；经 OverlayPresenter.present 的 AnyView 在 MenuBarView 体内渲染继承根环境，且 IMAPAccountSheet/DataRestoreView 还显式重注入 ✓。未发现 \"No ObservableObject found\" 崩溃路径。@State 持引用类型：ImageDropZoneView.pasteMonitor（NSEvent 监视 token, Any?）、previewImage(NSImage)、LogoView.loadedImage(NSImage) —— 均整体替换式使用，安全；pasteMonitor add/remove 在 dropZone 分支的 onAppear/onDisappear 成对，建议加 guard pasteMonitor == nil 防双 onAppear 覆盖泄漏（未能构造确定触发序列，不立 finding）。SettingsView:27 @ObservedObject var updates = UpdateService.shared 形式上命中 STATE-01，但为单例引用（每次 rebuild 取同一实例，不会重建/释放），安全，可改 @StateObject 消除观感。deprecated onChange 已按要求立 blue（finding #7：CalendarView:45/46 + SubscriptionFormView:134；DashboardView:49 与 IMAPAccountSheet:126 已是新签名）。

【干净类目】视图层 force unwrap 仅 AutopilotConsentSheet:37 的硬编码 URL 字面量（SAFETY-01 豁免，编译期常量）；as! 零；try! 零；unowned 零；@State 用于非 View 类型零；数组下标越界未发现（ImageDropZoneView:330 的 parsedList[0] 有非空保证；DashboardView colorForCategory 模 12 安全；ListView nextBilling 排序字典有 ?? .distantFuture 防御）；NAV-05 NavigationPath 不适用（无 NavigationStack）；MAC-01/02 不适用（无自建 NSWindow/NSPanel，仅临时调 keyWindow.level，nil 安全）；BannerCoordinator/AutopilotFlags/DashboardViewModel/ImportPresenter 审查干净（BannerCoordinator 为纯函数 + @MainActor；AutopilotFlags 的 Date? 哨兵编码正确且有测试覆盖）。ChangeRowView.markAck() 是空函数死代码（注释误导，调用方已由 handler 负责 ack），建议顺手删除。

### F-ux-audit

审计方法：通读了 Sources/Views 全部 25 个视图文件、SuberWidget 4 个文件、SubscriptionStore/SettingsStore/CloudSyncService/ExchangeRateService/AppGroupStore/DataBackupManager/IMAPAccount/SuberApp 全文，脚本化扫描 Localizable.xcstrings（99 key）与视图层字符串字面量（200 条），未运行 xcodebuild。

【10 个预定问题的结论】
1. 本地化缺口：确认。视图层 200 条用户可见字面量中仅 74 条在 99-key 目录内，126 条缺失（剔除纯数字插值约 117 条真实文案）→ UX-02。另发现更深一层断链：目录内已翻译的 key 有约 10 个经 String 参数通道（ToggleRow/groupHeader/lastScanText/Button(String)）在运行时永不查表 → UX-03。目录 99 key 本身 zh 覆盖 100%（LocalizationCatalogTests 保证形状，但测不到运行时接线）。
2. 破坏性操作矩阵：① SubCardView 右键 Mark as cancelled — SubCardView.swift:87 — 无确认 — 可恢复（编辑改回状态，但会残留 cancellationConfirmed 日志）→ UX-09；② DayDetail 横幅 Mark as cancelled — DayDetailView.swift:197 — 无确认 — 同上；③ IMAP 账号删除 — AutopilotSettingsSection.swift:198 — 无确认 — 不可恢复（IMAPCredentialStore.delete=SecItemDelete，IMAPAccount.swift:111；Keychain 不在 DataBackupManager.backupKeys 内；提供商不再显示旧 App Password）→ UX-01 红；④ 表单删除 — SubscriptionFormView.swift:221→266 自绘确认 — 有确认 — 可恢复（前一次写入的旋转快照，10 槽内）；⑤ Clear all — SettingsView.swift:186→249 自绘确认 — 有确认 — 可恢复（replaceAll(.clearAll) 先快照，SubscriptionStore.swift:123）——但 settingsStore.reset() 会清掉 imapAccount 配置而不删 Keychain 密码，留下孤儿凭据（小瑕疵）；⑥ JSON 导入覆盖 — SettingsView.swift:315 .alert（v1.9.2 加）— 有确认 — 可恢复；⑦ 恢复覆盖 — DataRestoreView.swift:90 .alert — 有确认 — 可恢复（restore 前自动快照，且 restore 本身可再 restore 回退）。④⑤⑥⑦ 判为干净。
3. 两套确认语言：清单见 UX-12（自绘 dimmed 卡 2 处 / NSAlert 5 处 / 全屏 overlay sheet 4 处）。
4. 无障碍：全仓 accessibility* 共 11 处，分布 MenuBarBadgeView 2、FirstCatchBanner 2、CancellationSuccessBanner 2、SinceYouWereAwayBanner 4、AutopilotBannerView 1；Calendar/List/Dashboard/Settings/Form/TopBar/Import/Widget = 0 → UX-08。
5. 视觉漂移：Theme 外 Color(hex:) 15 处；圆角 11 种取值（8×33 / 6×11 / 10×11 / 12×8 / 2,3,4,5,14,16 少量 / LogoView size*0.2）；.font(.system(size:)) 主 app 64 + Widget 13；状态色白底对比：#4ade80=1.74、#fbbf24=1.67、#60a5fa=2.54、#ff5555=3.07（深色模式全部 >9:1 通过）→ UX-13。
6. IA 错位：确认，首启代码序列还原见 UX-14（popover→CloudSyncOnboardingSheet 全覆盖→空日历灰字提示；Add CTA 只在 Dashboard 空状态）。
7. 可发现性：确认 → UX-15（tap-to-edit 零可供性 + 📦🔍 emoji）。
8. 设置问题：① 过期 onboarding 路径 → UX-07（yellow）；② 版本号两处显示 — SettingsView.swift:216 About 'Suber x.y.z' 与 433 Update 区完全相同一行，冗余（建议 About 区只留 GitHub 链接）；③ 提醒天数全局生效（Settings.reminderDaysBefore，无每订阅覆盖）——年付大额订阅想提前 7 天、周付想只提前 1 天无法并存，记录为产品限制；④ 语言改动需重启（NSBundle 缓存，LanguageOverride 有充分技术论证 + 重启弹窗）而货币即时生效——不对称成立但语言侧属平台限制，弹窗引导已算合理，仅在文案上建议货币行加『takes effect immediately』对称说明。②③④ 均为低危，不单列 finding。
9. 日期格式清单：完整 10 种，逐条 file:line 见 UX-16 及其 otherSites。
10. 反馈缺口：汇率静默 → UX-10；同步状态不可见 + 冲突仅 NSLog（确切位置 SuberApp.swift:236，含 'Future improvement' 自认注释）→ UX-11;全仓 0 处 UndoManager，唯一『撤销』是靠旋转备份走 Restore 流程——对单条误删可接受（有确认+快照），对 Mark-cancelled 无兜底（并入 UX-09）；Widget 无 widgetURL（0 处）→ UX-17。

【新发现（超出 10 类）】① Changes 窗口尺寸自相矛盾（defaultSize 620 < 内容 min 640，注释自述规格 760×520）→ UX-18；② 键盘缺口：自绘确认卡无 Esc/回车（并入 UX-12）；List 搜索无 ⌘F 聚焦、DayDetail 无 Esc 关闭；TopBar 的 ⌘N/⌘L/⌘, 存在但 Dashboard 无快捷键；③ zh 翻译质量（99 key 总体良好，三处可改进）：'Ignore' 与 'Dismiss' 都译作『忽略』——Changes 窗口两种语义不同的按钮在中文下同名；'Pending cancel'=『退订中』vs 'Pending cancellation'=『正在取消中』同一状态两种称谓；约 10 条 zh 文案使用半角逗号/括号（如『App 密码(不是你的账号登录密码)』『只保存金额和日期,不保存其他内容。』）排版不统一；④ ChangeRowView.markAck() 是空函数（line 364 '/* caller handles via store */'）——按钮闭包里调用它无任何效果，属误导性死代码；⑤ SubscriptionFormView.longDateFormatter (503-507) 无调用点，死代码。

【干净项声明】JSON 导入/恢复/清空/表单删除四条破坏性路径的确认与备份链路（replaceAll 唯一 chokepoint + DataBackupManager 10 槽旋转快照 + AppGroupStore.set 写后快照）设计良好，未捏造问题；CloudSyncMerger 三规则（空即补/缩即拒/合并）有 CloudSyncMergerTests、SubscriptionReplaceTests 覆盖；MenuBarBadgeView 与 4 个 Autopilot 横幅的无障碍标注是全 app 最佳实践区。测试盘点：25 个测试文件全部针对 Services/Store 逻辑层，视图层（确认流、本地化接线、a11y）零覆盖。

