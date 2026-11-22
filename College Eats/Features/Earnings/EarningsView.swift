import SwiftUI
import Charts

struct EarningsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var summary: EarningsSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cashOutMessage: String?
    @State private var showLinkBankFromCashOut = false
    @State private var isCashingOut = false
    @State private var isLinkingBank = false

    var body: some View {
        Group {
            if isLoading && summary == nil {
                VStack(spacing: AppSpacing.md) {
                    SkeletonView(height: 120)
                    SkeletonView(height: 180)
                    SkeletonView(height: 140)
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
        .alert("Cash out", isPresented: Binding(
            get: { cashOutMessage != nil },
            set: { if !$0 { cashOutMessage = nil; showLinkBankFromCashOut = false } }
        )) {
            if showLinkBankFromCashOut {
                Button("Link bank account") {
                    cashOutMessage = nil
                    showLinkBankFromCashOut = false
                    Task { await openConnect() }
                }
                Button("Not now", role: .cancel) {
                    cashOutMessage = nil
                    showLinkBankFromCashOut = false
                }
            } else {
                Button("OK", role: .cancel) { cashOutMessage = nil }
            }
        } message: {
            Text(cashOutMessage ?? "")
        }
    }

    private func content(_ summary: EarningsSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                availableCard(summary)

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

                payoutCard(summary)

                historyCard(summary)
            }
            .padding(AppSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func availableCard(_ summary: EarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Available")
                .appText(.caption, color: AppColors.textOnBrand.opacity(0.85))
            Text((Double(summary.availableCents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.display)
                .foregroundStyle(AppColors.textOnBrand)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Tips + fees · retail food reimbursements included when you buy with card.")
                .appText(.footnote, color: AppColors.textOnBrand.opacity(0.9))

            Button {
                Task { await cashOut(summary) }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    if isCashingOut {
                        ProgressView().tint(AppColors.brand)
                    } else {
                        Image(systemName: "building.columns.fill")
                        Text("Cash out to bank")
                            .font(AppTypography.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppSpacing.minTapTarget)
                .foregroundStyle(AppColors.brand)
                .background(AppColors.textOnBrand)
                .appCornerRadius(AppRadius.lg)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(summary.availableCents <= 0 || isCashingOut)
            .opacity(summary.availableCents > 0 ? 1 : 0.55)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppColors.brand, AppColors.brand.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .appCornerRadius(AppRadius.xxl)
    }

    private func payoutCard(_ summary: EarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Payouts").appText(.headline)
            Text(summary.payoutStatus)
                .appText(.subheadline, color: AppColors.textSecondary)

            Label(
                summary.bankLinked ? "Bank account linked" : "Link a bank to get paid",
                systemImage: summary.bankLinked ? "checkmark.seal.fill" : "link"
            )
            .font(AppTypography.subheadline)
            .foregroundStyle(summary.bankLinked ? AppColors.success : AppColors.brand)

            Text("Tap below to open Stripe Connect and add your debit or bank account — same flow DoorDash uses.")
                .appText(.footnote, color: AppColors.textTertiary)

            PrimaryButton(
                title: summary.bankLinked ? "Manage payout account" : "Link bank account",
                systemImage: "building.columns",
                style: .secondary,
                isLoading: isLinkingBank
            ) {
                Task { await openConnect() }
            }

            if !summary.bankLinked {
                Button("I’ve finished linking") {
                    RunnerPayoutStore.markLinkedFromReturnURL()
                    AppHaptics.success()
                    Task { await load() }
                }
                .font(AppTypography.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.brand)
                .frame(maxWidth: .infinity, minHeight: AppSpacing.minTapTarget)
            }
        }
        .padding(AppSpacing.md)
        .background(AppCardBackground(radius: AppRadius.xl))
    }

    private func historyCard(_ summary: EarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Delivery history").appText(.headline)
            if summary.history.isEmpty {
                Text("Complete a delivery and it’ll show up here with what you earned.")
                    .appText(.subheadline, color: AppColors.textSecondary)
            } else {
                ForEach(summary.history) { order in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(order.locationName).appText(.bodyEmphasized)
                            Text(order.fulfillmentMode.title)
                                .appText(.caption, color: AppColors.textSecondary)
                            Text(order.deliveredAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .appText(.caption, color: AppColors.textSecondary)
                        }
                        Spacer()
                        Text(((Double(order.runnerPayoutCents)) / 100).formatted(.currency(code: "USD")))
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

    private func openConnect() async {
        guard let runnerId = env.session.profile?.id else { return }
        isLinkingBank = true
        defer { isLinkingBank = false }
        do {
            let url = try await env.payments.createConnectOnboardingLink(runnerId: runnerId)
            openURL(url)
            AppHaptics.light()
            cashOutMessage = "Finish bank setup in the browser, then come back and tap “I’ve finished linking”."
            showLinkBankFromCashOut = false
        } catch {
            cashOutMessage = (error as? AppError)?.message ?? error.localizedDescription
            showLinkBankFromCashOut = false
            AppHaptics.error()
        }
    }

    private func cashOut(_ summary: EarningsSummary) async {
        isCashingOut = true
        defer { isCashingOut = false }
        guard let runnerId = env.session.profile?.id else { return }

        if !summary.bankLinked {
            cashOutMessage = "Link a bank account with Stripe Connect first — then cash out sends your balance for real."
            showLinkBankFromCashOut = true
            AppHaptics.light()
            return
        }

        do {
            let result = try await env.payments.cashOutAvailableBalance(runnerId: runnerId)
            cashOutMessage = result.message
            showLinkBankFromCashOut = false
            AppHaptics.success()
            await load()
        } catch {
            let message = (error as? AppError)?.message ?? error.localizedDescription
            if message.localizedCaseInsensitiveContains("link a bank") {
                cashOutMessage = message
                showLinkBankFromCashOut = true
            } else {
                cashOutMessage = message
                showLinkBankFromCashOut = false
            }
            AppHaptics.error()
        }
    }
}

private extension Int {
    var formattedAsMoney: String {
        (Double(self) / 100).formatted(.currency(code: "USD"))
    }
}
