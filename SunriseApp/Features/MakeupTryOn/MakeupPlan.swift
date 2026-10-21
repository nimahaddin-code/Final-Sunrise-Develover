import Foundation

struct ShapeWeight: Hashable, Sendable {
    let shape: FaceShape
    let weight: Double
}

/// Everything the Try On tab offers one person: a "Made for you" style per category, built from their scan,
/// followed by the face shape's catalog styles.
struct MakeupPlan: Hashable, Sendable {
    static let personalPrefix = "personal."

    /// The shape whose catalog styles and reasons are shown.
    let shape: FaceShape
    /// Shapes mixed into the made-for-you styles, strongest first; weights sum to 1.
    let blend: [ShapeWeight]
    /// Grouped by category in `MakeupCategory.allCases` order, made-for-you first in each category.
    let recommendations: [MakeupRecommendation]

    /// - Parameter chosenShape: a shape the user picked instead of the scanned one. The made-for-you styles then
    ///   use only that shape, still tuned to the scanned proportions.
    init(scan: FaceShapeResult, chosenShape: FaceShape? = nil) {
        let blend = chosenShape.map { [ShapeWeight(shape: $0, weight: 1)] } ?? Self.blend(of: scan)
        self.init(shape: chosenShape ?? scan.shape, blend: blend, deviation: scan.deviation)
    }

    /// A plan for a shape alone, without scan measurements.
    init(shape: FaceShape) {
        self.init(shape: shape, blend: [ShapeWeight(shape: shape, weight: 1)],
                  deviation: FaceProportions(length: 0, forehead: 0, jaw: 0, chin: 0))
    }

    private init(shape: FaceShape, blend: [ShapeWeight], deviation: FaceProportions) {
        self.shape = shape
        self.blend = blend
        recommendations = MakeupCategory.allCases.flatMap { category in
            [MakeupPersonalizer.recommendation(for: category, blend: blend, deviation: deviation)]
                + MakeupRecommender.recommendations(for: shape, in: category)
        }
    }

    func recommendations(in category: MakeupCategory) -> [MakeupRecommendation] {
        recommendations.filter { $0.category == category }
    }

    var madeForYou: [MakeupRecommendation] { recommendations.filter(Self.isMadeForYou) }

    func reason(for category: MakeupCategory) -> LocalizedStringResource {
        MakeupRecommender.reason(for: shape, category: category)
    }

    static func isMadeForYou(_ recommendation: MakeupRecommendation) -> Bool {
        recommendation.id.hasPrefix(personalPrefix)
    }

    /// Up to three closest shapes scoring at least 10%, renormalised. The top shape is always included.
    static func blend(of scan: FaceShapeResult) -> [ShapeWeight] {
        let ranked = scan.rankedShapes
        let kept = ranked.prefix(3).enumerated().filter { $0.offset == 0 || $0.element.score >= 0.1 }.map(\.element)
        let total = kept.reduce(0) { $0 + $1.score }
        guard total > 0 else { return [ShapeWeight(shape: scan.shape, weight: 1)] }
        return kept.map { ShapeWeight(shape: $0.shape, weight: $0.score / total) }
    }
}

/// Builds the made-for-you styles: the best-match styles of the blended shapes, averaged by weight, then nudged by
/// the measured proportions so two people with the same shape label still get different styles.
enum MakeupPersonalizer {
    /// Relative deviation from the average face that counts as a full-strength adjustment.
    static let fullDeviation: Float = 0.06

    static func recommendation(for category: MakeupCategory, blend: [ShapeWeight],
                               deviation: FaceProportions) -> MakeupRecommendation {
        let styles = blend.compactMap { weight in
            MakeupRecommender.recommendations(for: weight.shape, in: category).first.map { ($0.style, Float(weight.weight)) }
        }
        let shade = styles.first?.0.shade ?? MakeupPalette.shades(for: category)[0]
        let id = MakeupPlan.personalPrefix + category.rawValue + "."
            + blend.map { "\($0.shape.rawValue)\(Int(($0.weight * 100).rounded()))" }.joined(separator: "-")
        switch category {
        case .eyebrow:
            let brows = styles.compactMap { style, weight -> (BrowStyle, Float)? in
                if case .eyebrow(let brow) = style { (brow, weight) } else { nil }
            }
            return MakeupRecommendation(id: id, name: "Made for you",
                detail: "Arch, thickness and length blended from your closest shapes and tuned to your proportions.",
                style: .eyebrow(eyebrow(brows, shade: shade, deviation: deviation)))
        case .blush:
            let blushes = styles.compactMap { style, weight -> (BlushStyle, Float)? in
                if case .blush(let blush) = style { (blush, weight) } else { nil }
            }
            return MakeupRecommendation(id: id, name: "Made for you",
                detail: "Placement and angle blended from your closest shapes and tuned to your proportions.",
                style: .blush(blush(blushes, shade: shade, deviation: deviation)))
        case .eyeliner:
            let liners = styles.compactMap { style, weight -> (LinerStyle, Float)? in
                if case .eyeliner(let liner) = style { (liner, weight) } else { nil }
            }
            return MakeupRecommendation(id: id, name: "Made for you",
                detail: "Line weight and wing blended from your closest shapes and tuned to your proportions.",
                style: .eyeliner(eyeliner(liners, shade: shade, deviation: deviation)))
        }
    }

