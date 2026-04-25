# Suber Design System

> Canonical reference for visual tokens, copy voice, interaction patterns, and accessibility rules. All new features should calibrate against this file. Introduced in v1.6.0 (lifted from the Autopilot design-review decisions) to prevent v1.7+ features from re-deriving these patterns from scratch.
>
> When something in this doc no longer matches the app, fix the doc **and** the app in the same PR. Stale docs mislead worse than no docs.

---

## 1. Foundations

### 1.1 Platform

- **macOS 14+** deployment target. String Catalog (`.xcstrings`), `.windowResizability(.contentMinSize)`, and modern `NSBackgroundActivityScheduler` APIs all available.
- **Distribution:** Developer ID signed + Apple Notarization. DMG, not Mac App Store.
- **App shape:** Menu-bar app (`LSUIElement=true`, `.accessory` activation policy). Regular `Window` scenes opt into `.regular` activation via `WindowActivationCoordinator`.
- **Existing v1.5 conventions honored:** custom `AppFont` (Space Grotesk) + `Theme` color tokens in `Sources/Models/Constants.swift`. New v1.6 surfaces use these same tokens so everything feels like one app.

### 1.2 Voice

One-liner table, codified during design review Pass 3. Consumers of new strings should match register to context.

| Context | Voice cue | Example |
|---|---|---|
| Utility / status | Plain, passive OK | "Last scan: 2h ago" |
| Re-engagement (banner) | Specific, verb-led | "Review 3 new changes" |
| Trust moments | Honest, reversible | "Turn off any time in Settings → Autopilot" |
| Celebrations | Concrete number, one line | "Netflix cancelled. You'll save $215/year." |
| Failures | Empathetic, non-blaming | "Netflix didn't cancel — still active." |

**Never:**

- Emoji in system notifications, Settings labels, or button text
- Exclamation marks in banners (reserve for real delight; most of the app is utility)
- "things" as a generic noun (say "changes", "subscriptions", "charges")
- Passive constructions when active is shorter ("Suber caught" beats "was caught by Suber")
- "Powered by AI" marketing-speak
- Em dashes in strings destined for `Localizable.xcstrings` — use commas or periods

**Copy rules that keep trust:**

- Name what's NOT happening as loudly as what IS. Example consent modal: *"Suber will read receipts. Nothing leaves your Mac. Turn off any time."*
- Promise-and-verify: only say "Suber will check next month" when Suber actually has a data source to check with. The `hasDataSource` boolean in `CancelConfirmationSheet` gates this copy.
- Savings numbers are rounded **down** to whole dollars. "$215/year" — not "$215.40/year." Under-promise, over-deliver.

---

## 2. Color tokens

### 2.1 Semantic tokens, never hex

All colors reference one of two systems:

- **App-level tokens** in `Sources/Models/Constants.swift` — `Theme.bgPrimary`, `Theme.textPrimary`, etc. Auto-respond to light/dark mode.
- **System-level tokens** — `NSColor.controlAccentColor`, `NSColor.systemOrange`, `NSColor.labelColor`. Auto-respond to accessibility settings (Increase Contrast, Reduce Transparency).

Hard-coded hex values are a code-review reject. macOS adjusts system colors for Dark Mode, Accessibility Increase Contrast, and Color Filters — hard-coded hex bypasses all three.

### 2.2 State palette

| Semantic intent | Token | Typical use |
|---|---|---|
| Accent / brand / primary action | `NSColor.controlAccentColor` | Primary button tint, first-catch banner icon, link color |
| Warning / pending | `NSColor.systemOrange` | `.pendingCancellation` dashed border, countdown badge, priceChange ↑ icon |
| Success / earned | `NSColor.systemGreen` | CancellationSuccessBanner, cancellationConfirmed row icon, priceChange ↓ |
| Info / new | `NSColor.systemBlue` | newCharge row icon |
| Caution / noisy | `NSColor.systemYellow` | Duplicate charge icon, permission-denied inline banner |
| Failure | `NSColor.systemRed` | Menu-bar badge dot, cancellationFailed row, xmark icons |
| Trial / time-bound | `NSColor.systemPurple` | trialExpiring row icon |

### 2.3 Surfaces

| Token | Where it appears |
|---|---|
| `Theme.bgPrimary` | Main scroll views, window background |
| `Theme.bgSecondary` | Cards, banners, grouped surfaces |
| `Theme.bgCell` | Grouped content cells (Settings rows, trust bullets) |
| `Theme.border` | 1pt separators, non-hover card strokes |

