import SwiftUI

struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)

            TextField("Search subscriptions...", text: $text)
                .textFieldStyle(.plain)
                .font(AppFont.regular(12))
                .foregroundColor(Theme.textPrimary)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                // AUDIT-v1.9.2 U-10: icon-only clear button needs a label.
                // U-03: Text(...) wrapper so the String Catalog extracts it.
                .accessibilityLabel(Text("Clear search"))
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.bgSecondary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
