import SwiftUI
import WidgetKit

struct SmallSpendWidgetView: View {
    let entry: SuberWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                    .font(.system(size: 10, weight: .medium))
                Text("Monthly Spend")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)

            Spacer()

            Text(CurrencyFormatter.formatShort(entry.monthlySpend, currency: entry.currency))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("\(entry.activeCount) active")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
