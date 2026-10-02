import AppIntents
import SwiftUI
import WidgetKit

/// « Scanner un produit »: one tap from the home screen to the app's barcode scanner, which
/// logs the food it reads. It holds no data — nothing on it can be stale — and hides with
/// Nutrition when the athlete turned the page off.
struct ScanFoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScanFood", provider: SnapshotProvider()) { entry in
            ScanFoodWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link(entry.features.isOn(.nutrition) ? "/nutrition/scan" : "/today"))
        }
        .configurationDisplayName("Scanner un produit")
        .description("Ouvre le scanner de code-barres pour noter un aliment.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ScanFoodWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.features.isOn(.nutrition) {
            content
        } else {
            WidgetFeatureOff(feature: .nutrition)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Scanner un produit")
        default:
            WidgetFrame("Nutrition", symbol: "fork.knife", tint: SharpitColor.primary) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(SharpitColor.primary)
                    .widgetAccentable()
                    .padding(.bottom, 6)
                WidgetTitle(text: "Scanner un produit")
            }
        }
    }
}

/// The same scanner, from Control Center, the lock screen or the Action button.
struct ScanFoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.sharpit.ios.scan-food") {
            ControlWidgetButton(action: OpenURLIntent(WidgetSnapshot.link("/nutrition/scan"))) {
                Label("Scanner un produit", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scanner un produit")
        .description("Ouvre le scanner de code-barres de SharpIt.")
    }
}
