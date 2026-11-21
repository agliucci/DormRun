import SwiftUI

struct OrderChatView: View {
    let order: Order

    @Environment(AppEnvironment.self) private var env
    @State private var messages: [OrderMessage] = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    private var myId: String? { env.session.profile?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(AppSpacing.screenMargin)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(AppMotion.spring) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .appText(.caption, color: AppColors.danger)
                    .padding(.horizontal, AppSpacing.screenMargin)
            }

            HStack(spacing: AppSpacing.sm) {
                TextField("Message your \(peerLabel)…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(AppSpacing.sm)
                    .background(AppColors.surfaceMuted)
                    .appCornerRadius(AppRadius.md)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? AppColors.brand : AppColors.textTertiary)
                }
                .disabled(!canSend || isSending)
                .accessibilityLabel("Send")
            }
            .padding(AppSpacing.screenMargin)
            .background(.ultraThinMaterial)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var peerLabel: String {
        env.session.profile?.mode == .runner ? "customer" : "runner"
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
