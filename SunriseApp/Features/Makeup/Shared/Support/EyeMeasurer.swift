import Foundation
import simd

/// Eye proportions that do not depend on head size, camera distance, head roll or mirroring.
struct EyeMeasurements: Equatable, Codable, Sendable {
    /// Lid opening height divided by corner-to-corner width; a typical open eye is about 0.3, rounder eyes are higher.
    var openness: Float
    /// Degrees from the inner to the outer corner, measured against the line between the eyes. Positive means the
    /// outer corner sits higher (upturned).
    var tilt: Float
    /// Gap between the inner corners divided by the average eye width.
    var spacing: Float
    /// Gap from the eyebrow to the upper lid, in iris diameters. Small values can mean a hooded lid.
    var lidSpace: Float
}

/// Measures `EyeMeasurements` from `EyeScanLandmarks`. Pure geometry; no MediaPipe, camera or Vision involved.
///
/// The face's own axes come from the points: across is the line between the eyes, and up is the perpendicular
/// that points toward the brows. That makes the result the same for a rolled, mirrored or y-down image.
enum EyeMeasurer {
    /// Frames with a smaller `openness` are blinks or squints and should not be sampled.
    static let minimumOpenness: Float = 0.15

    static func measure(_ landmarks: EyeScanLandmarks) -> EyeMeasurements? {
        let eyes = [landmarks.first, landmarks.second]
        guard let centerA = centroid(landmarks.first.lid), let centerB = centroid(landmarks.second.lid),
              let browA = centroid(landmarks.first.brow), let browB = centroid(landmarks.second.brow) else { return nil }
        let across = centerB - centerA
        let distance = simd_length(across)
        guard distance > 0 else { return nil }
        var up = SIMD2(-across.y, across.x) / distance
        if simd_dot(up, (browA + browB) / 2 - (centerA + centerB) / 2) < 0 { up = -up }

        let centers = [centerA, centerB]
        var sides: [(openness: Float, tilt: Float, width: Float, lidSpace: Float)] = []
        for index in 0..<2 {
            guard let side = measure(eyes[index], center: centers[index], otherCenter: centers[1 - index], up: up) else {
                return nil
            }
            sides.append(side)
        }
        let width = (sides[0].width + sides[1].width) / 2
        let innerGap = simd_distance(landmarks.first.innerCorner, landmarks.second.innerCorner)
        return EyeMeasurements(openness: (sides[0].openness + sides[1].openness) / 2,
                               tilt: (sides[0].tilt + sides[1].tilt) / 2,
                               spacing: innerGap / width,
                               lidSpace: (sides[0].lidSpace + sides[1].lidSpace) / 2)
    }

    private static func measure(_ eye: EyeScanLandmarks.Eye, center: SIMD2<Float>, otherCenter: SIMD2<Float>,
                                up: SIMD2<Float>) -> (openness: Float, tilt: Float, width: Float, lidSpace: Float)? {
        let axis = eye.outerCorner - eye.innerCorner
        let width = simd_length(axis)
        guard width > 0, let brow = centroid(eye.brow), let irisDiameter = diameter(of: eye.iris),
              irisDiameter > 0 else { return nil }

        // Opening: how far the lid points stray from the corner line, on either side.
        var normal = SIMD2(-axis.y, axis.x) / width
        if simd_dot(normal, up) < 0 { normal = -normal }
        let offsets = eye.lid.map { simd_dot($0 - eye.innerCorner, normal) }
        guard let top = offsets.max(), let bottom = offsets.min() else { return nil }

        // Tilt against the eye line, so head roll cancels out. "Outward" points away from the other eye.
        let outward = simd_normalize(center - otherCenter)
        let tilt = atan2(simd_dot(axis, up), simd_dot(axis, outward)) * 180 / .pi

        let lidTop = eye.lid.map { simd_dot($0, up) }.max() ?? 0
        let lidSpace = (simd_dot(brow, up) - lidTop) / irisDiameter
        return ((top - bottom) / width, tilt, width, lidSpace)
    }

    private static func centroid(_ points: [SIMD2<Float>]) -> SIMD2<Float>? {
        points.isEmpty ? nil : points.reduce(.zero, +) / Float(points.count)
    }

    /// The farthest pair of rim points; for points on a circle that is the diameter, whatever order they come in.
    private static func diameter(of points: [SIMD2<Float>]) -> Float? {
        guard points.count >= 2 else { return nil }
        var longest: Float = 0
        for i in points.indices {
            for j in points.indices where j > i { longest = max(longest, simd_distance(points[i], points[j])) }
        }
        return longest
    }
}

/// Collects usable per-frame measurements and reports the per-field median, which ignores occasional bad frames.
struct EyeMeasurementsSampler {
    let requiredSamples: Int
    private(set) var samples: [EyeMeasurements] = []

    init(requiredSamples: Int) { self.requiredSamples = max(1, requiredSamples) }

    var progress: Double { min(1, Double(samples.count) / Double(requiredSamples)) }
    var isComplete: Bool { samples.count >= requiredSamples }

    /// Keeps the frame unless the sampler is full or the eyes are closed. Returns whether it was kept.
    @discardableResult
    mutating func add(_ measurements: EyeMeasurements) -> Bool {
        guard !isComplete, measurements.openness >= EyeMeasurer.minimumOpenness else { return false }
        samples.append(measurements)
        return true
    }

    mutating func reset() { samples.removeAll() }

    func median() -> EyeMeasurements? {
        guard !samples.isEmpty else { return nil }
        func middle(_ value: (EyeMeasurements) -> Float) -> Float {
            let sorted = samples.map(value).sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        return EyeMeasurements(openness: middle(\.openness), tilt: middle(\.tilt),
                               spacing: middle(\.spacing), lidSpace: middle(\.lidSpace))
    }
}
