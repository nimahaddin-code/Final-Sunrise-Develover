import simd

/// Liner outlines in the face texture's UV space, built in each eye's own frame so they do not depend on head roll,
/// distance or which eye it is. Geometry ported from the eyeliner spike; the repo's pipeline (Vision points mapped
/// to face-mesh UV) feeds it through `shape(_:eye:brow:frame:)`.
enum LinerGeometry {
    // MARK: - Tuning constants (eye-width units unless noted)

    /// Share of a liner's total width drawn on the outer side of the lash line (above it for the upper liner);
    /// the rest goes into the lid edge. 1 matches the eyeliner spike, which drew its whole width above the lash line.
    static let linerAboveFraction: Float = 1
    /// Moves the whole liner away from the eye: positive is further up for the upper liner (further down for the
    /// lower liner), negative moves it into the eye. 0.006 is the spike's own lash offset.
    static let linerLashOffset: Float = 0.006
    /// Scales every style's widths. 1 draws the widths as written. The live view is smaller and softer than the spike's screen overlay, so the line is drawn thicker to stay noticeable.
    static let linerThicknessScale: Float = 2.5
    /// How far the upper line is extended past the inner corner; the inner side curves down, so none by default.
    static let innerExtension: Float = 0
    /// How far the upper line is extended past the outer corner; the landmark usually sits inside the visible corner.
    static let outerExtension: Float = 0.07
    /// Wing elevation limits above the eye's axis, in degrees.
    static let wingElevationRange: ClosedRange<Float> = -20...60

    // MARK: - Result

    struct Shape: Equatable {
        /// Polygons to fill with the liner shade (upper liner merged with its wing, or separate; lower liner;
        /// tightline when requested).
        var outlines: [[SIMD2<Float>]]
        var wingTip: SIMD2<Float>?
        var hasLowerLine: Bool
    }

    // MARK: - Adapter from Vision points in UV

    /// `eye` is the Vision eye contour (about 6-8 points) and `brow` the brow points, both in UV.
    /// The corners are the points furthest apart along `frame.outward`; the rest split into upper and lower lid by
    /// which side of the corner-to-corner line they lie on (toward `frame.up` is upper).
    static func shape(_ style: LinerStyle, eye: [SIMD2<Float>], brow: [SIMD2<Float>], frame: FeatureFrame,
                      includeTightline: Bool = false) -> Shape? {
        guard eye.count >= 3,
              let inner = eye.min(by: { frame.across($0) < frame.across($1) }),
              let outer = eye.max(by: { frame.across($0) < frame.across($1) }),
              let eyeFrame = EyeFrame(inner: inner, outer: outer, up: frame.up) else { return nil }
        let local = eye.map(eyeFrame.toLocal)
        // Points within 1% of the corner line belong to neither lid (usually the corners themselves).
        let upper = local.filter { $0.y < -0.01 }
        let lower = local.filter { $0.y > 0.01 }
        return build(style, upper: upper, lower: lower, brow: brow.map(eyeFrame.toLocal), frame: eyeFrame,
                     includeTightline: includeTightline)
    }

    // MARK: - Builder

    private enum Side { case up, down }

