import CoreGraphics
import simd

/// Where the face shape was measured, in face-local space (meters): the width of the forehead, cheekbones, jaw and chin,
/// and the length. It is what `FaceShapeResultView` draws over the scan picture so the person can check the measurement.
struct FaceGuide: Equatable, Sendable {
    /// A width: the two ends of the face at one height. `left` has the smaller x.
    struct Span: Equatable, Sendable {
        var left: SIMD3<Float>
        var right: SIMD3<Float>
    }

    var forehead: Span
    var cheekbones: Span
    var jaw: Span
    var chin: Span
    /// Highest point of the ARKit mesh (the upper forehead, not the hairline).
    var top: SIMD3<Float>
    /// The tip of the chin.
    var bottom: SIMD3<Float>

    /// The lines in picture coordinates. `project` turns a face-local point into a normalized position in the picture;
    /// return `nil` for a point that cannot be shown and nothing is drawn.
    func overlay(project: (SIMD3<Float>) -> CGPoint?) -> ScanOverlay? {
        let outlinePoints = [forehead.left, cheekbones.left, jaw.left, chin.left, bottom,
                             chin.right, jaw.right, cheekbones.right, forehead.right].map(project)
        guard let topPoint = project(top), let bottomPoint = project(bottom),
              let outline = outlinePoints.allSatisfy({ $0 != nil }) ? outlinePoints.compactMap({ $0 }) : nil else { return nil }

        var strokes = [ScanOverlay.Stroke(points: outline, style: .outline)]
        let widths: [(Span, String)] = [(forehead, "Forehead"), (cheekbones, "Cheekbones"), (jaw, "Jaw")]
        for (span, label) in widths {
            guard let left = project(span.left), let right = project(span.right) else { return nil }
            strokes.append(ScanOverlay.Stroke(points: [left, right], style: .measure, label: label))
        }
        strokes.append(ScanOverlay.Stroke(points: [topPoint, bottomPoint], style: .measure))
        return ScanOverlay(strokes: strokes)
    }
}

extension FaceMeshMeasurer {
    /// The ends of each measured band, using the same bands as `proportions(of:)`.
    ///
    /// `correction` is the median comparison with Vision's face outline. When present, the widths are scaled the same way
    /// `ContourCorrection.applied(to:)` scales the proportions, so the lines show the widths the classifier actually used
    /// (the forehead stays as the mesh has it, because Vision's outline does not cover it).
    static func guide(of vertices: [SIMD3<Float>], correction: ContourCorrection? = nil) -> FaceGuide? {
        guard let bottom = vertices.min(by: { $0.y < $1.y }), let top = vertices.max(by: { $0.y < $1.y }),
              top.y > bottom.y else { return nil }
        let length = top.y - bottom.y

        func span(_ band: Band, scale: Float) -> FaceGuide.Span? {
            let low = bottom.y + band.lower * length, high = bottom.y + band.upper * length
            let inBand = vertices.filter { $0.y >= low && $0.y <= high }
            guard let left = inBand.min(by: { $0.x < $1.x }), let right = inBand.max(by: { $0.x < $1.x }),
                  right.x > left.x else { return nil }
            let y = (low + high) / 2, z = (left.z + right.z) / 2
            let center = (left.x + right.x) / 2, half = (right.x - left.x) / 2 * scale
            return FaceGuide.Span(left: SIMD3(center - half, y, z), right: SIMD3(center + half, y, z))
        }

        let cheekScale = correction?.cheekbones ?? 1
        let jawScale = correction?.jaw ?? cheekScale
        let chinScale = correction?.chin ?? jawScale
        guard let forehead = span(foreheadBand, scale: 1), let cheekbones = span(cheekboneBand, scale: cheekScale),
              let jaw = span(jawBand, scale: jawScale), let chin = span(chinBand, scale: chinScale) else { return nil }
        return FaceGuide(forehead: forehead, cheekbones: cheekbones, jaw: jaw, chin: chin, top: top, bottom: bottom)
    }
}
