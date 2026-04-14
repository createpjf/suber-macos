import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    @StateObject private var viewModel = DashboardViewModel()

    private let categoryColors: [Color] = [
        Color(hex: "6366f1"),  // indigo
        Color(hex: "f59e0b"),  // amber
        Color(hex: "10b981"),  // emerald
        Color(hex: "ef4444"),  // red
        Color(hex: "8b5cf6"),  // violet
        Color(hex: "06b6d4"),  // cyan
        Color(hex: "f97316"),  // orange
        Color(hex: "ec4899"),  // pink
        Color(hex: "14b8a6"),  // teal
        Color(hex: "84cc16"),  // lime
        Color(hex: "a855f7"),  // purple
        Color(hex: "64748b"),  // slate
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                spendOverview
                monthTrendChart
                categorySection
                topSubscriptionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { refresh() }
        .onChange(of: subscriptionStore.subscriptions) { refresh() }
    }

    private func refresh() {
        viewModel.update(
            subscriptions: subscriptionStore.subscriptions,
            currency: settingsStore.settings.primaryCurrency
        )
    }

    // MARK: - Section A: Spend Overview

    private var spendOverview: some View {
        VStack(spacing: 12) {
            // Main spend
            VStack(spacing: 2) {
                Text(CurrencyFormatter.formatShort(viewModel.monthlySpend, currency: settingsStore.settings.primaryCurrency))
                    .font(AppFont.bold(28))
                    .foregroundColor(Theme.textPrimary)
                Text("per month · \(CurrencyFormatter.formatShort(viewModel.yearlySpend, currency: settingsStore.settings.primaryCurrency))/yr")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
            }

            // Status counts
            HStack(spacing: 16) {
                statusBadge(count: viewModel.activeCount, label: "Active", color: Theme.success)
                statusBadge(count: viewModel.pausedCount, label: "Paused", color: Theme.warning)
                statusBadge(count: viewModel.trialCount, label: "Trial", color: Theme.trial)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func statusBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(AppFont.bold(13))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(AppFont.regular(10))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Section B: Month Trend

    private var monthTrendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MONTHLY TREND")
                .font(AppFont.bold(10))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if viewModel.monthTrend.isEmpty {
                Text("No data")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let maxVal = viewModel.monthTrend.map(\.total).max() ?? 1

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(viewModel.monthTrend) { month in
                        VStack(spacing: 4) {
                            Text(CurrencyFormatter.formatShort(month.total, currency: settingsStore.settings.primaryCurrency))
                                .font(AppFont.regular(8))
                                .foregroundColor(Theme.textDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(month.isCurrent ? Color(hex: "6366f1") : Theme.bgCell)
                                .frame(height: max(4, CGFloat(month.total / max(maxVal, 1)) * 80))

                            Text(month.label)
                                .font(AppFont.medium(9))
                                .foregroundColor(month.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(12)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Section C: Category Distribution

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORIES")
                .font(AppFont.bold(10))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if viewModel.categoryBreakdown.isEmpty {
                Text("No active subscriptions")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textDim)
            } else {
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(viewModel.categoryBreakdown) { cat in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorForCategory(cat.color))
                                .frame(width: max(4, geo.size.width * CGFloat(cat.percentage / 100) - 1))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                // Legend
                VStack(spacing: 6) {
                    ForEach(viewModel.categoryBreakdown) { cat in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForCategory(cat.color))
                                .frame(width: 8, height: 8)
                            Text(cat.name)
                                .font(AppFont.regular(11))
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text(CurrencyFormatter.formatShort(cat.total, currency: settingsStore.settings.primaryCurrency))
                                .font(AppFont.medium(11))
                                .foregroundColor(Theme.textPrimary)
                            Text(String(format: "%.0f%%", cat.percentage))
                                .font(AppFont.regular(10))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Section D: Top 5

    private var topSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP SUBSCRIPTIONS")
                .font(AppFont.bold(10))
                .foregroundColor(Theme.textSecondary)
                .tracking(1)

            if viewModel.topSubscriptions.isEmpty {
                Text("No active subscriptions")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textDim)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.topSubscriptions.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(AppFont.bold(12))
                                .foregroundColor(Theme.textDim)
                                .frame(width: 16)

                            LogoView(subscription: item.subscription, size: 28)

                            Text(item.subscription.name)
                                .font(AppFont.medium(12))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(CurrencyFormatter.formatShort(item.monthlyEquivalent, currency: item.subscription.currency) + "/mo")
                                .font(AppFont.medium(11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 6)

                        if index < viewModel.topSubscriptions.count - 1 {
                            Divider()
                                .background(Theme.border)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func colorForCategory(_ index: Int) -> Color {
        categoryColors[index % categoryColors.count]
    }
}