    /// `upper`, `lower` and `brow` are in the eye's local frame (x inner to outer, y down, unit = eye width).
    private static func build(_ style: LinerStyle, upper: [SIMD2<Float>], lower: [SIMD2<Float>],
                              brow: [SIMD2<Float>], frame: EyeFrame, includeTightline: Bool) -> Shape? {
        // The corner landmarks sit slightly inside the visible lash line, hence the extension past both corners.
        let upperLine = Polyline(MakeupTextureRenderer.smoothed(
            extended(localLashLine(upper), inner: innerExtension, outer: outerExtension)))
        let lowerLine = Polyline(MakeupTextureRenderer.smoothed(localLashLine(lower)))
        let outerLocal = SIMD2<Float>(1, 0)

        // ---- Upper liner ----
        let start = min(max(style.start, 0), 0.95)
        let count = 32
        let base = upperLine.sample(from: start, to: 1, count: count)
        var widths: [Float] = []
        for index in 0..<count {
            let progress = Float(index) / Float(count - 1)
            // Soft start so a liner that begins mid-lid fades in instead of starting blunt.
            widths.append(width(style, progress: progress) * min(1, 0.2 + progress * 5))
        }
        let upperStrip = strip(base: base, widths: widths, side: .up)

        // ---- Tightline: thin strip on the inner rim of the lash line ----
        var tightline: [SIMD2<Float>] = []
        if style.tightline && includeTightline {
            let rim = upperLine.sample(from: start, to: 1, count: 24)
            let rimWidths = (0..<rim.count).map { index -> Float in
                let u = Float(index) / Float(rim.count - 1)
                let fade = min(smoothstep(0, 0.15, u), smoothstep(0, 0.1, 1 - u))
                return 0.013 * (0.2 + 0.8 * fade)
            }
            tightline = strip(base: rim, widths: rimWidths, side: .down, aboveFraction: 1, offset: 0).polygon
        }

        // ---- Wing ----
        var wingPolygon: [SIMD2<Float>] = []
        var wingTip: SIMD2<Float>?
        var merged: [SIMD2<Float>]?
        if style.wingLength > 0.005 {
            var direction: SIMD2<Float>
            switch style.wingBase {
            case .horizontal: direction = SIMD2(1, 0)
            case .lowerLidTangent: direction = unit(lowerLine.point(at: 1) - lowerLine.point(at: 0.82))
            }
            if style.wingTargetsBrowTail, let tail = brow.max(by: { $0.x < $1.x }) {
                direction = unit(direction + (unit(tail - outerLocal) - direction) * 0.6)
            }
            // Elevation in radians, positive is up (up is -y locally).
            let range = wingElevationRange
            let lifted = atan2(-direction.y, direction.x) + style.wingAngle * .pi / 180
            let elevation = min(max(lifted, range.lowerBound * .pi / 180), range.upperBound * .pi / 180)
            direction = SIMD2(cos(elevation), -sin(elevation))

            let bottomRoot: SIMD2<Float>, topRoot: SIMD2<Float>, topTangent: SIMD2<Float>
            switch style.wingOrigin {
            case .outerCorner:
                bottomRoot = outerLocal + SIMD2(0, -linerLashOffset)
                if upperStrip.edge.count >= 2 {
                    topRoot = upperStrip.edge[upperStrip.edge.count - 1]
                    topTangent = unit(topRoot - upperStrip.edge[upperStrip.edge.count - 2])
                } else {
                    topRoot = outerLocal + SIMD2(0, -0.02)
                    topTangent = direction
                }
            case .underLowerLash:
                bottomRoot = lowerLine.point(at: 0.88) + SIMD2(0.01, 0.012)
                topRoot = outerLocal
                topTangent = direction
            }
            let tip = bottomRoot + direction * style.wingLength
            let control = topRoot + topTangent * (simd_distance(tip, topRoot) * 0.5)

            // Top edge: quadratic Bezier from the tip back to topRoot, leaving topRoot along the liner's top edge.
            let steps = 10
            let curve = (1..<steps).map { step -> SIMD2<Float> in
                let t = Float(step) / Float(steps)
                return tip * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + topRoot * (t * t)
            }
            wingPolygon = [bottomRoot, tip] + curve + [topRoot]
            wingTip = tip
            if style.wingOrigin == .outerCorner, upperStrip.edge.count >= 2 {
                merged = upperStrip.base + [tip] + curve + upperStrip.edge.reversed()
            }
        }

        // ---- Lower liner ----
        var lowerPolygon: [SIMD2<Float>] = []
        let lowerSpec = style.lowerLine
        if lowerSpec.enabled, lowerSpec.extent > 0.01, lowerSpec.thickness > 0.001 {
            let extent = min(max(lowerSpec.extent, 0), 1)
            let lowerBase = lowerLine.sample(from: 1 - extent, to: 1, count: 22)
            let lowerWidths = (0..<lowerBase.count).map { index -> Float in
                let u = Float(index) / Float(lowerBase.count - 1)
                return lowerSpec.thickness * (0.1 + 0.9 * smoothstep(0, 0.6, u))
            }
            lowerPolygon = strip(base: lowerBase, widths: lowerWidths, side: .down).polygon
        }

        var outlines: [[SIMD2<Float>]] = []
        if let merged {
            outlines.append(merged)
        } else {
            outlines.append(upperStrip.polygon)
            if !wingPolygon.isEmpty { outlines.append(wingPolygon) }
        }
        if !lowerPolygon.isEmpty { outlines.append(lowerPolygon) }
        if !tightline.isEmpty { outlines.append(tightline) }
        guard outlines.allSatisfy({ !$0.isEmpty }) else { return nil }
        return Shape(outlines: outlines.map { $0.map(frame.toWorld) },
                     wingTip: wingTip.map(frame.toWorld),
                     hasLowerLine: !lowerPolygon.isEmpty)
    }

    // MARK: - Helpers

    /// Total liner width (eye widths) at `progress` along the drawn part of the lid: inner, mid, then outer.
    /// Without a `midWidth` this is the straight taper the styles were designed with.
    private static func width(_ style: LinerStyle, progress: Float) -> Float {
        let scale = linerThicknessScale
        guard let mid = style.midWidth else {
            return (style.innerWidth + (style.outerWidth - style.innerWidth) * progress) * scale
        }
        if progress < 0.5 { return (style.innerWidth + (mid - style.innerWidth) * (progress / 0.5)) * scale }
        return (mid + (style.outerWidth - mid) * ((progress - 0.5) / 0.5)) * scale
    }

