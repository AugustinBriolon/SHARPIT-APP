import SwiftUI

/// Apple Weather for the athlete's current location, as a toolbar chip.
///
/// The chip draws its own `chip-surface` capsule rather than relying on the toolbar's
/// Liquid Glass — nested inside the system glass wrapper its content rendered invisible.
/// When there is no reading it renders nothing at all: an empty capsule in the corner is
/// chrome that says less than the space it takes.
struct WeatherToolbarChip: View {
    let service: LocationWeatherService

    var body: some View {
        if let reading = service.reading {
            Label {
                Text("\(reading.temperatureCelsius)°")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.foreground)
            } icon: {
                Image(systemName: reading.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(SharpitColor.primary)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xs)
            .background(Capsule().fill(SharpitColor.chipSurface).sharpitShadow(.control))
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
            )
        }
    }
}
