import Foundation

/// Picks eyebrow and blush styles that balance each face shape. Follows common makeup-artist guidance.
/// Eyeliner does not depend on the face shape (the research found no consensus); it follows the eye shape, see `EyelinerPlanner`.
enum MakeupRecommender {
    /// Recommendations grouped by category in `MakeupCategory.allCases` order, best match first in each category.
    static func recommendations(for shape: FaceShape) -> [MakeupRecommendation] {
        let (brows, blush): ([MakeupRecommendation], [MakeupRecommendation]) =
            switch shape {
            case .oval: ([Brow.softArch, Brow.straight], [Blush.applesToTemples, Blush.apples])
            case .round: ([Brow.highArch, Brow.angledArch], [Blush.liftedTemples, Blush.highCheekbones])
            case .square: ([Brow.roundedArch, Brow.softArch], [Blush.apples, Blush.applesToTemples])
            case .oblong: ([Brow.straight, Brow.fullExtended], [Blush.horizontal, Blush.apples])
            case .heart: ([Brow.roundedArch, Brow.softArch], [Blush.belowCheekbones, Blush.apples])
            case .diamond: ([Brow.roundedArch, Brow.softArch], [Blush.centered, Blush.apples])
            case .triangle: ([Brow.fullExtended, Brow.highArch], [Blush.highCheekbones, Blush.liftedTemples])
            }
        return brows + blush + EyelinerPlanner.catalog
    }

    static func recommendations(for shape: FaceShape, in category: MakeupCategory) -> [MakeupRecommendation] {
        recommendations(for: shape).filter { $0.category == category }
    }

    /// Why the category's best match suits the face shape.
    static func reason(for shape: FaceShape, category: MakeupCategory) -> LocalizedStringResource {
        switch (shape, category) {
        case (.oval, .eyebrow): "Balanced faces suit a soft arch that follows the natural brow."
        case (.oval, .blush): "Blush on the apples, lifted slightly, keeps the natural balance."
        case (.round, .eyebrow): "A higher, defined arch draws the eye up and adds length."
        case (.round, .blush): "Blush placed above the apples and swept to the temples lifts and slims."
        case (.square, .eyebrow): "A rounded arch softens a strong, angular jawline."
        case (.square, .blush): "Round blush on the apples softens the angles of the face."
        case (.oblong, .eyebrow): "Straighter, longer brows make a long face look wider."
        case (.oblong, .blush): "A horizontal sweep across the cheeks adds width."
        case (.heart, .eyebrow): "A rounded, low arch balances a wider forehead."
        case (.heart, .blush): "Blush below the cheekbones, toward the ears, keeps focus off the chin."
        case (.diamond, .eyebrow): "Curved brows soften prominent cheekbones and widen the forehead."
        case (.diamond, .blush): "Blush on the apples, blended inward, softens the cheekbones."
        case (.triangle, .eyebrow): "Fuller, longer brows widen the forehead to balance the jaw."
        case (.triangle, .blush): "Blush high on the cheekbones draws attention upward."
        case (_, .eyeliner): "Chosen from your eye shape, not your face shape."
        }
    }

    // MARK: - Catalog

    private static let taupe = MakeupPalette.taupe
    private static let softBrown = MakeupPalette.softBrown
    private static let peach = MakeupPalette.peach
    private static let rose = MakeupPalette.rose
    private static let coral = MakeupPalette.coral
    private static let berry = MakeupPalette.berry