    /// Deviation scaled to -1...1.
    static func strength(_ deviation: Float) -> Float { min(max(deviation / fullDeviation, -1), 1) }

    static func eyebrow(_ styles: [(BrowStyle, Float)], shade: MakeupShade, deviation: FaceProportions) -> BrowStyle {
        let length = strength(deviation.length), jaw = strength(deviation.jaw), forehead = strength(deviation.forehead)
        return BrowStyle(
            archPosition: mean(styles) { $0.archPosition },
            // A longer face looks balanced with a flatter brow; a shorter one with more lift.
            archHeight: mean(styles) { $0.archHeight } * (1 - 0.35 * length),
            thickness: mean(styles) { $0.thickness } * (1 + 0.1 * max(0, jaw)),
            // A wide jaw or narrow forehead is balanced by a longer brow.
            tailExtension: mean(styles) { $0.tailExtension } + 0.05 * max(0, jaw) + 0.04 * max(0, -forehead),
            angularity: clamp(mean(styles) { $0.angularity } - 0.2 * length, 0, 1),
            shade: shade)
    }

    static func blush(_ styles: [(BlushStyle, Float)], shade: MakeupShade, deviation: FaceProportions) -> BlushStyle {
        let length = strength(deviation.length), jaw = strength(deviation.jaw)
        let center = SIMD2(mean(styles) { $0.center.x }, mean(styles) { $0.center.y })
        let radii = SIMD2(mean(styles) { $0.radii.x }, mean(styles) { $0.radii.y })
        return BlushStyle(
            // A wide jaw is balanced by blush placed higher.
            center: SIMD2(center.x, center.y - 0.05 * max(0, jaw)),
            // A longer face gets a wider, flatter sweep; a shorter one a steeper lift.
            radii: SIMD2(radii.x * (1 + 0.15 * length), radii.y),
            tilt: clamp(mean(styles) { $0.tilt } - 12 * length, -10, 35),
            shade: shade)
    }

    static func eyeliner(_ styles: [(LinerStyle, Float)], shade: MakeupShade, deviation: FaceProportions) -> LinerStyle {
        let length = strength(deviation.length)
        // Numbers are averaged; flags and enums come from the strongest-weighted style.
        let lead = styles.max { $0.1 < $1.1 }?.0
        // The mid width only exists when at least one style has one; the others contribute their own taper midpoint.
        let hasMid = styles.contains { $0.0.midWidth != nil }
        return LinerStyle(
            innerWidth: mean(styles) { $0.innerWidth },
            outerWidth: mean(styles) { $0.outerWidth },
            midWidth: hasMid ? mean(styles) { $0.midWidth ?? ($0.innerWidth + $0.outerWidth) / 2 } : nil,
            start: mean(styles) { $0.start },
            // A shorter face benefits from a longer, more lifted wing.
            wingLength: max(0, mean(styles) { $0.wingLength } * (1 - 0.3 * length)),
            wingAngle: clamp(mean(styles) { $0.wingAngle } - 5 * length, 0, 40),
            wingOrigin: lead?.wingOrigin ?? .outerCorner,
            wingBase: lead?.wingBase ?? .horizontal,
            wingTargetsBrowTail: lead?.wingTargetsBrowTail ?? false,
            tightline: lead?.tightline ?? false,
            lowerLine: LowerLine(enabled: lead?.lowerLine.enabled ?? false,
                                 extent: mean(styles) { $0.lowerLine.extent },
                                 thickness: mean(styles) { $0.lowerLine.thickness }),
            shade: shade)
    }

    private static func mean<Style>(_ styles: [(Style, Float)], _ value: (Style) -> Float) -> Float {
        let total = styles.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return 0 }
        return styles.reduce(0) { $0 + value($1.0) * $1.1 } / total
    }

    private static func clamp(_ value: Float, _ low: Float, _ high: Float) -> Float { min(max(value, low), high) }
}
