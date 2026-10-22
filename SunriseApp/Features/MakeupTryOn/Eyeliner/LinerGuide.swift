import CoreGraphics

struct LinerAnchors {
    var innerCorner: CGPoint
    var outerCorner: CGPoint
    var upperStart: CGPoint
    var wingRoot: CGPoint?
    var wingTip: CGPoint?
    var browTail: CGPoint?
}

/// All polygons are in the same pixel space as the input landmarks.
/// Every polygon has the same winding so they can be filled as one union path.
struct LinerGuide {
    var upperLiner: [CGPoint]
    var tightline: [CGPoint]
    var wing: [CGPoint]
    var lowerLiner: [CGPoint]
    /// Seamless render outlines (upper liner + wing merged when the wing starts at the outer corner).
    var outlines: [[CGPoint]]
    var anchors: LinerAnchors
}

/// Global (not per-variant) geometry tweaks, in fractions of eye width.
struct LinerBuildOptions: Equatable {
    /// The spike's gap above the lash line (0.006 eye widths). On device the liner then read as sitting a bit too close
    /// to the eye, so `lashOffset` starts higher; tune `defaultLashOffset`.
    static let spikeLashOffset: CGFloat = 0.006
    static let defaultLashOffset: CGFloat = 0.012

    /// How steeply the wing may point up or down, either way, in radians. The spike clamped it to -20...60 degrees; a
    /// lid pulled hard sideways or upward needs far more room, so the wing may follow the eye up to 80 degrees.
    static let wingElevationLimit: CGFloat = 80 * .pi / 180
    /// Largest slope (rise over run, in eye widths) used to extend the lash line past a corner. The spike used 0.6.
    static let extensionSlopeLimit: CGFloat = 1.2

    /// Gap between the lash line and the liner's base, measured OUTWARD (up for the upper liner, down for the lower).
    /// 0 = liner starts exactly on the lash line (where the tightline would be). Negative = pushes into the eye.
    var lashOffset: CGFloat = LinerBuildOptions.defaultLashOffset
    /// How far the upper line is extended past the INNER / OUTER corner (the outer landmark usually sits inside
    /// the visible outer corner; the inner side curves down, so it gets none by default).
    var innerExtension: CGFloat = 0.0
    var outerExtension: CGFloat = 0.07
}

extension LinerGuide {
    /// The guide moved by a head-motion transform (translate, rotate, uniform scale); winding is preserved.
    func transformed(by t: SimilarityTransform) -> LinerGuide {
        func move(_ points: [CGPoint]) -> [CGPoint] { points.map(t.apply) }
        let a = anchors
        return LinerGuide(upperLiner: move(upperLiner), tightline: move(tightline), wing: move(wing),
                          lowerLiner: move(lowerLiner), outlines: outlines.map(move),
                          anchors: LinerAnchors(innerCorner: t.apply(a.innerCorner), outerCorner: t.apply(a.outerCorner),
                                                upperStart: t.apply(a.upperStart), wingRoot: a.wingRoot.map(t.apply),
                                                wingTip: a.wingTip.map(t.apply), browTail: a.browTail.map(t.apply)))
    }
}
