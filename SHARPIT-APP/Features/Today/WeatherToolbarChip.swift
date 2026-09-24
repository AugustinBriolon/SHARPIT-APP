import SwiftUI

/// Apple Weather for the athlete's current location, as a glass chip in Résumé's row under the
/// date. The content is laid out by hand: a filled, hierarchical symbol and the temperature in
/// the instrument face, rolling when it changes. With no reading it renders nothing at all —
/// an empty chip says less than its space.
struct WeatherChip: View {
    let service: LocationWeatherService

    var body: some View {
        if let reading = service.reading {
            HStack(spacing: SharpitSpacing.xxs + 2) {
                Image(systemName: reading.symbolName)
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.symbolEffect(.replace))
                Text("\(reading.temperatureCelsius)°")
                    .font(SharpitTypography.instrument.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: Double(reading.temperatureCelsius)))
            }
            .fixedSize()
            .sharpitGlassChip()
            .animation(SharpitMotion.reveal, value: reading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
