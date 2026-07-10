import SwiftUI

struct FilterBarView: View {
    @Binding var selected: String

    private let filters = ["all", "active", "paused", "trial", "cancelled"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(filters, id: \.self) { filter in
                FilterChip(
                    label: label(for: filter),
                    isSelected: selected == filter,
                    action: { selected = filter }
                )
            }
            Spacer()
        }
    }

    // AUDIT-v1.9.2 U-03: `filter.capitalized` produced a runtime String that
    // bypassed the String Catalog. The raw values stay stable identifiers
    // (they match SubscriptionStatus.rawValue for filtering); display goes
    // through literal LocalizedStringKeys so zh-Hans resolves.
    private func label(for filter: String) -> LocalizedStringKey {
        switch filter {
        case "all": return "All"
        case "active": return "Active"
        case "paused": return "Paused"
        case "trial": return "Trial"
        case "cancelled": return "Cancelled"
        default: return LocalizedStringKey(filter.capitalized)
        }
    }
}

private struct FilterChip: View {
    let label: LocalizedStringKey
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
