import SwiftUI

struct ToggleRow: View {
    // AUDIT-v1.9.2 U-03: was String — Text(String) takes the StringProtocol
    // overload and never consults the String Catalog, so translated keys
    // ("Watch Apple Mail" etc.) rendered English forever. LocalizedStringKey
    // keeps every literal-passing call site unchanged and restores lookup.
    let label: LocalizedStringKey
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
