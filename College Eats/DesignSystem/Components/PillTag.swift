import SwiftUI

struct PillTag: View {
    enum Kind {
        case dietary(DietaryTag)
        case status(LocationOpenStatus)
        case busy(BusyLevel)
        case custom(title: String, systemImage: String?, tint: Color)
    }

    /// `onMedia` = solid frosted chip for photos; `surface` = soft tinted chip on app backgrounds.
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
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(isCompact ? AppTypography.caption2 : AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, isCompact ? AppSpacing.xs + 2 : AppSpacing.sm)
        .padding(.vertical, isCompact ? AppSpacing.xxs : AppSpacing.xxs + 2)
        .background(chipBackground)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(chipBorder, lineWidth: surface == .onMedia ? 0.5 : 1)
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(
            color: surface == .onMedia ? Color.black.opacity(0.22) : .clear,
            radius: surface == .onMedia ? 6 : 0,
            y: surface == .onMedia ? 2 : 0
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

    private var labelColor: Color {
        switch surface {
        case .onMedia:
            AppColors.textPrimary
        case .surface:
            switch kind {
            case .dietary: AppColors.textPrimary
            default: accent
            }
        }
    }

    @ViewBuilder
    private var chipBackground: some View {
        switch surface {
        case .onMedia:
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.72))
                }
        case .surface:
            Capsule(style: .continuous)
                .fill(accent.opacity(0.14))
        }
    }

    private var chipBorder: Color {
        switch surface {
        case .onMedia: Color.white.opacity(0.55)
        case .surface: accent.opacity(0.28)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        Text("On surface")
        FlowLayout(spacing: AppSpacing.xs) {
            PillTag(kind: .status(.open))
            PillTag(kind: .busy(.high))
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
