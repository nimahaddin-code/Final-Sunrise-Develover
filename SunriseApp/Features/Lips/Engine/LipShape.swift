import CoreImage
import UIKit

/// The lips' outline and the mouth opening as closed rings of `LipLandmarks.ringCount` points, in pixels of the captured
/// camera image (like `EyeLandmarks`). Both rings start at the subject's right mouth corner, run along the upper lip to
/// the left corner and come back along the lower lip, so point i of one ring lies beside point i of the other.
struct LipLandmarks: Equatable, Sendable {
    static let ringCount = 20

    var outer: [CGPoint]
    var inner: [CGPoint]

    var isComplete: Bool { outer.count == Self.ringCount && inner.count == Self.ringCount }
}

/// The lips on screen for one camera frame, in view points. Rings as in `LipLandmarks`.
struct LipOverlayFrame: Equatable {
    var outer: [CGPoint]
    var inner: [CGPoint]
    var receivedAt: CFTimeInterval

    /// Ring positions: the two corners, the cupid's bow (its two peaks and the dip between) and the lower lip's middle.
    static let rightCorner = 0, rightPeak = 4, upperMiddle = 5, leftPeak = 6, leftCorner = 10, lowerMiddle = 15

    var width: CGFloat { (outer[Self.leftCorner] - outer[Self.rightCorner]).length }

    /// Where the tutorial's comparison cuts the picture: through the cupid's bow and the middle of the lower lip.
    var splitX: CGFloat { (outer[Self.upperMiddle].x + outer[Self.lowerMiddle].x) / 2 }
}

/// Turns the lips of one frame into what a style paints. Used by the live canvas, the photo and the tutorial guide, so all
/// three show the same shape.
enum LipShape {
    /// How far past the lip line "Full" reaches at the middle of each lip, as a fraction of the mouth's width; it tapers
    /// to nothing at the corners.
    static let fullReach: CGFloat = 0.035
    /// "Gradient": the strong middle ends this far from the mouth opening towards the lip's edge (0...1).
    static let gradientCore: CGFloat = 0.5
    /// Lipstick lets a little of the lip show through even at full strength.
    static let maxOpacity = 0.8

    /// The edge the style's colour reaches: the lip line, or a little past it for "Full".
    static func edge(_ frame: LipOverlayFrame, style: LipStyle) -> [CGPoint] {
        guard style == .full else { return frame.outer }
        let right = frame.outer[LipOverlayFrame.rightCorner], left = frame.outer[LipOverlayFrame.leftCorner]
        let half = max(frame.width / 2, 1)
        let centre = right.lerp(to: left, 0.5)
        let across = (left - right).normalized()
        let up = CGPoint(x: -across.y, y: across.x)
        return frame.outer.map { point in
            let offset = point - centre
            let along = min(abs(offset.dot(across)) / half, 1)
            let side: CGFloat = offset.dot(up) >= 0 ? 1 : -1
            return point + up * (side * frame.width * fullReach * (1 - along * along))
        }
    }

    /// The ring the tutorial guides: the style's edge, or for "Gradient" the middle where the colour goes on.
    static func guideRing(_ frame: LipOverlayFrame, style: LipStyle) -> [CGPoint] {
        style == .gradient ? core(frame) : edge(frame, style: style)
    }

    private static func core(_ frame: LipOverlayFrame) -> [CGPoint] {
        zip(frame.inner, frame.outer).map { $0.lerp(to: $1, gradientCore) }
    }

    /// One fill: `path` with the even-odd rule, softened by `blur` points, kept inside `clip` (even-odd) when set.
    struct Layer {
        let path: CGPath
        let alpha: Double
        let blur: CGFloat
        var clip: CGPath? = nil
    }

    static func layers(_ frame: LipOverlayFrame, style: LipStyle, shade: MakeupShade, intensity: Double) -> [Layer] {
        let opacity = min(shade.opacity, maxOpacity) * intensity
        guard opacity > 0.01, frame.outer.count == LipLandmarks.ringCount, frame.inner.count == LipLandmarks.ringCount else { return [] }
        // The camera picture is soft, so a crisp vector edge would look pasted on.
        let blur = min(max(frame.width * 0.012, 0.6), 2.5)
        let lips = ring(edge(frame, style: style), minus: frame.inner)
        guard style == .gradient else { return [Layer(path: lips, alpha: opacity, blur: blur)] }
        return [Layer(path: lips, alpha: opacity * 0.3, blur: blur),
                Layer(path: ring(core(frame), minus: frame.inner), alpha: opacity, blur: max(frame.width * 0.045, blur), clip: lips)]
    }

    /// A closed ring with the mouth opening cut out of it (even-odd).
    static func ring(_ outline: [CGPoint], minus opening: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        addSmooth(outline, to: path)
        addSmooth(opening, to: path)
        return path
    }

    /// A closed curve through the midpoints of the ring's sides, with the ring's points as controls: no corners between
    /// the detector's 20 points.
    static func addSmooth(_ ring: [CGPoint], to path: CGMutablePath) {
        guard ring.count > 2 else { return }
        path.move(to: ring[ring.count - 1].lerp(to: ring[0], 0.5))
        for index in ring.indices {
            path.addQuadCurve(to: ring[index].lerp(to: ring[(index + 1) % ring.count], 0.5), control: ring[index])
        }
        path.closeSubpath()
    }

    /// `snapshot` (the camera view, in view points) with the lipstick drawn over it, as the live canvas shows it.
    static func compose(_ snapshot: UIImage, frame: LipOverlayFrame, style: LipStyle, shade: MakeupShade, intensity: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.size, format: format)
        // Each fill alone on a transparent picture, softened, then laid over the photo.
        let fills = layers(frame, style: style, shade: shade, intensity: intensity).map { layer -> (UIImage, CGPath?) in
            let image = renderer.image { context in
                context.cgContext.setFillColor(red: shade.red, green: shade.green, blue: shade.blue, alpha: layer.alpha)
                context.cgContext.addPath(layer.path)
                context.cgContext.fillPath(using: .evenOdd)
            }
            return (blurred(image, radius: layer.blur * snapshot.scale), layer.clip)
        }
        return renderer.image { context in
            snapshot.draw(at: .zero)
            for (image, clip) in fills {
                context.cgContext.saveGState()
                if let clip {
                    context.cgContext.addPath(clip)
                    context.cgContext.clip(using: .evenOdd)
                }
                image.draw(at: .zero)
                context.cgContext.restoreGState()
            }
        }
    }

    private static func blurred(_ image: UIImage, radius: CGFloat) -> UIImage {
        guard let input = CIImage(image: image), let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}
