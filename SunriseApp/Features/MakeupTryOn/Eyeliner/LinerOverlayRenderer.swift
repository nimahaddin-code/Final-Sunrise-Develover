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
}

/// Draws the liner into a Core Graphics context in view points. Used by the live SwiftUI canvas and, with the same
/// numbers, by the photo composition, so a saved photo shows exactly what the screen showed.
enum LinerOverlayRenderer {
    /// A frame older than this is not drawn (the face was lost, or the detector stalled).
    static let maxAge: CFTimeInterval = 0.4

    /// Even at full intensity the ink lets a little skin show through, so it does not read as a sticker.
    static let maxOpacity = 0.88
    /// Edge softness as a fraction of the eye's width on screen. The camera image is soft (upscaled video), so a crisp
    /// vector edge looks pasted on; this matches the liner's edge to the picture. Clamped to `blurRange` points.
    static let blurFraction: CGFloat = 0.015
    static let blurRange: ClosedRange<CGFloat> = 0.6...2.0

    /// One filled shape per eye, in view points, with the opacity to fill it with and how much to soften its edge.
    struct Fill {
        let path: CGPath
        let alpha: Double
        let blur: CGFloat
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
    static func draw(_ frame: LinerOverlayFrame, shade: MakeupShade, intensity: Double, in cg: CGContext,
                     now: CFTimeInterval = CACurrentMediaTime()) {
        for fill in fills(frame, shade: shade, intensity: intensity, now: now) {
            cg.setFillColor(red: shade.red, green: shade.green, blue: shade.blue, alpha: fill.alpha)
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
        // The liner alone on a transparent layer, softened like the live overlay, then laid over the photo.
        var layer = renderer.image { context in
            draw(frame, shade: shade, intensity: intensity, in: context.cgContext)
        }
        if let blur = fills.map(\.blur).max(), let input = CIImage(image: layer),
           let filter = CIFilter(name: "CIGaussianBlur") {
            filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter.setValue(blur * snapshot.scale, forKey: kCIInputRadiusKey)
            if let output = filter.outputImage?.cropped(to: input.extent),
               let cg = CIContext().createCGImage(output, from: output.extent) {
                layer = UIImage(cgImage: cg, scale: snapshot.scale, orientation: .up)
            }
        }
        return renderer.image { _ in
            snapshot.draw(at: .zero)
            layer.draw(at: .zero)
        }
    }

    private static func add(_ polygon: [CGPoint], to path: CGMutablePath, mapping: ImageToViewMapping) {
        guard let first = polygon.first else { return }
        path.move(to: mapping.map(first))
        for point in polygon.dropFirst() { path.addLine(to: mapping.map(point)) }
        path.closeSubpath()
    }
}
