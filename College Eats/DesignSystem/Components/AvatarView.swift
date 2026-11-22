import SwiftUI
import UIKit

struct AvatarView: View {
    enum Size {
        case small
        case medium
        case large
        case hero

        var dimension: CGFloat {
            switch self {
            case .small: 32
            case .medium: 44
            case .large: 64
            case .hero: 88
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 12
            case .medium: 16
            case .large: 22
            case .hero: 30
            }
        }
    }

    var name: String
    var imageURL: URL? = nil
    var size: Size = .medium
    var showsOnlineDot: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let imageURL, imageURL.isFileURL, let uiImage = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.dimension, height: size.dimension)
                        .clipShape(Circle())
                } else if let imageURL {
                    AsyncImageView(url: imageURL, cornerRadius: size.dimension / 2)
                        .clipShape(Circle())
                } else {
                    initialsView
                }
            }
            .frame(width: size.dimension, height: size.dimension)
            .overlay {
                Circle()
                    .strokeBorder(AppColors.border, lineWidth: 1)
            }

            if showsOnlineDot {
                Circle()
                    .fill(AppColors.statusOpen)
                    .frame(width: size.dimension * 0.28, height: size.dimension * 0.28)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColors.surface, lineWidth: 2)
                    }
                    .offset(x: 2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) avatar")
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(AppColors.surfaceMuted)
            Text(initials)
                .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.brand)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first.map(String.init) }
        return chars.joined().uppercased()
    }
}

#Preview {
    HStack(spacing: AppSpacing.md) {
        AvatarView(name: "Maya Chen", size: .small, showsOnlineDot: true)
        AvatarView(name: "Maya Chen", size: .medium)
        AvatarView(name: "Jordan Lee", size: .large, showsOnlineDot: true)
        AvatarView(
            name: "Sam Rivera",
            imageURL: URL(string: "https://i.pravatar.cc/150?u=sam"),
            size: .hero
        )
    }
    .padding()
    .background(AppColors.background)
}
