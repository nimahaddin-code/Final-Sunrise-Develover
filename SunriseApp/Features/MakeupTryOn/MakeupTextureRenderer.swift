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

    static func image(for style: MakeupStyle, features: FaceFeatureMap) -> UIImage? {
        guard features.isPlausible else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Every style is fitted to the measured features; without them it is drawn as designed.
        let fit = FaceFit(features: features)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            for side in features.sides {
                let frame = FeatureFrame(side: side, in: features)
                let sideFit = fit?.side(for: frame)
                switch style {
                case .blush(let blush):
                    draw(sideFit.map { MakeupFitter.blush(blush, side: $0) } ?? blush, frame: frame, in: cg)
                case .eyebrow(let brow):
                    fill(browOutline(brow, brow: side.brow, frame: frame, fit: sideFit), shade: brow.shade,
                         blur: 10, in: cg)
                case .eyeliner(let liner):
                    let fitted = fit.map { MakeupFitter.eyeliner(liner, fit: $0) } ?? liner
                    fill(linerOutline(fitted, eye: side.eye, frame: frame), shade: liner.shade, blur: 2, in: cg)
                }
            }
        }
    }

    /// Opacity drawn into the texture for a shade.
    static func drawnOpacity(_ shade: MakeupShade) -> Double { min(1, shade.opacity / defaultIntensity) }

    // MARK: - Shapes in texture space

    /// Polygon of a brow running from the natural brow's inner end to its (extended) tail.
    /// With `fit`, the start, peak and end move toward the classic guide lines for this face.
    static func browOutline(_ style: BrowStyle, brow: [SIMD2<Float>], frame: FeatureFrame,
                            fit: SideFit? = nil) -> [SIMD2<Float>] {
        guard brow.count >= 2 else { return [] }
        let sorted = brow.sorted { frame.across($0) < frame.across($1) }
        let ends = min(2, sorted.count / 2)
        // The head is blunt, so its top and bottom points are averaged; the tail tapers to its outermost point.
        let naturalHead = sorted.prefix(ends).reduce(.zero, +) / Float(ends)
        let naturalTail = sorted[sorted.count - 1]
        var head = naturalHead, end = naturalTail
        var style = style
        let naturalSpan = frame.across(naturalTail) - frame.across(naturalHead)
        if let fit, naturalSpan > 0 {
            let guides = MakeupFitter.browGuides(side: fit, naturalHead: naturalHead, naturalTail: naturalTail)
            // Points on the natural brow line at a given horizontal position.
            func onBrowLine(_ across: Float) -> SIMD2<Float> {
                naturalHead + (naturalTail - naturalHead) * ((across - frame.across(naturalHead)) / naturalSpan)
            }
            head = onBrowLine(guides.head)
            end = onBrowLine(guides.tail)
            let span = guides.tail - guides.head
            if span > 0 {
                // The guide line sets the peak; the style shifts it a little for its face shape.
                let guided = (guides.peak - guides.head) / span + (style.archPosition - 0.62) * 0.5
                style.archPosition = min(max(guided, 0.35), 0.85)
            }
        }
        let length = simd_distance(head, end)
        guard length > 0 else { return [] }
        let tail = end + simd_normalize(end - head) * style.tailExtension * length
        let chord = tail - head
        let lift = oriented(perpendicular(chord), toward: frame.up)

        let steps = 32
        let centre = (0...steps).map { step -> SIMD2<Float> in
            let t = Float(step) / Float(steps)
            return head + chord * t + lift * archLift(t, style) * length
        }
        var top: [SIMD2<Float>] = [], bottom: [SIMD2<Float>] = []
        for (step, point) in centre.enumerated() {
            let t = Float(step) / Float(steps)
            let tangent = centre[min(step + 1, steps)] - centre[max(step - 1, 0)]
            let normal = oriented(perpendicular(tangent), toward: frame.up)
            // Full at the head, tapering to a fine tail.
            let half = style.thickness * length * (1 - 0.88 * pow(t, 1.6)) / 2
            top.append(point + normal * half)
            bottom.append(point - normal * half)
        }
        return bottom + top.reversed()
    }

    /// Height of the arch at `t` (0 inner end, 1 tail) as a fraction of the brow length.
    static func archLift(_ t: Float, _ style: BrowStyle) -> Float {
        let peak = min(max(style.archPosition, 0.05), 0.95)
        let angular = t < peak ? t / peak : (1 - t) / (1 - peak)
        let smooth = sin(.pi * (t < peak ? 0.5 * t / peak : 0.5 + 0.5 * (t - peak) / (1 - peak)))
        return style.archHeight * (smooth + (angular - smooth) * style.angularity)
    }

    /// Polygon of a liner along the upper lash line, with an optional wing past the outer corner.
    static func linerOutline(_ style: LinerStyle, eye: [SIMD2<Float>], frame: FeatureFrame) -> [SIMD2<Float>] {
        guard eye.count >= 3,
              let inner = eye.min(by: { frame.across($0) < frame.across($1) }),
              let outer = eye.max(by: { frame.across($0) < frame.across($1) }) else { return [] }
        let axis = outer - inner
        let eyeWidth = simd_length(axis)
        guard eyeWidth > 0 else { return [] }
        let lidNormal = oriented(perpendicular(axis), toward: frame.up)
        let upper = eye.filter { simd_dot($0 - inner, lidNormal) > eyeWidth * 0.02 }
            .sorted { frame.across($0) < frame.across($1) }
        let lid = smoothed([inner] + upper + [outer])

        // Arc length along the lid, 0 at the inner corner and 1 at the outer corner.
        var lengths: [Float] = [0]
        for index in 1..<lid.count { lengths.append(lengths[index - 1] + simd_distance(lid[index - 1], lid[index])) }
        guard let total = lengths.last, total > 0 else { return [] }

        var top: [SIMD2<Float>] = [], bottom: [SIMD2<Float>] = []
        for (index, point) in lid.enumerated() {
            let s = lengths[index] / total
            guard s >= style.start else { continue }
            let progress = style.start < 1 ? (s - style.start) / (1 - style.start) : 1
            let taper = min(1, 0.2 + progress * 5)
            let width = (style.innerWidth + (style.outerWidth - style.innerWidth) * progress) * eyeWidth * taper
            let tangent = lid[min(index + 1, lid.count - 1)] - lid[max(index - 1, 0)]
            let normal = oriented(perpendicular(tangent), toward: frame.up)
            // Mostly above the lash line, slightly into it so no skin gap shows.
            top.append(point + normal * width * 0.75)
            bottom.append(point - normal * width * 0.25)
        }
        guard !top.isEmpty else { return [] }

        let direction = simd_normalize(axis)
        let angle = style.wingAngle * .pi / 180
        let wingDirection = direction * cos(angle) + lidNormal * sin(angle)
        let tip = outer + wingDirection * max(style.wingLength, 0.03) * eyeWidth
        return bottom + [tip] + top.reversed()
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

    private static func draw(_ style: BlushStyle, frame: FeatureFrame, in context: CGContext) {
        let center = frame.origin + (frame.outward * style.center.x - frame.up * style.center.y) * frame.unit
        let angle = style.tilt * .pi / 180
        let axis = frame.outward * cos(angle) + frame.up * sin(angle)
        let opacity = drawnOpacity(style.shade)
        let colors = [color(style.shade, opacity: opacity),
                      color(style.shade, opacity: opacity * 0.55),
                      color(style.shade, opacity: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                        locations: [0, 0.5, 1]) else { return }
        context.saveGState()
        context.translateBy(x: cgPoint(center).x, y: cgPoint(center).y)
        context.rotate(by: CGFloat(atan2(axis.y, axis.x)))
        context.scaleBy(x: CGFloat(style.radii.x * frame.unit) * size, y: CGFloat(style.radii.y * frame.unit) * size)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1,
                                   options: [])
        context.restoreGState()
    }
}
