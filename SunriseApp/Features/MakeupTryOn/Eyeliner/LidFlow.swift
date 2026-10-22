import CoreGraphics
import CoreVideo
import Foundation

/// A grey-scale pyramid of a part of a camera frame (level 0 = full resolution), for tracking skin between frames.
struct LumaPyramid {
    struct Level {
        let width: Int
        let height: Int
        var data: [Float]

        /// Bilinear sample with the coordinates clamped to the image.
        func sample(_ x: Float, _ y: Float) -> Float {
            let cx = min(max(x, 0), Float(width - 1)), cy = min(max(y, 0), Float(height - 1))
            let x0 = Int(cx), y0 = Int(cy)
            let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let fx = cx - Float(x0), fy = cy - Float(y0)
            let top = data[y0 * width + x0] * (1 - fx) + data[y0 * width + x1] * fx
            let bottom = data[y1 * width + x0] * (1 - fx) + data[y1 * width + x1] * fx
            return top * (1 - fy) + bottom * fy
        }

        func halved() -> Level {
            let w = max(width / 2, 1), h = max(height / 2, 1)
            var out = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    let x0 = min(2 * x, width - 1), x1 = min(2 * x + 1, width - 1)
                    let y0 = min(2 * y, height - 1), y1 = min(2 * y + 1, height - 1)
                    out[y * w + x] = (data[y0 * width + x0] + data[y0 * width + x1]
                        + data[y1 * width + x0] + data[y1 * width + x1]) * 0.25
                }
            }
            return Level(width: w, height: h, data: out)
        }
    }

    /// Top-left of the part in image pixels.
    let origin: CGPoint
    let levels: [Level]
    /// Image pixels per pixel of level 0 (2 when the part was shrunk to half size to save work).
    let pixelScale: CGFloat

    var rect: CGRect {
        CGRect(origin: origin, size: CGSize(width: CGFloat(levels[0].width) * pixelScale,
                                            height: CGFloat(levels[0].height) * pixelScale))
    }

    init(origin: CGPoint, base: Level, levelCount: Int = 3, pixelScale: CGFloat = 1) {
        self.origin = origin
        self.pixelScale = pixelScale
        var levels = [base]
        while levels.count < levelCount, let last = levels.last, last.width >= 16, last.height >= 16 {
            levels.append(last.halved())
        }
        self.levels = levels
    }

    /// The luma plane of a YCbCr camera frame inside `rect` (clipped to the frame), shrunk to half size; `nil` for
    /// other formats.
    init?(buffer: CVPixelBuffer, rect: CGRect, levelCount: Int = 3) {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        let frameW = CVPixelBufferGetWidthOfPlane(buffer, 0), frameH = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let x0 = max(0, Int(rect.minX.rounded(.down))) & ~1, y0 = max(0, Int(rect.minY.rounded(.down))) & ~1
        let x1 = min(frameW, Int(rect.maxX.rounded(.up))), y1 = min(frameH, Int(rect.maxY.rounded(.up)))
        let w = (x1 - x0) / 2, h = (y1 - y0) / 2
        guard w >= 32, h >= 32 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var data = [Float](repeating: 0, count: w * h)
        data.withUnsafeMutableBufferPointer { out in
            for y in 0..<h {
                let top = bytes + (y0 + 2 * y) * stride + x0
                let bottom = top + stride
                for x in 0..<w {
                    out[y * w + x] = Float(Int(top[2 * x]) + Int(top[2 * x + 1]) + Int(bottom[2 * x]) + Int(bottom[2 * x + 1])) * 0.25
                }
            }
        }
        self.init(origin: CGPoint(x: x0, y: y0), base: Level(width: w, height: h, data: data), levelCount: levelCount,
                  pixelScale: 2)
    }
}

/// Pyramidal Lucas-Kanade: where a small patch of skin moved to between two frames.
enum LucasKanade {
    /// `point` in image pixels; the result is its place in `next`. `nil` when the patch has too little texture, the
    /// match is poor, or tracking it back does not return to the start (blur, a blink, a hand sweeping past).
    static func track(_ point: CGPoint, from prev: LumaPyramid, to next: LumaPyramid, halfWindow hw: Int = 5,
                      iterations: Int = 6) -> CGPoint? {
        guard let forward = flow(point, from: prev, to: next, halfWindow: hw, iterations: iterations),
              let back = flow(forward, from: next, to: prev, halfWindow: hw, iterations: iterations),
              hypot(back.x - point.x, back.y - point.y) < 1 else { return nil }
        return forward
    }

