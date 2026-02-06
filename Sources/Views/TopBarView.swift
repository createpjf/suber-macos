import SwiftUI

struct TopBarView: View {
    @Binding var currentView: AppView
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            // Centered title
            Text("SubReminder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .tracking(0.5)

            // Left + Right buttons
            HStack {
                HStack(spacing: 6) {
                    barButton(icon: "plus", action: onAdd)
                    barButton(
                        icon: currentView == .list ? "calendar" : "list.bullet",
                        action: { currentView = currentView == .list ? .calendar : .list }
                    )
                }

                Spacer()

                barButton(
                    icon: "gearshape",
                    isActive: currentView == .settings,
                    action: { currentView = currentView == .settings ? .calendar : .settings }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func barButton(icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.bgSecondary.opacity(0.01))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // SwiftUI handles hover natively via the background
        }
    }
}
