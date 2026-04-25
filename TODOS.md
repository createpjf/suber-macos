# TODOS

Captured open loops from planning and review cycles. Items are surfaced via
`/plan-ceo-review` and `/plan-eng-review`. Format: What, Why, Pros/Cons, Context,
Dependencies.

---

## v1.6.1 or v1.7 candidates

### KnownServices cancellation-URL staleness feedback mechanism
- **What**: Add a "Did this page work?" prompt 48h after a user taps "Open cancel page…"; if they tap "No," log locally which service had a stale URL. Later versions can ship URL-map updates informed by this signal.
- **Why**: v1.6 ships ~40 curated cancellation URLs in `KnownServices.Service.cancellationURL`. Services redesign their account pages every 3-12 months. A URL that leads to a 404 makes One-Tap Cancel feel broken.
- **Pros**: Self-healing — users doing real cancellations produce the data we need to keep the map fresh. Institutional memory so this doesn't get rediscovered every 6 months.
- **Cons**: Needs a local scheduler to fire 48h later (or an in-app "you tapped cancel on Netflix 2 days ago — did it work?" banner triggered on launch). Small extra surface area.
- **Context**: The `/plan-ceo-review` for v1.6 offered this as a cherry-pick candidate ("post-cancel follow-up check") and deferred it. `/plan-eng-review` D9 confirmed deferral to TODOS.md. When we revisit, review the real staleness rate from the first 3 months of v1.6 in the wild — we may find the problem is smaller than feared and a simpler fix (accept reports via GitHub issue) is enough.
- **Depends on / blocked by**: v1.6.0 shipping + ~3 months of real usage.

### Deferred from CEO review cherry-pick ceremony (lower priority)
- ⌘⇧R global shortcut to jump to the Changes window
- Change-dismiss memory + "you accepted 12 price rises this year" stats
- One-line monthly roundup clipboard share ("This month: saved $45")
- Auto-archive trivial changes (e.g. duplicate-then-refund within 48h)
- Per-change deep-link notifications (ungroup only if user reports the grouped ones are ambiguous)

### Fast-follow (v1.6.1)
- `missedCharge` detection in `ChangeDetector.ChangeType` — detect when an expected billing date passed ≥7 days ago with no matching incoming charge. Needs two-cycle evidence to avoid false positives; deferred from v1.6.0 for that reason.

### Next-major vectors (v1.7+)
- Gmail OAuth / IMAP direct — adds real email ingestion beyond Apple Mail
- Cancellation email drafting — category-different (unsubscribe.com territory); don't ship until we have signal it's worth the category shift
- iOS companion app — separate track
- AI-powered "what to cancel" advisor — deliberately skipped during v1.6 framing (user chose "automation tool" posture)
