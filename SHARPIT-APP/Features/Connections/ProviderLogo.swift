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

        var assetName: String {
            switch self {
            case .garmin: "Provider/Garmin"
            case .appleHealth: "Provider/AppleHealth"
            }
        }

        var fallbackSymbol: String {
            switch self {
            case .garmin: "applewatch.side.right"
            case .appleHealth: "heart.fill"
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
