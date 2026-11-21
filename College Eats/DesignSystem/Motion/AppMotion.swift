import SwiftUI
import UIKit

/// Springs, transitions, and haptics for a polished feel.
enum AppMotion {
    /// Primary interactive spring — response ~0.4, damping ~0.8.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Snappier spring for small UI (pills, badges).
    static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Softer spring for large layout shifts (cart bar, sheets).
    static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.86)

    /// Runner pin glide between location updates.
    static let pinGlide = Animation.easeInOut(duration: 0.85)
}

enum AppHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
