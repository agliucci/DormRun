import SwiftUI

/// AsyncImage with shimmering skeleton placeholder and optional gradient scrim.
struct AsyncImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var showsScrim: Bool = false

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    SkeletonView(cornerRadius: cornerRadius)
                        .frame(width: geo.size.width, height: geo.size.height)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
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
                case .failure:
                    ZStack {
                        AppColors.surfaceMuted
                        Image(systemName: "fork.knife")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                            .symbolRenderingMode(.hierarchical)
                    }
                @unknown default:
                    SkeletonView(cornerRadius: cornerRadius)
                }
            }
        }
        .appCornerRadius(cornerRadius)
        .accessibilityHidden(true)
    }
}

#Preview {
    AsyncImageView(
        url: URL(string: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800"),
        cornerRadius: AppRadius.xl,
        showsScrim: true
    )
    .frame(height: 200)
    .padding()
    .background(AppColors.background)
}
