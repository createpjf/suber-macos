# Spec — Imminent Charges View ("临期消费")

> **Status:** Draft spec. Build is **post-freeze** (v1.9.2 feature freeze runs to ~2026-06-16). This doc is planning, not shipping — it does not break the freeze.
> **Go/no-go gate:** the 10-minute real-data gut-check (see bottom). Don't build until that passes.
> **Slots as:** first real feature after the freeze — candidate v1.11.0.

## Context

Suber's mission (owner's words): *"a tool where a user can see what subscriptions they have, and know their subscription spending."* It's an **awareness** product. The two hero numbers that matter:

1. **Monthly total** — the ambient "am I overspending" number. **Already built** (`DashboardView` headline: "$22.99 per month · $275.88/yr").
2. **"What's about to hit my card"** — the *trigger* number. Changes day-to-day, creates a reason to open the app and a decision moment. **This is the net-new build.**

The monthly total is passive (you glance, you sigh). The imminent number is active — it's what makes the app worth re-opening and what surfaces the **forgotten** charge (the annual renewal you haven't thought about in 11 months).

## Goal

Show the user, at a glance, **how much is leaving their account in the next 7 days**, with the **forgotten/infrequent charges made prominent**, and **light up the menu bar** when a charge is imminent so the app earns attention only when it matters.

## JTBD

> When I have a vague worry that subscriptions are quietly draining my account, I want to see exactly what's about to be charged in the next few days, so I can catch the ones I forgot about and decide to keep or kill them before the money leaves.

## Locked design decisions (from brainstorm)

1. **Window:** rolling **7 days** `[now, now+7d]`.
2. **Never-empty rule:** always show a **"next beyond the window"** peek, even on quiet weeks. This is also where infrequent/annual charges get surfaced early.
3. **Forgotten charges POP:** infrequent cycles (yearly/quarterly) get visual emphasis. This is NOT a calendar filtered to 7 days — the framing ("¥215 leaving this week" + the surprising annual) is the value, not the raw dates.
4. **Menu bar:** monthly total is the at-rest meaning; the badge **lights up when an imminent charge approaches**, reusing the existing `MenuBarBadgeView` overlay mechanism. The two numbers never compete for the same pixel.
5. **Honesty:** the numbers are only as true as the list is complete + dates accurate. A wrong "¥0 this week" that misses Thursday's annual renewal is worse than no feature. (This is why the data-safety work came first.)

## Architecture — builds entirely on existing primitives

| Need | Existing primitive | File |
|------|-------------------|------|
| Next charge date for a sub | `BillingCalculator.getNextBillingDate(_:)` | `Services/BillingCalculator.swift:49` |
| Days until next charge | `BillingCalculator.getDaysUntilBilling(_:)` | `:215` |
| Cross-currency conversion | `ExchangeRateService.shared.convert(_:from:to:)` | used in `DashboardViewModel:57` |
| Display formatting | `CurrencyFormatter.formatShort(_:currency:)` | used across `DashboardView` |
| Primary currency | `settingsStore.settings.primaryCurrency` | — |
| Menu-bar badge overlay | `MenuBarBadgeView(count:)` | `Views/Autopilot/MenuBarBadgeView.swift` |

No new calculation engine math is needed — only composition.

### Component 1 — `ImminentChargesCalculator` (new, pure service)

