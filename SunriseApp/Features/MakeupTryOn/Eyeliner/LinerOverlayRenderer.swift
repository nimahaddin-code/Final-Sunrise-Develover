import CoreGraphics
import UIKit

/// What the overlay shows right now.
struct LinerOverlayFrame {
    var eyes: [RenderedEye]
    var mapping: ImageToViewMapping
    var receivedAt: CFTimeInterval
    /// DEBUG dots: MediaPipe's eye points as reported, and after smoothing.
    var debugRaw: [EyeLandmarks] = []
    var debugSmoothed: [EyeLandmarks] = []
    /// Where hands are (developer view only; the liner is drawn over them).
    var occlusion: Occlusion?
}

/// Draws the liner into a Core Graphics context in view points. Used by the live SwiftUI canvas and, with the same
/// numbers, by the photo composition, so a saved photo shows exactly what the screen showed.
enum LinerOverlayRenderer {
    /// A frame older than this is not drawn (the face was lost, or the detector stalled).
    static let maxAge: CFTimeInterval = 0.4

    /// Even at full intensity the ink lets a little skin show through, so it does not read as a sticker.
    static let maxOpacity = 0.9
    /// Real ink still reflects some light: the liner is multiplied over the skin with this much of the light left
    /// (the shade lifted toward white by this share), so it is charcoal on skin, lighter in bright light, darker in dim
    /// light, and tinted by the skin under it, instead of a flat black.
    static let inkReflectance: Double = 0.16

    /// The colour the liner is multiplied with: the shade, lifted by `inkReflectance`.
    static func ink(_ shade: MakeupShade) -> (red: Double, green: Double, blue: Double) {
        func lift(_ c: Double) -> Double { inkReflectance + (1 - inkReflectance) * c }
        return (lift(shade.red), lift(shade.green), lift(shade.blue))
    }
    /// Edge softness as a fraction of the eye's width on screen. The camera image is soft (upscaled video), so a crisp
    /// vector edge looks pasted on; this matches the liner's edge to the picture. Clamped to `blurRange` points.
    static let blurFraction: CGFloat = 0.008
    static let blurRange: ClosedRange<CGFloat> = 0.4...1.2
    /// Ink on skin bleeds a little: under the crisp liner a faint, wider-blurred copy (`haloShare` of its opacity,
    /// `haloBlurScale` times its blur) melts its edge into the lid, the way try-on filters draw makeup.
    static let haloShare = 0.35
    static let haloBlurScale: CGFloat = 4

    /// One filled shape per eye, in view points, with the opacity to fill it with and how much to soften its edge.
    struct Fill {
        let path: CGPath
        let alpha: Double
        let blur: CGFloat
        var haloAlpha: Double { alpha * LinerOverlayRenderer.haloShare }
        var haloBlur: CGFloat { blur * LinerOverlayRenderer.haloBlurScale }
    }

    static func fills(_ frame: LinerOverlayFrame, shade: MakeupShade, intensity: Double,
                      now: CFTimeInterval = CACurrentMediaTime()) -> [Fill] {
        guard now - frame.receivedAt <= maxAge, intensity > 0.01 else { return [] }
        let opacity = min(MakeupTextureRenderer.drawnOpacity(shade), maxOpacity) * intensity
        return frame.eyes.compactMap { eye in
            let alpha = opacity * eye.alpha
            guard alpha > 0.005 else { return nil }
            let path = CGMutablePath()
            for outline in eye.guide.outlines { add(outline, to: path, mapping: frame.mapping) }
            if !eye.guide.tightline.isEmpty { add(eye.guide.tightline, to: path, mapping: frame.mapping) }
            let width = (frame.mapping.map(eye.guide.anchors.outerCorner) - frame.mapping.map(eye.guide.anchors.innerCorner)).length
            return Fill(path: path, alpha: alpha, blur: min(max(width * blurFraction, blurRange.lowerBound), blurRange.upperBound))
        }
    }

    /// Fills the liner into a UIKit-style context (origin top left, units of view points), edges unsoftened.
    /// `halo` fills the faint bleed layer instead of the liner itself.
    static func draw(_ frame: LinerOverlayFrame, shade: MakeupShade, intensity: Double, in cg: CGContext,
                     halo: Bool = false, now: CFTimeInterval = CACurrentMediaTime()) {
        for fill in fills(frame, shade: shade, intensity: intensity, now: now) {
            let ink = ink(shade)
            cg.setFillColor(red: ink.red, green: ink.green, blue: ink.blue, alpha: halo ? fill.haloAlpha : fill.alpha)
            // The outlines share one winding, so a single nonzero fill is their union.
            cg.addPath(fill.path)
            cg.fillPath(using: .winding)
        }
    }

    /// `snapshot` (the camera view with the other makeup) with the liner drawn over it.
    static func compose(_ snapshot: UIImage, overlay frame: LinerOverlayFrame, shade: MakeupShade,
                        intensity: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
        let fills = fills(frame, shade: shade, intensity: intensity)
        // The bleed and the liner each alone on a transparent layer, softened like the live overlay, then multiplied
        // over the photo: the ink darkens the skin under it and keeps its texture and shading.
        func layer(halo: Bool, blur: CGFloat?) -> UIImage {
            let image = renderer.image { context in
                draw(frame, shade: shade, intensity: intensity, in: context.cgContext, halo: halo)
            }
            guard let blur, let input = CIImage(image: image), let filter = CIFilter(name: "CIGaussianBlur") else { return image }
            filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter.setValue(blur * snapshot.scale, forKey: kCIInputRadiusKey)
            guard let output = filter.outputImage?.cropped(to: input.extent),
                  let cg = CIContext().createCGImage(output, from: output.extent) else { return image }
            return UIImage(cgImage: cg, scale: snapshot.scale, orientation: .up)
        }
        let bleed = layer(halo: true, blur: fills.map(\.haloBlur).max())
        let liner = layer(halo: false, blur: fills.map(\.blur).max())
        return renderer.image { _ in
            snapshot.draw(at: .zero)
            bleed.draw(at: .zero, blendMode: .multiply, alpha: 1)
            liner.draw(at: .zero, blendMode: .multiply, alpha: 1)
        }
    }

    private static func add(_ polygon: [CGPoint], to path: CGMutablePath, mapping: ImageToViewMapping) {
        guard let first = polygon.first else { return }
        path.move(to: mapping.map(first))
        for point in polygon.dropFirst() { path.addLine(to: mapping.map(point)) }
        path.closeSubpath()
    }
}
