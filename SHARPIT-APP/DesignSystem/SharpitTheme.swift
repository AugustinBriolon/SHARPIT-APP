import SwiftUI

enum SharpitSpacing {
    static let xxs: CGFloat = 8
    static let xs: CGFloat = 12
    static let sm: CGFloat = 14
    static let md: CGFloat = 16
    static let pageInset: CGFloat = 20
    static let section: CGFloat = 20
    static let lg: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 24
}

enum SharpitTypography {
    static func eyebrow() -> Font { .system(size: 11, weight: .semibold) }
    static var eyebrowTracking: CGFloat { 1.6 }
    static func verdict() -> Font { .system(size: 36, weight: .semibold) }
    static var verdictTracking: CGFloat { -0.8 }
    static func label() -> Font { .system(size: 10, weight: .semibold) }
    static var labelTracking: CGFloat { 0.8 }
    static func data() -> Font { .title3.monospacedDigit().weight(.semibold) }
}

enum SharpitPostureStyle {
    static func color(for posture: V1TodayPosture) -> Color {
        switch posture {
        case .protect: .orange
        case .steady: Color.accentColor
        case .push: .green
        case .uncertain: .secondary
        }
    }

    static func canvasTop(for posture: V1TodayPosture?) -> Color {
        (posture.map(color(for:)) ?? Color.accentColor).opacity(0.18)
    }
}