    private static func flow(_ point: CGPoint, from prev: LumaPyramid, to next: LumaPyramid, halfWindow hw: Int,
                             iterations: Int) -> CGPoint? {
        guard prev.levels.count == next.levels.count else { return nil }
        let side = 2 * hw + 1, n = side * side
        var intensity = [Float](repeating: 0, count: n)
        var gradX = intensity, gradY = intensity
        let px = Float((point.x - prev.origin.x) / prev.pixelScale), py = Float((point.y - prev.origin.y) / prev.pixelScale)
        var gx: Float = 0, gy: Float = 0
        let top = prev.levels.count - 1
        for level in stride(from: top, through: 0, by: -1) {
            if level != top { gx *= 2; gy *= 2 }
            let a = prev.levels[level], b = next.levels[level]
            let scale = Float(1 << level)
            let ux = px / scale, uy = py / scale
            var sxx: Float = 0, sxy: Float = 0, syy: Float = 0
            var k = 0
            for dy in -hw...hw {
                for dx in -hw...hw {
                    let x = ux + Float(dx), y = uy + Float(dy)
                    intensity[k] = a.sample(x, y)
                    gradX[k] = (a.sample(x + 1, y) - a.sample(x - 1, y)) * 0.5
                    gradY[k] = (a.sample(x, y + 1) - a.sample(x, y - 1)) * 0.5
                    sxx += gradX[k] * gradX[k]; sxy += gradX[k] * gradY[k]; syy += gradY[k] * gradY[k]
                    k += 1
                }
            }
            // Smallest eigenvalue per pixel: both directions need texture (an edge alone slides along itself).
            let trace = sxx + syy, det = sxx * syy - sxy * sxy
            let smallest = (trace - max(trace * trace - 4 * det, 0).squareRoot()) / 2 / Float(n)
            guard smallest > 2, det > 1e-3 else {
                if level == 0 { return nil }
                continue
            }
            for _ in 0..<iterations {
                var bx: Float = 0, by: Float = 0
                k = 0
                for dy in -hw...hw {
                    for dx in -hw...hw {
                        let d = intensity[k] - b.sample(ux + gx + Float(dx), uy + gy + Float(dy))
                        bx += d * gradX[k]; by += d * gradY[k]
                        k += 1
                    }
                }
                let stepX = (syy * bx - sxy * by) / det, stepY = (sxx * by - sxy * bx) / det
                gx += stepX; gy += stepY
                if abs(stepX) + abs(stepY) < 0.01 { break }
            }
        }
        // Mean difference at level 0 after the last step: a poor match is rejected.
        let a = prev.levels[0], b = next.levels[0]
        var error: Float = 0
        for dy in -hw...hw {
            for dx in -hw...hw {
                error += abs(a.sample(px + Float(dx), py + Float(dy)) - b.sample(px + gx + Float(dx), py + gy + Float(dy)))
            }
        }
        guard error / Float(n) < 18 else { return nil }
        let result = CGPoint(x: point.x + CGFloat(gx) * prev.pixelScale, y: point.y + CGFloat(gy) * prev.pixelScale)
        let local = CGPoint(x: (result.x - next.origin.x) / next.pixelScale, y: (result.y - next.origin.y) / next.pixelScale)
        guard local.x > 0, local.y > 0, local.x < CGFloat(b.width - 1), local.y < CGFloat(b.height - 1) else { return nil }
        return result
    }
}

