import CoreGraphics
import CoreVideo
import Foundation

/// Plain 0...1 colour, so the colour maths needs neither UIKit nor SwiftUI.
struct InkColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    func mixed(toward other: InkColor, by amount: Double) -> InkColor {
        let t = min(max(amount, 0), 1)
        return InkColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                        blue: blue + (other.blue - blue) * t)
    }
}

/// How the liner's colour and texture are made to belong to the skin it sits on. Pure maths, no camera or UI.
enum LinerInk {
    /// Real liner is a thin, slightly translucent film: the skin's tone bleeds into it. Fraction of the skin colour
    /// mixed into the pigment.
    static let skinBleed = 0.12
    /// Skin farther than this from the median brightness of the samples is hair, brow or shadow, and is ignored.
    static let skinLumaSpread = 0.16

    /// The pigment as it looks on this skin. Without a skin reading it is the shade itself.
    static func color(shade: MakeupShade, skin: InkColor?) -> InkColor {
        tint(InkColor(red: shade.red, green: shade.green, blue: shade.blue), skin: skin)
    }

    /// `ink` with the skin's tone mixed in; `ink` itself without a skin reading.
    static func tint(_ ink: InkColor, skin: InkColor?) -> InkColor {
        guard let skin else { return ink }
        return ink.mixed(toward: skin, by: skinBleed)
    }

    // MARK: Skin from camera samples

    /// 8-bit YCbCr (each as 0...1) to RGB, BT.601 (what ARKit's camera buffers use).
    static func rgb(y: Double, cb: Double, cr: Double, fullRange: Bool) -> InkColor {
        let luma = fullRange ? y : (y - 16.0 / 255) * 255 / 219
        let u = fullRange ? cb - 0.5 : (cb - 128.0 / 255) * 255 / 224
        let v = fullRange ? cr - 0.5 : (cr - 128.0 / 255) * 255 / 224
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        return InkColor(red: clamp(luma + 1.402 * v), green: clamp(luma - 0.344136 * u - 0.714136 * v),
                        blue: clamp(luma + 1.772 * u))
    }

    /// The mean of the samples whose brightness is near the median (drops hair, brow and shadow), or `nil` if none.
    static func skinTone(of samples: [InkColor]) -> InkColor? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.map(\.luma).sorted()
        let median = sorted[sorted.count / 2]
        let kept = samples.filter { abs($0.luma - median) <= skinLumaSpread }
        guard !kept.isEmpty else { return nil }
        let n = Double(kept.count)
        return InkColor(red: kept.reduce(0) { $0 + $1.red } / n, green: kept.reduce(0) { $0 + $1.green } / n,
                        blue: kept.reduce(0) { $0 + $1.blue } / n)
    }

    /// Reads the skin around an eye from a camera buffer (biplanar YCbCr) at points in buffer pixels: above the lid,
    /// below the eye and to the sides. A handful of reads, so cheap; `nil` for other pixel formats or points off the image.
    static func sampleSkin(in buffer: CVPixelBuffer, aroundEyeFrom inner: CGPoint, to outer: CGPoint) -> InkColor? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard fullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), cStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let mid = CGPoint(x: (inner.x + outer.x) / 2, y: (inner.y + outer.y) / 2)
        let along = CGPoint(x: outer.x - inner.x, y: outer.y - inner.y)
        let across = CGPoint(x: -along.y, y: along.x)   // as long as the eye is wide
        let offsets: [(CGFloat, CGFloat)] = [(0, -0.55), (0.25, -0.5), (-0.25, -0.5), (0, 0.6), (0.3, 0.55), (-0.3, 0.55),
                                             (0.75, 0.1), (-0.75, 0.1)]
        var samples: [InkColor] = []
        for (a, c) in offsets {
            let x = Int((mid.x + along.x * a + across.x * c).rounded()), y = Int((mid.y + along.y * a + across.y * c).rounded())
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            let luma = Double(yBase.load(fromByteOffset: y * yStride + x, as: UInt8.self)) / 255
            let chroma = (y / 2) * cStride + (x / 2) * 2
            let cb = Double(cBase.load(fromByteOffset: chroma, as: UInt8.self)) / 255
            let cr = Double(cBase.load(fromByteOffset: chroma + 1, as: UInt8.self)) / 255
            samples.append(rgb(y: luma, cb: cb, cr: cr, fullRange: fullRange))
        }
        return skinTone(of: samples)
    }

    // MARK: Grain

    /// Side of the grain tile, in points. Small enough that the speckle is about the camera image's own noise.
    static let grainTileSize = 32
    /// Most ink the grain can lift off at one spot.
    static let grainDepth = 0.34

    /// A square of monochrome speckle as alpha values in `0...grainDepth`. Drawn with destination-out over the liner,
    /// it lets a little skin through unevenly, as pigment does on a textured surface. Deterministic.
    static func grainAlphas(side: Int = grainTileSize, seed: UInt64 = 0x5EED) -> [UInt8] {
        var state = seed
        var out = [UInt8](repeating: 0, count: side * side)
        for i in out.indices {
            // xorshift64*
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            let r = Double((state &* 2685821657736338717) >> 40) / Double(1 << 24)
            // Squared, so most of the speckle is faint and a few specks are strong, like pores.
            out[i] = UInt8((r * r * grainDepth * 255).rounded())
        }
        return out
    }

    /// The tile as an image (black, alpha only).
    static let grainTile: CGImage? = {
        let side = grainTileSize
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for (i, alpha) in grainAlphas().enumerated() { pixels[i * 4 + 3] = alpha }   // premultiplied black
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    /// Tile rectangles (in points) covering `rect`, on a grid anchored at `anchor` so the speckle stays on the skin
    /// when the eye moves.
    static func grainTiles(covering rect: CGRect, anchoredAt anchor: CGPoint) -> [CGRect] {
        let side = CGFloat(grainTileSize)
        guard rect.width > 0, rect.height > 0, rect.width < 4000, rect.height < 4000 else { return [] }
        let x0 = anchor.x + ((rect.minX - anchor.x) / side).rounded(.down) * side
        let y0 = anchor.y + ((rect.minY - anchor.y) / side).rounded(.down) * side
        var tiles: [CGRect] = []
        var y = y0
        while y < rect.maxY {
            var x = x0
            while x < rect.maxX { tiles.append(CGRect(x: x, y: y, width: side, height: side)); x += side }
            y += side
        }
        return tiles
    }
}
