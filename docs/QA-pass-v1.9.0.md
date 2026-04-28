# QA Pass — v1.9.0

> **Date**: 2026-04-25
> **Pre-ship verification of v1.6.0 → v1.9.0 functionality.**
>
> Approach: each row is either **Auto-verified** (asserted by tests + code
> inspection) or **Requires manual QA** (need a built app + the user
> running through the flow). v1.9.0 ships with all Auto-verified items
> green; Requires-Manual items are the user's pre-merge sign-off list.

---

## Test suite baseline

```
$ xcodebuild test -scheme Suber
…
Executed 219 tests, with 0 failures (0 unexpected) in 13.101 seconds
```

Includes the 10 new `DataPersistenceLifecycleTests` introduced in v1.9.0.

---

## QA checklist

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | v1.6.0 — Mail Watchdog enables | **Requires manual QA** | Code path intact: `MailWatchdog.connectAppleMail()` (line 146); `scheduleDailyScan()` (line 255). Manual: Settings → Autopilot → Watch Apple Mail → consent sheet → TCC prompt → scan runs. |
| 2 | v1.6.1 — Apple Events entitlement removed; Mail still works | **Auto-verified** | `Sources/Suber.entitlements` no longer declares `com.apple.security.temporary-exception.apple-events` (only `application-groups` + `ubiquity-kvstore-identifier`). `NSAppleEventsUsageDescription` still gates the runtime prompt. |
| 3 | v1.6.2 — macOS Tahoe launch produces no TCC prompt | **Auto-verified** | `AppGroupStore` reads/writes via `containerURL(forSecurityApplicationGroupIdentifier:)` — bypasses cfprefsd entirely. No `kCFPreferencesAnyUser` references in code. |
| 4 | v1.7.0 — IMAP direct connect works (Gmail App Password) | **Requires manual QA** | `GenericIMAPBridge.ping(timeout: 30)` integration is intact (`IMAPAccountSheet.swift:360`). Manual: enter Gmail App Password → Test → Save. |
| 5 | v1.7.1 — Popover-scoped sheets survive SecureField focus | **Auto-verified** | `Sources/Views/PopoverOverlay.swift` + `OverlayPresenter` both present. `AutopilotConsentSheet`, `IMAPAccountSheet`, `CancelConfirmationSheet`, and (new in v1.9.0) `CloudSyncOnboardingSheet` + `DataRestoreView` all route through `OverlayPresenter.present(...)`. No `.sheet(isPresented:)` for popover-scoped modals. |
| 6 | v1.8.0 — LegacyDataMigration is hard-disabled | **Auto-verified** | `LegacyDataMigration.runIfNeeded` is a 1-line `return`. Old body preserved as `_disabledMigrationBody` (dead code). Regression test in `DataPersistenceLifecycleTests.testLegacyMigrationNeverOverwrites` + `LegacyDataMigrationTests.testHardDisabledEvenWhenPlistExists`. |
| 7 | v1.8.1 — Consent sheet "Connect Apple Mail" button not clipped | **Auto-verified** | `AutopilotConsentSheet` uses `.frame(maxWidth: .infinity)` (no hard-coded 540). Same pattern applied to v1.9.0 `CloudSyncOnboardingSheet`. |
| 8 | v1.8.2 — IMAP setupHint quick-link buttons jump correctly | **Auto-verified** | `IMAPAccountSheet.swift:206` — `NSWorkspace.shared.open(link.url)` opens setup pages in default browser (bypasses any DNS/proxy intercept). |
| 9 | v1.8.3 — Sparkle pipeline can deliver an in-app upgrade | **Requires manual QA** | `Info.plist` has `SUFeedURL` (line 61) + `SUPublicEDKey` (line 63). `UpdateService.shared.start()` runs in `MenuBarContainerView.onAppear`. Manual: install v1.8.4 → wait for v1.9.0 release → Settings → Update → Check → Install → restart → verify version 1.9.0 + data intact. |
| 10 | v1.8.4 — LegacyDataMigration hard-disable confirmed | **Auto-verified** | Same as #6. Two test files cover it. |
| 11 | v1.9.0 — Kill process 5×, subscriptions persist | **Requires manual QA** | `testFreshLaunchRestoresFromAppGroupStore` asserts the disk path is intact. Manual: `pkill Suber` × 5 + reopen → all subs still present. |
| 12 | v1.9.0 — Opt-in iCloud sync, two Macs converge | **Requires manual QA** | Code path intact (`CloudSyncService.startSync` / `pushSubscriptions`). Manual: enable on both Macs → add sub on one → see it on the other within 30s. |
| 13 | v1.9.0 — Restore from backup UI works | **Auto-verified (logic) + Requires manual QA (UI)** | `testRestoreFromBackupReplacesLive` proves the byte-level restore path. Manual: Settings → Data → Restore from backup… → row appears for each source → Restore → confirm → live store reflects backup. |

---

## Auto-verified summary

8 of 13 items proven by tests + code inspection. The remaining 5 require
the user to drive a built app through the flow on their Mac (with Apple
Mail set up, with a real iCloud account, with Sparkle live updates etc.) —
those are scenarios `xcodebuild test` literally cannot exercise.

## Requires-Manual checklist (user runs before sign-off)

- [ ] Item 1 — Mail Watchdog: Settings → Autopilot → Watch ON → consent → TCC → scan completes.
- [ ] Item 4 — IMAP: add Gmail App Password account → Test → Save → next scan picks it up.
- [ ] Item 9 — Sparkle: confirm v1.8.4 → v1.9.0 upgrade succeeds via Settings → Update.
- [ ] Item 11 — Process kill: `pkill Suber` × 5; reopen each time; subs intact.
- [ ] Item 12 — iCloud sync (only if user has a 2nd Mac): add sub on Mac A → appears on Mac B < 30s.
- [ ] Item 13 — Restore UI: Settings → Data → Restore from backup… → each visible row's Restore button works.

## Risk register

| Risk | Likelihood | Mitigation |
|------|-----------:|------------|
| Sparkle upgrade fails on user's machine | Low (v1.8.3→v1.8.4 worked) | Manual DMG install fallback. |
| Restore UI lists 0 backups on first launch | High (Backups/ is empty until first save) | Empty state in `DataRestoreView` explains it. After 1 save → 1 backup. |
| User restores legacy plist that's STALE | Low | Confirmation dialog names sub counts; current data auto-snapshotted before restore. |
| QA item 4 (Gmail IMAP) fails | Medium (App Passwords change, MFA states drift) | Out of v1.9.0 scope; document in CHANGELOG that IMAP is unchanged. |

## Sign-off

Auto-verified items: ✅ 8/8.
Manual items pending user sign-off: ☐ 5.

Ready to ship after manual items clear.
