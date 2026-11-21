import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var reviews: [RunnerRating] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppSpacing.md) {
                        AvatarView(name: env.session.profile?.fullName ?? "Guest", size: .large)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(env.session.profile?.fullName ?? "Guest")
                                .appText(.headline)
                            Text(env.session.profile?.email ?? "")
                                .appText(.caption, color: AppColors.textSecondary)
                            if let rating = env.session.profile?.rating {
                                Label(String(format: "%.2f runner rating", rating), systemImage: "star.fill")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.accentWarm)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

                if !reviews.isEmpty {
                    Section("Your reviews") {
                        ForEach(reviews.prefix(8)) { review in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= review.stars ? "star.fill" : "star")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppColors.accentWarm)
                                    }
                                    Spacer()
                                    Text(review.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .appText(.caption2, color: AppColors.textTertiary)
                                }
                                if let comment = review.comment, !comment.isEmpty {
                                    Text(comment).appText(.subheadline, color: AppColors.textSecondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Campus") {
                    LabeledContent("Campus", value: env.session.selectedCampus.name)
                    if let buildingId = env.session.profile?.homeBuildingId,
                       let building = env.session.buildings.first(where: { $0.id == buildingId }) {
                        LabeledContent("Home", value: "\(building.name) · \(building.neighborhood)")
                    }
                    if let vehicle = env.session.profile?.vehicleType {
                        LabeledContent("Vehicle", value: vehicle.label)
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            try? await env.authRepository.signOut()
                            env.session.profile = nil
                            env.cart.clear()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadReviews() }
            .refreshable { await loadReviews() }
        }
    }

    private func loadReviews() async {
        guard let id = env.session.profile?.id else { return }
        reviews = (try? await env.orderRepository.fetchRatings(forRunnerId: id)) ?? []
    }
}