`Sources/Services/ImminentChargesCalculator.swift`. Pure, no I/O, fully unit-testable (mirrors `BillingCalculator`'s static-func style).

```swift
struct ImminentCharge: Identifiable, Equatable {
    let id: UUID                 // subscription id
    let subscriptionName: String
    let date: Date               // projected charge date
    let daysUntil: Int
    let amountInPrimary: Double   // converted to primaryCurrency
    let originalAmount: Double
    let originalCurrency: String
    let cycle: BillingCycle
    var isInfrequent: Bool { cycle == .yearly || cycle == .quarterly }
}

struct ImminentChargesResult: Equatable {
    let windowCharges: [ImminentCharge]   // in [now, now+window], sorted by date
    let windowTotalInPrimary: Double
    let nextBeyondWindow: ImminentCharge? // soonest charge AFTER the window (the peek)
}

enum ImminentChargesCalculator {
    /// Default window = 7 days. `now` injectable for tests.
    static func compute(
        subscriptions: [Subscription],
        primaryCurrency: String,
        windowDays: Int = 7,
        now: Date = Date()
    ) -> ImminentChargesResult
}
```

**Rules:**
- Skip `.cancelled` and `.paused` subs (not charging). Skip `.oneTime` whose date already passed.
- **Trials count:** a `.trial` sub converting within the window IS an imminent charge — use `trialEndDate` as the charge date, `amount` as the (post-trial) amount. This is the highest-value case ("trial about to convert").
- Charge date for non-trials = `BillingCalculator.getNextBillingDate(sub)`. For a 7-day window each cycle has at most one charge, so next-charge-date is sufficient.
- `windowCharges` = those with charge date in `[now, now+windowDays]`, sorted ascending.
- `nextBeyondWindow` = the soonest charge strictly after the window (nil if none).
- All amounts converted to `primaryCurrency` via `ExchangeRateService.shared.convert`.

### Component 2 — `ImminentChargesView` (new view)

`Sources/Views/ImminentChargesView.swift`. Rendered at the **top of `DashboardView`**, directly under the monthly-total headline (Dashboard is the "know what you spend" surface; imminent is its actionable companion).

Layout:
```
This 7 days · ¥215
  Netflix          ¥98    in 2 days
  iCloud           ¥21    Fri
  ───────────────────────────────
  Next: Photomator ¥198 · in 18 days   [yearly]   ← always shown, never empty
```
- Quiet-week state: "Nothing due in the next 7 days" + the peek row.
- Infrequent rows (`isInfrequent`) get a subtle `[yearly]`/`[quarterly]` tag + slightly stronger weight so they POP.
- Uses `Theme` + `AppFont` conventions already in `DashboardView`.
- Tapping a row → opens that subscription's detail/edit (reuse existing `onEdit` path) so "decide to keep or kill" is one tap.

### Component 3 — Menu-bar badge extension

Extend `MenuBarBadgeView` so the badge reflects **imminent state with priority over unread-changes**:

- Compute the soonest imminent charge within `badgeThresholdDays` (default **3**).
- **If** a charge is within the threshold → amber/orange capsule showing the day count (e.g. `2d`) — the "money about to leave" state.
- **Else if** `unreadChangeCount > 0` → existing red count badge.
- **Else** → no badge.

Imminent (money) outranks unread (info). Reuse the existing overlay; only add a state-driven color+content. **Carry over the template-mode QA risk + `NSImage` fallback already documented in `MenuBarBadgeView`** — verify the amber renders on a notarized build before shipping.

Wiring: `SuberApp` menu-bar `label:` currently passes `MenuBarBadgeView(count: subscriptionStore.unreadChangeCount)`. Extend the view's inputs to also take the imminent signal (a small computed value off `subscriptionStore.subscriptions` + `settingsStore`), computed cheaply on render.

**Noise control:** for a user with monthly subs, a ≤3-day badge fires ~monthly per sub. Default threshold 3 keeps it modest; expose `badgeThresholdDays` as a setting if it proves noisy. **v2 refinement (out of scope):** fire the badge only for `isInfrequent` charges (the truly-forgotten ones), since monthly charges are expected.

## Tests (`Tests/ImminentChargesCalculatorTests.swift`)

The calculator is pure → straightforward unit tests:
1. Monthly sub due in 3 days → in `windowCharges`; due in 10 days → only in `nextBeyondWindow`.
2. Cross-currency: ¥ + $ subs → `windowTotalInPrimary` correctly converted + summed.
3. `nextBeyondWindow` returns the soonest post-window charge; nil when none.
4. `.paused` / `.cancelled` excluded; `.oneTime` past-dated excluded.
5. Trial converting in 5 days → appears as an imminent charge at `trialEndDate`.
6. Yearly sub → `isInfrequent == true`; monthly → false.
7. Empty result when no subs in window AND none beyond (truly empty).
8. Weekly sub → exactly one charge in the 7-day window (boundary check).

View + badge are SwiftUI → verify by build + manual QA (consistent with how `SettingsView` confirm-dialog work was verified).

## The one open decision

**Placement for max visibility.** The default landing tab is **Calendar**, not Dashboard. If imminent-charges lives only on Dashboard, the user must switch tabs to see it — weakening the "glance and see what's coming" value.

- **Option A (spec default, lowest effort):** top of Dashboard. Menu-bar badge is the trigger; details on Dashboard.
- **Option B (fast-follow):** also render a compact one-line imminent strip on the Calendar (default) tab.

Recommend ship **A** first, measure whether it gets opened, add **B** if the badge→view path feels too buried. Decide at build time.

## Out of scope (v1)

- Per-charge push notifications — Suber **already** has "1/2/3/5/7 days before each bill" reminders (`NotificationService`). The imminent view is the in-app/menu-bar surface of the same projection; **potential consolidation** of both onto `ImminentChargesCalculator` is a nice-to-have, not required for v1.
- `badgeThresholdDays` user setting (ship with hardcoded default 3; add setting only if noise complaints).
- Infrequent-only badge filtering (v2 refinement).
- Calendar-tab strip (Option B, fast-follow).

## Sequencing

1. **Now:** this spec exists; freeze still in effect.
2. **Go/no-go gate (owner, 10 min):** take the 9 real recovered subs — does the **monthly total** exceed what you assumed? Does **this-7-days / this-month** surface a charge you'd forgotten? If yes → build. If the list is all monthly-and-expected → the hook is weaker for this user profile and worth re-checking before investing.
3. **Post-freeze (~2026-06-16):** convert this spec to a task-by-task plan (`superpowers:writing-plans`) and execute via subagent-driven development, same as v1.9.2. Estimated 3 components + 1 test file ≈ a 1-day build.

## Why this is the right next feature

It completes the awareness loop Suber is *for* — not "another view," but the one number that's both glanceable (menu bar) and actionable (decide before the charge lands), with the forgotten annual renewals finally surfaced. Everything it needs already exists in `BillingCalculator` + `ExchangeRateService` + the badge; the work is composition, not new infrastructure.
