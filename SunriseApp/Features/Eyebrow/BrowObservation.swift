// MediaPipe brow path: what the face landmarker saw, turned into brow-local coordinates. No ARKit mesh, no Vision.
import CoreGraphics
import Foundation
import simd

/// Head rotation in degrees, from MediaPipe's facial transformation matrix (canonical face to camera).
struct BrowHeadPose: Equatable, Sendable {
    var yaw: Float
    var pitch: Float
    var roll: Float
    /// The face's forward axis in camera space, kept so the pose can be turned into another image frame.
    private var forward = SIMD3<Float>(0, 0, 1)
    static let frontal = BrowHeadPose(yaw: 0, pitch: 0, roll: 0)

    init(yaw: Float, pitch: Float, roll: Float) { self.yaw = yaw; self.pitch = pitch; self.roll = roll }

    /// `m` is the 4x4 matrix in row-major order. Only the rotation part is used; the signs follow the detector's
    /// image frame, so callers compare magnitudes or use `turned(toRoll:)`.
    init?(rowMajor m: [Float]) {
        guard m.count == 16, m.allSatisfy(\.isFinite) else { return nil }
        let x = simd_normalize(SIMD3(m[0], m[4], m[8])), z = simd_normalize(SIMD3(m[2], m[6], m[10]))
        guard x.x.isFinite, z.z.isFinite else { return nil }
        let degrees: Float = 180 / .pi
        forward = z
        yaw = atan2(z.x, z.z) * degrees
        pitch = asin(max(-1, min(1, -z.y))) * degrees
        roll = atan2(x.y, x.x) * degrees
    }

    /// The same head pose in an image frame turned about the camera axis so that its roll reads `newRoll` degrees.
    func turned(toRoll newRoll: Float) -> BrowHeadPose {
        let angle = (newRoll - roll) * .pi / 180, c = cos(angle), s = sin(angle)
        let z = SIMD3(forward.x * c - forward.y * s, forward.x * s + forward.y * c, forward.z)
        let degrees: Float = 180 / .pi
        var pose = BrowHeadPose(yaw: atan2(z.x, z.z) * degrees, pitch: asin(max(-1, min(1, -z.y))) * degrees, roll: newRoll)
        pose.forward = z
        return pose
    }
}

/// One brow in captured-image pixels. Both rows run from the brow head (nose side) to the tail.
struct BrowContour: Equatable, Sendable {
    var upper: [SIMD2<Float>]
    var lower: [SIMD2<Float>]
}

/// Eye and nose points for one side, used for the tutorial's nose-eye mapping lines and the landmark debug view.
struct BrowEyeMarks: Equatable, Sendable {
    var inner: SIMD2<Float>
    var outer: SIMD2<Float>
    var iris: SIMD2<Float>?
    var ala: SIMD2<Float>
    /// Upper eyelid margin, outer corner to inner (MediaPipe's lid row); bounds how far down the brow is hidden.
    var lid: [SIMD2<Float>] = []
}

/// One MediaPipe result for the brow renderer, in pixels of the captured (unrotated) camera image.
struct BrowObservation: Sendable {
    var imageSize: CGSize
    var timestamp: TimeInterval
    var brows: [EyeSide: BrowContour]
    var eyes: [EyeSide: BrowEyeMarks]
    var noseBridge: SIMD2<Float>
    var pose: BrowHeadPose
    /// Every face landmark as detected (not smoothed), for the tracking view.
    var mesh: [SIMD2<Float>] = []

    /// Every point in a fixed order, for smoothing.
    var flattened: [SIMD2<Float>] {
        var out = [noseBridge]
        for side in [EyeSide.subjectRight, .subjectLeft] {
            if let brow = brows[side] { out += brow.upper + brow.lower }
            if let eye = eyes[side] { out += [eye.inner, eye.outer, eye.ala] + (eye.iris.map { [$0] } ?? []) + eye.lid }
        }
        return out
    }

    func replacing(_ points: [SIMD2<Float>]) -> BrowObservation? {
        guard points.count == flattened.count else { return nil }
        var copy = self, i = 0
        func next() -> SIMD2<Float> { defer { i += 1 }; return points[i] }
        copy.noseBridge = next()
        for side in [EyeSide.subjectRight, .subjectLeft] {
            if let brow = brows[side] {
                copy.brows[side] = BrowContour(upper: brow.upper.map { _ in next() }, lower: brow.lower.map { _ in next() })
            }
            if let eye = eyes[side] {
                let inner = next(), outer = next(), ala = next(), iris = eye.iris == nil ? nil : next()
                copy.eyes[side] = BrowEyeMarks(inner: inner, outer: outer, iris: iris, ala: ala, lid: eye.lid.map { _ in next() })
            }
        }
        return copy
    }

    /// Distance between the inner eye corners, the face's own length unit in this image.
    var eyeSpan: Float? {
        guard let r = eyes[.subjectRight], let l = eyes[.subjectLeft] else { return nil }
        let d = simd_distance(r.inner, l.inner)
        return d > 1 ? d : nil
    }
}

