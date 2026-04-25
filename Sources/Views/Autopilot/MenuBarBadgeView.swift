import SwiftUI
import AppKit

// ┌───────────── MenuBarBadgeView — unread-changes count overlay ──────────────┐
// │                                                                            │
// │  Design review spec: 10pt bold white on red circle, topTrailing of the     │
// │  16pt template-mode menubar icon. Offset +6,-6 puts it half-outside the    │
// │  icon bounds so it reads as a badge, not a glyph.                          │
// │                                                                            │
// │  Risk (from plan): macOS template-mode may strip the red fill and render   │
// │  the badge as an outline-only dot. FALLBACK: compose NSImage manually via  │
// │  lockFocus / NSBezierPath with the red fill baked in.                      │
// │                                                                            │
// │  v1.6.0-beta.2 QA step: verify badge renders red on a notarized build     │
// │  BEFORE shipping. If template stripping happens, swap the MenuBarExtra    │
// │  label from SwiftUI overlay → NSImage fallback without breaking consumers. │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct MenuBarBadgeView: View {
    let count: Int

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(min(count, 99))\(count > 99 ? "+" : "")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.red)
                        )
                        .offset(x: 6, y: -6)
                }
            }
            .accessibilityLabel(accessibilityDescription)
    }

    // Uses `Text` (not `String`) so SwiftUI's LocalizedStringKey init extracts
    // these three patterns into the String Catalog (H2 eng-review fix).
    private var accessibilityDescription: Text {
        switch count {
        case 0: return Text("Suber — no unread changes")
        case 1: return Text("Suber — 1 unread change")
        default: return Text("Suber — \(count) unread changes")
        }
    }
}

// MARK: - NSImage fallback

/// Static fallback renderer. If macOS strips the SwiftUI overlay's red fill
/// in template mode (QA may find this on notarized builds), switch the
/// MenuBarExtra to use this rendered image instead.
///
/// Usage (if needed):
///     MenuBarExtra {
///         MenuBarView()
///     } label: {
///         if let img = MenuBarBadgeFallback.render(count: store.unreadChangeCount) {
///             Image(nsImage: img)
///         } else {
///             Image("MenuBarIcon")
///         }
///     }
enum MenuBarBadgeFallback {

    /// Compose a 22×22 NSImage: template menubar icon + red dot with count.
    /// Returns nil if the base icon can't be loaded.
    static func render(count: Int, iconName: String = "MenuBarIcon") -> NSImage? {
        guard let baseIcon = NSImage(named: iconName) else { return nil }
        baseIcon.isTemplate = true

        // If no badge needed, return the plain icon.
        if count <= 0 { return baseIcon }

        let size = NSSize(width: 22, height: 22)
        let composed = NSImage(size: size)
        composed.lockFocus()
        defer { composed.unlockFocus() }

        // Draw the base icon (macOS tints it for light/dark menu bar).
        baseIcon.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        // Red badge circle at topTrailing.
        let countStr = count > 99 ? "99+" : "\(count)"
        let badgeDiameter: CGFloat = 10
        let badgeWidth: CGFloat = countStr.count > 1 ? badgeDiameter + 4 : badgeDiameter
        let badgeRect = NSRect(
            x: size.width - badgeWidth + 2,
            y: size.height - badgeDiameter + 2,
            width: badgeWidth,
            height: badgeDiameter
        )

        // Capsule
        let path = NSBezierPath(roundedRect: badgeRect,
                                xRadius: badgeDiameter / 2,
                                yRadius: badgeDiameter / 2)
        NSColor.systemRed.setFill()
        path.fill()

        // Number
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = countStr.size(withAttributes: attributes)
        let textPoint = NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        )
        countStr.draw(at: textPoint, withAttributes: attributes)

        // IMPORTANT: mark NOT a template so the red doesn't get stripped.
        // The base icon keeps its template-ness via the separate draw above.
        composed.isTemplate = false
        return composed
    }
}

#if DEBUG
#Preview("badge 3") { MenuBarBadgeView(count: 3).frame(width: 22, height: 22) }
#Preview("badge 99+") { MenuBarBadgeView(count: 125).frame(width: 22, height: 22) }
#Preview("badge 0 (hidden)") { MenuBarBadgeView(count: 0).frame(width: 22, height: 22) }
#endif
