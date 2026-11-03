// Ported from the EyelinerSpike. Geometry only: (EyeLandmarks, LinerSpec) -> LinerGuide.
import CoreGraphics

/// PURE geometry: (EyeLandmarks, LinerSpec) -> LinerGuide. No UI code.
/// Everything is computed in the eye's local frame (origin = inner corner, x = inner->outer,
/// unit = eye width, up = -y) and converted back to image pixels at the end, which makes the
/// guide invariant to head roll, distance and scale.
enum LinerPathBuilder {

    private enum Side { case up, down }

    static func build(landmarks eye: EyeLandmarks, spec: LinerSpec,
                      options: LinerBuildOptions = LinerBuildOptions()) -> LinerGuide? {
        guard let frame = EyeCoordinateFrame(inner: eye.innerCorner, outer: eye.outerCorner,
                                             upper: eye.upperLid, lower: eye.lowerLid,
                                             brow: eye.browPoints) else { return nil }

        // The corner landmarks sit slightly INSIDE the visible lash line, so the upper line is extended a little
        // past both corners (tangent extrapolation) to cover the whole lid length.
        let upperLine = Polyline2D.smoothed(extended(EyeGeometry.localLashLine(eye.upperLid, frame: frame),
                                                     inner: options.innerExtension + CGFloat(spec.innerExtension),
                                                     outer: options.outerExtension))
        let lowerLine = Polyline2D.smoothed(EyeGeometry.localLashLine(eye.lowerLid, frame: frame))
        let outerLocal = CGPoint(x: 1, y: 0)

        // ---- Upper liner ------------------------------------------------------------
        let start = CGFloat(clamp(spec.upperStart, 0.0, 0.95))
        let thick = thicknessProfile(spec.upperThickness)
        let n = 32
        let upperBase = upperLine.sample(from: start, to: 1, count: n)
        var upperOffsets: [CGFloat] = []
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let t = start + (1 - start) * u
            var k: CGFloat = 1
            // soft start; also tapers the tip of an inner extension so it does not hang off the lid
            if start > 0.001 || spec.innerExtension > 0 { k = 0.15 + 0.85 * smoothstep(0, 0.12, t - start) }
            upperOffsets.append(thick(t) * k * options.thicknessScale)
        }
        let upper = strip(base: upperBase, offsets: upperOffsets, side: .up, inset: -options.lashOffset)

        // ---- Tightline (thin strip on the inner rim of the lash line) ---------------
        var tight: [CGPoint] = []
        if spec.tightline {
            let m = 24
            let base = upperLine.sample(from: start, to: 1, count: m)
            var off: [CGFloat] = []
            for i in 0..<m {
                let u = CGFloat(i) / CGFloat(m - 1)
                let f = min(smoothstep(0, 0.15, u), smoothstep(0, 0.1, 1 - u))
                off.append(0.013 * (0.2 + 0.8 * f))
            }
            tight = strip(base: base, offsets: off, side: .down).polygon
        }

        // ---- Wing --------------------------------------------------------------------
        var wingPolygon: [CGPoint] = []
        var wingTip: CGPoint?
        var wingRoot: CGPoint?
        var merged: [CGPoint]?
        var browTailLocal: CGPoint?

        if spec.wingLength > 0.005 {
            var dir: CGPoint
            switch spec.wingBase {
            case .horizontal:
                dir = CGPoint(x: 1, y: 0)
            case .lowerLidTangent:
                dir = (lowerLine.point(at: 1) - lowerLine.point(at: 0.82)).normalized()
            }

            browTailLocal = eye.browPoints.map { frame.toLocal($0) }.max(by: { $0.x < $1.x })
            if spec.wingTargetsBrowTail, let tail = browTailLocal {
                let toBrow = (tail - outerLocal).normalized()
                dir = dir.lerp(to: toBrow, 0.6).normalized()
            }

            // Elevation in radians, positive = up (up is -y locally).
            var elev = atan2(-dir.y, dir.x) + CGFloat(spec.wingAngleDeg) * CGFloat.pi / 180
            elev = clamp(elev, -LinerBuildOptions.wingElevationLimit, LinerBuildOptions.wingElevationLimit)
            dir = CGPoint(x: cos(elev), y: -sin(elev))

            let bottomRoot: CGPoint
            let topRoot: CGPoint
            let topTangent: CGPoint
            switch spec.wingOrigin {
            case .outerCorner:
                bottomRoot = outerLocal
                if upper.edge.count >= 2 {
                    let last = upper.edge[upper.edge.count - 1]
                    let prev = upper.edge[upper.edge.count - 2]
                    topRoot = last
                    topTangent = (last - prev).normalized()
                } else {
                    topRoot = outerLocal + CGPoint(x: 0, y: -0.02)
                    topTangent = dir
                }
            case .underLowerLash:
                let l = lowerLine.point(at: 0.88)
                bottomRoot = l + CGPoint(x: 0.01, y: 0.012)
                topRoot = outerLocal
                topTangent = dir
            }

            var tip = bottomRoot + dir * CGFloat(spec.wingLength)
            // The wing is attached to a skin point beside the eye: when that skin is stretched the tip goes with it.
            if let anchor = eye.wingAnchor {
                var pull = frame.toLocal(anchor) - LinerBuildOptions.wingAnchorLocal
                if pull.length > LinerBuildOptions.wingAnchorReach { pull = pull.normalized() * LinerBuildOptions.wingAnchorReach }
                tip = tip + pull
            }
            let dist = (tip - topRoot).length
            let ctrl = topRoot + topTangent * (dist * 0.5)

            // Top edge: quadratic Bezier tip -> topRoot, leaving topRoot along the liner's top edge.
            var curve: [CGPoint] = []
            let steps = 10
            for i in 1..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                let a = (1 - t) * (1 - t)
                let b = 2 * (1 - t) * t
                let c = t * t
                curve.append(tip * a + ctrl * b + topRoot * c)
            }

