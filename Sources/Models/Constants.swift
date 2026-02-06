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

    static let statusColors: [SubscriptionStatus: Color] = [
        .active: Color(hex: "4ade80"),
        .paused: Color(hex: "fbbf24"),
        .cancelled: Color(hex: "ff5555"),
        .trial: Color(hex: "60a5fa"),
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

    // MARK: - Status Colors (same in both modes)
    static let danger = Color(hex: "ff5555")
    static let success = Color(hex: "4ade80")
    static let warning = Color(hex: "fbbf24")
    static let trial = Color(hex: "60a5fa")
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
