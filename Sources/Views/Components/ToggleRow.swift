import SwiftUI

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(Theme.textPrimary)
                .labelsHidden()
        }
    }
}
