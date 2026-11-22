import SwiftUI

struct PillTag: View {
    enum Kind {
        case dietary(DietaryTag)
        case status(LocationOpenStatus)
        case busy(BusyLevel)
        case custom(title: String, systemImage: String?, tint: Color)
    }

    /// `onMedia` = solid frosted chip for photos; `surface` = solid chip on app backgrounds.
    enum Surface {
        case surface
        case onMedia
    }

    let kind: Kind
    var isCompact: Bool = false
    var surface: Surface = .surface

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foreground)
            }
            Text(title)
                .font(isCompact ? AppTypography.caption2 : AppTypography.caption)
                .fontWeight(.bold)
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, isCompact ? AppSpacing.xs + 2 : AppSpacing.sm)
        .padding(.vertical, isCompact ? AppSpacing.xxs + 1 : AppSpacing.xs)
        .background(chipBackground)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(chipBorder, lineWidth: usesFilledStatusStyle ? 0 : 1)
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(
            color: surface == .onMedia ? Color.black.opacity(0.22) : Color.black.opacity(0.12),
            radius: surface == .onMedia ? 6 : 3,
            y: surface == .onMedia ? 2 : 1
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch kind {
        case .dietary(let tag): tag.label
        case .status(let status): status.label
        case .busy(let level): level.label
        case .custom(let title, _, _): title
        }
    }

    private var systemImage: String? {
        switch kind {
        case .dietary(let tag): tag.systemImage
        case .status(let status):
            switch status {
            case .open: "circle.fill"
            case .closingSoon: "clock.fill"
            case .closed: "moon.fill"
            }
        case .busy: "person.3.fill"
        case .custom(_, let image, _): image
        }
    }

    private var accent: Color {
        switch kind {
        case .dietary: AppColors.brand
        case .status(let status):
            switch status {
            case .open: AppColors.statusOpen
            case .closingSoon: AppColors.statusClosingSoon
            case .closed: AppColors.statusClosed
            }
        case .busy(let level):
            switch level {
            case .low: AppColors.busyLow
            case .medium: AppColors.busyMedium
            case .high: AppColors.busyHigh
            }
        case .custom(_, _, let tint): tint
        }
    }

    /// Status + busy chips get solid filled capsules for max contrast on dark UI.
    private var usesFilledStatusStyle: Bool {
        switch kind {
        case .status, .busy, .custom: true
        case .dietary: false
        }
    }

    private var foreground: Color {
        if usesFilledStatusStyle { return .white }
        if surface == .onMedia { return Color(hex: "#1F1008") }
        return AppColors.textPrimary
    }

    @ViewBuilder
    private var chipBackground: some View {
        if usesFilledStatusStyle {
            // Open = green, Packed = red/orange — same on photos and plain backgrounds.
            Capsule(style: .continuous)
                .fill(accent)
                .shadow(color: accent.opacity(0.45), radius: 4, y: 1)
        } else if surface == .onMedia {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.92))
        } else {
            Capsule(style: .continuous)
                .fill(AppColors.surfaceElevated)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.16))
                }
        }
    }

    private var chipBorder: Color {
        if usesFilledStatusStyle { return .clear }
        return surface == .onMedia ? Color.black.opacity(0.08) : accent.opacity(0.45)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        Text("On surface")
        FlowLayout(spacing: AppSpacing.xs) {
            PillTag(kind: .status(.open))
            PillTag(kind: .busy(.high))
            PillTag(kind: .custom(title: "~9 min", systemImage: "bicycle", tint: AppColors.brand))
            PillTag(kind: .dietary(.vegan))
        }

        Text("On media")
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.brown.opacity(0.85))
                .frame(height: 120)
            HStack(spacing: AppSpacing.xs) {
                PillTag(kind: .status(.open), isCompact: true, surface: .onMedia)
                PillTag(kind: .busy(.high), isCompact: true, surface: .onMedia)
            }
            .padding(AppSpacing.sm)
        }
    }
    .padding()
    .background(AppColors.background)
}

