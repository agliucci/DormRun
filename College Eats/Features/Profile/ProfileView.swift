import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var reviews: [RunnerRating] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var photoError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppSpacing.md) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(
                                name: env.session.profile?.fullName ?? "Guest",
                                imageURL: env.session.profile?.avatarURL,
                                size: .large
                            )
                            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppColors.textOnBrand)
                                    .padding(7)
                                    .background(AppColors.brand)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Upload profile photo")
                        }

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
                            if isUploadingPhoto {
                                Text("Updating photo…")
                                    .appText(.caption2, color: AppColors.textTertiary)
                            } else {
                                Text("Tap camera to change photo")
                                    .appText(.caption2, color: AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)

                    if let photoError {
                        Text(photoError).appText(.footnote, color: AppColors.danger)
                    }
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await savePhoto(item) }
            }
        }
    }

    private func loadReviews() async {
        guard let id = env.session.profile?.id else { return }
        reviews = (try? await env.orderRepository.fetchRatings(forRunnerId: id)) ?? []
    }

    private func savePhoto(_ item: PhotosPickerItem) async {
        isUploadingPhoto = true
        photoError = nil
        defer {
            isUploadingPhoto = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.82),
                  var profile = env.session.profile else {
                photoError = "Couldn’t read that photo."
                return
            }
            let url = try ProfilePhotoStore.save(jpeg, userId: profile.id)
            profile.avatarURL = url
            env.session.profile = try await env.authRepository.updateProfile(profile)
            AppHaptics.success()
        } catch {
            photoError = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}

enum ProfilePhotoStore {
    static func save(_ jpeg: Data, userId: String) throws -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(userId).jpg")
        try jpeg.write(to: file, options: .atomic)
        return file
    }
}
