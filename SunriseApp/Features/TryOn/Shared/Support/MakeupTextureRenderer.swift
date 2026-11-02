import UIKit
import simd

/// One side of the face in texture space: origin at the eye centre, `outward` away from the nose, `up` toward the brow.
struct FeatureFrame: Equatable, Sendable {
    let origin: SIMD2<Float>
    let outward: SIMD2<Float>
    let up: SIMD2<Float>
    /// Distance between the eye centres; blush offsets are measured in it.
    let unit: Float

    init(side: FaceFeatureMap.Side, in map: FaceFeatureMap) {
        origin = side.eyeCenter
        outward = simd_normalize(side.eyeCenter - map.midpoint)
        let up = SIMD2(-outward.y, outward.x)
        self.up = simd_dot(up, side.browCenter - side.eyeCenter) >= 0 ? up : -up
        unit = map.eyeDistance
    }

    /// Distance along `outward` from the eye centre.
    func across(_ point: SIMD2<Float>) -> Float { simd_dot(point - origin, outward) }
}

/// Draws makeup into a transparent texture laid out like the ARKit face mesh's texture coordinates.
/// Each category gets its own texture so its intensity can change instantly through the material's transparency.
enum MakeupTextureRenderer {
    static let size: CGFloat = 2048
    /// Intensity at which a shade shows at its own opacity. Textures are drawn stronger so the intensity
    /// slider can go above the default.
    static let defaultIntensity: Double = 0.65

    /// DEBUG only, default off: draw the eyeliner into the face-mesh texture (the old way) instead of the MediaPipe
    /// overlay, to compare the two. Launch with `-legacyMeshEyeliner YES` (scheme arguments).
    static var legacyMeshEyeliner: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "legacyMeshEyeliner")
        #else
        false
        #endif
    }

    /// Intensity a category starts at. The liner is a thin line, so it starts fully opaque to stay noticeable.
    static func startingIntensity(for category: MakeupCategory) -> Double {
        category == .eyeliner ? 1 : defaultIntensity
    }

    /// `fit` is measured from `features` unless given; pass one when `features` carries live, moving points
    /// (see `FaceFeatureMap.replacingEyes`) so the fitting does not jump with every frame.
    static func image(for style: MakeupStyle, features: FaceFeatureMap, fit: FaceFit? = nil) -> UIImage? {
        // -Nimah: Removed legacy eyebrow/blush texture rendering; Hanum liner debug path only.
        guard case .eyeliner = style,features.isPlausible else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Every style is fitted to the measured features; without them it is drawn as designed.
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            for side in features.sides {
                let frame = FeatureFrame(side: side, in: features)
                switch style {
                case .blush,.eyebrow: break
                case .eyeliner(let liner):
                    // Already chosen for this person's eye shape in the face scan; not fitted again here.
                    for outline in linerOutlines(liner, eye: side.eye, brow: side.brow, frame: frame) {
                        fill(outline, shade: liner.shade, blur: 1, in: cg)
                    }
                }
            }
        }
    }

    /// Opacity drawn into the texture for a shade.
    static func drawnOpacity(_ shade: MakeupShade) -> Double { min(1, shade.opacity / defaultIntensity) }

    // MARK: - Shapes in texture space

    /// Draw the tightline (a strip on the inner rim of the upper lid). Off because the face renderer fills the whole
    /// mesh, so anything inside the eye opening would be painted over the eyeball.
    static let drawsTightline = false

    /// Polygons of a liner along the upper lash line, with an optional wing past the outer corner and lower line.
    static func linerOutlines(_ style: LinerStyle, eye: [SIMD2<Float>], brow: [SIMD2<Float>],
                              frame: FeatureFrame) -> [[SIMD2<Float>]] {
        LinerGeometry.shape(style, eye: eye, brow: brow, frame: frame, includeTightline: drawsTightline)?.outlines ?? []
    }

    /// Catmull-Rom curve through `points`, eight samples per segment.
    static func smoothed(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }
        var result: [SIMD2<Float>] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)], p1 = points[index]
            let p2 = points[index + 1], p3 = points[min(index + 2, points.count - 1)]
            for step in 0..<8 {
                let t = Float(step) / 8, t2 = t * t, t3 = t2 * t
                let a = 2 * p1, b = p2 - p0, c = 2 * p0 - 5 * p1 + 4 * p2 - p3, d = 3 * p1 - p0 - 3 * p2 + p3
                result.append(0.5 * (a + b * t + c * t2 + d * t3))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func perpendicular(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(vector)
        return length > 0 ? SIMD2(-vector.y, vector.x) / length : .zero
    }

    private static func oriented(_ vector: SIMD2<Float>, toward reference: SIMD2<Float>) -> SIMD2<Float> {
        simd_dot(vector, reference) >= 0 ? vector : -vector
    }

    // MARK: - Drawing

    private static func cgPoint(_ uv: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(uv.x) * size, y: CGFloat(uv.y) * size)
    }

    private static func color(_ shade: MakeupShade, opacity: Double) -> CGColor {
        CGColor(srgbRed: shade.red, green: shade.green, blue: shade.blue, alpha: opacity)
    }

    private static func fill(_ outline: [SIMD2<Float>], shade: MakeupShade, blur: CGFloat, in context: CGContext) {
        guard let first = outline.first else { return }
        context.saveGState()
        let opacity = drawnOpacity(shade)
        context.setShadow(offset: .zero, blur: blur, color: color(shade, opacity: opacity))
        context.setFillColor(color(shade, opacity: opacity))
        context.move(to: cgPoint(first))
        for point in outline.dropFirst() { context.addLine(to: cgPoint(point)) }
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

}
