import SwiftUI
import WidgetKit

struct MediumUpcomingWidgetView: View {
    let entry: SuberWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "bell")
                        .font(.system(size: 10, weight: .medium))
                    Text("Upcoming Bills")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.secondary)

                Spacer()

                // U-03: interpolation (not `+` concat) so "%@/mo" resolves.
                Text("\(CurrencyFormatter.formatShort(entry.monthlySpend, currency: entry.currency))/mo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if entry.upcomingBills.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                        Text("No upcoming bills this week")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(spacing: 4) {
                    ForEach(entry.upcomingBills) { bill in
                        HStack(spacing: 8) {
                            // Initial circle as icon placeholder
                            Text(bill.initial)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text(bill.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)

                            Spacer()

                            Text(CurrencyFormatter.formatShort(bill.amount, currency: bill.currency))
                                .font(.system(size: 12, weight: .semibold))

                            Text(daysText(bill.daysUntil))
                                .font(.system(size: 10))
                                .foregroundColor(bill.daysUntil <= 1 ? .orange : .secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func daysText(_ days: Int) -> String {
        // U-03: String(localized:) — note the widget bundle currently ships
        // without the catalog (see project.yml), so this falls back to
        // English until the catalog is added to the SuberWidget target.
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Tomorrow") }
        return String(localized: "in \(days)d")
    }
}
