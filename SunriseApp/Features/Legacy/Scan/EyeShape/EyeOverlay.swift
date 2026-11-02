import CoreGraphics
import simd

/// Draws what the eye measurement used: each eye's outline, the corner-to-corner line (tilt), the opening, the iris, the
/// brow, and the gap between the eyes (spacing). Pure geometry on `EyeScanLandmarks`, so it is tested without a camera.
enum EyeOverlay {
    /// - Parameters:
    ///   - landmarks: points in image pixels.
    ///   - imageSize: the image the points belong to, in pixels.
    ///   - mirrored: flips left and right, because the person looked at a mirrored preview while scanning.
    static func overlay(for landmarks: EyeScanLandmarks, imageSize: SIMD2<Float>, mirrored: Bool = true) -> ScanOverlay? {
        guard imageSize.x > 0, imageSize.y > 0 else { return nil }
        func normalized(_ point: SIMD2<Float>) -> CGPoint {
            let x = CGFloat(point.x / imageSize.x)
            return CGPoint(x: mirrored ? 1 - x : x, y: CGFloat(point.y / imageSize.y))
        }

        var strokes: [ScanOverlay.Stroke] = []
        for eye in [landmarks.first, landmarks.second] {
            guard eye.lid.count >= 4 else { return nil }
            // The first half of `lid` runs along the upper lid and the second along the lower, both from the outer corner.
            let half = eye.lid.count / 2
            let outline = [eye.outerCorner] + eye.lid[..<half] + [eye.innerCorner] + eye.lid[half...].reversed()
            strokes.append(.init(points: outline.map(normalized), style: .outline, closed: true))

            if !eye.brow.isEmpty { strokes.append(.init(points: eye.brow.map(normalized), style: .guide)) }
            if let iris = circle(through: eye.iris) {
                strokes.append(.init(points: iris.map(normalized), style: .guide, closed: true))
            }
            // Unlabelled: a name on top of an eye hides the eye. The caption under the picture explains the dashed lines.
            strokes.append(.init(points: [eye.innerCorner, eye.outerCorner].map(normalized), style: .measure))
            if let opening = openingLine(of: eye) { strokes.append(.init(points: opening.map(normalized), style: .measure)) }
        }
        strokes.append(.init(points: [landmarks.first.innerCorner, landmarks.second.innerCorner].map(normalized),
                             style: .measure, label: "Spacing"))
        return ScanOverlay(strokes: strokes)
    }

    /// The line across the widest part of the lid opening, at right angles to the corner-to-corner line.
    static func openingLine(of eye: EyeScanLandmarks.Eye) -> [SIMD2<Float>]? {
        let axis = eye.outerCorner - eye.innerCorner
        let width = simd_length(axis)
        guard width > 0, !eye.lid.isEmpty else { return nil }
        let along = axis / width, across = SIMD2(-along.y, along.x)
        let offsets = eye.lid.map { simd_dot($0 - eye.innerCorner, across) }
        let positions = eye.lid.map { simd_dot($0 - eye.innerCorner, along) }
        guard let top = offsets.max(), let bottom = offsets.min(), top > bottom,
              let topIndex = offsets.firstIndex(of: top), let bottomIndex = offsets.firstIndex(of: bottom) else { return nil }
        let at = (positions[topIndex] + positions[bottomIndex]) / 2
        return [eye.innerCorner + along * at + across * top, eye.innerCorner + along * at + across * bottom]
    }

    /// A ring through the iris rim points: centred on them, as wide as their farthest pair.
    static func circle(through rim: [SIMD2<Float>], segments: Int = 20) -> [SIMD2<Float>]? {
        guard rim.count >= 2 else { return nil }
        let center = rim.reduce(.zero, +) / Float(rim.count)
        var diameter: Float = 0
        for i in rim.indices { for j in rim.indices where j > i { diameter = max(diameter, simd_distance(rim[i], rim[j])) } }
        guard diameter > 0 else { return nil }
        return (0..<segments).map { step in
            let angle = Float(step) / Float(segments) * 2 * .pi
            return center + SIMD2(cos(angle), sin(angle)) * (diameter / 2)
        }
    }
}
