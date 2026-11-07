// Ported from the EyelinerSpike.
import CoreGraphics

struct OneEuroConfig: Equatable {
    /// Lower = smoother when still (more lag). Units: Hz.
    var minCutoff: Double = 0.4
    /// Higher = less lag when moving fast. Landmarks are in pixels, so beta is small. Only fast motion (a blink, a
    /// pulled lid) raises the cutoff, so a high beta does not cost steadiness when the eye is still.
    var beta: Double = 0.04
    var dCutoff: Double = 1.0
    /// Stillness dead-band as a fraction of the anchor spread. A point only moves once its filtered position drifts
    /// further than this from where it was last drawn, so a still face gives a perfectly still liner. 0 = off.
    var deadband: Double = 0.008

    /// Filter-like steadiness: head motion is taken from ARKit (see `FrameContext.headAnchors`), so these only have to
    /// calm the eye's own landmarks. The spike used 0.6 / 0.02 / 0.004. (A faster speed estimate, 3 Hz with beta 0.08,
    /// made a still face shake; blinks get their own quick config instead, see `EyeLandmarksSmoother.blinking`.)
    static let steady = OneEuroConfig()
    /// Quicker to follow a pulled or squeezed lid, at the cost of visible jitter.
    static let responsive = OneEuroConfig(minCutoff: 1.2, beta: 0.06, dCutoff: 1.0, deadband: 0.002)
}

struct OneEuroFilter {
    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var tPrev: Double = 0

    mutating func reset() { xPrev = nil; dxPrev = 0 }

    private func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * max(cutoff, 1e-6))
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ x: Double, t: Double, config: OneEuroConfig) -> Double {
        guard let xp = xPrev else {
            xPrev = x; dxPrev = 0; tPrev = t
            return x
        }
        let dt = max(t - tPrev, 1e-3)
        let dx = (x - xp) / dt
        let aD = alpha(dt: dt, cutoff: config.dCutoff)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        let cutoff = config.minCutoff + config.beta * abs(dxHat)
        let a = alpha(dt: dt, cutoff: cutoff)
        let xHat = a * x + (1 - a) * xp
        xPrev = xHat; dxPrev = dxHat; tPrev = t
        return xHat
    }
}

struct OneEuroFilter2D {
    private var fx = OneEuroFilter()
    private var fy = OneEuroFilter()

    mutating func filter(_ p: CGPoint, t: Double, config: OneEuroConfig) -> CGPoint {
        CGPoint(x: fx.filter(Double(p.x), t: t, config: config),
                y: fy.filter(Double(p.y), t: t, config: config))
    }
}

/// Per-landmark One Euro smoothing for every point of an EyeLandmarks (+ the open ratio).
/// Independent of the provider, so a replacement provider gets smoothing for free.
final class EyeLandmarksSmoother {
    private var pointFilters: [EyeSide: [OneEuroFilter2D]] = [:]
    private var ratioFilters: [EyeSide: OneEuroFilter] = [:]
    private var anchorFilters: [OneEuroFilter2D] = []
    /// Face anchors of the first frame: head motion is removed (mapped into this frame) before filtering,
    /// so only real eye-local motion counts as velocity and head movement adds neither jitter nor lag.
    private var canonical: [CGPoint]?
    private var lastAnchorOut: [CGPoint] = []
    private var lastPointOut: [EyeSide: [CGPoint]] = [:]
    private var lastRatio: [EyeSide: (ratio: Double, t: Double)] = [:]

    /// While the eye opens or closes faster than this (open ratio per second; a blink is about 3) its points follow
    /// almost directly, so the liner keeps up with the lid; otherwise the steady config holds a still face still.
    static let blinkSpeed = 1.0
    static let blinking = OneEuroConfig(minCutoff: 6, beta: 0.04, dCutoff: 1, deadband: 0)

    private static func spread(_ pts: [CGPoint]) -> CGFloat {
        guard !pts.isEmpty else { return 0 }
        let c = pts.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(pts.count))
        let ms = pts.reduce(CGFloat(0)) { $0 + ($1 - c).dot($1 - c) } / CGFloat(pts.count)
        return sqrt(ms)
    }

    /// Moves `last` toward `new` only by the part of the displacement that exceeds `db` (continuous, no pops).
    private static func dead(_ new: [CGPoint], last: [CGPoint], db: CGFloat) -> [CGPoint] {
        guard db > 0, last.count == new.count else { return new }
        var out: [CGPoint] = []
        out.reserveCapacity(new.count)
        for i in new.indices {
            let d = new[i] - last[i]
            let dist = d.length
            out.append(dist <= db ? last[i] : new[i] - d * (db / dist))
        }
        return out
    }

    func reset() {
        pointFilters.removeAll()
        ratioFilters.removeAll()
        anchorFilters.removeAll()
        canonical = nil
        lastAnchorOut = []
        lastPointOut.removeAll()
        lastRatio.removeAll()
    }

    func smoothAnchors(_ pts: [CGPoint], t: Double, config: OneEuroConfig) -> [CGPoint] {
        if anchorFilters.count != pts.count {
            anchorFilters = Array(repeating: OneEuroFilter2D(), count: pts.count)
        }
        var out: [CGPoint] = []
        for i in pts.indices { out.append(anchorFilters[i].filter(pts[i], t: t, config: config)) }
        out = Self.dead(out, last: lastAnchorOut, db: CGFloat(config.deadband) * Self.spread(out))
        lastAnchorOut = out
        return out
    }

    func reset(side: EyeSide) {
        pointFilters[side] = nil
        ratioFilters[side] = nil
        lastPointOut[side] = nil
        lastRatio[side] = nil
    }

    func smooth(_ eye: EyeLandmarks, anchors: [CGPoint], t: Double, config: OneEuroConfig) -> EyeLandmarks {
        if canonical == nil, anchors.count >= 3 { canonical = anchors }
        var xf: SimilarityTransform?
        if let c = canonical, c.count == anchors.count { xf = SimilarityTransform(from: anchors, to: c) }
        var rf = ratioFilters[eye.side] ?? OneEuroFilter()
        // Fixed, fairly responsive config so blinks are not delayed.
        let ratio = rf.filter(Double(eye.eyeOpenRatio), t: t,
                              config: OneEuroConfig(minCutoff: 4.0, beta: 0.0, dCutoff: 1.0))
        ratioFilters[eye.side] = rf
        let speed = lastRatio[eye.side].map { abs(ratio - $0.ratio) / max(t - $0.t, 1e-3) } ?? 0
        lastRatio[eye.side] = (ratio, t)
        let config = speed > Self.blinkSpeed ? Self.blinking : config

        let pts = eye.flattened.map { xf?.apply($0) ?? $0 }
        var filters = pointFilters[eye.side] ?? []
        if filters.count != pts.count {
            filters = Array(repeating: OneEuroFilter2D(), count: pts.count)
            lastPointOut[eye.side] = nil
        }
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)
        for i in pts.indices {
            out.append(filters[i].filter(pts[i], t: t, config: config))
        }
        pointFilters[eye.side] = filters
        let sp = canonical.map { Self.spread($0) } ?? Self.spread(pts)
        out = Self.dead(out, last: lastPointOut[eye.side] ?? [], db: CGFloat(config.deadband) * sp)
        lastPointOut[eye.side] = out

        let back = out.map { xf?.applyInverse($0) ?? $0 }
        var result = eye.replacingPoints(with: back) ?? eye
        result.eyeOpenRatio = CGFloat(ratio)
        return result
    }
}