    /// Lash line in the local frame: the corners (0,0) and (1,0) are forced as end points and the interior points
    /// are sorted along x.
    ///
    /// Vision gives only about 6-8 contour points per eye, so each lid has 0-3 interior points. The spike's filters
    /// (x within 0.04...0.96, at least 0.02 apart) only drop points that crowd the corners, so they are kept as-is.
    /// A lid with no interior points falls back to the straight corner-to-corner line.
    static func localLashLine(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let interior = points.filter { $0.x > 0.04 && $0.x < 0.96 }.sorted { $0.x < $1.x }
        var line: [SIMD2<Float>] = [SIMD2(0, 0)]
        for point in interior where point.x - line[line.count - 1].x > 0.02 { line.append(point) }
        line.append(SIMD2(1, 0))
        return line
    }

    private static func extended(_ points: [SIMD2<Float>], inner: Float, outer: Float) -> [SIMD2<Float>] {
        guard points.count >= 2 else { return points }
        func slope(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            min(max((b.y - a.y) / max(b.x - a.x, 1e-3), -0.6), 0.6)
        }
        var result = points
        if inner > 0 {
            result.insert(SIMD2(points[0].x - inner, points[0].y - slope(points[0], points[1]) * inner), at: 0)
        }
        if outer > 0 {
            let last = points[points.count - 1], before = points[points.count - 2]
            result.append(SIMD2(last.x + outer, last.y + slope(before, last) * outer))
        }
        return result
    }

    /// Offsets each base point along its normal. A width `w` puts `w * aboveFraction + offset` on the outer side
    /// of the base (up for `.up`, down for `.down`) and `w * (1 - aboveFraction) - offset` on the inner side.
    private static func strip(base: [SIMD2<Float>], widths: [Float], side: Side,
                              aboveFraction: Float = linerAboveFraction, offset: Float = linerLashOffset)
        -> (polygon: [SIMD2<Float>], edge: [SIMD2<Float>], base: [SIMD2<Float>]) {
        guard base.count >= 2, base.count == widths.count else { return ([], [], []) }
        var edge: [SIMD2<Float>] = [], bottom: [SIMD2<Float>] = []
        for index in base.indices {
            let tangent = unit(base[min(index + 1, base.count - 1)] - base[max(index - 1, 0)])
            var normal = SIMD2(tangent.y, -tangent.x)   // -y (up) when travelling toward +x
            if side == .down { normal = -normal }
            edge.append(base[index] + normal * (widths[index] * aboveFraction + offset))
            bottom.append(base[index] - normal * (widths[index] * (1 - aboveFraction) - offset))
        }
        return (bottom + edge.reversed(), edge, bottom)
    }

    private static func unit(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(vector)
        return length > 1e-9 ? vector / length : SIMD2(1, 0)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// The eye's own frame: origin at the inner corner, x toward the outer corner, y pointing away from `up`
/// (so the upper lid is at negative y on either eye), unit = eye width.
struct EyeFrame: Equatable {
    let origin: SIMD2<Float>
    let ex: SIMD2<Float>
    let ey: SIMD2<Float>
    let width: Float

    init?(inner: SIMD2<Float>, outer: SIMD2<Float>, up: SIMD2<Float>) {
        let axis = outer - inner
        let length = simd_length(axis)
        guard length > 1e-6 else { return nil }
        origin = inner
        ex = axis / length
        let perpendicular = SIMD2(-ex.y, ex.x)
        ey = simd_dot(perpendicular, up) > 0 ? -perpendicular : perpendicular
        width = length
    }

    func toLocal(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let offset = point - origin
        return SIMD2(simd_dot(offset, ex), simd_dot(offset, ey)) / width
    }

    func toWorld(_ local: SIMD2<Float>) -> SIMD2<Float> {
        origin + (ex * local.x + ey * local.y) * width
    }
}

/// Points with arc-length lookup.
private struct Polyline {
    let points: [SIMD2<Float>]
    private let cumulative: [Float]

    init(_ points: [SIMD2<Float>]) {
        self.points = points
        var sums: [Float] = [], total: Float = 0
        for (index, point) in points.enumerated() {
            if index > 0 { total += simd_distance(point, points[index - 1]) }
            sums.append(total)
        }
        cumulative = sums
    }

    /// Point at arc-length fraction `fraction` in 0...1.
    func point(at fraction: Float) -> SIMD2<Float> {
        guard points.count > 1, let total = cumulative.last, total > 1e-9 else { return points.first ?? .zero }
        let target = min(max(fraction, 0), 1) * total
        var low = 0, high = cumulative.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] <= target { low = middle } else { high = middle }
        }
        let segment = cumulative[high] - cumulative[low]
        let t = segment > 1e-12 ? (target - cumulative[low]) / segment : 0
        return points[low] + (points[high] - points[low]) * t
    }

    func sample(from start: Float, to end: Float, count: Int) -> [SIMD2<Float>] {
        let n = max(count, 2)
        return (0..<n).map { point(at: start + (end - start) * Float($0) / Float(n - 1)) }
    }
}
