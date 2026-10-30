// Brow pictures laid over the hidden natural brow. Each is a PNG with alpha (head left, tail right) in the asset catalog;
// it is baked once into the same brow-space texture the shape designs use, so the Metal strip draws it unchanged.
import CoreGraphics
import Foundation
import UIKit
import simd

/// A brow picture the user can choose in the eyebrow tool.
struct BrowOverlay: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Image set in `Assets.xcassets`.
    let assetName: String
    /// Drawn as a 3D hair mesh on ARKit's face pose when ARKit tracks the face; otherwise as its picture.
    var is3D = false

    static let all: [BrowOverlay] = [
        // Original production overlays remain available before the new sample
        // set; the samples are additive choices in the same picker.
        BrowOverlay(id: "overlay.1", title: String(localized: "Brow 1"), assetName: "brow-overlay-1"),
        BrowOverlay(id: "overlay.2", title: String(localized: "Brow 2"), assetName: "brow-overlay-2"),
        BrowOverlay(id: "sample.1", title: String(localized: "Feathered arch"), assetName: "brow-sample-1"),
        BrowOverlay(id: "sample.2", title: String(localized: "Full feather"), assetName: "brow-sample-2"),
        BrowOverlay(id: "sample.3", title: String(localized: "Lifted feather"), assetName: "brow-sample-3"),
        BrowOverlay(id: "sample.4", title: String(localized: "Soft feather"), assetName: "brow-sample-4"),
        BrowOverlay(id: "sample.5", title: String(localized: "Textured arch"), assetName: "brow-sample-5"),
        BrowOverlay(id: "sample.6", title: String(localized: "Dense natural"), assetName: "brow-sample-6"),
        BrowOverlay(id: "sample.7", title: String(localized: "Bold arch"), assetName: "brow-sample-7"),
        BrowOverlay(id: "sample.8", title: String(localized: "Defined natural"), assetName: "brow-sample-8"),
    ]
    static let standard = all[0]
    /// A picture is nearly opaque, so the eyebrow starts higher than the 0.65 of the shape designs.
    static let defaultIntensity = 0.9
}

/// A baked overlay: RGBA float16 bits, `width` x `height`, in the layout `browStripFragment` samples.
/// r coverage, g strand density (equal to coverage: the picture has its own strands), b unused, a detail (the picture's
/// luminance relative to its own mean, 1 outside the picture) that keeps the strands visible when the shade tints it.
struct BakedBrowSprite: Sendable {
    let width: Int
    let height: Int
    let texels: [UInt16]
}

enum BrowSpriteBaker {
    static let width = 1024, height = 512
    /// The picture's head and tail sit at these u. MediaPipe's brow rows end short of the real hair, so the picture runs a
    /// little past 0...1 at both ends and covers the natural brow's ends.
    // Extend the nose-side head slightly beyond the tracked contour so the
    // two brow overlays meet the face naturally instead of leaving a wide
    // center gap. The tail keeps the original conservative extension.
    static let defaultHeadU: Float = -0.10, tailU: Float = 1.06
    static let headUKey = "beautyBrow.headExtension"
    static var headU: Float {
        let value = UserDefaults.standard.object(forKey: headUKey) as? NSNumber
        return max(-0.25, min(0, value?.floatValue ?? defaultHeadU))
    }
    /// Columns with less than this share of the busiest column's coverage are stray hairs, not the brow's ends.
    private static let endShare: Float = 0.02