### 2.4 Text

| Token | Where |
|---|---|
| `Theme.textPrimary` | Titles, labels, values |
| `Theme.textSecondary` | Subtitles, helper copy, last-scan stamps |
| `Theme.textDim` | Tertiary noise (attribution, timestamps, keyboard hints) |

Contrast: every tinted non-text graphic (dashed border, success checkmark, badge fill) is verified against `windowBackgroundColor` AND `controlBackgroundColor` at ≥3:1. Text hits WCAG AA 4.5:1 via the system tokens above; do not override with manual opacities that drop it.

---

## 3. Typography

Space Grotesk via `AppFont` for most UI; SF Pro system font for micro-labels where Space Grotesk's metrics are too loose (badges, 9pt countdowns). Never use `system-ui` or `-apple-system` as a PRIMARY display font — Pass 4 anti-AI-slop rule.

| Purpose | Token | Size | Weight | Color |
|---|---|---|---|---|
| Window title / empty-state title | `AppFont.bold(17)` | 17pt | bold | `Theme.textPrimary` |
| Row hero line (Changes Window) | `AppFont.medium(15)` | 15pt | semibold | `Theme.textPrimary` |
| Body / supporting line | `AppFont.regular(13)` | 13pt | regular | `Theme.textSecondary` |
| Secondary text / sublabels | `AppFont.regular(12)` | 12pt | regular | `Theme.textSecondary` |
| Tertiary / footnote / last-scan stamp | `AppFont.regular(11)` | 11pt | regular | `Theme.textDim` |
| Section header (all-caps) | `AppFont.medium(11)` | 11pt | medium (uppercase) | `Theme.textSecondary` |
| Hero number (banner "3") | `AppFont.bold(24)` | 24pt | bold | `Theme.textPrimary` |
| Badge count (menu-bar) | `.system(size: 10, weight: .bold)` | 10pt | bold | white on `.red` |
| Day-cell "Nd" countdown | `.system(size: 9, weight: .bold)` | 9pt | bold | white on `systemOrange` |

**When to keep a fixed point size:** fitting into a size-constrained surface the user can't scale (menu-bar icon overlay, 40pt calendar tile). Everywhere else, prefer the semantic `AppFont.*` token so future Dynamic Type support is a one-place change.

---

## 4. Spacing

Scale: **4, 8, 12, 16, 24, 32** (pt). Anything else is a smell.

| Context | Value |
|---|---|
| Banner internal padding | 16pt horizontal, 12pt vertical |
| Banner height | **56pt** (hard constraint — shared by all 3 Autopilot banners) |
| Row internal padding | 16pt horizontal, 12pt vertical |
| Row min height (ChangeRowView) | 72pt (decision prompt) / 44pt (log-style, confirmed variant) |
| Settings group separator | 24pt vertical |
| Dismiss ✕ button hit target | 24pt square (above HIG a11y minimum of 22pt) |
| Action-button hit target | standard `.bordered` / `.borderedProminent` sizing (≥28pt auto) |

---

## 5. Banner rhythm

Three Autopilot banners share a single visual grammar so the app speaks with one voice:

- **SinceYouWereAwayBanner** — daily utility (number-first layout)
- **FirstCatchBanner** — once-forever trust-fall payoff
- **CancellationSuccessBanner** — earned celebration with concrete savings

**Shared chrome** (see `AutopilotBannerView`):

- 56pt tall, full-width
- `Theme.bgSecondary` background
- 1pt separators top and bottom (`Theme.border`)
- Horizontal padding 16pt
- Leading SF Symbol 20pt with semantic tint
- Trailing ✕ dismiss button, 24pt hit target, `Theme.textDim` color
- Optional primary action (`.borderedProminent`, `.controlSize(.small)`)

**Single-slot rendering** (design review A1): `BannerCoordinator` picks AT MOST ONE banner per render. Dismiss of the top banner cascades to the next-priority banner on the next render. Prevents the 168pt banner stack on edge cases.

**Priority order:**

1. `cancellationSuccess` (rare, high-emotional weight, earned)
2. `firstCatch` (once-forever)
3. `sinceYouWereAway` (daily utility)

---

## 6. Icon system (SF Symbols only)

No emoji in production UI. Every user-facing icon is an SF Symbol.

