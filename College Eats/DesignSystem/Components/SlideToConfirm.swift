import SwiftUI

/// Satisfying slide-to-accept control. Fires `onConfirm` once the thumb reaches the end.
struct SlideToConfirm: View {
    var title: String = "Slide to accept"
    var confirmedTitle: String = "Accepted"
    var isEnabled: Bool = true
    var onConfirm: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    @State private var isConfirmed = false
    @State private var trackWidth: CGFloat = 0

    private let thumbSize: CGFloat = 52
    private let horizontalPadding: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let maxTravel = max(0, geo.size.width - thumbSize - horizontalPadding * 2)

            ZStack {
                Capsule(style: .continuous)
                    .fill(isConfirmed ? AppColors.success : AppColors.surfaceMuted)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(AppColors.border, lineWidth: 1)
                    }

                // Fill progress
                HStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(AppColors.brand.opacity(isConfirmed ? 0 : 0.18))
                        .frame(width: dragOffset + thumbSize)
                    Spacer(minLength: 0)
                }
                .padding(horizontalPadding)
                .allowsHitTesting(false)

                Text(isConfirmed ? confirmedTitle : title)
                    .font(AppTypography.headline)
                    .foregroundStyle(isConfirmed ? AppColors.textOnBrand : AppColors.textSecondary)
                    .opacity(isConfirmed ? 1 : Double(1 - (dragOffset / max(maxTravel, 1)) * 0.85))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack {
                    ZStack {
                        Circle()
                            .fill(isConfirmed ? AppColors.success : AppColors.brand)
                            .frame(width: thumbSize, height: thumbSize)
                            .appElevatedShadow(colorScheme)

                        Image(systemName: isConfirmed ? "checkmark" : "chevron.right.2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppColors.textOnBrand)
                            .symbolEffect(.bounce, value: isConfirmed)
                    }
                    .offset(x: dragOffset)
                    .gesture(dragGesture(maxTravel: maxTravel))
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Drag to the right to confirm")
                    .accessibilityValue(isConfirmed ? "Confirmed" : "Not confirmed")

                    Spacer(minLength: 0)
                }
                .padding(.leading, horizontalPadding)
            }
            .onAppear { trackWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, newValue in
                trackWidth = newValue
            }
        }
        .frame(height: thumbSize + 8)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled && !isConfirmed)
        .accessibilityElement(children: .combine)
    }

    private func dragGesture(maxTravel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isConfirmed, isEnabled else { return }
                let clamped = min(max(0, value.translation.width), maxTravel)
                dragOffset = clamped
                if clamped > maxTravel * 0.92 {
                    // Near the end — light tick
                }
            }
            .onEnded { value in
                guard !isConfirmed, isEnabled else { return }
                let clamped = min(max(0, value.translation.width), maxTravel)
                if clamped >= maxTravel * 0.88 {
                    withAnimation(AppMotion.spring) {
                        dragOffset = maxTravel
                        isConfirmed = true
                    }
                    AppHaptics.rigid()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        AppHaptics.success()
                        onConfirm()
                    }
                } else {
                    withAnimation(AppMotion.spring) {
                        dragOffset = 0
                    }
                    AppHaptics.soft()
                }
            }
    }
}

#Preview {
    VStack(spacing: AppSpacing.xl) {
        SlideToConfirm { }
        SlideToConfirm(title: "Slide to confirm pickup", confirmedTitle: "Picked up") { }
    }
    .padding(AppSpacing.screenMargin)
    .background(AppColors.background)
}
