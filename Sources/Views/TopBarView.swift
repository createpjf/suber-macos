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
            HStack {
                HStack(spacing: 6) {
                    TopBarButton(icon: "plus.circle", isActive: false, action: onAdd)
                    TopBarButton(
                        icon: currentView == .list ? "calendar" : "list.bullet.clipboard",
                        isActive: false,
                        action: { currentView = currentView == .list ? .calendar : .list }
                    )
                    TopBarButton(
                        icon: "chart.bar",
                        isActive: currentView == .dashboard,
                        action: { currentView = currentView == .dashboard ? .calendar : .dashboard }
                    )
                }

                Spacer()

                TopBarButton(
                    icon: "gearshape",
                    isActive: currentView == .settings,
                    action: { currentView = currentView == .settings ? .calendar : .settings }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

private struct TopBarButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isActive { return Theme.bgCell }
        return isHovering ? Theme.bgSecondary : Color.clear
    }
}
