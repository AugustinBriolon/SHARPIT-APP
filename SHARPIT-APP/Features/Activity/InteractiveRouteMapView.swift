import MapKit
import SwiftUI

enum MapStyleOption: String, CaseIterable, Identifiable, Sendable {
    case standard = "Plan"
    case imagery = "Satellite"
    case hybrid = "Mixte"

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        }
    }
}

/// Full-screen interactive map allowing the athlete to freely pan, zoom, rotate, and inspect their GPS trace.
struct InteractiveRouteMapView: View {
    let route: [V1ActivityCoordinate]
    let tone: Color
    let title: String
    let sportLabel: String
    let sportSymbol: String
    var distanceM: Double? = nil
    var elevationM: Double? = nil
    var duration: Double? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var mapStyleSelection: MapStyleOption = .standard

    typealias MapStyleOption = Sharpit.MapStyleOption

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var defaultRegion: MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard
            let minLatitude = latitudes.min(),
            let maxLatitude = latitudes.max(),
            let minLongitude = longitudes.min(),
            let maxLongitude = longitudes.max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.764, longitude: 4.835),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(maxLatitude - minLatitude, 0.008) * 1.3,
                longitudeDelta: max(maxLongitude - minLongitude, 0.008) * 1.3
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, interactionModes: .all) {
                MapPolyline(coordinates: coordinates)
                    .stroke(tone, lineWidth: 5)

                if let start = coordinates.first {
                    Annotation("Départ", coordinate: start) {
                        InteractiveRoutePointMarker(
                            title: "D",
                            color: .white,
                            stroke: tone
                        )
                    }
                }

                if let finish = coordinates.last {
                    Annotation("Arrivée", coordinate: finish) {
                        InteractiveRoutePointMarker(
                            title: "A",
                            color: tone,
                            stroke: .white
                        )
                    }
                }
            }
            .mapStyle(mapStyleSelection.mapStyle)
            .mapControls {
                MapScaleView()
                MapCompass()
                MapPitchToggle()
            }
            .ignoresSafeArea()

            // Header controls overlay
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 44, height: 44)
                            .sharpitGlassCircle()
                            .sharpitShadow(.control)
                    }
                    .accessibilityLabel("Fermer la carte")

                    Spacer()

                    VStack(alignment: .trailing, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                position = .region(defaultRegion)
                            }
                        } label: {
                            Image(systemName: "location.viewfinder")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(SharpitColor.foreground)
                                .frame(width: 44, height: 44)
                                .sharpitGlassCircle()
                                .sharpitShadow(.control)
                        }
                        .accessibilityLabel("Recentrer sur le tracé")

                        // Style picker menu
                        Menu {
                            Picker("Style de carte", selection: $mapStyleSelection) {
                                ForEach(MapStyleOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "square.2.layers.3d")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SharpitColor.foreground)
                                .frame(width: 44, height: 44)
                                .sharpitGlassCircle()
                                .sharpitShadow(.control)
                        }
                        .accessibilityLabel("Changer le style de carte")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()

                // Bottom summary card
                bottomMetricsCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            position = .region(defaultRegion)
        }
        .enableInteractivePopGesture()
    }

    private var bottomMetricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(sportLabel, systemImage: sportSymbol)
                    .font(SharpitTypography.eyebrow)
                    .tracking(SharpitTypography.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(tone)

                Spacer()

                Text("\(route.count) points GPS")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)

            HStack(spacing: 24) {
                if let distance = distanceM {
                    metricItem(
                        label: "Distance",
                        value: distance >= 1_000 ? String(format: "%.1f km", distance / 1_000) : "\(Int(distance.rounded())) m"
                    )
                }

                if let elevation = elevationM, elevation > 0 {
                    metricItem(
                        label: "Dénivelé",
                        value: "\(Int(elevation.rounded())) m"
                    )
                }

                if let duration = duration, duration > 0 {
                    metricItem(
                        label: "Durée",
                        value: ActivityFormat.duration(duration)
                    )
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .sharpitShadow(.panel)
        )
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharpitColor.foreground)
        }
    }
}

private struct InteractiveRoutePointMarker: View {
    let title: String
    let color: Color
    let stroke: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(stroke, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            .overlay {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(stroke)
            }
    }
}
