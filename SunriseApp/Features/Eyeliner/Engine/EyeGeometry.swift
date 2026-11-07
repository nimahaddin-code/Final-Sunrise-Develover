// Ported from the EyelinerSpike. Geometry only: no UI, no MediaPipe.
import CoreGraphics

// MARK: - Local eye coordinate frame

/// origin = inner corner, x-axis = inner -> outer, unit = eye width.
/// y is chosen so the UPPER lid is at smaller y than the LOWER lid, for both eyes
/// (so "up" is always -y and the same rules work on either eye).
struct EyeCoordinateFrame {
    let origin: CGPoint
    let ex: CGPoint
    let ey: CGPoint
    let width: CGFloat

    /// `brow` decides which side is UP (brows are always above the eye). Using the lids for this flips when the eye
    /// is nearly closed (upper and lower lid cross), which made the guide jump below the eye.
    init?(inner: CGPoint, outer: CGPoint, upper: [CGPoint], lower: [CGPoint], brow: [CGPoint] = []) {
        let v = outer - inner
        let w = v.length
        guard w > 1e-3 else { return nil }
        let axis = v * (1 / w)
        var perp = CGPoint(x: -axis.y, y: axis.x)

        func meanProjection(_ pts: [CGPoint]) -> CGFloat? {
            guard !pts.isEmpty else { return nil }
            var sum: CGFloat = 0
            for p in pts { sum += (p - inner).dot(CGPoint(x: -axis.y, y: axis.x)) }
            return sum / CGFloat(pts.count)
        }
        if let b = meanProjection(brow) {
            if b > 0 { perp = -perp }
        } else if let u = meanProjection(upper), let l = meanProjection(lower), l < u {
            perp = -perp
        }
        self.origin = inner
        self.ex = axis
        self.ey = perp
        self.width = w
    }

    func toLocal(_ p: CGPoint) -> CGPoint {
        let d = p - origin
        return CGPoint(x: d.dot(ex) / width, y: d.dot(ey) / width)
    }

    func toWorld(_ l: CGPoint) -> CGPoint {
        origin + (ex * l.x + ey * l.y) * width
    }
}

// MARK: - Arc-length polyline with Catmull-Rom smoothing

struct Polyline2D {
    private(set) var points: [CGPoint]
    private var cumulative: [CGFloat]
    var totalLength: CGFloat { cumulative.last ?? 0 }

    init(points: [CGPoint]) {
        self.points = points
        var c: [CGFloat] = []
        var acc: CGFloat = 0
        for (i, p) in points.enumerated() {
            if i > 0 { acc += (p - points[i - 1]).length }
            c.append(acc)
        }
        self.cumulative = c
    }

    static func smoothed(_ pts: [CGPoint], subdivisions: Int = 8) -> Polyline2D {
        Polyline2D(points: catmullRom(pts, subdivisions: subdivisions))
    }

    private static func cr(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        let term1: CGFloat = 2 * b
        let term2: CGFloat = (c - a) * t
        let term3: CGFloat = (2 * a - 5 * b + 4 * c - d) * t2
        let term4: CGFloat = (3 * b - a - 3 * c + d) * t3
        return 0.5 * (term1 + term2 + term3 + term4)
    }

    static func catmullRom(_ p: [CGPoint], subdivisions: Int) -> [CGPoint] {
        guard p.count >= 3 else { return p }
        var out: [CGPoint] = []
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)]
            let p1 = p[i]
            let p2 = p[i + 1]
            let p3 = p[min(i + 2, p.count - 1)]
            for s in 0..<subdivisions {
                let t = CGFloat(s) / CGFloat(subdivisions)
                out.append(CGPoint(x: cr(p0.x, p1.x, p2.x, p3.x, t),
                                   y: cr(p0.y, p1.y, p2.y, p3.y, t)))
            }
        }
        out.append(p[p.count - 1])
        return out
    }

    /// Point at arc-length fraction f in 0...1.
    func point(at f: CGFloat) -> CGPoint {
        guard points.count > 1, totalLength > 1e-9 else { return points.first ?? .zero }
        let s = clamp(f, 0, 1) * totalLength
        var lo = 0
        var hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= s { lo = mid } else { hi = mid }
        }
        let seg = cumulative[hi] - cumulative[lo]
        let u = seg > 1e-12 ? (s - cumulative[lo]) / seg : 0
        return points[lo].lerp(to: points[hi], u)
    }

    func sample(from a: CGFloat, to b: CGFloat, count: Int) -> [CGPoint] {
        let n = max(count, 2)
        return (0..<n).map { i in
            let u = CGFloat(i) / CGFloat(n - 1)
            return point(at: a + (b - a) * u)
        }
    }
}

// MARK: - Eye helpers shared by providers and the path builder

enum EyeGeometry {

    static func sortedAlongAxis(_ pts: [CGPoint], inner: CGPoint, outer: CGPoint) -> [CGPoint] {
        let axis = (outer - inner).normalized()
        return pts.sorted { ($0 - inner).dot(axis) < ($1 - inner).dot(axis) }
    }

    /// Builds a clean EyeLandmarks from unordered raw points: sorts lids and brows inner -> outer
    /// and computes eyeOpenRatio. A teammate's provider can reuse this.
    static func makeEyeLandmarks(side: EyeSide,
                                 inner: CGPoint,
                                 outer: CGPoint,
                                 upper: [CGPoint],
                                 lower: [CGPoint],
                                 brow: [CGPoint]) -> EyeLandmarks {
        let u = sortedAlongAxis(upper, inner: inner, outer: outer)
        let l = sortedAlongAxis(lower, inner: inner, outer: outer)
        let b = sortedAlongAxis(brow, inner: inner, outer: outer)
        var ratio: CGFloat = 0
        if let frame = EyeCoordinateFrame(inner: inner, outer: outer, upper: u, lower: l, brow: b) {
            ratio = openRatio(upper: u, lower: l, frame: frame)
        }
        return EyeLandmarks(side: side, innerCorner: inner, outerCorner: outer,
                            upperLid: u, lowerLid: l, browPoints: b, eyeOpenRatio: ratio)
    }

