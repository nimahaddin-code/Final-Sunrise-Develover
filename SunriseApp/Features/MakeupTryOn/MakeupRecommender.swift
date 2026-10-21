import Foundation

/// Picks eyebrow, blush and eyeliner styles that balance each face shape. Follows common makeup-artist guidance.
enum MakeupRecommender {
    /// Recommendations grouped by category in `MakeupCategory.allCases` order, best match first in each category.
    static func recommendations(for shape: FaceShape) -> [MakeupRecommendation] {
        let (brows, blush, liner): ([MakeupRecommendation], [MakeupRecommendation], [MakeupRecommendation]) =
            switch shape {
            case .oval: ([Brow.softArch, Brow.straight], [Blush.applesToTemples, Blush.apples], [Liner.classicWing, Liner.lashLine])
            case .round: ([Brow.highArch, Brow.angledArch], [Blush.liftedTemples, Blush.highCheekbones], [Liner.catEye, Liner.outerLift])
            case .square: ([Brow.roundedArch, Brow.softArch], [Blush.apples, Blush.applesToTemples], [Liner.softFlick, Liner.classicWing])
            case .oblong: ([Brow.straight, Brow.fullExtended], [Blush.horizontal, Blush.apples], [Liner.horizontal, Liner.lashLine])
            case .heart: ([Brow.roundedArch, Brow.softArch], [Blush.belowCheekbones, Blush.apples], [Liner.softFlick, Liner.lashLine])
            case .diamond: ([Brow.roundedArch, Brow.softArch], [Blush.centered, Blush.apples], [Liner.classicWing, Liner.softFlick])
            case .triangle: ([Brow.fullExtended, Brow.highArch], [Blush.highCheekbones, Blush.liftedTemples], [Liner.outerLift, Liner.catEye])
            }
        return brows + blush + liner + Liner.spikeVariants
    }

    static func recommendations(for shape: FaceShape, in category: MakeupCategory) -> [MakeupRecommendation] {
        recommendations(for: shape).filter { $0.category == category }
    }

    /// Why the category's best match suits the face shape.
    static func reason(for shape: FaceShape, category: MakeupCategory) -> LocalizedStringResource {
        switch (shape, category) {
        case (.oval, .eyebrow): "Balanced faces suit a soft arch that follows the natural brow."
        case (.oval, .blush): "Blush on the apples, lifted slightly, keeps the natural balance."
        case (.oval, .eyeliner): "Almost any liner works; a classic wing adds gentle definition."
        case (.round, .eyebrow): "A higher, defined arch draws the eye up and adds length."
        case (.round, .blush): "Blush placed above the apples and swept to the temples lifts and slims."
        case (.round, .eyeliner): "An elongated wing adds angles and length to soft features."
        case (.square, .eyebrow): "A rounded arch softens a strong, angular jawline."
        case (.square, .blush): "Round blush on the apples softens the angles of the face."
        case (.square, .eyeliner): "A soft, short flick keeps the eyes gentle against a strong jaw."
        case (.oblong, .eyebrow): "Straighter, longer brows make a long face look wider."
        case (.oblong, .blush): "A horizontal sweep across the cheeks adds width."
        case (.oblong, .eyeliner): "Liner extended outward, not upward, widens the eyes."
        case (.heart, .eyebrow): "A rounded, low arch balances a wider forehead."
        case (.heart, .blush): "Blush below the cheekbones, toward the ears, keeps focus off the chin."
        case (.heart, .eyeliner): "A soft flick adds definition without widening the upper face."
        case (.diamond, .eyebrow): "Curved brows soften prominent cheekbones and widen the forehead."
        case (.diamond, .blush): "Blush on the apples, blended inward, softens the cheekbones."
        case (.diamond, .eyeliner): "A classic wing adds width to the narrower upper face."
        case (.triangle, .eyebrow): "Fuller, longer brows widen the forehead to balance the jaw."
        case (.triangle, .blush): "Blush high on the cheekbones draws attention upward."
        case (.triangle, .eyeliner): "An outer-corner lift draws the eye up and away from the jaw."
        }
    }

    // MARK: - Catalog

    private static let taupe = MakeupPalette.taupe
    private static let softBrown = MakeupPalette.softBrown
    private static let peach = MakeupPalette.peach
    private static let rose = MakeupPalette.rose
    private static let coral = MakeupPalette.coral
    private static let berry = MakeupPalette.berry
    private static let black = MakeupPalette.black
    private static let brown = MakeupPalette.brown

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

