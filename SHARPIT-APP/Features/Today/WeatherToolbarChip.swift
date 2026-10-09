import SwiftUI

/// Apple Weather for the athlete's current location, as a glass chip in Résumé's row under the
/// date. The content is laid out by hand: a filled, hierarchical symbol and the temperature in
/// the instrument face, rolling when it changes. With no reading it renders nothing at all —
/// an empty chip says less than its space.
///
/// A tap opens the reading with Apple Weather's mark and legal link, which WeatherKit requires
/// wherever its data is shown.
struct WeatherChip: View {
    let service: LocationWeatherService
    @State private var isShowingDetail = false

    var body: some View {
        if let reading = service.reading {
            Button { isShowingDetail = true } label: {
                HStack(spacing: SharpitSpacing.xs) {
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
            }
            .buttonStyle(.sharpitPressable)
            .animation(SharpitMotion.reveal, value: reading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(reading.city), \(reading.temperatureCelsius) degrés, \(reading.condition)"
            )
            .accessibilityHint("Affiche la source météo")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $isShowingDetail) {
                WeatherDetail(reading: reading, attribution: service.attribution)
                    .presentationCompactAdaptation(.popover)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

/// The reading in words, then the source: Apple Weather's mark and its legal page.
private struct WeatherDetail: View {
    let reading: AppleWeatherReading
    let attribution: AppleWeatherAttribution?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("\(reading.city) · \(reading.temperatureCelsius)°")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            Text(reading.condition)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
            Divider()
            mark
            Link(
                "Sources des données météo",
                destination: attribution?.legalPageURL ?? AppleWeatherAttribution.fallbackLegalPageURL
            )
            .font(SharpitTypography.meta)
        }
        .padding(SharpitSpacing.md)
        .frame(minWidth: 220, alignment: .leading)
    }

    @ViewBuilder
    private var mark: some View {
        if let attribution {
            AsyncImage(url: colorScheme == .dark ? attribution.darkMarkURL : attribution.lightMarkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                markText
            }
            .frame(height: 14)
            .accessibilityLabel("Apple Météo")
        } else {
            markText
        }
    }

    private var markText: some View {
        Text(" Météo")
            .font(SharpitTypography.meta.weight(.semibold))
            .foregroundStyle(SharpitColor.foreground)
    }
}
