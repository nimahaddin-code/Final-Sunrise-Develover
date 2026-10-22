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
    /// Hands in front of the face: the liner is erased where this is set.
    var occlusion: Occlusion?
    /// The skin tone around the eyes, read from the camera; the pigment picks a little of it up.
    var skin: InkColor?
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

    /// The pigment bleeds a little into the skin around it: a wider, fainter copy under the liner.
    static let haloAlpha = 0.22
    static let haloBlurScale: CGFloat = 2.6

    /// One filled shape per eye, in view points, with the opacity to fill it with and how much to soften its edge.
    /// Each eye gives a faint wide `halo` first, then the liner's body.
    struct Fill {
        let path: CGPath
        let color: InkColor
        let alpha: Double
        let blur: CGFloat
        let isHalo: Bool
        /// Where the skin texture (grain) is anchored: the eye's inner corner on screen.
        let anchor: CGPoint
    }

    static func fills(_ frame: LinerOverlayFrame, shade: MakeupShade, intensity: Double,
                      now: CFTimeInterval = CACurrentMediaTime()) -> [Fill] {
        guard now - frame.receivedAt <= maxAge, intensity > 0.01 else { return [] }
        let opacity = min(MakeupTextureRenderer.drawnOpacity(shade), maxOpacity) * intensity
        let color = LinerInk.color(shade: shade, skin: frame.skin)
        return frame.eyes.flatMap { eye -> [Fill] in
            let alpha = opacity * eye.alpha
            guard alpha > 0.005 else { return [] }
            let path = CGMutablePath()
            for outline in eye.guide.outlines { add(outline, to: path, mapping: frame.mapping) }
            if !eye.guide.tightline.isEmpty { add(eye.guide.tightline, to: path, mapping: frame.mapping) }
            let inner = frame.mapping.map(eye.guide.anchors.innerCorner)
            let width = (frame.mapping.map(eye.guide.anchors.outerCorner) - inner).length
            let blur = min(max(width * blurFraction, blurRange.lowerBound), blurRange.upperBound)
            return [Fill(path: path, color: color, alpha: alpha * haloAlpha, blur: blur * haloBlurScale, isHalo: true, anchor: inner),
                    Fill(path: path, color: color, alpha: alpha, blur: blur, isHalo: false, anchor: inner)]
        }
    }

    /// Fills the shapes into a UIKit-style context (origin top left, units of view points), edges unsoftened.
    static func draw(_ fills: [Fill], in cg: CGContext) {
        for fill in fills {
            cg.setFillColor(red: fill.color.red, green: fill.color.green, blue: fill.color.blue, alpha: fill.alpha)
            // The outlines share one winding, so a single nonzero fill is their union.
            cg.addPath(fill.path)
            cg.fillPath(using: .winding)
        }
    }

    /// Lifts the ink off in faint speckles (a UIKit context is current), so skin texture shows through the liner.
    static func eraseGrain(for fills: [Fill], in cg: CGContext) {
        guard let tile = LinerInk.grainTile else { return }
        for fill in fills where !fill.isHalo {
            // It only removes ink that is there, so no clip is needed; the box covers the soft fringe too.
            let box = fill.path.boundingBoxOfPath.insetBy(dx: -fill.blur * 3, dy: -fill.blur * 3)
            for rect in LinerInk.grainTiles(covering: box, anchoredAt: fill.anchor) {
                UIImage(cgImage: tile).draw(in: rect, blendMode: .destinationOut, alpha: 1)
            }
        }
    }

    /// Erases what is already drawn wherever the occlusion mask is set (a UIKit context is current).
    static func erase(_ occlusion: Occlusion, in cg: CGContext) {
        cg.saveGState()
        cg.concatenate(occlusion.transform)
        UIImage(cgImage: occlusion.image).draw(in: CGRect(origin: .zero, size: occlusion.size), blendMode: .destinationOut,
                                               alpha: 1)
        cg.restoreGState()
    }

    /// `snapshot` (the camera view with the other makeup) with the liner on it. The liner is multiplied into the
    /// picture like the live overlay, so the skin's shading and texture show through it.
    static func compose(_ snapshot: UIImage, overlay frame: LinerOverlayFrame, shade: MakeupShade,
                        intensity: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
        let fills = fills(frame, shade: shade, intensity: intensity)
        // Halo and body each softened by their own radius, laid together, then speckled and cut out behind hands.
        func layer(isHalo: Bool) -> UIImage {
            let part = fills.filter { $0.isHalo == isHalo }
            let image = renderer.image { draw(part, in: $0.cgContext) }
            return blurred(image, radius: (part.map(\.blur).max() ?? 0) * snapshot.scale, scale: snapshot.scale)
        }
        let halo = layer(isHalo: true), body = layer(isHalo: false)
        let liner = renderer.image { context in
            halo.draw(at: .zero)
            body.draw(at: .zero)
            eraseGrain(for: fills, in: context.cgContext)
            if let occlusion = frame.occlusion { erase(occlusion, in: context.cgContext) }
        }
        return renderer.image { _ in
            snapshot.draw(at: .zero)
            liner.draw(at: .zero, blendMode: .multiply, alpha: 1)
        }
    }

    private static func blurred(_ image: UIImage, radius: CGFloat, scale: CGFloat) -> UIImage {
        guard radius > 0, let input = CIImage(image: image), let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    private static func add(_ polygon: [CGPoint], to path: CGMutablePath, mapping: ImageToViewMapping) {
        guard let first = polygon.first else { return }
        path.move(to: mapping.map(first))
        for point in polygon.dropFirst() { path.addLine(to: mapping.map(point)) }
        path.closeSubpath()
    }
}
