import SwiftUI

struct LocationCard: View {
    let location: DiningLocationCardModel
    var namespace: Namespace.ID? = nil
    var isCompact: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                hero
                details
            }
            .background(AppCardBackground(radius: AppRadius.xl))
            .appCornerRadius(AppRadius.xl)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens menu")
        .accessibilityAddTraits(.isButton)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let namespace {
                    CampusImageView(
                        assetName: location.imageAssetName,
                        url: location.imageURL,
                        showsScrim: true
                    )
                    .matchedGeometryEffect(id: "location-image-\(location.id)", in: namespace)
                } else {
                    CampusImageView(
                        assetName: location.imageAssetName,
                        url: location.imageURL,
                        showsScrim: true
                    )
                }
            }
            .frame(height: isCompact ? 120 : 148)
            .frame(maxWidth: .infinity)
            .clipped()

            HStack(spacing: AppSpacing.xs) {
                PillTag(kind: .status(location.openStatus), isCompact: true, surface: .onMedia)
                if location.openStatus != .closed {
                    PillTag(kind: .busy(location.busyLevel), isCompact: true, surface: .onMedia)
                }
            }
            .padding(AppSpacing.sm)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(location.name)
                .appText(.title3)
                .lineLimit(1)

            Text(location.subtitle)
                .appText(.caption, color: AppColors.textSecondary)
                .lineLimit(1)

            if location.openStatus != .closed {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.brand)
                        .symbolRenderingMode(.hierarchical)
                    Text("~\(location.estimatedDeliveryMinutes) min")
                        .appText(.caption, color: AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.xxxs)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityLabel: String {
        var parts = [location.name, location.subtitle, location.openStatus.label]
        if location.openStatus != .closed {
            parts.append(location.busyLevel.label)
            parts.append("About \(location.estimatedDeliveryMinutes) minutes")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: AppSpacing.carouselGap) {
            LocationCard(location: GalleryMocks.worcester) {}
                .frame(width: 260)
            LocationCard(location: GalleryMocks.franklin) {}
                .frame(width: 260)
            LocationCard(location: GalleryMocks.closedHall) {}
                .frame(width: 260)
        }
        .padding(AppSpacing.screenMargin)
    }
    .background(AppColors.background)
}
