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

    var hasNose: Bool { left.noseWing != nil && right.noseWing != nil }

    /// Why the category looks the way it does on this face.
    func notes(for category: MakeupCategory) -> [LocalizedStringResource] {
        switch category {
        case .eyebrow:
            hasNose
                ? ["Starts above your inner eye corner, arches over the outer edge of your iris and ends on the line from your nose to your outer eye corner."]
                : ["Starts above your inner eye corner and arches over the outer edge of your iris."]
        case .eyeliner:
            [tiltNote, spacingNote].compactMap { $0 }
        case .blush:
            left.noseDepth != nil
                ? ["Kept above the tip of your nose and outside your pupils, scaled to your cheeks."]
                : ["Kept outside your pupils."]
        }
    }

    private var tiltNote: LocalizedStringResource? {
        switch tilt {
        case .down: "Your outer eye corners sit a little low, so the wing lifts higher to open up your eyes."
        case .up: "Your eyes already lift at the outer corners, so the wing stays lower to keep it balanced."
        case .balanced: "Your eye tilt is balanced, so the wing follows the classic angle."
        }
    }

    private var spacingNote: LocalizedStringResource? {
        switch spacing {
        case .close: "Your eyes are close-set, so the liner focuses on the outer half."
        case .wide: "Your eyes are wide-set, so the liner starts right at the inner corner."
        case .balanced: nil
        }
    }
}

/// Fits a catalog style to measured features using makeup-artist guide lines.
enum MakeupFitter {
    /// The iris edge sits about this far from the eye centre, in eye widths.
    static let irisEdge: Float = 0.2

    static func eyeliner(_ style: LinerStyle, fit: FaceFit) -> LinerStyle {
        var fitted = style
        if style.wingLength > 0 {
            // Compensate for the eye's own tilt, so every wing ends up lifting about the same amount visually.
            fitted.wingAngle = min(max(style.wingAngle + (FaceFit.typicalEyeTilt - fit.eyeTilt) * 0.8, 0), 40)
        }
        let spacing = fit.eyeSpacing - FaceFit.typicalEyeSpacing
        // Close-set eyes look wider with liner on the outer half; wide-set eyes with liner from the inner corner.
        fitted.start = min(max(style.start - spacing * 0.6, 0), 0.6)
        if spacing > 0.15 {
            fitted.innerWidth = style.innerWidth * 1.3
            fitted.midWidth = style.midWidth.map { $0 * 1.15 }
        }
        return fitted
    }

    static func blush(_ style: BlushStyle, side: SideFit) -> BlushStyle {
        var fitted = style
        if let depth = side.noseDepth, depth > 0 {
            // Scale the height to this face, then keep the patch between the lower lid and the tip of the nose.
            let scaled = style.center.y * min(max(depth / 0.6, 0.75), 1.3)
            let lowest = depth - style.radii.y * 0.6
            let highest = 0.15 + style.radii.y * 0.8
            fitted.center.y = max(min(scaled, lowest), highest)
        }
        // Not closer to the nose than the pupil line.
        let innerReach = style.radii.x * cos(style.tilt * .pi / 180) * 0.6
        fitted.center.x = max(style.center.x, innerReach - 0.1)
        return fitted
    }

    /// Where along the face's horizontal axis (frame `across` units) the brow should start, peak and end.
    struct BrowGuides: Equatable {
        var head: Float
        var peak: Float
        var tail: Float
    }

    /// Guide positions blended with the natural brow, so the drawn brow never wanders far from the real one.
    static func browGuides(side: SideFit, naturalHead: SIMD2<Float>, naturalTail: SIMD2<Float>) -> BrowGuides {
        let frame = side.frame
        let headAcross = frame.across(naturalHead), tailAcross = frame.across(naturalTail)
        var tail = tailAcross
        if let wing = side.noseWing,
           let ruleTail = intersection(wing, side.outerCorner, naturalHead, naturalTail).map(frame.across),
           ruleTail > headAcross, ruleTail < tailAcross + (tailAcross - headAcross) * 0.8 {
            // Move halfway toward the guide, and never more than a fifth of the brow past the natural tail.
            tail = min(tailAcross + (ruleTail - tailAcross) * 0.5, tailAcross + (tailAcross - headAcross) * 0.2)
        }
        let head = headAcross + (frame.across(side.innerCorner) - headAcross) * 0.5
        return BrowGuides(head: head, peak: side.eyeWidth * irisEdge, tail: tail)
    }

    /// Intersection of the line through a and b with the line through c and d.
    static func intersection(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>,
                             _ d: SIMD2<Float>) -> SIMD2<Float>? {
        let r = b - a, s = d - c
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        return a + r * t
    }
}
