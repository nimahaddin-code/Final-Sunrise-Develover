// MediaPipe brow path: the selected style drawn along the observed brow, from the same rule fields as
// EyebrowGuideGenerator. No mesh: everything is in brow-local coordinates.
import Foundation
import simd

/// The designed brow for one style. `u` runs from the brow head (0) to its tail (1) along the observed centerline,
/// and offsets across it are fractions of the observed brow width, positive towards the forehead.
struct BrowDesign: Equatable, Sendable {
    static let sampleCount = 41
    /// The rule limits displacement in metres on the ARKit mesh. MediaPipe landmarks have no metric scale, so the
    /// limit is taken relative to a nominal adult brow width.
    static let nominalBrowWidthMeters: Float = 0.05
    let style: EyebrowStyle
    /// (u, centre offset, half thickness, t) per sample, head to tail.
    let points: [SIMD4<Float>]
    let maxAlpha: Float
    let headFade: Float
    let edgeFeather: Float

    static func make(style: EyebrowStyle) -> BrowDesign? {
        guard let rule = MakeupRuleDatabase.brow(style) else { return nil }
        let peak = rule.number("arch_t"), limit = rule.number("max_displacement") / nominalBrowWidthMeters
        // The observed centerline is the baseline (offset 0); the style only moves the brow off it.
        func adjusted(_ t: Float) -> SIMD2<Float> {
            let phase = t <= peak ? t / max(peak, 0.0001) : (1 - t) / max(1 - peak, 0.0001)
            let bump = phase * phase * (3 - 2 * phase)
            let shift = rule.number("arch_delta") * bump + rule.number("tail_delta") * t
            return SIMD2(t, max(-limit, min(limit, shift)))
        }
        func tangent(_ t: Float) -> SIMD2<Float> {
            let lo = max(0, t - 0.001), hi = min(1, t + 0.001)
            return (adjusted(hi) - adjusted(lo)) / (hi - lo)
        }
        // Two cubic segments keep the measured head and tail and the selected arch continuous.
        let params = MakeupRuleDatabase.shared?.runtime_fitting_rules.parameters
        func intended(_ t: Float) -> SIMD2<Float> {
            let start: Float = t <= peak ? 0 : peak, end: Float = t <= peak ? peak : 1
            let fraction = (t - start) / (end - start), span = end - start
            let h0 = params?[start == 0 ? "brow_handle_head" : "brow_handle_arch"]?.value ?? 0.33
            let h1 = params?[end == 1 ? "brow_handle_tail" : "brow_handle_arch"]?.value ?? 0.33
            let p0 = adjusted(start), p3 = adjusted(end)
            let p1 = p0 + tangent(start) * span * h0, p2 = p3 - tangent(end) * span * h1
            let v = 1 - fraction
            let p = p0 * (v * v * v) + p1 * (3 * v * v * fraction) + p2 * (3 * v * fraction * fraction) + p3 * (fraction * fraction * fraction)
            return SIMD2(p.x, max(-limit, min(limit, p.y)))
        }
        let head = rule.number("head_taper"), tail = rule.number("tail_taper")
        let thickness = rule.number("half_thickness_design") * rule.number("thickness_scale")
        let points = (0..<sampleCount).map { i -> SIMD4<Float> in
            let t = Float(i) / Float(sampleCount - 1)
            let taper = t <= peak ? head + (1 - head) * t / peak : 1 + (tail - 1) * (t - peak) / (1 - peak)
            let p = intended(t)
            return SIMD4(p.x, p.y, thickness * taper, t)
        }
        return BrowDesign(style: style, points: points, maxAlpha: rule.number("max_alpha"),
                          headFade: rule.number("head_fade_extent"), edgeFeather: rule.number("edge_feather"))
    }
}
