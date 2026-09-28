import SwiftUI
import WidgetKit

/// Where a tap on a widget opens the app: its `https://sharpit.app` paths, as for a link.
enum WidgetLink {
    static let today = URL(string: "https://sharpit.app/today")!
    static let plan = URL(string: "https://sharpit.app/plan")!
}

/// The line under a session's title: its figures, or that it is done.
struct SessionFigures: View {
    let session: WidgetSnapshot.Session

    var body: some View {
        HStack(spacing: 4) {
            if session.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SharpitColor.primary)
                Text("Faite")
            }
            Text(session.figures.joined(separator: " · "))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(SharpitColor.mutedForeground)
        .lineLimit(1)
    }
}

/// The sport's mark, tinted with its identity color.
struct SportMark: View {
    let sport: V1ActivityType
    var size: CGFloat = 30

    var body: some View {
        let tint = SharpitSportColor.color(sport.identity)
        ZStack {
            Circle().fill(tint.opacity(0.16))
            Image(systemName: sport.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }
}

/// What a widget says when the app has not written today yet.
struct OpenTheAppHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(SharpitColor.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
