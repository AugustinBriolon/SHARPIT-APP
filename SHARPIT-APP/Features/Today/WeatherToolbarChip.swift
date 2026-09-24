import SwiftUI

/// Apple Weather for the athlete's current location, in Résumé's navigation bar.
///
/// On iOS 26 and later the chip is its own Liquid Glass control, set apart from the Journal
/// button by a fixed toolbar spacer (`TodayTrailingToolbar`), and draws no surface of its
/// own: a capsule drawn inside the system's glass read as a pill inside a pill. The content
/// is laid out by hand rather than as a `Label`, which the toolbar collapses to its icon.
/// Before iOS 26 the bar has no glass, so the chip keeps a quiet `chip-surface` capsule.
/// With no reading it renders nothing at all: an empty control says less than its space.
struct WeatherToolbarChip: View {
    let service: LocationWeatherService

    var body: some View {
        if let reading = service.reading {
            HStack(spacing: SharpitSpacing.xxs + 2) {
                Image(systemName: reading.symbolName)
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.symbolEffect(.replace))
                Text("\(reading.temperatureCelsius)°")
                    .font(SharpitTypography.instrument.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText(value: Double(reading.temperatureCelsius)))
            }
            .padding(.horizontal, SharpitSpacing.xs)
            .fixedSize()
            .modifier(PreGlassChipSurface())
            .animation(SharpitMotion.reveal, value: reading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
            )
        }
    }
}

/// The capsule the chip needs only where the bar is not glass.
private struct PreGlassChipSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .padding(.vertical, SharpitSpacing.xxs)
                .background(Capsule().fill(SharpitColor.chipSurface).sharpitShadow(.control))
        }
    }
}

/// Résumé's trailing controls: Journal and the weather, each its own glass control on iOS 26
/// and later — a fixed spacer keeps the system from fusing them into one capsule.
struct TodayTrailingToolbar<Journal: View>: ViewModifier {
    let weather: LocationWeatherService
    @ViewBuilder let journal: () -> Journal

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) { journal() }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { WeatherToolbarChip(service: weather) }
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarTrailing) { journal() }
                ToolbarItem(placement: .topBarTrailing) { WeatherToolbarChip(service: weather) }
            }
        }
    }
}
