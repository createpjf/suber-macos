# Suber Release Process — Hard Rules (v1.9.0+)

> **Trigger:** v1.6.0 → v1.8.4 shipped 12 versions in 4 days, with 1 real
> data-loss event and 0 full QA passes. v1.9.0 introduces architectural
> redundancy for data safety, and this document introduces process
> redundancy for everything else.

## Rule 1 — 7-day feature freeze after every release

Starting with v1.9.0, **every release is followed by at least 7 calendar
days during which no new feature ships.** A release is a release for this
purpose if it:

- changes user-visible behavior, OR
- changes the persistence schema (subscriptions / settings / change log), OR
- changes any code path that runs at app launch.

Pure version bumps for control / observability releases (e.g. v1.8.3) do
NOT reset the 7-day clock — that release didn't ship anything new.

### Exceptions

The freeze can be broken — but only for one of these:

- **P0 security** (CVE-class vulnerability, exposed credentials, etc.)
- **P0 data safety** (active data-loss bug, like v1.8.4 was)
- **P0 install blocker** (notarization fails, Gatekeeper rejects, code-signing
  identity revoked, …)

Anything else — design polish, IMAP UI tweaks, additional currency
support, copy fixes, new categories — waits until the freeze period ends.
Quality of life is not a P0.

### What the freeze actually means

During the 7-day window:

- ✅ Bug fixes that AREN'T P0 can land in `main` but DON'T trigger a release.
- ✅ Refactors / tests / docs are fine — they don't ship to users.
- ✅ External work (design exploration, planning the next release) continues.
- ❌ No `gh release create`. No new tag. No DMG upload. No appcast.xml
  update except for adding metadata (notes) to the already-published latest
  release.

The point is to give the most recent release time to be **proven stable in
the wild** before stacking the next change on top of it.

## Rule 2 — Release notes start with reflection

Every release's first paragraph (in CHANGELOG.md and the GitHub release
notes) names what was learned from the previous release cycle, in plain
language. Examples:

- v1.9.0 opens with the firefighting-cycle reflection (12 versions / 4
  days / 1 data loss).
- v1.8.4 opens with the LegacyDataMigration root cause and "all v1.8.0–8.3
  users should upgrade immediately."

Users deserve to know what we learned, especially when they were affected.
Release notes that pretend a problem didn't happen erode trust faster than
the underlying bug did.

## Rule 3 — Full QA pass before any feature release

The 13-item checklist in `docs/QA-pass-v1.9.0.md` (or its successor for
each release) walks every v1.6.0+ feature once. Items split into:

- **Auto-verified** — covered by `xcodebuild test` + code review of the
  affected paths. These are documented as part of the QA doc and don't
  need re-running per release.
- **Requires manual** — Mail / IMAP / Sparkle upgrade / iCloud convergence
  / process-kill scenarios. The user runs the built app and signs off
  before the release tag is pushed.

A new feature release WITHOUT these items signed off doesn't ship. The
v1.6.0 → v1.8.4 cycle skipped this and shipped a data-loss bug as a
consequence.

## Rule 4 — Tests gate the build

`xcodebuild test` must report **0 failures** before any DMG is built. The
`scripts/build-dmg.sh` already runs the build phase; tests are a
prerequisite step the developer runs first. The current count (v1.9.0)
is 219 tests; expect that number to grow but never shrink.

Adding new functionality without adding tests for it is a soft violation
that the next QA pass should call out as tech debt.

## Rule 5 — Backups before destructive operations

Any code path that overwrites a user's `suber-subscriptions` /
`suber-settings` / `suber-changes` blob MUST go through `AppGroupStore.set()`,
which automatically takes a `DataBackupManager` snapshot. Bypassing
`AppGroupStore.set` (e.g. raw `Data.write(to:)` against the live JSON path)
is a code-review red flag and requires explicit justification.

## Rule 6 — Disabled code stays disabled

If a piece of code has been disabled because of a real bug (like
`LegacyDataMigration._disabledMigrationBody`), it does NOT come back
without:

1. A documented post-mortem of why it was originally disabled.
2. New tests that fail before the fix and pass after.
3. A signed-off QA pass on the affected feature areas.

Re-enabling such code mid-release-cycle without those three is treated as
a P0 violation regardless of the user-visible bug it might fix.

---

## Release timeline (target)

```
Day 0  ← release ships (e.g. v1.9.0 — Tuesday/Wednesday, 2026-04)
Day 1  ← monitor user reports; only P0 fixes land
Day 2  ← same
Day 3  ← same
Day 4  ← same
Day 5  ← same
Day 6  ← same; start drafting next release plan in private branch
Day 7+ ← freeze ends; next feature work can land + release
```

If during Day 1–7 the released version proves UNSTABLE (data loss, crash
loop, …), we revert to the last stable release first, then ship a fix —
we don't accumulate new work on a broken base.

## How to invoke an exception

If a P0 exception is needed during a freeze:

1. Document the trigger in `docs/INCIDENT-LOG.md` (one paragraph).
2. Write tests covering the regression.
3. Run the standard QA pass (or a focused subset for the affected feature).
4. Ship.
5. The 7-day freeze clock **resets** from the new release date.

The clock reset is the point — every emergency release earns the next 7
days back, so we don't compound urgency on top of urgency.
