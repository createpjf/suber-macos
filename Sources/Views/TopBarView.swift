import SwiftUI

struct TopBarView: View {
    @Binding var currentView: AppView
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            // Centered title
            HStack(spacing: 6) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundColor(Theme.textPrimary)
                Text("Suber")
                    .font(AppFont.medium(14))
                    .foregroundColor(Theme.textPrimary)
            }

            // Left + Right buttons
            // AUDIT-v1.9.2 U-10: every top-bar button is icon-only — give each
            // a functional label (VoiceOver + tooltip). The SF Symbol default
            // describes the glyph ("Bar Chart"), not the destination.
            HStack {
                HStack(spacing: 6) {
                    BarButtonView(icon: "plus.circle", label: "Add subscription", action: onAdd)
                        .keyboardShortcut("n", modifiers: .command)
                    BarButtonView(
                        icon: currentView == .list ? "calendar" : "list.bullet.clipboard",
                        label: currentView == .list ? "Show calendar" : "Show list",
                        action: { currentView = currentView == .list ? .calendar : .list }
                    )
                    .keyboardShortcut("l", modifiers: .command)
                    BarButtonView(
                        icon: "chart.bar",
                        label: "Dashboard",
                        isActive: currentView == .dashboard,
                        action: { currentView = currentView == .dashboard ? .calendar : .dashboard }
                    )
                }

                Spacer()

                BarButtonView(
                    icon: "gearshape",
                    label: "Settings",
                    isActive: currentView == .settings,
                    action: { currentView = currentView == .settings ? .calendar : .settings }
                )
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// Extracted to a separate View so each button has its own @State for hover tracking.
private struct BarButtonView: View {
    let icon: String
    /// AUDIT-v1.9.2 U-10: functional label, used for both VoiceOver and the
    /// hover tooltip.
    /// AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) so the literal
    /// labels the callers pass resolve through the String Catalog.
    let label: LocalizedStringKey
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive || isHovered ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(isHovered ? Theme.bgCell : Theme.bgSecondary.opacity(0.01))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(label)
        .help(label)
    }
}