    /// Lays `image` into brow space. The picture's head-to-tail span becomes u `headU`...`tailU` and its head-to-tail line (the
    /// chord) lies on w = 0 in chord space; the strip adds the observed brow's own offset from its chord when it samples, so the
    /// picture keeps its arch whatever the user's natural brow looks like. The span is one brow width, scaled by `tailU - headU`.
    /// `extent` is `BeautyBlushEngine.browExtent`.
    static func bake(_ image: CGImage, extent: SIMD4<Float>, width: Int = width, height: Int = height,
                     headU: Float = BrowSpriteBaker.headU) -> BakedBrowSprite? {
        let w = image.width, h = image.height
        let headU = max(extent.x, min(0, headU))
        guard w > 8, h > 8, width > 0, height > 0 else { return nil }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        // Coverage and coverage-weighted linear luminance per source pixel.
        var alpha = [Float](repeating: 0, count: w * h), luma = [Float](repeating: 0, count: w * h)
        var total: Float = 0, weighted: Float = 0
        for i in 0..<w * h {
            let a = Float(rgba[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            let r = linear(Float(rgba[i * 4]) / 255 / a), g = linear(Float(rgba[i * 4 + 1]) / 255 / a), b = linear(Float(rgba[i * 4 + 2]) / 255 / a)
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            alpha[i] = a; luma[i] = a * y
            total += a; weighted += a * y
        }
        guard total > 1, weighted > 0 else { return nil }
        let mean = weighted / total

        // The brow's head and tail columns, and where the brow sits vertically at each end.
        var mass = [Float](repeating: 0, count: w)
        for y in 0..<h { for x in 0..<w { mass[x] += alpha[y * w + x] } }
        let peak = mass.max() ?? 0
        guard peak > 0, let first = mass.firstIndex(where: { $0 > peak * endShare }), let last = mass.lastIndex(where: { $0 > peak * endShare }),
              last - first > 8 else { return nil }
        let span = Float(last + 1 - first)
        func centre(_ columns: Range<Int>) -> Float {
            var sum: Float = 0, weight: Float = 0
            for y in 0..<h { for x in columns { let a = alpha[y * w + x]; sum += a * (Float(y) + 0.5); weight += a } }
            return weight > 0 ? sum / weight : Float(h) / 2
        }
        let end = max(2, Int(span * 0.04))
        let headY = centre(first..<min(last + 1, first + end)), tailY = centre(max(first, last + 1 - end)..<(last + 1))

        func sample(_ plane: [Float], _ x: Float, _ y: Float) -> Float {
            let fx = x - 0.5, fy = y - 0.5
            let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down)), tx = fx - Float(x0), ty = fy - Float(y0)
            func at(_ xx: Int, _ yy: Int) -> Float { xx >= 0 && xx < w && yy >= 0 && yy < h ? plane[yy * w + xx] : 0 }
            let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx, bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
            return top * (1 - ty) + bottom * ty
        }
        var texels = [UInt16](repeating: 0, count: width * height * 4)
        let one = Float16(1).bitPattern
        for ty in 0..<height {
            let across = extent.z - (Float(ty) + 0.5) / Float(height) * 2 * extent.z
            for tx in 0..<width {
                let u = extent.x + (Float(tx) + 0.5) / Float(width) * (extent.y - extent.x)
                let f = (u - headU) / (tailU - headU)
                let px = Float(first) + f * span, py = headY + (tailY - headY) * f - across * span / (tailU - headU)
                let a = sample(alpha, px, py)
                let o = (ty * width + tx) * 4
                guard a > 1e-4 else { texels[o + 3] = one; continue }
                // Softened: strand highlights at full contrast sparkle when the tracking moves the picture by a pixel.
                let detail = max(0.5, min(1.8, pow(sample(luma, px, py) / a / mean, 0.8)))
                texels[o] = Float16(min(a, 1)).bitPattern
                texels[o + 1] = texels[o]
                texels[o + 3] = Float16(detail).bitPattern
            }
        }
        return BakedBrowSprite(width: width, height: height, texels: texels)
    }

    private static func linear(_ c: Float) -> Float {
        let c = max(0, min(1, c))
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}

/// Bakes each overlay once, off the render queue, and keeps the result.
final class BrowSpriteStore: @unchecked Sendable {
    static let shared = BrowSpriteStore()
    private let lock = NSLock()
    private var ready: [String: BakedBrowSprite] = [:], working: Set<String> = [], failed: Set<String> = []

    static func cacheKey(_ overlay: BrowOverlay) -> String {
        "\(overlay.id):\(Int((BrowSpriteBaker.headU * 1000).rounded()))"
    }

    func baked(_ overlay: BrowOverlay) -> BakedBrowSprite? {
        lock.lock(); defer { lock.unlock() }
        return ready[Self.cacheKey(overlay)]
    }
    func hasFailed(_ overlay: BrowOverlay) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return failed.contains(Self.cacheKey(overlay))
    }
    /// Starts baking unless it is done, running or failed.
    func prepare(_ overlay: BrowOverlay) {
        let key = Self.cacheKey(overlay)
        lock.lock()
        guard ready[key] == nil, !working.contains(key), !failed.contains(key) else { lock.unlock(); return }
        working.insert(key)
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let headU = BrowSpriteBaker.headU
            let result = UIImage(named: overlay.assetName)?.cgImage.flatMap { BrowSpriteBaker.bake($0, extent: BeautyBlushEngine.browExtent, headU: headU) }
            lock.lock()
            working.remove(key)
            if let result { ready[key] = result } else { failed.insert(key) }
            lock.unlock()
        }
    }
}
