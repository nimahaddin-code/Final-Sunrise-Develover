import Foundation

/// How round the eye opening is.
enum EyeOpenness: String, CaseIterable, Identifiable, Codable, Sendable {
    case almond, round

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .almond: "Almond"
        case .round: "Round"
        }
    }
}

/// Whether the outer corner sits lower than, level with, or higher than the inner corner.
enum EyeTilt: String, CaseIterable, Identifiable, Codable, Sendable {
    case downturned, straight, upturned

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .downturned: "Downturned"
        case .straight: "Straight"
        case .upturned: "Upturned"
        }
    }
}

/// How far apart the eyes sit, in eye widths.
enum EyeSpacing: String, CaseIterable, Identifiable, Codable, Sendable {
    case close, balanced, wide

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .close: "Close-set"
        case .balanced: "Evenly spaced"
        case .wide: "Wide-set"
        }
    }
}

/// The eyelid, which landmarks cannot see (there is no crease point), so the person picks it.
enum EyeLid: String, CaseIterable, Identifiable, Codable, Sendable {
    case crease, hooded, monolid

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .crease: "Visible crease"
        case .hooded: "Hooded"
        case .monolid: "Monolid"
        }
    }
}

struct EyeShapeResult: Equatable, Codable, Sendable {
    let openness: EyeOpenness
    let tilt: EyeTilt
    let spacing: EyeSpacing
    /// The brow-to-lid gap is small. Only a hint to suggest the hooded choice; the person decides `lid`.
    let mayBeHooded: Bool
    /// Chosen by the person after the scan; `nil` until they answer.
    var lid: EyeLid?
    let measurements: EyeMeasurements
    /// How far the least certain of openness, tilt and spacing sits from its nearest threshold, from 0 to 1.
    /// Low values mean the eyes are on the edge between two categories.
    let confidence: Double
}
