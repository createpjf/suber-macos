import AppKit

/// Encapsulates the NSApp activation-policy dance needed when a menu-bar-only
/// app (`LSUIElement=true`, activation policy `.accessory`) wants to open a
/// regular `Window` scene and have it actually come to foreground.
///
/// Problem: in `.accessory` policy the app has no Dock icon and macOS will not
/// bring it to front when a new window is created. `openWindow(id:)` succeeds
/// but the window lands behind whatever app was frontmost (browser, etc.),
/// and the menu-bar popover auto-closes when it loses key — so users see
/// nothing and think the app froze.
///
/// Fix: right before surfacing the window, flip to `.regular` and call
/// `activate()`. When the window closes with no other regular windows open,
/// flip back to `.accessory` so the Dock icon disappears again.
enum WindowActivationCoordinator {

    /// Bring the app foreground when a regular window is about to appear.
    /// Changes activation policy from `.accessory` to `.regular` (gets a Dock
    /// icon + Cmd-Tab presence) and calls `NSApp.activate()` so macOS orders
    /// the new window above other apps' windows.
    @MainActor
    static func surface() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    /// Call when a regular window just closed. After a short delay (so SwiftUI
    /// finishes tearing down the window), if no other regular windows remain
    /// visible, revert activation policy to `.accessory` — we're a pure
    /// menu-bar app again.
    ///
    /// The delay is important: SwiftUI's `dismiss()` doesn't remove the
    /// underlying NSWindow synchronously. Counting windows immediately would
    /// still see the closing one as visible.
    @MainActor
    static func relinquishIfNoWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let hasVisibleRegularWindow = NSApp.windows.contains { (window: NSWindow) -> Bool in
                window.isVisible
                    && window.styleMask.contains(NSWindow.StyleMask.titled)
                    && !window.styleMask.contains(NSWindow.StyleMask.nonactivatingPanel)
            }
            if !hasVisibleRegularWindow && NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
