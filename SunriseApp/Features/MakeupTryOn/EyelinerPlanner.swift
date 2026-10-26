import Foundation

/// The eyeliner chosen for one person's eyes, with the reasons.
struct EyelinerPlan: Sendable {
    /// Shapes mixed into `style`, strongest first; weights sum to 1. Empty when the neutral line is used.
    let blend: [(shape: EyeShape, weight: Float)]
    let style: LinerStyle
    /// True when the reading was missing or not trustworthy and the natural line is used (R7).
    let isNeutral: Bool
    /// True when the wing was removed for wide-set eyes (R4).
    let wingRemoved: Bool

    var primary: EyeShape? { blend.first?.shape }

    /// One line under the category: why this liner.
    var reason: LocalizedStringResource {
        if isNeutral { return "Your eye shape is not clear enough to pick a bolder line, so a thin natural line is used." }
        return "Chosen from your eye shape, not your face shape."
    }

    /// Why the made-for-you liner looks the way it does on these eyes.
    var notes: [LocalizedStringResource] {
        if isNeutral {
            return ["Your eyes could not be measured clearly, so this is a thin natural line. Scan again with your eyes relaxed and open for a tailored liner."]
        }
        var notes = blend.map { Self.note(for: $0.shape) }
        if wingRemoved { notes.append("Wide-set eyes look balanced without a wing, so the liner stops at the outer corner.") }
        return notes
    }

    private static func note(for shape: EyeShape) -> LocalizedStringResource {
        switch shape {
        case .almond: "Your eyes are almond-shaped, so the liner follows the natural curve and builds toward a small flick."
        case .round: "Your eyes are round, so the liner starts a little in from the inner corner and lengthens the outer corner."
        case .hooded: "You said your lids are hooded, so the line stays thin and the wing is small and lifted."
        case .monolid: "You said your lids are monolid, so the line is thicker toward the outer end to stay visible with your eyes open."
        case .upturned: "Your eyes lift at the outer corners, so the wing stays short and level."
        case .downturned: "Your outer corners sit low, so the wing follows your lower lash line toward the end of your brow."
        case .closeSet: "Your eyes are close-set, so the inner corner stays light and the liner builds toward the outer end."
        case .wideSet: "Your eyes are wide-set, so the liner is strongest at the inner corner."
        }
    }
}

/// The two eyeliner looks offered on Try On (a third state, no liner, is the tool being off).
enum LinerLook: String, CaseIterable, Identifiable, Sendable {
    /// A clean line along the upper lash line that ends at the outer corner, no wing.
    case lineOnly
    /// The same line with the pointed wing from the reference sheet.
    case winged

    var id: String { rawValue }
    var title: LocalizedStringResource { self == .lineOnly ? "Liner only" : "With wing" }
}

/// Picks one liner per eye shape from the research (`Docs/Research/makeup_placement_rules.json`, `eye_shape`) and
/// combines the strongest two with its `blend_rules` and `combination_rules`.
///
/// Every number is an ESTIMATE: the research is qualitative. Where the eyeliner spike's numbers disagreed with the
/// research, the research wins (e.g. the downturned wing follows the lower lash line with no extra angle).
/// TODO(R3): a thick wing (monolid, hooded) pairs with medium brows; not applied yet because brows are chosen separately.
enum EyelinerPlanner {
    /// Wide-set eyes lose their wing when wide-set is the primary shape or scores at least `EyeScan.strongScore` (R4).
    static func plan(for eyes: EyeScan?) -> EyelinerPlan {
        guard let eyes, !eyes.isLowConfidence else { return neutralPlan }
        let top = Array(eyes.ranked.prefix(2))
        guard !top.isEmpty else { return neutralPlan }
        let total = top.reduce(0) { $0 + $1.weighted }
        let blend = top.map { (shape: $0.shape, weight: $0.weighted / total) }
        var style = combine(blend)
        let scores = eyes.scores
        let removesWing = blend.first?.shape == .wideSet || (scores[.wideSet] ?? 0) >= EyeScan.strongScore
        if removesWing {
            style.wingLength = 0
            style.wingAngle = 0
        }
        return EyelinerPlan(blend: blend, style: style, isNeutral: false, wingRemoved: removesWing)
    }

    /// `base` (the fitted liner) drawn as `look`. Line only has no wing at all. Winged keeps the fitted wing, but a
    /// fitted style with a short or no wing (wide-set, neutral) gets the classic cat-eye wing of the reference sheet,
    /// so the two looks always differ clearly.
    static func style(_ base: LinerStyle, look: LinerLook) -> LinerStyle {
        var style = base
        switch look {
        case .lineOnly:
            style.wingLength = 0
            style.wingAngle = 0
        case .winged:
            let classic = variant(for: .almond)
            if style.wingLength < classic.wingLength {
                style.wingLength = classic.wingLength
                style.wingAngle = classic.wingAngle
                style.wingBase = classic.wingBase
                style.wingOrigin = classic.wingOrigin
            }
            // Reference wings run sideways from the outer corner with only a slight lift, never steeply upward.
            style.wingBase = .horizontal
            style.wingTargetsBrowTail = false
            style.wingAngle = min(max(style.wingAngle, 6), 10)
            // The wing grows out of the line, so the outer end must be thick enough to carry it.
            style.outerWidth = max(style.outerWidth, classic.outerWidth)
        }
        return style
    }

    static var neutralPlan: EyelinerPlan {
        EyelinerPlan(blend: [], style: naturalLine, isNeutral: true, wingRemoved: false)
    }

