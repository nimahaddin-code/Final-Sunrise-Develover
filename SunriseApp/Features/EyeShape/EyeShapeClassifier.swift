import Foundation

/// Sorts `EyeMeasurements` into openness, tilt and spacing with plain thresholds, and rates how clear-cut each call is.
///
/// The defaults are starting points taken from `FaceFit`'s eye rules and typical eye proportions. They have not been
/// checked against MediaPipe landmarks on real faces; tune them on a Face ID iPhone and a labelled set.
struct EyeShapeClassifier: Sendable {
    struct Thresholds: Sendable {
        /// At or above this, the eye reads as round.
        var roundOpenness: Float = 0.38
        /// Below this tilt (degrees) the eye reads as downturned, above `upturnedTilt` as upturned.
        var downturnedTilt: Float = 1
        var upturnedTilt: Float = 7
        /// Below `closeSpacing` the eyes read as close-set, above `wideSpacing` as wide-set.
        var closeSpacing: Float = 0.9
        var wideSpacing: Float = 1.15
        /// Below this many iris diameters between brow and lid, the lid may be hooded.
        var hoodedLidSpace: Float = 0.9

        /// A value this far from its threshold counts as fully certain.
        var opennessBand: Float = 0.04
        var tiltBand: Float = 3
        var spacingBand: Float = 0.1
    }

    var thresholds = Thresholds()

    func classify(_ measurements: EyeMeasurements) -> EyeShapeResult {
        let t = thresholds
        let openness: EyeOpenness = measurements.openness >= t.roundOpenness ? .round : .almond
        let tilt: EyeTilt = if measurements.tilt < t.downturnedTilt { .downturned }
            else if measurements.tilt > t.upturnedTilt { .upturned } else { .straight }
        let spacing: EyeSpacing = if measurements.spacing < t.closeSpacing { .close }
            else if measurements.spacing > t.wideSpacing { .wide } else { .balanced }

        let certainty = [
            Self.certainty(measurements.openness, thresholds: [t.roundOpenness], band: t.opennessBand),
            Self.certainty(measurements.tilt, thresholds: [t.downturnedTilt, t.upturnedTilt], band: t.tiltBand),
            Self.certainty(measurements.spacing, thresholds: [t.closeSpacing, t.wideSpacing], band: t.spacingBand),
        ]
        return EyeShapeResult(openness: openness, tilt: tilt, spacing: spacing,
                              mayBeHooded: measurements.lidSpace < t.hoodedLidSpace, lid: nil,
                              measurements: measurements, confidence: Double(certainty.min() ?? 0))
    }

    /// 0 on a threshold, rising to 1 once the value is `band` or more away from the nearest one.
    private static func certainty(_ value: Float, thresholds: [Float], band: Float) -> Float {
        let distance = thresholds.map { abs(value - $0) }.min() ?? band
        return min(1, distance / band)
    }
}
