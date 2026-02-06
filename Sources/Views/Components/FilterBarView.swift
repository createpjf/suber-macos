import SwiftUI

struct FilterBarView: View {
    @Binding var selected: String

    private let filters = ["all", "active", "paused", "trial", "cancelled"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(filters, id: \.self) { filter in
                Button(action: { selected = filter }) {
                    Text(filter.capitalized)
                        .font(AppFont.medium(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected == filter ? Theme.textPrimary : Theme.bgSecondary)
                        .foregroundColor(selected == filter ? Theme.bgPrimary : Theme.textSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
