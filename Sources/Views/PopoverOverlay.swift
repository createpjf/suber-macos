import SwiftUI

// ┌───────────── PopoverOverlay — sheet replacement for menubar popover ───────┐
// │                                                                            │
// │  v1.7.1 fix: `.sheet(isPresented:)` modifiers inside the MenuBarExtra      │
// │  popover get destroyed whenever the popover loses key — which happens      │
// │  easily (SecureField → SecureInputServer focus, system dialogs, etc.).     │
// │  v1.7.0's IMAPAccountSheet was completely unusable because clicking the    │
// │  App Password SecureField immediately dismissed the entire sheet.          │
// │                                                                            │
// │  The previous `MenuBarView.formOverlay` helper proved the right pattern:   │
// │  render the modal as an overlay INSIDE the popover view tree so the        │
// │  popover stays key the whole time. This file lifts that pattern into a     │
// │  reusable modifier so any popover-scoped modal can use the same approach.  │
// │                                                                            │
// │  WHEN TO USE                                                               │
// │    Use `.popoverOverlay(isPresented:)` instead of `.sheet(isPresented:)`   │
// │    for any modal flow inside the menubar popover.                          │
// │                                                                            │
// │  WHEN NOT TO USE                                                           │
// │    For workflows that need to coexist with system dialogs (file picker,    │
// │    TCC permission prompt, NSSavePanel, sibling alerts), promote to a       │
// │    separate `Window` scene + WindowActivationCoordinator — see ImportWindow│
// │    in SuberApp.swift for the established pattern.                          │
// │                                                                            │
// │  WHY `.alert` STILL WORKS                                                  │
// │    SwiftUI `.alert(...)` is implemented via NSAlert, which lives at        │
// │    .modalPanel window level — independent of the popover NSWindow.         │
// │    `.sheet(...)` does not get this treatment; it's a CHILD of its parent   │
// │    NSWindow and dies with it. NSAlert-backed `.alert` and                  │
// │    `.confirmationDialog` are safe to use from popover scope.               │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct PopoverOverlay<Overlay: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let overlay: () -> Overlay

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                overlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bgPrimary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    /// Render `overlay` as an in-popover modal while `isPresented` is true.
    /// Use instead of `.sheet(isPresented:)` for menubar-popover-scoped modals.
    /// See `PopoverOverlay` header for context on when to use this vs a Window.
    func popoverOverlay<Overlay: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) -> some View {
        modifier(PopoverOverlay(isPresented: isPresented, overlay: overlay))
    }

    /// `.sheet(item:)` ergonomic parity. Renders overlay when `item != nil`,
    /// passes the unwrapped value into the closure. Setting the binding to
    /// nil dismisses the overlay.
    func popoverOverlay<Item: Identifiable, Overlay: View>(
        item: Binding<Item?>,
        @ViewBuilder overlay: @escaping (Item) -> Overlay
    ) -> some View {
        modifier(PopoverOverlay(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            overlay: { item.wrappedValue.map(overlay) }
        ))
    }
}