    private enum Liner {
        static let classicWing = MakeupRecommendation(id: "liner.classicWing", name: "Classic wing",
            detail: "Thin at the inner corner, with a short wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.02, outerWidth: 0.06, start: 0, wingLength: 0.18, wingAngle: 18,
                                        shade: black)))
        static let catEye = MakeupRecommendation(id: "liner.catEye", name: "Elongated cat eye",
            detail: "A bolder line with a long, lifted wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.025, outerWidth: 0.08, start: 0, wingLength: 0.3, wingAngle: 22,
                                        shade: black)))
        static let softFlick = MakeupRecommendation(id: "liner.softFlick", name: "Soft flick",
            detail: "A fine line on the outer lid with a tiny flick.",
            style: .eyeliner(LinerStyle(innerWidth: 0.015, outerWidth: 0.045, start: 0.25, wingLength: 0.1, wingAngle: 25,
                                        shade: brown)))
        static let lashLine = MakeupRecommendation(id: "liner.lashLine", name: "Thin lash line",
            detail: "A fine line hugging the lashes, no wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.015, outerWidth: 0.03, start: 0, wingLength: 0, wingAngle: 0,
                                        shade: brown)))
        static let horizontal = MakeupRecommendation(id: "liner.horizontal", name: "Horizontal extension",
            detail: "Extended straight out past the outer corner.",
            style: .eyeliner(LinerStyle(innerWidth: 0.02, outerWidth: 0.06, start: 0, wingLength: 0.22, wingAngle: 4,
                                        shade: black)))
        static let outerLift = MakeupRecommendation(id: "liner.outerLift", name: "Outer-corner lift",
            detail: "Liner on the outer half, flicked upward.",
            style: .eyeliner(LinerStyle(innerWidth: 0.02, outerWidth: 0.07, start: 0.4, wingLength: 0.16, wingAngle: 30,
                                        shade: black)))

        // The eyeliner spike's variants, so each can be tried on, with the spike's own widths (drawn above the
        // lash line, see `LinerGeometry.linerAboveFraction`).
        static let spikeVariants = [naturalLine, spikeClassicWing, elongatedOuter, liftedFlick, hoodedTightlineWing,
                                    monolidBold, monolidUnderWing, closeSetOutward, upturnedLowerWeighted,
                                    wideSetInnerFocused]

        static let naturalLine = MakeupRecommendation(id: "liner.naturalLine", name: "Natural line",
            detail: "Thin, even line along the upper lash line, no wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.012, outerWidth: 0.016, midWidth: 0.014, start: 0,
                                        wingLength: 0, wingAngle: 0, wingBase: .lowerLidTangent, shade: brown)))
        static let spikeClassicWing = MakeupRecommendation(id: "liner.almondWing", name: "Almond wing",
            detail: "Follows the natural curve, builds toward the outer corner with a small flick.",
            style: .eyeliner(LinerStyle(innerWidth: 0.01, outerWidth: 0.036, midWidth: 0.022, start: 0.05,
                                        wingLength: 0.22, wingAngle: 10, wingBase: .lowerLidTangent, shade: black)))
        static let elongatedOuter = MakeupRecommendation(id: "liner.elongatedOuter", name: "Elongated outer",
            detail: "Concentrated on the outer third and extended outward for a longer look.",
            style: .eyeliner(LinerStyle(innerWidth: 0.01, outerWidth: 0.04, midWidth: 0.018, start: 0.55,
                                        wingLength: 0.38, wingAngle: 4, wingBase: .lowerLidTangent, shade: black)))
        static let liftedFlick = MakeupRecommendation(id: "liner.liftedFlick", name: "Lifted flick",
            detail: "Inner corner left open, thin to thick, with a clearly upward flick.",
            style: .eyeliner(LinerStyle(innerWidth: 0.008, outerWidth: 0.034, midWidth: 0.02, start: 0.1,
                                        wingLength: 0.3, wingAngle: 22, wingBase: .lowerLidTangent, shade: black)))
        static let hoodedTightlineWing = MakeupRecommendation(id: "liner.hoodedTightlineWing",
            name: "Tightline + small wing", detail: "Mostly tightline with a thin start and a small wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.006, outerWidth: 0.02, midWidth: 0.012, start: 0.05,
                                        wingLength: 0.16, wingAngle: 12, wingBase: .lowerLidTangent,
                                        tightline: true, shade: black)))
        static let monolidBold = MakeupRecommendation(id: "liner.monolidBold", name: "Bold lash line",
            detail: "A thicker line along the upper lash line.",
            style: .eyeliner(LinerStyle(innerWidth: 0.02, outerWidth: 0.045, midWidth: 0.032, start: 0,
                                        wingLength: 0.08, wingAngle: 3, wingBase: .lowerLidTangent, shade: black)))
        static let monolidUnderWing = MakeupRecommendation(id: "liner.monolidUnderWing", name: "Under-wing",
            detail: "The wing starts under the lower lash line and extends straight out.",
            style: .eyeliner(LinerStyle(innerWidth: 0.01, outerWidth: 0.018, midWidth: 0.014, start: 0,
                                        wingLength: 0.28, wingAngle: 0, wingOrigin: .underLowerLash,
                                        wingBase: .horizontal, shade: black)))
        static let closeSetOutward = MakeupRecommendation(id: "liner.closeSetOutward", name: "Outward focus",
            detail: "Bare on the inner half, thickest at the outer end, wing aimed at the brow tail.",
            style: .eyeliner(LinerStyle(innerWidth: 0, outerWidth: 0.034, midWidth: 0.008, start: 0.5,
                                        wingLength: 0.28, wingAngle: 0, wingBase: .lowerLidTangent,
                                        wingTargetsBrowTail: true, shade: black)))
        static let upturnedLowerWeighted = MakeupRecommendation(id: "liner.upturnedLowerWeighted",
            name: "Wing + lower liner", detail: "A subtle upper wing with lower liner on the outer half.",
            style: .eyeliner(LinerStyle(innerWidth: 0.008, outerWidth: 0.022, midWidth: 0.014, start: 0,
                                        wingLength: 0.14, wingAngle: 5, wingBase: .lowerLidTangent,
                                        lowerLine: LowerLine(enabled: true, extent: 0.5, thickness: 0.016),
                                        shade: black)))
        static let wideSetInnerFocused = MakeupRecommendation(id: "liner.wideSetInnerFocused",
            name: "Inner focus", detail: "Starts at the inner corner, thinning outward, with a minimal wing.",
            style: .eyeliner(LinerStyle(innerWidth: 0.026, outerWidth: 0.012, midWidth: 0.02, start: 0,
                                        wingLength: 0.06, wingAngle: 2, wingBase: .lowerLidTangent, shade: black)))
    }
}
