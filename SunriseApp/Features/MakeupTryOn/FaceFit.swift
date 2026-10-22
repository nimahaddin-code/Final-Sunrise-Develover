import Foundation
import simd

/// One side of the face, measured from the located features, used to fit makeup to this person.
struct SideFit: Equatable, Sendable {
    let frame: FeatureFrame
    let innerCorner: SIMD2<Float>
    let outerCorner: SIMD2<Float>
    let eyeWidth: Float
    /// Degrees; positive when the outer corner sits higher than the inner corner.
    let eyeTilt: Float
    /// Height of the eye opening along the face's vertical, divided by the eye width. Small when the eye is closed.
    let eyeOpenness: Float
    /// Widest point of the nose on this side, the start of the classic brow and liner guide lines.
    let noseWing: SIMD2<Float>?
    /// How far the bottom of the nose sits below the eye centre, in eye-distance units.
    let noseDepth: Float?

    init?(side: FaceFeatureMap.Side, map: FaceFeatureMap) {
        let frame = FeatureFrame(side: side, in: map)
        guard let inner = side.eye.min(by: { frame.across($0) < frame.across($1) }),
              let outer = side.eye.max(by: { frame.across($0) < frame.across($1) }) else { return nil }
        let axis = outer - inner
        let width = simd_length(axis)
        guard width > 0 else { return nil }
        self.frame = frame
        innerCorner = inner
        outerCorner = outer
        eyeWidth = width
        eyeTilt = atan2(simd_dot(axis, frame.up), simd_dot(axis, frame.outward)) * 180 / .pi
        let heights = side.eye.map { simd_dot($0, frame.up) }
        eyeOpenness = ((heights.max() ?? 0) - (heights.min() ?? 0)) / width
        noseWing = map.nose.max { frame.across($0) < frame.across($1) }
        noseDepth = map.nose.map { -simd_dot($0 - frame.origin, frame.up) / frame.unit }.max()
    }
}

/// Measurements of the whole face that tailor every makeup style to the person in front of the camera.
struct FaceFit: Equatable, Sendable {
    enum Tilt: Equatable, Sendable { case down, balanced, up }
    enum Spacing: Equatable, Sendable { case close, balanced, wide }

    /// Typical canthal tilt; eyes below it read as downturned.
    static let typicalEyeTilt: Float = 4
    /// Typical gap between the inner eye corners, in eye widths.
    static let typicalEyeSpacing: Float = 1

    let left: SideFit
    let right: SideFit

    init?(features: FaceFeatureMap) {
        guard let left = SideFit(side: features.left, map: features),
              let right = SideFit(side: features.right, map: features) else { return nil }
        self.left = left
        self.right = right
    }

    func side(for frame: FeatureFrame) -> SideFit { frame == left.frame ? left : right }

    var eyeTilt: Float { (left.eyeTilt + right.eyeTilt) / 2 }

    /// Gap between the inner eye corners divided by the average eye width.
    var eyeSpacing: Float {
        simd_distance(left.innerCorner, right.innerCorner) / ((left.eyeWidth + right.eyeWidth) / 2)
    }

    var tilt: Tilt {
        if eyeTilt < Self.typicalEyeTilt - 3 { .down } else if eyeTilt > Self.typicalEyeTilt + 3 { .up } else { .balanced }
    }

    var spacing: Spacing {
        if eyeSpacing < 0.9 { .close } else if eyeSpacing > 1.15 { .wide } else { .balanced }
    }

    /// Eye opening height divided by eye width, averaged over both eyes.
    var eyeOpenness: Float { (left.eyeOpenness + right.eyeOpenness) / 2 }

    /// The eye measurements the face scan keeps. `samples` is the number of Vision readings averaged into them.
    func eyeScan(samples: Int) -> EyeScan {
        EyeScan(tiltLeft: left.eyeTilt, tiltRight: right.eyeTilt, spacing: eyeSpacing, openness: eyeOpenness,
                samples: samples)
    }

    var hasNose: Bool { left.noseWing != nil && right.noseWing != nil }

    /// Why the category looks the way it does on this face.
    func notes(for category: MakeupCategory) -> [LocalizedStringResource] {
        switch category {
        case .eyebrow:
            hasNose
                ? ["Starts above your inner eye corner, arches over the outer edge of your iris and ends on the line from your nose to your outer eye corner."]
                : ["Starts above your inner eye corner and arches over the outer edge of your iris."]
        case .eyeliner:
            // Chosen from the eye shape measured in the face scan; see `EyelinerPlan.notes`.
            []
        case .blush:
            left.noseDepth != nil
                ? ["Kept above the tip of your nose and outside your pupils, scaled to your cheeks."]
                : ["Kept outside your pupils."]
        }
    }
}

/// Fits a catalog style to measured features using makeup-artist guide lines.
// -Nimah: Removed legacy eyebrow/blush MakeupFitter; eye measurements above remain shared.