### 6.1 ChangeType map

Used in `ChangeRowView` (list rows) and `NotificationService.composeChangesBody` (notification body phrasing).

| `ChangeType` | SF Symbol | Tint |
|---|---|---|
| `priceChange` (↑) | `arrow.up.right.circle.fill` | `systemOrange` |
| `priceChange` (↓) | `arrow.down.right.circle.fill` | `systemGreen` |
| `newCharge` | `plus.circle.fill` | `systemBlue` |
| `duplicate` | `exclamationmark.2` | `systemYellow` |
| `trialExpiring` | `hourglass.circle.fill` | `systemPurple` |
| `cancellationConfirmed` | `checkmark.circle.fill` | `systemGreen` |
| `cancellationFailed` | `xmark.octagon.fill` | `systemRed` |

### 6.2 Banner icons

| Banner | Symbol | Tint |
|---|---|---|
| `FirstCatchBanner` | `target` | `controlAccentColor` |
| `CancellationSuccessBanner` | `checkmark.circle.fill` | `systemGreen` |
| `SinceYouWereAwayBanner` | — (number-first, no leading symbol) | — |

### 6.3 Other recurring icons

| Purpose | Symbol |
|---|---|
| "Open cancel page…" action | `arrow.up.right.square` |
| Consent modal hero | `envelope.badge.shield.half.filled` |
| Permission-denied warning | `exclamationmark.triangle.fill` |
| Pending-cancel indicator | `clock.badge.exclamationmark` |
| Dismiss | `xmark` |

---

## 7. `.pendingCancellation` visual reconciliation

Same logical state renders at size-appropriate fidelity across 4 view contexts. Shared primitives in `Sources/Views/Autopilot/PendingCancellationIndicator.swift`.

| Tier | Size (pt) | Rendering |
|---|---|---|
| `.tile` | ~40 (CalendarDayCellView) | Dashed border only, 2pt stroke, pattern `[4, 2]`, `systemOrange @ 0.6 alpha` + tiny "Nd" countdown badge top-right when N ≤ 7 |
| `.row` | ~64 (ListView / SubCardView) | Dashed border 2pt pattern `[5, 2]` + "Pending cancel · Xd" inline label with `clock.badge.exclamationmark` icon |
| `.card` | ~100 (DashboardView — future) | Dashed border 2pt pattern `[6, 3]` + corner badge |
| `.detail` | ~300 (DayDetailView, SubCard detail) | Dashed border 2pt pattern `[6, 3]` + full inline banner: "⚠️ Pending cancellation — due by Jun 7 (3 days left)" |

**Color:** `NSColor.systemOrange.withAlphaComponent(0.6)` — semantic "warning, not error." Verified against both `windowBackgroundColor` and `controlBackgroundColor` at ≥3:1 in light and dark mode.

**Without-color fallback:** dashed stroke pattern + text label ("Pending cancel") + countdown badge together convey the state without relying on hue. Works for colorblind users and Differentiate Without Color accessibility mode.

---

## 8. Interaction states (matrix)

Every user-facing surface specifies its loading / empty / error / success / partial treatment. Full reference — keep in sync with `Sources/Views/Autopilot/` source.

| Surface | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Settings → Autopilot | "Scanning… (142 of ~900 messages)" replaces Last-scan row | N/A | Permission-denied banner or Mail-not-running helper | Green checkmark next to Last scan for 3s, fades | N/A |
| Consent modal | N/A | N/A | If TCC dialog never appears: after 6s, inline helper `"Didn't see a permission dialog? [Open System Settings →]"` | Dismisses on grant; Settings row updates to `.idle` | N/A |
| Menu-bar badge | N/A | Hidden (no overlay when `unreadChangeCount == 0`) | N/A | Count renders; on acknowledgment animates to new value (200ms) | 99+ cap |
| "Since you were away" banner | N/A | Banner doesn't render | N/A | Dismisses on Review or ✕ | N/A |
| Pending-cancel tile | N/A | N/A | Billing day passed >7d ago and no resolution → solid red border + "overdue" label | On `cancellationConfirmed`: dashed clears, dot color fades to `.cancelled` (400ms) | N/A |
| Changes Window `.reviewChanges` | Centered `ProgressView` + "Scanning Apple Mail…" | Two states: first-run vs returning-user (see §9) | Full-window retry state | Row fadeOut 200ms on Accept/Ignore | "Showing 10 of 42 \| View all" |
| "Open cancel page" sheet | Primary button spinner for 300ms | N/A | Toast: `"Couldn't open {url} — copied to clipboard instead"` 4s | Sheet dismisses; Calendar tile updates within 200ms | N/A |
| List right-click menu | N/A | N/A | N/A | N/A | Menu item disabled + tooltip `"Already pending cancellation"` for `.pendingCancellation`; omitted entirely for `.cancelled` |
| `.pendingCancellation` card | N/A | N/A | N/A | N/A | See §7 reconciliation |
| Grouped notification | N/A | No notification when `changes.count == 0` | Not-authorized: silent fail; badge still updates | Delivered per template | Notifs disabled in macOS: badge still updates (respect user pref) |

