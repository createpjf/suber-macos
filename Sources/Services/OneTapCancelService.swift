import Foundation
import AppKit

// ┌───────────── OneTapCancelService — v1.6 Act pillar ────────────────────────┐
// │                                                                            │
// │  Resolves the right cancel URL for a given Subscription and opens it in    │
// │  the user's default browser. Routed from:                                  │
// │    - DayDetail "Open cancel page…" button                                  │
// │    - ListView right-click context menu                                     │
// │    - Changes Window row primary action (priceChange / trialExpiring /      │
// │      cancellationFailed "Try again")                                       │
// │                                                                            │
// │  URL resolution priority:                                                  │
// │    1. `subscription.cancellationURL` (user-overrideable per-sub)           │
// │    2. `KnownServices.cancellationURL(for: sub.name)` (top-40 seed)         │
// │    3. DuckDuckGo search fallback: "how to cancel {encoded-name}"           │
// │                                                                            │
// │  Why DuckDuckGo and not Google: DDG doesn't require a search-session       │
// │  cookie, returns results instantly without a consent modal, and matches    │
// │  the plan's "honest about the fallback" posture — we couldn't find the     │
// │  URL, here's how to help yourself.                                         │
// │                                                                            │
// │  D5 idempotency (eng review iter-1): re-tapping on an already-pending sub  │
// │  re-opens the URL but does NOT mutate pendingCancellationSetAt. Belt-and- │
// │  braces for users who got distracted mid-cancel. The store.markPending-   │
// │  Cancellation method handles the idempotency (see SubscriptionStore).     │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

enum OneTapCancelService {

    /// Resolved URL for a subscription. Nil only if URL encoding somehow fails
    /// (empty name, etc.) — caller should fall back to a toast "name too short".
    static func resolveURL(for subscription: Subscription) -> URL? {
        // 1. Per-sub override.
        if let override = subscription.cancellationURL,
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }

        // 2. KnownServices seed.
        if let known = KnownServices.cancellationURL(for: subscription.name),
           let url = URL(string: known) {
            return url
        }

        // 3. DuckDuckGo fallback.
        return duckDuckGoFallback(for: subscription.name)
    }

    /// Build the DuckDuckGo fallback URL. "how to cancel {service}" returns
    /// consistently useful first-page results for any non-obscure service.
    /// Uses URLComponents so query VALUES are properly percent-encoded
    /// (urlQueryAllowed keeps `&` and `=` as-is — those are query syntax,
    /// not safe for value contents).
    static func duckDuckGoFallback(for serviceName: String) -> URL? {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: "how to cancel \(trimmed)")]
        return components?.url
    }

    /// Whether we have a direct known URL (not just the DuckDuckGo fallback).
    /// UI uses this to choose between "Open cancel page…" and "Find cancel page…".
    static func hasKnownCancelPage(for subscription: Subscription) -> Bool {
        if let override = subscription.cancellationURL, !override.isEmpty { return true }
        return KnownServices.cancellationURL(for: subscription.name) != nil
    }

    // MARK: - Launch

    /// Open the resolved URL in the default browser. For `itms-apps://` URLs
    /// (Apple Subscriptions deep-link), NSWorkspace routes to the App Store.
    /// Returns true on success.
    @MainActor
    @discardableResult
    static func openCancelPage(for subscription: Subscription) -> Bool {
        guard let url = resolveURL(for: subscription) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
