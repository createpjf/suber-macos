# Changelog

All notable changes to Suber. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); semver per release.

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