/// Brow-local frame for one observed brow. `point(u:w:)` maps brow coordinates to image pixels: `u` along the
/// observed centerline (0 head, 1 tail, extrapolated beyond), `w` across it in brow widths, positive upwards.
struct BrowGeometry: Sendable {
    let knots: [Float]
    let mids: [SIMD2<Float>]
    let halves: [Float]
    /// Pixels per brow width across the brow. It is the less foreshortened brow's width, so a turned head does not
    /// thin the far brow; along the brow the landmarks carry the foreshortening.
    let across: Float
    /// Head-to-tail length of this brow in pixels.
    let width: Float
    private let tangents: [SIMD2<Float>]
    private let upSign: Float

    init?(contour: BrowContour, across: Float? = nil) {
        let n = contour.upper.count
        guard n >= 3, contour.lower.count == n else { return nil }
        let mids = zip(contour.upper, contour.lower).map { ($0 + $1) / 2 }
        var lengths: [Float] = [0]
        for i in 1..<n { lengths.append(lengths[i - 1] + simd_distance(mids[i], mids[i - 1])) }
        let total = lengths[n - 1], width = simd_distance(mids[0], mids[n - 1])
        guard total > 1, width > 1, mids.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let scale = max(across ?? width, 1)
        knots = lengths.map { $0 / total }
        self.mids = mids
        self.width = width
        self.across = scale
        halves = zip(contour.upper, contour.lower).map { simd_distance($0, $1) / 2 / scale }
        // Finite-difference tangents (pixels per unit u) for a cubic Hermite centerline through the midpoints.
        var t: [SIMD2<Float>] = []
        for i in 0..<n {
            let a = max(0, i - 1), b = min(n - 1, i + 1)
            t.append((mids[b] - mids[a]) / max(knots[b] - knots[a], 1e-4))
        }
        tangents = t
        // The across axis points to the upper contour, whichever way the image is rotated or mirrored.
        var votes: Float = 0
        for i in 0..<n {
            let normal = SIMD2(-t[i].y, t[i].x)
            votes += simd_dot(normal, contour.upper[i] - contour.lower[i])
        }
        upSign = votes >= 0 ? 1 : -1
    }

    private func segment(_ u: Float) -> Int {
        var i = 0
        while i < knots.count - 2 && u > knots[i + 1] { i += 1 }
        return i
    }

    /// Centerline position and tangent (pixels, pixels per unit u). Linear beyond the head and tail.
    func centerline(_ u: Float) -> (point: SIMD2<Float>, tangent: SIMD2<Float>) {
        if u <= 0 { return (mids[0] + tangents[0] * u, tangents[0]) }
        if u >= 1 { let last = mids.count - 1; return (mids[last] + tangents[last] * (u - 1), tangents[last]) }
        let i = segment(u), h = max(knots[i + 1] - knots[i], 1e-4), s = (u - knots[i]) / h
        let s2 = s * s, s3 = s2 * s
        let p = mids[i] * (2 * s3 - 3 * s2 + 1) + tangents[i] * (h * (s3 - 2 * s2 + s))
            + mids[i + 1] * (-2 * s3 + 3 * s2) + tangents[i + 1] * (h * (s3 - s2))
        let d = mids[i] * ((6 * s2 - 6 * s) / h) + tangents[i] * (3 * s2 - 4 * s + 1)
            + mids[i + 1] * ((-6 * s2 + 6 * s) / h) + tangents[i + 1] * (3 * s2 - 2 * s)
        return (p, d)
    }

    func point(u: Float, w: Float) -> SIMD2<Float> {
        let c = centerline(u)
        let length = simd_length(c.tangent)
        let normal = length > 1e-4 ? SIMD2(-c.tangent.y, c.tangent.x) / length * upSign : SIMD2(0, 0)
        return c.point + normal * (w * across)
    }

    /// How far the centerline at `u` lies above the straight head-to-tail line (the chord), in brow widths, so a picture
    /// drawn relative to its own chord can be laid on this brow: a point at `w` from the centerline is at
    /// `w + chordOffset(u)` from the chord. Zero for a straight brow.
    func chordOffset(_ u: Float) -> Float {
        let a = centerline(0).point, b = centerline(1).point, chord = b - a, length = simd_length(chord)
        guard length > 1e-4 else { return 0 }
        var normal = SIMD2(-chord.y, chord.x) / length
        if simd_dot(normal, point(u: 0.5, w: 1) - point(u: 0.5, w: 0)) < 0 { normal = -normal }
        return simd_dot(centerline(u).point - (a + chord * u), normal) / across
    }

    /// How far `p` lies from the centerline at `u`, across the brow, in brow widths (positive upwards).
    func offset(of p: SIMD2<Float>, at u: Float) -> Float {
        let c = centerline(u), length = simd_length(c.tangent)
        guard length > 1e-4 else { return 0 }
        return simd_dot(p - c.point, SIMD2(-c.tangent.y, c.tangent.x) / length * upSign) / across
    }