    /// Continuous values are the weighted mean of the blended shapes; flags and enums come from the primary one.
    static func combine(_ blend: [(shape: EyeShape, weight: Float)]) -> LinerStyle {
        let styles = blend.map { (style: variant(for: $0.shape), weight: $0.weight) }
        guard let lead = styles.first?.style else { return naturalLine }
        func mean(_ value: (LinerStyle) -> Float) -> Float { styles.reduce(0) { $0 + value($1.style) * $1.weight } }
        // The lower line's extent only averages over the shapes that have one; its thickness fades with the others.
        let lowerWeight = styles.filter(\.style.lowerLine.enabled).reduce(0) { $0 + $1.weight }
        let lowerExtent = lowerWeight > 0
            ? styles.filter(\.style.lowerLine.enabled).reduce(0) { $0 + $1.style.lowerLine.extent * $1.weight } / lowerWeight
            : lead.lowerLine.extent
        return LinerStyle(
            innerWidth: mean(\.innerWidth), outerWidth: mean(\.outerWidth),
            midWidth: mean { $0.midWidth ?? ($0.innerWidth + $0.outerWidth) / 2 },
            start: mean(\.start), wingLength: mean(\.wingLength), wingAngle: mean(\.wingAngle),
            wingOrigin: lead.wingOrigin, wingBase: lead.wingBase, wingTargetsBrowTail: lead.wingTargetsBrowTail,
            tightline: lead.tightline,
            lowerLine: LowerLine(enabled: lead.lowerLine.enabled, extent: lowerExtent,
                                 thickness: mean { $0.lowerLine.enabled ? $0.lowerLine.thickness : 0 }),
            shade: lead.shade)
    }

    // MARK: - Catalog

    /// The liner for an eye shape. Widths and lengths are fractions of the eye width; angles are in degrees from the
    /// wing base (the extension of the lower lash line unless noted).
    static func variant(for shape: EyeShape) -> LinerStyle {
        let black = MakeupPalette.black
        switch shape {
        case .almond:
            // Follows the natural lash line from the inner corner, small flick, light lower line.
            return LinerStyle(innerWidth: 0.010, outerWidth: 0.036, midWidth: 0.022, start: 0, wingLength: 0.26,
                              wingAngle: 14, wingBase: .lowerLidTangent,
                              lowerLine: LowerLine(enabled: true, extent: 0.5, thickness: 0.010), shade: black)
        case .round:
            // Starts a little in from the inner corner, thickens toward a medium wing, light lower line.
            return LinerStyle(innerWidth: 0.008, outerWidth: 0.030, midWidth: 0.012, start: 0.08, wingLength: 0.32,
                              wingAngle: 12, wingBase: .lowerLidTangent,
                              lowerLine: LowerLine(enabled: true, extent: 0.67, thickness: 0.010), shade: black)
        case .hooded:
            // Thin line with a small lifted wing; the tightline is modelled but not drawn.
            return LinerStyle(innerWidth: 0.006, outerWidth: 0.032, midWidth: 0.012, start: 0, wingLength: 0.24,
                              wingAngle: 18, wingBase: .lowerLidTangent, tightline: true,
                              lowerLine: LowerLine(enabled: true, extent: 0.33, thickness: 0.014), shade: black)
        case .monolid:
            // Thicker toward the outer end so it does not vanish with the eyes open; the wing extends and lifts.
            return LinerStyle(innerWidth: 0.014, outerWidth: 0.045, midWidth: 0.030, start: 0, wingLength: 0.32,
                              wingAngle: 14, wingBase: .lowerLidTangent, shade: black)
        case .upturned:
            // Full upper line, short level wing, lower liner on the outer half.
            return LinerStyle(innerWidth: 0.008, outerWidth: 0.018, midWidth: 0.012, start: 0, wingLength: 0.20,
                              wingAngle: 6, wingBase: .horizontal,
                              lowerLine: LowerLine(enabled: true, extent: 0.5, thickness: 0.012), shade: black)
        case .downturned:
            // Inner corner left open, wing follows the lower lash line toward the brow tail with no extra lift.
            return LinerStyle(innerWidth: 0.008, outerWidth: 0.034, midWidth: 0.018, start: 0.10, wingLength: 0.28,
                              wingAngle: 18, wingBase: .lowerLidTangent, shade: black)
        case .closeSet:
            // Very thin from the inner corner, thickest at the outer end, tapered wing in line with the brow tail.
            return LinerStyle(innerWidth: 0.004, outerWidth: 0.034, midWidth: 0.008, start: 0, wingLength: 0.34,
                              wingAngle: 6, wingBase: .horizontal, wingTargetsBrowTail: true, shade: black)
        case .wideSet:
            // Strongest at the inner corner, thinning outward, no wing.
            return LinerStyle(innerWidth: 0.028, outerWidth: 0.010, midWidth: 0.020, start: 0, wingLength: 0,
                              wingAngle: 0, wingBase: .lowerLidTangent, shade: black)
        }
    }

    /// Thin, even line along the upper lash line; used when the eyes could not be read (R7).
    static var naturalLine: LinerStyle {
        LinerStyle(innerWidth: 0.012, outerWidth: 0.016, midWidth: 0.014, start: 0, wingLength: 0, wingAngle: 0,
                   wingBase: .lowerLidTangent, shade: MakeupPalette.brown)
    }

    /// The nine liners offered next to "Made for you": one per eye shape, then the neutral natural line.
    static var catalog: [MakeupRecommendation] {
        EyeShape.allCases.map { shape in
            MakeupRecommendation(id: "liner.eye.\(shape.rawValue)", name: shape.title, detail: shape.summary,
                                 style: .eyeliner(variant(for: shape)))
        } + [MakeupRecommendation(id: "liner.eye.neutral", name: "Natural line",
                                  detail: "Thin, even line along the upper lash line, no wing.",
                                  style: .eyeliner(naturalLine))]
    }
}
