import CoreGraphics
import Foundation

/// Where hands (and anything else that is "body skin" rather than the face) are in the camera image. Lid tracking uses it
/// to know when a finger may be pulling a lid; the liner itself is not hidden behind hands. Pure data and geometry; the detector is `HandOcclusionSegmenter`.
struct OcclusionMask {
    /// Alpha is 255 where the person's body skin (a hand, a finger) was found, 0 elsewhere. `size` pixels.
    let image: CGImage
    let size: CGSize
    /// The upright (rotated) image the segmenter saw, in the pixels of the full-size frame, and how it was rotated.
    let uprightSize: CGSize
    let rotation: DetectorRotation
    let rawSize: CGSize
    /// ARKit's head anchors in the image when this mask was measured; the mask is carried to the head's later position.
    let headAnchors: [CGPoint]
    let time: CFTimeInterval
    /// 1 where the mask is set, row by row (`size` pixels); lets the mask be asked where a hand is.
    var occupied: [UInt8] = []

    /// A mask older than this is not trusted: the hand may be gone.
    static let maxAge: CFTimeInterval = 0.5

    /// Mask pixels to raw camera-image pixels.
    var toImage: CGAffineTransform {
        CGAffineTransform(scaleX: uprightSize.width / max(size.width, 1), y: uprightSize.height / max(size.height, 1))
            .concatenating(rotation.uprightToRaw(raw: rawSize))
    }

    /// Share (0...1) of the points inside a circle of `radius` image pixels around `point` that are hand. `point` is in
    /// the current frame's image pixels, `headAnchors` are the head's anchors in that same frame.
    func handFraction(around point: CGPoint, radius: CGFloat, headAnchors now: [CGPoint], at time: CFTimeInterval) -> Double {
        guard !occupied.isEmpty, occupied.count >= Int(size.width * size.height), time - self.time <= Self.maxAge,
              uprightSize.width > 0 else { return 0 }
        var imagePoint = point
        if let head = SimilarityTransform(from: now, to: headAnchors), head.isPlausible { imagePoint = head.apply(point) }
        let center = imagePoint.applying(toImage.inverted())
        let r = radius * size.width / uprightSize.width
        let width = Int(size.width), height = Int(size.height)
        var hits = 0, total = 0
        for i in -3...3 {
            for j in -3...3 {
                let dx = CGFloat(i) / 3, dy = CGFloat(j) / 3
                guard dx * dx + dy * dy <= 1 else { continue }
                total += 1
                let x = Int((center.x + dx * r).rounded()), y = Int((center.y + dy * r).rounded())
                if x >= 0, y >= 0, x < width, y < height, occupied[y * width + x] != 0 { hits += 1 }
            }
        }
        return total > 0 ? Double(hits) / Double(total) : 0
    }

    /// Mask pixels to view points for the current frame: to the image, moved with the head, then the screen mapping.
    func placement(headAnchors now: [CGPoint], mapping: ImageToViewMapping, at time: CFTimeInterval) -> Occlusion? {
        guard time - self.time <= Self.maxAge else { return nil }
        var transform = toImage
        if let head = SimilarityTransform(from: headAnchors, to: now), head.isPlausible {
            transform = transform.concatenating(head.affine)
        }
        return Occlusion(image: image, size: size, transform: transform.concatenating(mapping.transform))
    }

    /// The category mask of a segmenter (one class id per pixel) as an alpha image: 255 where the class is one of
    /// `occluders`. Premultiplied black, so it can be drawn as a tint (developer hand-mask view).
    static func alphaImage(categories: [UInt8], width: Int, height: Int, occluders: Set<UInt8>) -> CGImage? {
        guard width > 0, height > 0, categories.count >= width * height else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where occluders.contains(categories[i]) { pixels[i * 4 + 3] = 255 }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// An occlusion mask ready to draw: its image, size in pixels, and the matrix from those pixels to view points.
struct Occlusion {
    let image: CGImage
    let size: CGSize
    let transform: CGAffineTransform
}

extension SimilarityTransform {
    /// The same motion as `apply`, as a matrix.
    var affine: CGAffineTransform {
        CGAffineTransform(a: zr, b: zi, c: -zi, d: zr, tx: dstCenter.x - (zr * srcCenter.x - zi * srcCenter.y),
                          ty: dstCenter.y - (zi * srcCenter.x + zr * srcCenter.y))
    }

    /// A head cannot grow or shrink by more than 2x between a measurement and a later frame; anything else is a broken reading.
    var isPlausible: Bool {
        let scale = (zr * zr + zi * zi).squareRoot()
        return scale > 0.5 && scale < 2
    }
}