    /// Local-frame lash line: corners (0,0) and (1,0) forced as end points, interior points sorted by x.
    static func localLashLine(_ pts: [CGPoint], frame: EyeCoordinateFrame) -> [CGPoint] {
        let interior = pts.map { frame.toLocal($0) }
            .filter { $0.x > 0.04 && $0.x < 0.96 }
            .sorted { $0.x < $1.x }
        var out: [CGPoint] = [CGPoint(x: 0, y: 0)]
        for p in interior where p.x - out[out.count - 1].x > 0.02 {
            out.append(p)
        }
        out.append(CGPoint(x: 1, y: 0))
        return out
    }

    static func yAt(_ x: CGFloat, _ line: [CGPoint]) -> CGFloat {
        guard line.count >= 2 else { return 0 }
        for i in 1..<line.count where line[i].x >= x {
            let a = line[i - 1]
            let b = line[i]
            let d = b.x - a.x
            return d > 1e-6 ? a.y + (b.y - a.y) * (x - a.x) / d : a.y
        }
        return line[line.count - 1].y
    }

    static func openRatio(upper: [CGPoint], lower: [CGPoint], frame: EyeCoordinateFrame) -> CGFloat {
        let ul = localLashLine(upper, frame: frame)
        let ll = localLashLine(lower, frame: frame)
        let xs: [CGFloat] = [0.3, 0.5, 0.7]
        var total: CGFloat = 0
        for x in xs { total += yAt(x, ll) - yAt(x, ul) }
        return max(0, total / CGFloat(xs.count))
    }
}

// MARK: - EyeLandmarks utilities

extension EyeLandmarks {
    var flattened: [CGPoint] { [innerCorner, outerCorner] + upperLid + lowerLid + browPoints + (wingAnchor.map { [$0] } ?? []) }

    func replacingPoints(with pts: [CGPoint]) -> EyeLandmarks? {
        guard pts.count == 2 + upperLid.count + lowerLid.count + browPoints.count + (wingAnchor == nil ? 0 : 1) else { return nil }
        var out = self
        var i = 0
        out.innerCorner = pts[i]; i += 1
        out.outerCorner = pts[i]; i += 1
        out.upperLid = Array(pts[i..<(i + upperLid.count)]); i += upperLid.count
        out.lowerLid = Array(pts[i..<(i + lowerLid.count)]); i += lowerLid.count
        out.browPoints = Array(pts[i..<(i + browPoints.count)]); i += browPoints.count
        if wingAnchor != nil { out.wingAnchor = pts[i] }
        return out
    }

    /// Rigid similarity (translate + rotate + uniform scale) that maps this eye's corners onto
    /// the target's corners. Used to keep the last OPEN-eye geometry attached during a blink.
    func aligned(to target: EyeLandmarks) -> EyeLandmarks {
        let a = outerCorner - innerCorner
        let b = target.outerCorner - target.innerCorner
        let den = a.x * a.x + a.y * a.y
        guard den > 1e-6 else { return self }
        let zr = (b.x * a.x + b.y * a.y) / den
        let zi = (b.y * a.x - b.x * a.y) / den
        let src = innerCorner
        let dst = target.innerCorner
        let moved = flattened.map { p -> CGPoint in
            let d = p - src
            return dst + CGPoint(x: zr * d.x - zi * d.y, y: zi * d.x + zr * d.y)
        }
        var out = replacingPoints(with: moved) ?? self
        out.eyeOpenRatio = target.eyeOpenRatio
        return out
    }
}

// MARK: - Least-squares similarity transform (translate + rotate + uniform scale)

struct SimilarityTransform {
    let zr: CGFloat
    let zi: CGFloat
    let srcCenter: CGPoint
    let dstCenter: CGPoint

    init?(from src: [CGPoint], to dst: [CGPoint]) {
        guard src.count == dst.count, src.count >= 3 else { return nil }
        let n = CGFloat(src.count)
        let cs = src.reduce(CGPoint.zero) { $0 + $1 } * (1 / n)
        let cd = dst.reduce(CGPoint.zero) { $0 + $1 } * (1 / n)
        var numR: CGFloat = 0
        var numI: CGFloat = 0
        var den: CGFloat = 0
        for i in src.indices {
            let a = src[i] - cs
            let b = dst[i] - cd
            numR += b.x * a.x + b.y * a.y
            numI += b.y * a.x - b.x * a.y
            den += a.x * a.x + a.y * a.y
        }
        guard den > 1e-6 else { return nil }
        zr = numR / den
        zi = numI / den
        srcCenter = cs
        dstCenter = cd
    }

    func apply(_ p: CGPoint) -> CGPoint {
        let d = p - srcCenter
        return dstCenter + CGPoint(x: zr * d.x - zi * d.y, y: zi * d.x + zr * d.y)
    }

    func applyInverse(_ q: CGPoint) -> CGPoint {
        let d = q - dstCenter
        let den = zr * zr + zi * zi
        guard den > 1e-12 else { return srcCenter }
        return srcCenter + CGPoint(x: (zr * d.x + zi * d.y) / den, y: (zr * d.y - zi * d.x) / den)
    }
}

extension EyeLandmarks {
    func transformed(by t: SimilarityTransform) -> EyeLandmarks {
        replacingPoints(with: flattened.map { t.apply($0) }) ?? self
    }
}
