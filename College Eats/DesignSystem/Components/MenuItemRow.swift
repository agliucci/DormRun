import SwiftUI

struct MenuItemRow: View {
    let item: MenuItemDisplayModel
    var namespace: Namespace.ID? = nil
    let action: () -> Void

    var body: some View {
        Button {
            guard item.isAvailable else { return }
            AppHaptics.light()
            action()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(item.name)
                        .appText(.headline)
                        .multilineTextAlignment(.leading)
                        .opacity(item.isAvailable ? 1 : 0.5)

                    Text(item.description)
                        .appText(.subheadline, color: AppColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: AppSpacing.xs) {
                        Text(item.formattedPrice)
                            .font(AppTypography.price)
                            .foregroundStyle(AppColors.textPrimary)
                            .monospacedDigit()

                        if !item.tags.isEmpty {
                            HStack(spacing: AppSpacing.xxs) {
                                ForEach(item.tags.prefix(3)) { tag in
                                    PillTag(kind: .dietary(tag), isCompact: true)
                                }
                            }
                        }
                    }

                    if !item.isAvailable {
                        Text("Sold out")
                            .appText(.caption, color: AppColors.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                thumbnail
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isAvailable ? "Customize and add to cart" : "Unavailable")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        Group {
            if let namespace {
                AsyncImageView(url: item.imageURL, cornerRadius: AppRadius.md)
                    .matchedGeometryEffect(id: "menu-item-image-\(item.id)", in: namespace)
            } else {
                AsyncImageView(url: item.imageURL, cornerRadius: AppRadius.md)
            }
        }
        .frame(width: 84, height: 84)
        .overlay(alignment: .bottomTrailing) {
            if item.isAvailable {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppColors.textOnBrand, AppColors.brand)
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .opacity(item.isAvailable ? 1 : 0.45)
    }

    private var accessibilityLabel: String {
        var parts = [item.name, item.description, item.formattedPrice]
        parts.append(contentsOf: item.tags.map(\.label))
        if !item.isAvailable { parts.append("Sold out") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    VStack(spacing: 0) {
        MenuItemRow(item: GalleryMocks.burger) {}
        Divider().padding(.leading, AppSpacing.screenMargin)
        MenuItemRow(item: GalleryMocks.bowl) {}
        Divider().padding(.leading, AppSpacing.screenMargin)
        MenuItemRow(item: MenuItemDisplayModel(
            id: "pasta",
            name: "Arrabbiata Pasta",
            description: "Spicy tomato, garlic, parsley.",
            priceCents: 850,
            imageURL: nil,
            tags: [.vegetarian],
            isAvailable: false
        )) {}
    }
    .background(AppColors.background)
}
