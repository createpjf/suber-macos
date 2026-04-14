import SwiftUI
import WidgetKit

// MARK: - Monthly Spend Widget (Small)

struct MonthlySpendWidget: Widget {
    let kind = "MonthlySpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SuberTimelineProvider()) { entry in
            SmallSpendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
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
        }
        .configurationDisplayName("Upcoming Bills")
        .description("See subscriptions billing in the next 7 days.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct SubReminderWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthlySpendWidget()
        UpcomingBillingWidget()
    }
}
