import SwiftUI
import UIKit

/// Prefers bundled campus asset photos, then remote URL, then a branded placeholder.
struct CampusImageView: View {
    var assetName: String? = nil
    var url: URL? = nil
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var showsScrim: Bool = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let assetName, UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if let url {
                    AsyncImageView(url: url, contentMode: contentMode, cornerRadius: 0, showsScrim: false)
                } else {
                    ZStack {
                        AppColors.surfaceMuted
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(AppColors.brand.opacity(0.55))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay {
                if showsScrim {
                    LinearGradient(
                        colors: [.clear, AppColors.scrim],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
            }
        }
        .appCornerRadius(cornerRadius)
        .accessibilityHidden(true)
    }
}
