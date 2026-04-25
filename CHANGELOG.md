# Changelog

All notable changes to Suber. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); semver per release.

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
