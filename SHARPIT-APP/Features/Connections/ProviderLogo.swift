import SwiftUI
import UIKit

/// A data source's own mark, at the size and corner iOS uses for an app icon in a list row.
///
/// The artwork comes from the asset catalog (`Provider/Garmin`, `Provider/AppleHealth`), as
/// each provider ships it — SHARPIT never redraws a brand. Until an asset is added the row
/// shows a neutral tile with a system symbol, so the screen never has a hole in it.
struct ProviderLogo: View {
    enum Provider {
        case garmin
        case appleHealth
        case sharpit
        case strava
        case withings
        case renpho
        case google

        /// The web's integration id (`garmin`, `apple-health`…), for lists the web sends.
        init?(integrationId: String) {
            switch integrationId {
            case "garmin": self = .garmin
            case "apple-health": self = .appleHealth
            case "sharpit": self = .sharpit
            case "strava": self = .strava
            case "withings": self = .withings
            case "renpho": self = .renpho
            case "google": self = .google
            default: return nil
            }
        }

        var assetName: String {
            switch self {
            case .garmin: "Provider/Garmin"
            case .appleHealth: "Provider/AppleHealth"
            case .sharpit: "Provider/Sharpit"
            case .strava: "Provider/Strava"
            case .withings: "Provider/Withings"
            case .renpho: "Provider/Renpho"
            case .google: "Provider/Google"
            }
        }

        var fallbackSymbol: String {
            switch self {
            case .garmin: "applewatch.side.right"
            case .appleHealth: "heart.fill"
            case .sharpit: "fork.knife"
            case .strava: "figure.run"
            case .withings, .renpho: "scalemass"
            case .google: "calendar"
            }
        }
    }

    let provider: Provider

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    var body: some View {
        Group {
            if UIImage(named: provider.assetName) != nil {
                Image(provider.assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: provider.fallbackSymbol)
                    .font(.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SharpitColor.muted)
            }
        }
        .frame(width: size, height: size)
        // 22.37% continuous: the corner iOS draws on every app icon.
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .strokeBorder(SharpitColor.border, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
