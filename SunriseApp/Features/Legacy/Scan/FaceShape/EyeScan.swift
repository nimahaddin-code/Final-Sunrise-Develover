import Foundation

/// Eye shapes the eyeliner is chosen by. Hooded and monolid cannot be detected, so the person says which applies.
enum EyeShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case almond, round, hooded, monolid, upturned, downturned, closeSet, wideSet

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .almond: "Almond"
        case .round: "Round"
        case .hooded: "Hooded"
        case .monolid: "Monolid"
        case .upturned: "Upturned"
        case .downturned: "Downturned"
        case .closeSet: "Close-set"
        case .wideSet: "Wide-set"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .almond: "Balanced, with a gently tapered outer corner."
        case .round: "Open and rounded, with more white visible above or below the iris."
        case .hooded: "The crease sits close to the lash line and the fold covers part of the lid."
        case .monolid: "A flat lid with little or no visible crease."
        case .upturned: "The outer corner sits higher than the inner corner."
        case .downturned: "The outer corner sits lower than the inner corner."
        case .closeSet: "The gap between your inner corners is less than one eye width."
        case .wideSet: "The gap between your inner corners is more than one eye width."
        }
    }

    /// How much the research trusts its eyeliner rule for this shape (high 1, medium .8, low-medium .6, low .5).
    var confidence: Float {
        switch self {
        case .almond, .downturned, .closeSet, .wideSet: 1
        case .monolid: 0.8
        case .round: 0.6
        case .hooded, .upturned: 0.5
        }
    }
}

/// What the person says about their lids; the camera cannot see a crease.
enum LidType: String, CaseIterable, Identifiable, Codable, Sendable {
    case neither, hooded, monolid

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .neither: "Neither"
        case .hooded: "Hooded"
        case .monolid: "Monolid"
        }
    }
}

/// One shape's score (0...1) and the score weighted by how much the research trusts that shape's rule.
struct EyeShapeScore: Equatable, Sendable {
    let shape: EyeShape
    let score: Float
    var weighted: Float { score * shape.confidence }
}

/// The eye measurements taken once during the face scan, with the lid type the person chose.
/// Shape scores are derived from the measurements, so recalibrating the thresholds applies to saved scans too.
///
/// Every threshold is an ESTIMATE from `Docs/Research/makeup_placement_rules.json`, which gives no numbers;
/// calibrate them on real devices (the DEBUG overlay shows the measured values).
struct EyeScan: Equatable, Hashable, Codable, Sendable {
    /// Degrees, positive when the outer corner sits higher than the inner corner.
    var tiltLeft: Float
    var tiltRight: Float
    /// Gap between the inner eye corners divided by the average eye width.
    var spacing: Float
    /// Eye opening height divided by eye width, averaged over both eyes, measured with the eyes open.
    var openness: Float
    /// Vision readings averaged into these measurements.
    var samples: Int
    var lidType: LidType = .neither

    // MARK: Thresholds (ESTIMATE)

    /// Typical canthal tilt; the tilt scores ramp away from `typicalTilt` ± `tiltBand`.
    static let typicalTilt: Float = 4
    static let tiltBand: Float = 3
    static let tiltRamp: Float = 5
    /// The research threshold: the gap between inner corners against one eye width.
    static let spacingThreshold: Float = 1
    static let spacingRamp: Float = 0.15
    /// Openness at which an eye starts to read as round, and the extra openness that makes it fully round.
    static let roundStart: Float = 0.30
    static let roundRamp: Float = 0.10
    /// Almond is the baseline: it only wins while no other trait is clearly present.
    static let almondBaseline: Float = 0.4
    /// Below this the eyes were not open during the measurement; no shape is trusted (R7, R8).
    static let minimumOpenness: Float = 0.15
    /// Left and right tilt further apart than this are treated as a bad reading (R7).
    static let maximumTiltDifference: Float = 6
    /// The best weighted score must reach this, or the neutral line is used (R7).
    static let minimumConfidence: Float = 0.25
    /// Shapes at or above this raw score count as present for R4.
    static let strongScore: Float = 0.5

    var tilt: Float { (tiltLeft + tiltRight) / 2 }

    private static func ramp(_ value: Float) -> Float { min(max(value, 0), 1) }

    /// Raw score of every shape, 0...1. Hooded and monolid are 1 only when the person chose them.
    var scores: [EyeShape: Float] {
        let round = Self.ramp((openness - Self.roundStart) / Self.roundRamp)
        return [
            .upturned: Self.ramp((tilt - (Self.typicalTilt + Self.tiltBand)) / Self.tiltRamp),
            .downturned: Self.ramp(((Self.typicalTilt - Self.tiltBand) - tilt) / Self.tiltRamp),
            .closeSet: Self.ramp((Self.spacingThreshold - spacing) / Self.spacingRamp),
            .wideSet: Self.ramp((spacing - Self.spacingThreshold) / Self.spacingRamp),
            .round: round,
            .almond: Self.almondBaseline * (1 - round),
            .hooded: lidType == .hooded ? 1 : 0,
            .monolid: lidType == .monolid ? 1 : 0,
        ]
    }

    /// Shapes that are present, strongest weighted score first.
    var ranked: [EyeShapeScore] {
        let scores = scores
        return EyeShape.allCases
            .map { EyeShapeScore(shape: $0, score: scores[$0] ?? 0) }
            .filter { $0.weighted > 0 }
            .sorted { $0.weighted > $1.weighted }
    }

    /// True when the reading cannot be trusted, so the neutral natural line is used (R7).
    var isLowConfidence: Bool {
        openness < Self.minimumOpenness
            || abs(tiltLeft - tiltRight) > Self.maximumTiltDifference
            || (ranked.first?.weighted ?? 0) < Self.minimumConfidence
    }
}
