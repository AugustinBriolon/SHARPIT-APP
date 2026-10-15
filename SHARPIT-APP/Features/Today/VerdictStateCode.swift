import SwiftUI

/// Stable machine verdict code from `/api/v1/today` — drives tag colour / icon.
///
/// Unknown codes fall back to a muted uncertain tone so an additive server value never
/// blanks the plate.
nonisolated enum VerdictStateCode: Equatable, Hashable, Sendable {
    case recover
    case caution
    case trainEasy
    case trainSmart
    case trainHard
    case raceReady
    case insufficientData
    case unknown(String)

    static let knownOrdered: [VerdictStateCode] = [
        .recover, .caution, .trainEasy, .trainSmart, .trainHard, .raceReady, .insufficientData,
    ]

    var wireValue: String? {
        switch self {
        case .recover: "RECOVER"
        case .caution: "CAUTION"
        case .trainEasy: "TRAIN_EASY"
        case .trainSmart: "TRAIN_SMART"
        case .trainHard: "TRAIN_HARD"
        case .raceReady: "RACE_READY"
        case .insufficientData: "INSUFFICIENT_DATA"
        case .unknown: nil
        }
    }

    init(wire: String) {
        switch wire {
        case "RECOVER": self = .recover
        case "CAUTION": self = .caution
        case "TRAIN_EASY": self = .trainEasy
        case "TRAIN_SMART": self = .trainSmart
        case "TRAIN_HARD": self = .trainHard
        case "RACE_READY": self = .raceReady
        case "INSUFFICIENT_DATA": self = .insufficientData
        default: self = .unknown(wire)
        }
    }

    /// Softest → strongest mapping onto the plate's status tone.
    var statusTone: PackTierTone {
        switch self {
        case .recover, .caution: .caution
        case .insufficientData, .unknown: .muted
        case .trainEasy, .trainSmart, .trainHard, .raceReady: .highlight
        }
    }

    var symbolName: String {
        switch self {
        case .recover: "bed.double.fill"
        case .caution: "exclamationmark.shield.fill"
        case .trainEasy: "figure.walk"
        case .trainSmart: "target"
        case .trainHard: "flame.fill"
        case .raceReady: "flag.checkered"
        case .insufficientData, .unknown: "questionmark.circle"
        }
    }

    /// Ink-band accent for the status tag.
    var inkAccent: Color {
        switch self {
        case .recover: SharpitColor.primary
        case .caution: SharpitColor.signalVo2
        case .trainEasy: SharpitColor.signalTempo
        case .trainSmart: SharpitColor.signalRecovery
        case .trainHard, .raceReady: SharpitColor.inkAccent
        case .insufficientData, .unknown: SharpitColor.inkSurfaceForeground.opacity(0.4)
        }
    }
}

extension VerdictStateCode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unknown("")
            return
        }
        self = VerdictStateCode(wire: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unknown(let raw): try container.encode(raw)
        default: try container.encode(wireValue ?? "")
        }
    }
}
