import SwiftUI

enum AppConstants {
    static let currencies: [String] = [
        "USD", "EUR", "GBP", "CNY", "JPY", "KRW", "CAD", "AUD",
        "CHF", "HKD", "SGD", "SEK", "NOK", "DKK", "INR", "BRL",
        "MXN", "TWD", "THB", "RUB",
    ]

    static let currencySymbols: [String: String] = [
        "USD": "$", "EUR": "\u{20AC}", "GBP": "\u{00A3}", "CNY": "\u{00A5}", "JPY": "\u{00A5}",
        "KRW": "\u{20A9}", "CAD": "C$", "AUD": "A$", "CHF": "CHF", "HKD": "HK$",
        "SGD": "S$", "SEK": "kr", "NOK": "kr", "DKK": "kr", "INR": "\u{20B9}",
        "BRL": "R$", "MXN": "MX$", "TWD": "NT$", "THB": "\u{0E3F}", "RUB": "\u{20BD}",
    ]

    static let categories: [String] = [
        "Streaming", "Music", "Software", "Cloud Storage", "Productivity",
        "AI", "Education", "News", "Gaming", "Fitness", "Finance", "Other",
    ]

    /// AUDIT-v1.9.2 U-02: display-only localization for the preset categories.
    /// The stored `Subscription.category` value stays the English identifier
    /// (search, filters, and synced data are unaffected); views route display
    /// through this helper. Unknown/legacy values pass through unchanged.
    static func localizedCategory(_ raw: String) -> String {
        switch raw {
        case "Streaming": return String(localized: "Streaming")
        case "Music": return String(localized: "Music")
        case "Software": return String(localized: "Software")
        case "Cloud Storage": return String(localized: "Cloud Storage")
        case "Productivity": return String(localized: "Productivity")
        case "AI": return String(localized: "AI")
        case "Education": return String(localized: "Education")
        case "News": return String(localized: "News")
        case "Gaming": return String(localized: "Gaming")
        case "Fitness": return String(localized: "Fitness")
        case "Finance": return String(localized: "Finance")
        case "Other": return String(localized: "Other")
        default: return raw
        }
    }

    // AUDIT-v1.9.2 U-14: route through Theme so status colors adapt per
    // appearance — the old fixed hex values had 1.67–2.54:1 contrast on a
    // white background.
    static let statusColors: [SubscriptionStatus: Color] = [
        .active: Theme.success,
        .paused: Theme.warning,
        .cancelled: Theme.danger,
        .trial: Theme.trial,
    ]
}

// MARK: - Font Helpers

/// Custom font using Space Grotesk with system fallback.
enum AppFont {
    static func regular(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Regular", size: size)
    }

    static func medium(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Medium", size: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Bold", size: size)
    }

    static func light(_ size: CGFloat) -> Font {
        .custom("SpaceGrotesk-Light", size: size)
    }
}

/// Adaptive theme that follows system appearance.
/// Light mode matches the reference UI: light bg, prominent gray cells.
/// Dark mode uses darker equivalents.
enum Theme {
    // MARK: - Adaptive Colors

    /// Main background — light: near-white, dark: dark gray
    static let bgPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)   // #1a1a1a
            : NSColor(red: 0.976, green: 0.976, blue: 0.980, alpha: 1)   // #f9f9fa
    })

    /// Secondary background — light: white, dark: slightly lighter
    static let bgSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)   // #2a2a2a
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)         // #ffffff
    })

    /// Cell background — light: visible gray to match reference, dark: darker gray
    static let bgCell = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)   // #2a2a2a
            : NSColor(red: 0.918, green: 0.922, blue: 0.933, alpha: 1)   // #eaebee
    })

    /// Primary text — light: near-black, dark: white
    static let textPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            : NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)      // #17171c
    })

    /// Secondary text — light: medium gray, dark: lighter gray
    static let textSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.533, green: 0.533, blue: 0.533, alpha: 1)   // #888888
            : NSColor(red: 0.40, green: 0.40, blue: 0.44, alpha: 1)      // #666670
    })

    /// Dim text — light: faded gray, dark: dark gray
    static let textDim = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1)   // #555555
            : NSColor(red: 0.60, green: 0.60, blue: 0.63, alpha: 1)      // #9999a0
    })

    /// Accent color — same as textPrimary (dark buttons)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            : NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)      // #26262e
    })

    /// Border color
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1)      // #333333
            : NSColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1)      // #e0e0e6
    })

    // MARK: - Status Colors
    // AUDIT-v1.9.2 U-14: previously fixed hex in both modes — 1.67–2.54:1
    // contrast on white (below the WCAG 3:1 non-text floor, and these also
    // serve as text in the import confidence badges and "Clear all data").
    // Light mode now uses darker variants (≥4.1:1 on white); dark mode keeps
    // the original values (>9:1 on #1a1a1a).

    /// Danger/destructive — dark: #ff5555, light: #dc2626 (~4.8:1 on white)
    static let danger = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.0, green: 0.333, blue: 0.333, alpha: 1)     // #ff5555
            : NSColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1)   // #dc2626
    })

    /// Success/active — dark: #4ade80, light: ~#178c45 (~4.1:1 on white)
    static let success = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)      // #4ade80
            : NSColor(red: 0.09, green: 0.55, blue: 0.27, alpha: 1)      // ~#178c45
    })

    /// Warning/paused — dark: #fbbf24, light: #b45309 (~5.0:1 on white)
    static let warning = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)   // #fbbf24
            : NSColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1)   // #b45309
    })

    /// Trial — dark: #60a5fa, light: #2563eb (~5.2:1 on white)
    static let trial = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1)   // #60a5fa
            : NSColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1)   // #2563eb
    })

    // MARK: - Chart & Accent Colors
    // AUDIT-v1.9.2 U-14: hex colors that lived at call sites (DashboardView
    // chart wheel + trend bar, SubscriptionFormView steppers) now live here
    // so Theme is the single source of color truth.

    /// Category chart palette (Dashboard stacked bar + legend).
    static let chartPalette: [Color] = [
        Color(hex: "6366f1"),  // indigo
        Color(hex: "f59e0b"),  // amber
        Color(hex: "10b981"),  // emerald
        Color(hex: "ef4444"),  // red
        Color(hex: "8b5cf6"),  // violet
        Color(hex: "06b6d4"),  // cyan
        Color(hex: "f97316"),  // orange
        Color(hex: "ec4899"),  // pink
        Color(hex: "14b8a6"),  // teal
        Color(hex: "84cc16"),  // lime
        Color(hex: "a855f7"),  // purple
        Color(hex: "64748b"),  // slate
    ]

    /// Current-month highlight bar in the Dashboard trend chart
    /// (same indigo as chartPalette[0]).
    static let chartHighlight = Color(hex: "6366f1")

    /// Price stepper accent in SubscriptionFormView.
    static let accentTeal = Color(hex: "38b2ac")

    // MARK: - Corner Radius Tokens
    // AUDIT-v1.9.2 U-14: 11 ad-hoc corner-radius values existed across views;
    // new/edited code should pick from these instead of literals.
    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue >> 16) & 0xFF) / 255.0,
            green: Double((rgbValue >> 8) & 0xFF) / 255.0,
            blue: Double(rgbValue & 0xFF) / 255.0
        )
    }
}
