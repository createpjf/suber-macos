import SwiftUI
import WidgetKit

// MARK: - Monthly Spend Widget (Small)

struct MonthlySpendWidget: Widget {
    let kind = "MonthlySpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SuberTimelineProvider()) { entry in
            SmallSpendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // AUDIT-v1.9.2 U-18: Suber is an LSUIElement app — without a
                // deep link a widget tap does nothing visible. suber://changes
                // opens the Changes window via the existing URLSchemeHandler
                // route (SuberApp already handles external "suber" events).
                .widgetURL(URL(string: "suber://changes"))
        }
        .configurationDisplayName("Monthly Spend")
        .description("See your total monthly subscription spend.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Upcoming Billing Widget (Medium)

struct UpcomingBillingWidget: Widget {
    let kind = "UpcomingBillingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SuberTimelineProvider()) { entry in
            MediumUpcomingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // AUDIT-v1.9.2 U-18: same deep link as MonthlySpendWidget.
                .widgetURL(URL(string: "suber://changes"))
        }
        .configurationDisplayName("Upcoming Bills")
        .description("See subscriptions billing in the next 7 days.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct SuberWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthlySpendWidget()
        UpcomingBillingWidget()
    }
}