    private enum Brow {
        static let softArch = MakeupRecommendation(id: "brow.softArch", name: "Soft arch",
            detail: "A gentle lift two-thirds along the brow.",
            style: .eyebrow(BrowStyle(archPosition: 0.65, archHeight: 0.10, thickness: 0.17, tailExtension: 0.05,
                                      angularity: 0.3, shade: softBrown)))
        static let highArch = MakeupRecommendation(id: "brow.highArch", name: "High arch",
            detail: "A lifted, defined peak that opens up the eyes.",
            style: .eyebrow(BrowStyle(archPosition: 0.65, archHeight: 0.17, thickness: 0.16, tailExtension: 0.05,
                                      angularity: 0.7, shade: taupe)))
        static let angledArch = MakeupRecommendation(id: "brow.angledArch", name: "Angled arch",
            detail: "A sharp peak with a short, clean tail.",
            style: .eyebrow(BrowStyle(archPosition: 0.7, archHeight: 0.14, thickness: 0.16, tailExtension: 0,
                                      angularity: 1, shade: taupe)))
        static let roundedArch = MakeupRecommendation(id: "brow.roundedArch", name: "Rounded arch",
            detail: "A smooth curve with no sharp peak.",
            style: .eyebrow(BrowStyle(archPosition: 0.55, archHeight: 0.11, thickness: 0.17, tailExtension: 0,
                                      angularity: 0, shade: softBrown)))
        static let straight = MakeupRecommendation(id: "brow.straight", name: "Straight brow",
            detail: "A flatter, fuller line with only a hint of arch.",
            style: .eyebrow(BrowStyle(archPosition: 0.6, archHeight: 0.04, thickness: 0.18, tailExtension: 0.1,
                                      angularity: 0.2, shade: softBrown)))
        static let fullExtended = MakeupRecommendation(id: "brow.fullExtended", name: "Full, extended brow",
            detail: "A bolder brow that reaches past the natural tail.",
            style: .eyebrow(BrowStyle(archPosition: 0.6, archHeight: 0.08, thickness: 0.21, tailExtension: 0.14,
                                      angularity: 0.3, shade: taupe)))
    }

    private enum Blush {
        static let apples = MakeupRecommendation(id: "blush.apples", name: "Apples of the cheeks",
            detail: "Round, soft colour on the fullest part of the cheeks.",
            style: .blush(BlushStyle(center: SIMD2(0.05, 0.52), radii: SIMD2(0.26, 0.21), tilt: 0, shade: rose)))
        static let applesToTemples = MakeupRecommendation(id: "blush.applesToTemples", name: "Apples to temples",
            detail: "Starts on the apples and fades lightly toward the temples.",
            style: .blush(BlushStyle(center: SIMD2(0.15, 0.48), radii: SIMD2(0.33, 0.18), tilt: 15, shade: peach)))
        static let liftedTemples = MakeupRecommendation(id: "blush.liftedTemples", name: "Lifted to the temples",
            detail: "Just above the apples, swept up toward the temples.",
            style: .blush(BlushStyle(center: SIMD2(0.3, 0.42), radii: SIMD2(0.36, 0.15), tilt: 28, shade: coral)))
        static let highCheekbones = MakeupRecommendation(id: "blush.highCheekbones", name: "High on the cheekbones",
            detail: "A narrow band high on the cheekbones.",
            style: .blush(BlushStyle(center: SIMD2(0.32, 0.38), radii: SIMD2(0.32, 0.13), tilt: 22, shade: peach)))
        static let horizontal = MakeupRecommendation(id: "blush.horizontal", name: "Horizontal sweep",
            detail: "Blended straight across the cheeks.",
            style: .blush(BlushStyle(center: SIMD2(0.12, 0.5), radii: SIMD2(0.4, 0.16), tilt: 0, shade: rose)))
        static let belowCheekbones = MakeupRecommendation(id: "blush.belowCheekbones", name: "Below the cheekbones",
            detail: "Just under the cheekbones, blended toward the ears.",
            style: .blush(BlushStyle(center: SIMD2(0.36, 0.6), radii: SIMD2(0.34, 0.14), tilt: 15, shade: berry)))
        static let centered = MakeupRecommendation(id: "blush.centered", name: "Blended inward",
            detail: "On the apples, softened toward the nose.",
            style: .blush(BlushStyle(center: SIMD2(-0.02, 0.52), radii: SIMD2(0.24, 0.2), tilt: -5, shade: rose)))
    }
}