### 9. Empty-state copy (Changes Window)

Design review D7: two distinct states share the same blank `.reviewChanges` layout. Gated by `AutopilotFlags.hasSeenFirstScan`.

**First-run** (no scan completed yet OR no prior changes):

- Icon: `eye.circle`, 48pt, `secondaryLabel`
- Title (`.title2` semibold): `"Autopilot is on watch."`
- Body (`.body`, secondary, max-width 420pt): `"Suber is scanning Apple Mail for billing receipts. You'll see price changes, new subscriptions, and duplicate charges here as they're detected."`
- Action: `[Scan now]` (`.borderedProminent`)

**Returning-user** (prior changes, all acknowledged, current empty):

- Icon: `checkmark.circle.fill`, 36pt, `systemGreen`
- Title: `"You're all caught up."`
- Body: `"Last scan found nothing new. Suber will check again tomorrow."`
- Tertiary: `"Last checked: 2 hours ago"` (`.caption`, tertiary)

---

## 10. Accessibility

### 10.1 Keyboard navigation

**Changes Window:**

- `Tab` / `Shift-Tab` — move focus between rows
- `Return` on focused row — trigger row's primary action
- `Space` on focused row — trigger secondary (Accept for priceChange) — **v1.7 candidate**
- `Delete` / `Backspace` — Ignore
- `⌘W` — close window (standard)

**Consent modal / confirmation sheets:**

- `Esc` — Cancel
- `Return` — default action (primary button)

Never suppress `.focusEffectDisabled()`. System focus ring must be visible.

### 10.2 VoiceOver labels

Every new custom view has an explicit `.accessibilityLabel`. Rule of thumb: spell out symbols and abbreviations.

| Surface | Label |
|---|---|
| Menu-bar badge | `"{N} unread changes"` (e.g. `"3 unread changes"`) |
| "Since you were away" banner | `"{N} new changes since yesterday. Button, Review."` |
| First-catch banner | `"Suber caught your first change. Tap a row to review. Button, dismiss."` |
| CancellationSuccessBanner | `"Netflix cancelled. You will save 215 dollars per year. Button, dismiss."` (note: "dollars per year" not "$/yr") |
| ChangeRowView priceChange | `"Netflix raised to 22 dollars 99 cents per month, up 44 percent, plus 84 dollars per year. Button, Open cancel page. Button, Ignore."` |
| `.pendingCancellation` tile | `"Netflix, pending cancellation, due by June 7th, 3 days remaining"` |

**String Catalog + `.accessibilityLabel` caveat (eng re-review H2):** Xcode's String Catalog auto-extraction catches `Text("…")` and `String(localized:)` but NOT `.accessibilityLabel("…")` when passed a plain String. Always wrap accessibility label strings in `LocalizedStringKey(...)` or call `String(localized: …)` explicitly. `LocalizationCatalogTests` will flag plain-literal `.accessibilityLabel(...)` as a failure.

### 10.3 Differentiate without color

Every color-carrying state also carries a non-color signal:

- `.pendingCancellation`: dashed stroke pattern + text label + countdown badge
- ChangeType: SF Symbol shape (arrow-up vs plus vs hourglass) — not just tint
- Menu-bar badge: numeric count — not just a red dot
- Notification severity: inferred from title/body copy — notifications can't color their text on macOS anyway

### 10.4 Reduce Motion

With `@Environment(\.accessibilityReduceMotion)` enabled:

| Animation | Default (250ms) | Reduced |
|---|---|---|
| Row removal on Accept/Ignore | fade 200ms | instant |
| Success banner entrance | slide-down 300ms | cross-fade 200ms |
| Badge count change | scale + fade 200ms | snap transition |
| Pending-cancel dashed border | no animation | — |
| Scan progress text update | text update (no effect) | — |

