import CoreGraphics
import simd

/// A known pair: where a point lands in the captured image (pixels) and on screen (view points).
struct MappingReference: Equatable, Sendable {
    var image: CGPoint
    var view: CGPoint
}

/// Everything needed to put one camera frame's landmarks on screen, captured when the frame was submitted so a late
/// result still lands where that frame's face was.
struct FrameContext: Equatable, Sendable {
    /// `ARFrame.displayTransform(for: .portrait, viewportSize:)`: normalized image coordinates to normalized view
    /// coordinates (this includes aspect-fill).
    var displayTransform: CGAffineTransform
    var imageSize: CGSize
    var viewportSize: CGSize
    /// Face points projected both ways (see `LinerOverlayModel`); used to check the mapping, and to repair it.
    var references: [MappingReference] = []
    /// Rigid points around the eyes from ARKit's head tracking (image pixels): they move exactly with the head, so
    /// the liner is steadied against them instead of against the detector's own, noisier face points.
    var headAnchors: [CGPoint] = []
}

/// Maps points of the captured camera image (pixels) to the view that shows it (points): the display transform
/// (rotation to portrait, aspect-fill crop) and, for the front camera, the selfie mirror.
struct ImageToViewMapping: Equatable {
    enum Source: Equatable { case displayTransform, mirroredDisplayTransform, fitted }

    let transform: CGAffineTransform
    let source: Source

    func map(_ point: CGPoint) -> CGPoint { point.applying(transform) }

    /// Root mean square distance, in view points, between the mapped image points and their known view positions.
    func residual(_ references: [MappingReference]) -> CGFloat {
        guard !references.isEmpty else { return 0 }
        let sum = references.reduce(CGFloat(0)) { total, reference in
            let d = map(reference.image) - reference.view
            return total + d.dot(d)
        }
        return (sum / CGFloat(references.count)).squareRoot()
    }

    /// Image pixels -> normalized image -> display transform (-> mirror) -> view points.
    static func displayTransform(_ context: FrameContext, mirrored: Bool) -> ImageToViewMapping {
        var t = CGAffineTransform(scaleX: 1 / max(context.imageSize.width, 1), y: 1 / max(context.imageSize.height, 1))
            .concatenating(context.displayTransform)
        if mirrored { t = t.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)) }
        t = t.concatenating(CGAffineTransform(scaleX: context.viewportSize.width, y: context.viewportSize.height))
        return ImageToViewMapping(transform: t, source: mirrored ? .mirroredDisplayTransform : .displayTransform)
    }

    /// The display transform, as ARKit documents it, unless it disagrees with the face's own projection (ARKit's
    /// front camera is shown mirrored, and the transform's treatment of that is not guaranteed). Then the mirrored
    /// variant is tried, and as a last resort the mapping is fitted from the references themselves.
    static func resolve(_ context: FrameContext) -> ImageToViewMapping {
        let plain = displayTransform(context, mirrored: false)
        guard context.references.count >= 3 else { return plain }
        let tolerance = max(context.viewportSize.width * 0.015, 3)
        let mirrored = displayTransform(context, mirrored: true)
        let best = plain.residual(context.references) <= mirrored.residual(context.references) ? plain : mirrored
        if best.residual(context.references) <= tolerance { return best }
        if let fitted = fit(context.references) { return fitted }
        return best
    }

    /// Least-squares affine transform through the references; `nil` if they do not span a plane.
    static func fit(_ references: [MappingReference]) -> ImageToViewMapping? {
        guard references.count >= 3 else { return nil }
        // Solve [x y 1] * [a c tx; b d ty] = [X Y] in the least-squares sense via the normal equations.
        var normal = simd_double3x3(0)
        var rightX = SIMD3<Double>(0), rightY = SIMD3<Double>(0)
        for reference in references {
            let row = SIMD3<Double>(Double(reference.image.x), Double(reference.image.y), 1)
            normal += simd_double3x3(rows: [row * row.x, row * row.y, row * row.z])
            rightX += row * Double(reference.view.x)
            rightY += row * Double(reference.view.y)
        }
        guard abs(normal.determinant) > 1e-9 else { return nil }
        let inverse = normal.inverse
        let x = inverse * rightX, y = inverse * rightY
        let t = CGAffineTransform(a: x.x, b: y.x, c: x.y, d: y.y, tx: x.z, ty: y.z)
        return ImageToViewMapping(transform: t, source: .fitted)
    }
}
