import SwiftUI

struct WeatherToolbarChip: View {
    let service: LocationWeatherService

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            if let reading = service.reading {
                Text("\(reading.temperatureCelsius)°")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var symbolName: String {
        if let reading = service.reading {
            return reading.symbolName
        }
        return "cloud.slash"
    }

    private var accessibilityText: String {
        if let reading = service.reading {
            return "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
        }
        return service.statusLine
    }
}
