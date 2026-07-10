import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore

    @StateObject private var viewModel = DashboardViewModel()

    var onAdd: (() -> Void)? = nil
    var onImport: (() -> Void)? = nil

    // AUDIT-v1.9.2 U-14: chart colors centralized in Theme.chartPalette.

    var body: some View {
        ScrollView {
            if hasAnyData {
                VStack(spacing: 0) {
                    spendOverview
                    sectionDivider
                    monthTrendChart
                    sectionDivider
                    categorySection
                    sectionDivider
                    topSubscriptionsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                emptyState
                    .padding(.horizontal, 16)
                    .padding(.top, 40)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { refresh() }
        .onChange(of: subscriptionStore.subscriptions) { refresh() }
    }

    private var sectionDivider: some View {
        Divider()
            .background(Theme.border)
            .padding(.vertical, 4)
    }

    private var hasAnyData: Bool {
        subscriptionStore.subscriptions.contains { $0.status != .cancelled }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.textDim)

            VStack(spacing: 6) {
                Text("No subscriptions yet")
                    .font(AppFont.medium(15))
                    .foregroundColor(Theme.textPrimary)
                Text("Add your first subscription to see monthly spend, trends, and category breakdown here.")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            VStack(spacing: 8) {
                if let onAdd = onAdd {
                    Button(action: onAdd) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add subscription")
                                .font(AppFont.medium(12))
                        }
                        .foregroundColor(Theme.bgPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.textPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let onImport = onImport {
                    Button(action: onImport) {
                        Text("or import a bank statement")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.textSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
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
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textSecondary)
            }

            // Status counts (hide when everything is zero)
            if viewModel.activeCount + viewModel.pausedCount + viewModel.trialCount > 0 {
                HStack(spacing: 16) {
                    statusBadge(count: viewModel.activeCount, label: "Active", color: Theme.success)
                    statusBadge(count: viewModel.pausedCount, label: "Paused", color: Theme.warning)
                    statusBadge(count: viewModel.trialCount, label: "Trial", color: Theme.trial)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // AUDIT-v1.9.2 U-03: LocalizedStringKey (was String) — literal labels.
    private func statusBadge(count: Int, label: LocalizedStringKey, color: Color) -> some View {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly trend")
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)

            let allZero = viewModel.monthTrend.allSatisfy { $0.total == 0 }

            if viewModel.monthTrend.isEmpty || allZero {
                Text("No spend yet")
                    .font(AppFont.regular(12))
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                let maxVal = viewModel.monthTrend.map(\.total).max() ?? 1

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(viewModel.monthTrend) { month in
                        VStack(spacing: 4) {
                            if month.total > 0 {
                                Text(CurrencyFormatter.formatShort(month.total, currency: settingsStore.settings.primaryCurrency))
                                    .font(AppFont.regular(8))
                                    .foregroundColor(Theme.textDim)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                Text(" ")
                                    .font(AppFont.regular(8))
                            }

                            if month.total > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(month.isCurrent ? Theme.chartHighlight : Theme.bgCell)
                                    .frame(height: max(4, CGFloat(month.total / max(maxVal, 1)) * 80))
                            } else {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 0)
                            }

                            Text(month.label)
                                .font(AppFont.medium(10))
                                .foregroundColor(month.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(.vertical, 14)
    }

    // MARK: - Section C: Category Distribution

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)

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
                            Text(AppConstants.localizedCategory(cat.name))
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
        .padding(.vertical, 14)
    }

    // MARK: - Section D: Top 5

    private var topSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top subscriptions")
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)

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

                            // U-03: interpolation (not `+` concat) so the
                            // "%@/mo" catalog key resolves.
                            Text("\(CurrencyFormatter.formatShort(item.monthlyEquivalent, currency: item.subscription.currency))/mo")
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
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func colorForCategory(_ index: Int) -> Color {
        Theme.chartPalette[index % Theme.chartPalette.count]
    }
}
