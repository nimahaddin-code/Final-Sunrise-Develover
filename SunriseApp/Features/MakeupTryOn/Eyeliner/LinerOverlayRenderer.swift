import CoreGraphics
import UIKit

/// What the overlay shows right now.
struct LinerOverlayFrame {
    var eyes: [RenderedEye]
    var mapping: ImageToViewMapping
    var receivedAt: CFTimeInterval
}

/// Draws the liner into a Core Graphics context in view points. Used by the live SwiftUI canvas and, with the same
/// numbers, by the photo composition, so a saved photo shows exactly what the screen showed.
enum LinerOverlayRenderer {
    /// A frame older than this is not drawn (the face was lost, or the detector stalled).
    static let maxAge: CFTimeInterval = 0.4

    /// One filled shape per eye, in view points, with the opacity to fill it with.
    struct Fill {
        let path: CGPath
        let alpha: Double
    }

    static func fills(_ frame: LinerOverlayFrame, shade: MakeupShade, intensity: Double,
                      now: CFTimeInterval = CACurrentMediaTime()) -> [Fill] {
        guard now - frame.receivedAt <= maxAge, intensity > 0.01 else { return [] }
        let opacity = MakeupTextureRenderer.drawnOpacity(shade) * intensity
        return frame.eyes.compactMap { eye in
            let alpha = opacity * eye.alpha
            guard alpha > 0.005 else { return nil }
            let path = CGMutablePath()
            for outline in eye.guide.outlines { add(outline, to: path, mapping: frame.mapping) }
            if !eye.guide.tightline.isEmpty { add(eye.guide.tightline, to: path, mapping: frame.mapping) }
            return Fill(path: path, alpha: alpha)
        }
    }

    /// Fills the liner into a UIKit-style context (origin top left, units of view points).
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
        return UIGraphicsImageRenderer(size: snapshot.size, format: format).image { context in
            snapshot.draw(at: .zero)
            draw(frame, shade: shade, intensity: intensity, in: context.cgContext)
        }
    }

    private static func add(_ polygon: [CGPoint], to path: CGMutablePath, mapping: ImageToViewMapping) {
        guard let first = polygon.first else { return }
        path.move(to: mapping.map(first))
        for point in polygon.dropFirst() { path.addLine(to: mapping.map(point)) }
        path.closeSubpath()
    }
}