/// Keeps each eye's upper-lid points and outer corner on the skin between detector results, so a lid that is pulled up follows the
/// pull even though the detector's face prior does not. Work happens in a head-fixed frame (ARKit's rigid anchors),
/// so head motion and the detector's delay do not matter. The detector pulls the points back gently, and wins outright
/// whenever the eye is blinking, tracking fails, or the two disagree wildly.
final class LidFollower: @unchecked Sendable {
    /// Share of the gap to the detector closed per detector result (about 30 per second): slow enough that a held
    /// pull stays, fast enough that tracking drift is corrected within a couple of seconds.
    static let pullPerResult: CGFloat = 0.02
    /// The outer corner (which the wing grows from) is pulled back even more slowly: the detector's idea of it barely
    /// moves when the skin there is stretched.
    static let cornerPullPerResult: CGFloat = 0.008
    /// With no hand near the eye nothing is being pulled, so the detector corrects the points quickly (a head turned
    /// or tilted, drift); a hand within `handNear` of the eye means the lid may be held, and the slow rates apply.
    static let freePull: CGFloat = 0.3
    static let handNear: Double = 0.04
    /// After a blink starts the detector alone is trusted for this long.
    static let blinkHold: TimeInterval = 0.3
    /// Mean gap, in eye widths, beyond which the detector wins.
    static let maximumGap: CGFloat = 0.9

    private struct Track {
        var canonical: [CGPoint]
        /// Eye width in head-frame units.
        var eyeWidth: CGFloat
        var pyramid: LumaPyramid?
        /// Head-frame to image transform when `pyramid` was taken.
        var transform: SimilarityTransform?
        var valid = true
        var openBase: CGFloat = 0
        var lastRatio: CGFloat = 0
        var holdUntil: TimeInterval = 0
        /// Bumped when the detector re-seeds the points, so a picture-based update computed meanwhile is dropped.
        var generation = 0
    }