    /// Where the line straight down from the centerline at `u` meets `polyline` (the upper eyelid), as an offset in
    /// brow widths (negative, below the brow). Past the polyline's ends it uses the nearer end point.
    func depth(of polyline: [SIMD2<Float>], at u: Float) -> Float? {
        guard polyline.count >= 2 else { return polyline.first.map { offset(of: $0, at: u) } }
        let c = centerline(u), length = simd_length(c.tangent)
        guard length > 1e-4 else { return nil }
        let normal = SIMD2(-c.tangent.y, c.tangent.x) / length * upSign, along = c.tangent / length
        var best: Float?
        for (a, b) in zip(polyline, polyline.dropFirst()) {
            // Solve c + normal * t = a + (b - a) * r.
            let edge = b - a, denominator = normal.x * edge.y - normal.y * edge.x
            guard abs(denominator) > 1e-6 else { continue }
            let d = a - c.point
            let t = (d.x * edge.y - d.y * edge.x) / denominator
            let r = (d.x * normal.y - d.y * normal.x) / denominator
            if (0...1).contains(r), t < 0, best.map({ t > $0 }) ?? true { best = t }
        }
        if let best { return best / across }
        let nearest = polyline.min { abs(simd_dot($0 - c.point, along)) < abs(simd_dot($1 - c.point, along)) }
        return nearest.map { offset(of: $0, at: u) }
    }

    /// Observed half thickness at `u`, in brow widths.
    func observedHalf(_ u: Float) -> Float {
        let u = max(0, min(1, u)), i = segment(u)
        let s = (u - knots[i]) / max(knots[i + 1] - knots[i], 1e-4)
        return halves[i] + (halves[i + 1] - halves[i]) * max(0, min(1, s))
    }

    /// Where the ray from `origin` through `through` crosses the centerline (searched a little past the head and
    /// tail), for the nose-eye mapping lines.
    func crossing(from origin: SIMD2<Float>, through: SIMD2<Float>) -> SIMD2<Float>? {
        let direction = through - origin
        guard simd_length(direction) > 1e-3 else { return nil }
        var previous = centerline(-0.3).point
        for i in 1...32 {
            let current = centerline(-0.3 + 1.6 * Float(i) / 32).point
            let edge = current - previous
            let denominator = direction.x * edge.y - direction.y * edge.x
            if abs(denominator) > 1e-6 {
                let offset = previous - origin
                let s = (offset.x * edge.y - offset.y * edge.x) / denominator
                let r = (offset.x * direction.y - offset.y * direction.x) / denominator
                if s > 0, (0...1).contains(r) { return origin + direction * s }
            }
            previous = current
        }
        return nil
    }
}

/// One Euro smoothing for brow landmarks. Head motion follows the nose bridge with a quick filter; each point's
/// offset from it, in eye spans, gets a steadier one, so a still face gives a still brow and a turning head no lag.
struct BrowObservationSmoother {
    static let anchor = OneEuroConfig(minCutoff: 3, beta: 0.02, dCutoff: 1, deadband: 0)
    static let local = OneEuroConfig(minCutoff: 1, beta: 4, dCutoff: 1, deadband: 0)
    /// A gap longer than this restarts the filters, so a face found again does not glide in from its old place.
    static let resetGap: TimeInterval = 0.25
    private var anchorFilter = (OneEuroFilter(), OneEuroFilter())
    private var filters: [(OneEuroFilter, OneEuroFilter)] = []
    private var last: TimeInterval?

    mutating func reset() { filters = []; last = nil; anchorFilter = (OneEuroFilter(), OneEuroFilter()) }

    mutating func smooth(_ observation: BrowObservation) -> BrowObservation {
        let t = observation.timestamp
        let points = observation.flattened
        guard let span = observation.eyeSpan, t.isFinite else { reset(); return observation }
        if let last, t <= last { return observation }
        if let last, t - last > Self.resetGap { reset() }
        if filters.count != points.count { reset(); filters = Array(repeating: (OneEuroFilter(), OneEuroFilter()), count: points.count) }
        last = t
        let bridge = observation.noseBridge
        let anchor = SIMD2(Float(anchorFilter.0.filter(Double(bridge.x), t: t, config: Self.anchor)),
                           Float(anchorFilter.1.filter(Double(bridge.y), t: t, config: Self.anchor)))
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(points.count)
        for (i, p) in points.enumerated() {
            let offset = (p - bridge) / span
            let x = filters[i].0.filter(Double(offset.x), t: t, config: Self.local)
            let y = filters[i].1.filter(Double(offset.y), t: t, config: Self.local)
            out.append(anchor + SIMD2(Float(x), Float(y)) * span)
        }
        return observation.replacing(out) ?? observation
    }
}