### 10.5 Reduce Transparency

All banner backgrounds use opaque `NSColor.controlBackgroundColor` already — no vibrancy to dial down. Menu-bar popover vibrancy is macOS default, which respects the setting automatically.

### 10.6 Dynamic Type

macOS has limited Dynamic Type support compared to iOS. We respect the user's "Font size" accessibility preference via SwiftUI's semantic text styles (`AppFont.regular(13)` maps to `.body`-adjacent size) everywhere EXCEPT:

- Menu-bar badge count (10pt — must fit inside 16pt menubar icon overlay)
- Day-cell countdown (9pt — must fit inside 40pt calendar tile)

Both fixed-point exceptions are annotated in source and deliberate.

---

## 11. Window sizing

macOS expects resizable windows. `Window("import")` (Import + Changes Window):

- `.defaultSize(width: 620, height: 620)` — v1.5 default, retained
- `.windowResizability(.contentMinSize)` — honors the content's `.frame(minWidth:minHeight:)`
- **ChangesListView min: 640×480** (design review D12) — prevents row action clipping at narrow widths
- macOS auto-persists last frame by scene identifier — no extra state code

Settings window: standard macOS fixed size (no change from v1.5).
Menu-bar popover: fixed 360pt wide (no change from v1.5).

---

## 12. UserDefaults namespacing (`autopilot.*`)

A2 (eng re-review) compile-time-safe wrapper. All Autopilot UI state flows through `AutopilotFlags`:

| Key | Type | Default | Purpose |
|---|---|---|---|
| `autopilot.hasSeenFirstScan` | `Bool` | `false` | Gates first-run vs returning empty state |
| `autopilot.hasSeenFirstCatch` | `Bool` | `false` | Once-forever FirstCatchBanner gate |
| `autopilot.lastBannerShownAt` | `Date?` (TimeInterval-backed) | `nil` | Per-day throttle for SinceYouWereAwayBanner |
| `autopilot.lastCelebrationAckedAt` | `Date?` (TimeInterval-backed) | `nil` | Collapses same-day CancellationSuccessBanner |

MailWatchdog's per-account scan cursors (`mailwatchdog.lastScannedMessageID`, `mailwatchdog.lastScanDate`) live in a separate namespace and are NOT exposed via `AutopilotFlags`. Different domain (UI state vs. scan state).

**H4 pattern (eng re-review):** Swift's `@AppStorage` doesn't cleanly store `Date?`. Use a TimeInterval-backed `Double` (0.0 = nil sentinel) with a computed `Date?` getter/setter. See `AutopilotFlags.setRaw(key:date:)`.

---

## 13. Patterns to AVOID (anti-AI-slop)

Pass 4 blacklist — ship-blocker if these appear:

1. **Three-column feature grid** (the single most AI-looking pattern). Consent modal bullets MUST be a vertical stack, never 3 columns.
2. Purple/violet gradients as background decoration.
3. Icons in colored circles as section decoration.
4. Centered-everything layouts (centering fine per-element, not layout-wide).
5. Uniform bubbly border-radius on every element.
6. Decorative SVG blobs / floating circles / wavy dividers.
7. Emoji as design elements. (Row copy can include `✓` as an exception for the `cancellationConfirmed` log-row; production elsewhere is SF Symbols.)
8. Colored left-border "tip" cards — EXCEPT the permission-denied inline banner which uses `systemYellow` leading border (standard macOS inline-warning pattern, not slop).
9. Generic hero copy ("Welcome to…", "Unlock the power of…").
10. `system-ui` / `-apple-system` as primary display font.
11. "Powered by AI" marketing-speak.

Pass 1 cons: when unsure, apply subtraction — if deleting 30% of a surface's text or chrome improves it, keep deleting.

---

## 14. When to update this doc

Update DESIGN.md in the same PR as:

- New semantic color or surface token
- New shared UI primitive (banner, row, indicator)
- New voice-table row (new copy register)
- New ChangeType or banner kind (extend §6, §7, §8)
- New Autopilot `autopilot.*` UserDefaults key (§12)
- Changes to the anti-AI-slop blacklist (§13) — additions only; removals require design-review approval

Stale specs in this doc mislead contributors. Keep it honest.