            wingPolygon = [bottomRoot, tip] + curve + [topRoot]
            wingTip = tip
            wingRoot = bottomRoot
            if spec.wingOrigin == .outerCorner, upper.edge.count >= 2 {
                merged = upper.base + [tip] + curve + Array(upper.edge.reversed())
            }
        }

        // ---- Lower liner ----------------------------------------------------------------
        var lowerPoly: [CGPoint] = []
        if spec.lowerLine.enabled, spec.lowerLine.extent > 0.01, spec.lowerLine.thickness > 0.001 {
            let ext = CGFloat(clamp(spec.lowerLine.extent, 0.0, 1.0))
            let m = 22
            let base = lowerLine.sample(from: 1 - ext, to: 1, count: m)
            var off: [CGFloat] = []
            for i in 0..<m {
                let u = CGFloat(i) / CGFloat(m - 1)
                off.append(CGFloat(spec.lowerLine.thickness) * options.thicknessScale * (0.1 + 0.9 * smoothstep(0, 0.6, u)))
            }
            lowerPoly = strip(base: base, offsets: off, side: .down, inset: -options.lashOffset).polygon
        }

        // ---- Outlines + conversion back to pixels ------------------------------------------
        var outlinesLocal: [[CGPoint]] = []
        if let merged {
            outlinesLocal.append(merged)
        } else {
            outlinesLocal.append(upper.polygon)
            if !wingPolygon.isEmpty { outlinesLocal.append(wingPolygon) }
        }
        if !lowerPoly.isEmpty { outlinesLocal.append(lowerPoly) }

        func world(_ pts: [CGPoint]) -> [CGPoint] {
            let w = pts.map { frame.toWorld($0) }
            return signedArea(w) < 0 ? Array(w.reversed()) : w
        }

        let anchors = LinerAnchors(
            innerCorner: eye.innerCorner,
            outerCorner: eye.outerCorner,
            upperStart: frame.toWorld(upperBase.first ?? .zero),
            wingRoot: wingRoot.map { frame.toWorld($0) },
            wingTip: wingTip.map { frame.toWorld($0) },
            browTail: browTailLocal.map { frame.toWorld($0) }
        )

        return LinerGuide(upperLiner: world(upper.polygon),
                          tightline: world(tight),
                          wing: world(wingPolygon),
                          lowerLiner: world(lowerPoly),
                          outlines: outlinesLocal.map { world($0) },
                          anchors: anchors)
    }

    // MARK: - Helpers

    private static func extended(_ pts: [CGPoint], inner: CGFloat, outer: CGFloat) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        func slope(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            clamp((b.y - a.y) / max(b.x - a.x, 1e-3), -LinerBuildOptions.extensionSlopeLimit, LinerBuildOptions.extensionSlopeLimit)
        }
        var out = pts
        if inner > 0 {
            let f = pts[0], f2 = pts[1]
            // Hugs the curve of the inner corner: most of the lid's slope there, easing only slightly, in three steps.
            let s = slope(f, f2) * 0.8
            for step in (1...3).reversed() {
                let u = inner * CGFloat(step) / 3
                out.insert(CGPoint(x: f.x - u, y: f.y - s * (u - 0.15 * u * u / inner)), at: 0)
            }
        }
        if outer > 0 {
            let l = pts[pts.count - 1], l2 = pts[pts.count - 2]
            out.append(CGPoint(x: l.x + outer, y: l.y + slope(l2, l) * outer))
        }
        return out
    }

    /// Piecewise-linear [inner, mid, outer] thickness over the full lash line (t in 0...1).
    private static func thicknessProfile(_ values: [Double]) -> (CGFloat) -> CGFloat {
        let v: [CGFloat] = Array((values + [0, 0, 0]).prefix(3)).map { CGFloat(max($0, 0)) }
        return { t in
            let tt = clamp(t, 0, 1)
            if tt < 0.5 { return v[0] + (v[1] - v[0]) * (tt / 0.5) }
            return v[1] + (v[2] - v[1]) * ((tt - 0.5) / 0.5)
        }
    }

    /// Offsets each base point along its normal; returns the closed polygon and the offset edge.
    /// `inset` > 0 pushes the base edge INTO the eye, < 0 pushes it OUTWARD (liner sits on top of the lash line).
    private static func strip(base: [CGPoint], offsets: [CGFloat], side: Side, inset: CGFloat = 0)
        -> (polygon: [CGPoint], edge: [CGPoint], base: [CGPoint]) {
        guard base.count >= 2, base.count == offsets.count else { return ([], [], []) }
        var edge: [CGPoint] = []
        var insetBase: [CGPoint] = []
        for i in base.indices {
            let a = base[max(i - 1, 0)]
            let b = base[min(i + 1, base.count - 1)]
            let tangent = (b - a).normalized()
            var nrm = CGPoint(x: tangent.y, y: -tangent.x)   // -y (up) for +x travel
            if side == .down { nrm = -nrm }
            // The whole strip moves with `inset`, so the gap above the lash line never thins the liner. (The spike moved
            // only the base edge, which made the liner thinner as the gap grew and inverted its thin ends.)
            edge.append(base[i] + nrm * (offsets[i] - inset))
            insetBase.append(base[i] - nrm * inset)
        }
        return (insetBase + Array(edge.reversed()), edge, insetBase)
    }
}
