import SwiftUI

struct FilterBarView: View {
    @Binding var selected: String

    private let filters = ["all", "active", "paused", "trial", "cancelled"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(filters, id: \.self) { filter in
                FilterChip(
                    label: filter.capitalized,
                    isSelected: selected == filter,
                    action: { selected = filter }
                )
            }
            Spacer()
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppFont.medium(11))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(background)
                .foregroundColor(isSelected ? Theme.bgPrimary : Theme.textSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.textPrimary }
        return isHovering ? Theme.bgCell : Theme.bgSecondary
    }
}
