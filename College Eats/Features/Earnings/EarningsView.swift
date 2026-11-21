import SwiftUI
import Charts

struct EarningsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var summary: EarningsSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && summary == nil {
                    VStack(spacing: AppSpacing.md) {
                        SkeletonView(height: 100)
                        SkeletonView(height: 180)
                        SkeletonView(height: 120)
                    }
                    .padding(AppSpacing.screenMargin)
                } else if let errorMessage, summary == nil {
                    EmptyStateView(
                        systemImage: EmptyStateCopy.offline.image,
                        title: "Earnings unavailable",
                        message: errorMessage,
                        actionTitle: "Retry"
                    ) { Task { await load() } }
                } else if let summary {
                    content(summary)
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func content(_ summary: EarningsSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                HStack(spacing: AppSpacing.md) {
                    metricCard(title: "Today", cents: summary.todayCents)
                    metricCard(title: "This week", cents: summary.weekCents)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("This week").appText(.headline)
                    Chart(summary.dailyBars) { bar in
                        BarMark(
                            x: .value("Day", bar.dayLabel),
                            y: .value("Earned", Double(bar.cents) / 100.0)
                        )
                        .foregroundStyle(AppColors.brand.gradient)
                        .cornerRadius(6)
                    }
                    .frame(height: 180)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                }
                .padding(AppSpacing.md)
                .background(AppCardBackground(radius: AppRadius.xl))

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Payouts").appText(.headline)
                    Text(summary.payoutStatus)
                        .appText(.subheadline, color: AppColors.textSecondary)
                    PrimaryButton(title: "Stripe Connect (test)", style: .secondary) {
                        Task {
                            _ = try? await env.payments.createConnectOnboardingLink(
                                runnerId: env.session.profile?.id ?? ""
                            )
                            AppHaptics.light()
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppCardBackground(radius: AppRadius.xl))

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Delivery history").appText(.headline)
                    if summary.history.isEmpty {
                        Text("Completed deliveries will land here.")
                            .appText(.subheadline, color: AppColors.textSecondary)
                    } else {
                        ForEach(summary.history) { order in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(order.locationName).appText(.bodyEmphasized)
                                    Text(order.deliveredAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                        .appText(.caption, color: AppColors.textSecondary)
                                }
                                Spacer()
                                Text(((Double(order.deliveryFeeCents + order.tipCents)) / 100).formatted(.currency(code: "USD")))
                                    .font(AppTypography.price)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, AppSpacing.xs)
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppCardBackground(radius: AppRadius.xl))
            }
            .padding(AppSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCard(title: String, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title).appText(.caption, color: AppColors.textSecondary)
            Text((Double(cents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppCardBackground(radius: AppRadius.xl))
    }

    private func load() async {
        guard let runnerId = env.session.profile?.id else { return }
        isLoading = summary == nil
        defer { isLoading = false }
        do {
            summary = try await env.orderRepository.fetchEarnings(runnerId: runnerId)
            errorMessage = nil
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }
}
