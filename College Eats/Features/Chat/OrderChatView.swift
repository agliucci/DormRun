import SwiftUI

enum ChatPerspective: Sendable {
    /// Infer from order + signed-in user when possible.
    case auto
    /// Customer talking to runner (tracking screen).
    case asCustomer
    /// Runner talking to customer (active delivery).
    case asRunner
}

struct OrderChatView: View {
    let order: Order
    var perspective: ChatPerspective = .auto

    @Environment(AppEnvironment.self) private var env
    @State private var messages: [OrderMessage] = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var didHideTabBar = false

    private var myId: String? { env.session.profile?.id }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let errorMessage {
                Text(errorMessage)
                    .appText(.caption, color: AppColors.danger)
                    .padding(.horizontal, AppSpacing.screenMargin)
                    .padding(.vertical, AppSpacing.xs)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Chat · \(peerLabel)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onAppear {
            guard !didHideTabBar else { return }
            env.setFloatingTabBarHidden(true)
            didHideTabBar = true
        }
        .onDisappear {
            guard didHideTabBar else { return }
            env.setFloatingTabBarHidden(false)
            didHideTabBar = false
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if messages.isEmpty {
                        emptyState
                            .padding(.top, AppSpacing.xxl)
                    }
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                }
                .padding(AppSpacing.screenMargin)
                .padding(.bottom, AppSpacing.md)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(AppMotion.spring) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.brand.opacity(0.85))
            Text("No messages yet")
                .appText(.headline)
            Text("Say hi to your \(peerLabel) — drop-off tips, ETA questions, all good here.")
                .appText(.subheadline, color: AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.sm) {
            TextField("Message your \(peerLabel)…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(AppSpacing.sm)
                .background(AppColors.surfaceMuted)
                .appCornerRadius(AppRadius.md)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? AppColors.brand : AppColors.textTertiary)
                    .frame(width: AppSpacing.minTapTarget, height: AppSpacing.minTapTarget)
            }
            .disabled(!canSend || isSending)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .padding(.vertical, AppSpacing.sm)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Divider().opacity(0.35)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var peerLabel: String {
        switch perspective {
        case .asCustomer: return "runner"
        case .asRunner: return "customer"
        case .auto:
            if let myId {
                if myId == order.runnerId, myId != order.customerId { return "customer" }
                if myId == order.customerId { return "runner" }
            }
            // Solo test (same account both sides): don't use tab mode — default to runner peer.
            return "runner"
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && myId != nil
    }

    private func bubble(_ message: OrderMessage) -> some View {
        let mine = message.senderId == myId
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .appText(.body, color: mine ? AppColors.textOnBrand : AppColors.textPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(mine ? AppColors.brand : AppColors.surfaceMuted)
                    .appCornerRadius(AppRadius.lg)
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .appText(.caption2, color: AppColors.textTertiary)
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        do {
            messages = try await env.chatRepository.fetchMessages(orderId: order.id)
            errorMessage = nil
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func send() async {
        guard let myId, canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await env.chatRepository.sendMessage(
                orderId: order.id,
                senderId: myId,
                body: draft
            )
            messages.append(sent)
            draft = ""
            AppHaptics.light()
            errorMessage = nil
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}

#Preview("Order chat") {
    let env = AppEnvironment(chatRepository: MockChatRepository())
    env.session.profile = MockCatalogData.demoCustomer
    return NavigationStack {
        OrderChatView(
            order: Order(
                id: "preview-order",
                customerId: MockCatalogData.customerId,
                runnerId: MockCatalogData.runnerId,
                locationId: "d0000000-0000-4000-8000-000000000005",
                locationName: "Blue Wall",
                dropoffBuildingId: "b0000000-0000-4000-8000-000000000002",
                dropoffBuildingName: "John Quincy Adams Hall",
                dropoffNote: "Lobby",
                status: .enRoute,
                subtotalCents: 1200,
                deliveryFeeCents: 299,
                tipCents: 200,
                runnerMealBumpCents: 0,
                fulfillmentMode: .retailPurchase,
                handoffCode: "4821",
                items: [],
                runner: MockCatalogData.demoRunner,
                placedAt: .now.addingTimeInterval(-600)
            )
        )
    }
    .environment(env)
}
