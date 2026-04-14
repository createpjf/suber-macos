import AppKit
import Carbon.HIToolbox

/// Registers a global keyboard shortcut (Option+S) to toggle the menu bar popover.
final class HotkeyService {
    static let shared = HotkeyService()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    // MARK: - Public

    func register() {
        // Global monitor: catches key events when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: catches key events when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // consume the event
            }
            return event
        }
    }

    func unregister() {
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
    }

    // MARK: - Private

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for Option + S
        guard event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              event.keyCode == UInt16(kVK_ANSI_S) else {
            return false
        }

        DispatchQueue.main.async {
            self.toggleMenuBarPopover()
        }
        return true
    }

    private func toggleMenuBarPopover() {
        // Find the app's status bar button and simulate a click
        guard let button = NSApp.windows
            .compactMap({ $0 as? NSPanel })
            .first?.contentView?
            .window?
            .parent?
            .contentView?
            .superview as? NSStatusBarButton ?? findStatusButton()
        else {
            // Fallback: just activate the app which may trigger the menu bar window
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        button.performClick(nil)
    }

    private func findStatusButton() -> NSStatusBarButton? {
        // Walk through status items to find ours
        // The MenuBarExtra creates a status item; we find it via the app's windows
        for window in NSApp.windows {
            // MenuBarExtra windows have a specific class name pattern
            let className = String(describing: type(of: window))
            if className.contains("StatusBar") || className.contains("MenuBar") {
                if let button = window.contentView?.superview as? NSStatusBarButton {
                    return button
                }
            }
        }
        return nil
    }
}
