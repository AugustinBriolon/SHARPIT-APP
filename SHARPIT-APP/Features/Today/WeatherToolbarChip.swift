import SwiftUI

struct WeatherToolbarChip: View {
    let service: LocationWeatherService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: service.reading?.symbolName ?? "location")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            if let reading = service.reading {
                Text("\(reading.temperatureCelsius)°")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text(service.reading?.city ?? service.statusLine)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(ToolbarItemGlass())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let reading = service.reading {
            return "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
        }
        return service.statusLine
    }
}

private struct ToolbarItemGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.sharpitGlassCapsule()
        }
    }
}
