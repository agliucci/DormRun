import SwiftUI

struct PrimaryButton: View {
    enum Style {
        case primary
        case secondary
        case tertiary
        case destructive
    }

    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            AppHaptics.light()
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(title)
                        .font(AppTypography.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppSpacing.minTapTarget)
            .padding(.horizontal, AppSpacing.lg)
            .foregroundStyle(foreground)
            .background(background)
            .appCornerRadius(AppRadius.lg)
            .overlay {
                if style == .secondary || style == .tertiary {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: style == .secondary ? 1.5 : 0)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: AppColors.textOnBrand
        case .secondary, .tertiary: AppColors.textPrimary
        }
    }

    private var background: Color {
        switch style {
        case .primary: AppColors.brand
        case .secondary: AppColors.surface
        case .tertiary: AppColors.surfaceMuted
        case .destructive: AppColors.danger
        }
    }

    private var borderColor: Color {
        style == .secondary ? AppColors.border : .clear
    }
}

/// Scales down slightly on press for a tactile feel.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppMotion.springSnappy, value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: AppSpacing.md) {
        PrimaryButton(title: "Place order", systemImage: "bag.fill") {}
        PrimaryButton(title: "Secondary", style: .secondary) {}
        PrimaryButton(title: "Tertiary", style: .tertiary) {}
        PrimaryButton(title: "Cancel order", style: .destructive) {}
        PrimaryButton(title: "Loading", isLoading: true) {}
        PrimaryButton(title: "Disabled", isEnabled: false) {}
    }
    .padding(AppSpacing.screenMargin)
    .background(AppColors.background)
}