    /// `advance` runs on a background queue while `fuse` runs on the main thread.
    private let lock = NSLock()
    private var tracks: [EyeSide: Track] = [:]
    private var headFrame: [CGPoint]?
    /// Eyes whose points were followed by the skin (not the detector alone) in the last result, for the readout.
    private(set) var followingCount = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        tracks.removeAll()
        headFrame = nil
        followingCount = 0
    }

    private struct Update {
        var canonical: [CGPoint]
        var pyramid: LumaPyramid?
        var transform: SimilarityTransform?
        var valid: Bool
        var generation: Int
    }

    /// Every camera frame (off the main thread): move the tracked points with the skin.
    func advance(_ buffer: CVPixelBuffer, headAnchors: [CGPoint]) {
        lock.lock()
        let snapshot = tracks, frame = headFrame
        lock.unlock()
        guard let frame, headAnchors.count == frame.count,
              let now = SimilarityTransform(from: frame, to: headAnchors) else { return }
        let scale = (now.zr * now.zr + now.zi * now.zi).squareRoot()
        var updates: [EyeSide: Update] = [:]
        for (side, track) in snapshot where track.valid {
            var u = Update(canonical: track.canonical, pyramid: track.pyramid, transform: track.transform,
                           valid: true, generation: track.generation)
            defer { updates[side] = u }
            let widthPx = track.eyeWidth * scale
            guard widthPx > 20 else { continue }
            guard let previous = track.pyramid, let before = track.transform else {
                u.pyramid = Self.pyramid(buffer, around: track.canonical.map(now.apply), width: widthPx)
                u.transform = now
                continue
            }
            guard let current = LumaPyramid(buffer: buffer, rect: previous.rect) else {
                u.pyramid = nil; u.valid = false
                continue
            }
            let from = track.canonical.map(before.apply)
            let moved: [CGPoint?] = from.map { LucasKanade.track($0, from: previous, to: current) }
            let found = moved.compactMap { $0 }
            // Too many lost points, or one that jumped, means the picture is not trustworthy (blink, hand): the
            // detector takes over until the next result re-seeds the points.
            let jump = widthPx * 0.2
            let steady = zip(from, moved).allSatisfy { start, end in
                end.map { hypot($0.x - start.x, $0.y - start.y) < jump } ?? true
            }
            guard found.count * 4 >= from.count * 3, steady else {
                u.valid = false; u.pyramid = nil
                continue
            }
            // Lost points move like the rest.
            let shift = zip(from, moved).compactMap { s, e in e.map { $0 - s } }
                .reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(found.count))
            let imagePoints = zip(from, moved).map { $1 ?? ($0 + shift) }
            u.canonical = imagePoints.map(now.applyInverse)
            // Keep the picture centred on the points.
            let padded = Self.bounds(imagePoints).insetBy(dx: -widthPx * 0.35, dy: -widthPx * 0.35)
            u.pyramid = current.rect.contains(padded) ? current : Self.pyramid(buffer, around: imagePoints, width: widthPx)
            u.transform = now
        }
        lock.lock(); defer { lock.unlock() }
        for (side, u) in updates where tracks[side]?.generation == u.generation {
            tracks[side]?.canonical = u.canonical
            tracks[side]?.pyramid = u.pyramid
            tracks[side]?.transform = u.transform
            tracks[side]?.valid = u.valid
        }
    }

    /// Every detector result: returns it with the upper-lid points replaced by the followed ones.
    func fuse(_ frame: EyeLandmarkFrame, now: TimeInterval, hand: [EyeSide: Double] = [:]) -> EyeLandmarkFrame {
        guard frame.context?.headAnchors.count ?? 0 >= 3 else { reset(); return frame }
        lock.lock(); defer { lock.unlock() }
        guard let anchors = frame.context?.headAnchors else { return frame }
        if headFrame == nil { headFrame = anchors }
        guard let headFrame, headFrame.count == anchors.count,
              let toImage = SimilarityTransform(from: headFrame, to: anchors) else { return frame }
        let scale = (toImage.zr * toImage.zr + toImage.zi * toImage.zi).squareRoot()
        var result = frame
        var following = 0
        for side in [EyeSide.subjectLeft, .subjectRight] {
            guard var eye = side == .subjectLeft ? frame.subjectLeft : frame.subjectRight else {
                tracks[side] = nil
                continue
            }
            // The tracked points: the upper lid, then the outer corner (the wing follows it).
            let detected = (eye.upperLid + [eye.outerCorner]).map(toImage.applyInverse)
            let eyeWidth = hypot(eye.outerCorner.x - eye.innerCorner.x, eye.outerCorner.y - eye.innerCorner.y)
                / max(scale, 1e-6)
            var track = tracks[side] ?? Track(canonical: detected, eyeWidth: eyeWidth)

            // Blink: the opening shrinks or changes fast relative to this person's normal opening.
            let ratio = eye.eyeOpenRatio
            track.openBase = max(ratio, track.openBase * 0.995)
            if track.openBase > 0.02, ratio < track.openBase * 0.75 || abs(ratio - track.lastRatio) > track.openBase * 0.25 {
                track.holdUntil = now + Self.blinkHold
            }
            track.lastRatio = ratio
            track.eyeWidth = eyeWidth

            let gap = track.canonical.count == detected.count
                ? zip(track.canonical, detected).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0, +) / CGFloat(detected.count)
                : .infinity
            if !track.valid || now < track.holdUntil || gap > Self.maximumGap * eyeWidth {
                track.canonical = detected
                track.valid = true
                track.pyramid = nil
                track.generation += 1
            } else {
                following += 1
                let held = (hand[side] ?? 0) >= Self.handNear
                track.canonical = zip(track.canonical, detected).enumerated().map { index, pair in
                    let rate = !held ? Self.freePull
                        : index == detected.count - 1 ? Self.cornerPullPerResult : Self.pullPerResult
                    return pair.0 + (pair.1 - pair.0) * rate
                }
            }
            tracks[side] = track
            let followed = track.canonical.map(toImage.apply)
            eye.upperLid = Array(followed.dropLast())
            if let corner = followed.last { eye.outerCorner = corner }
            if side == .subjectLeft { result.subjectLeft = eye } else { result.subjectRight = eye }
        }
        followingCount = following
        return result
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// A picture of the frame around the lid points: room to move up when pulled, and to the sides.
    private static func pyramid(_ buffer: CVPixelBuffer, around points: [CGPoint], width: CGFloat) -> LumaPyramid? {
        let box = bounds(points)
        let rect = CGRect(x: box.minX - width * 0.6, y: box.minY - width * 0.9,
                          width: box.width + width * 1.2, height: box.height + width * 1.5)
        return LumaPyramid(buffer: buffer, rect: rect)
    }
}
