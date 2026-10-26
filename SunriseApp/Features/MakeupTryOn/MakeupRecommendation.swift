import Foundation

enum MakeupCategory: String, CaseIterable, Identifiable, Sendable {
    case eyebrow, blush, eyeliner

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .eyebrow: "Eyebrow"
        case .blush: "Blush"
        case .eyeliner: "Eyeliner"
        }
    }

    var symbol: String {
        switch self {
        case .eyebrow: "eyebrow"
        case .blush: "paintbrush.pointed"
        case .eyeliner: "eye"
        }
    }
}

struct MakeupShade: Identifiable, Hashable, Sendable {
    let id: String
    let name: LocalizedStringResource
    let red: Double
    let green: Double
    let blue: Double
    /// Opacity at the default intensity.
    let opacity: Double

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Shades offered for each category in the live try-on, light to dark.
enum MakeupPalette {
    static func shades(for category: MakeupCategory) -> [MakeupShade] {
        switch category {
        case .eyebrow: databaseShades(category:"eyebrow")
        case .blush: databaseShades(category:"blush")
        case .eyeliner: [brown, plum, navy, black]
        }
    }

    // -Nimah: Chosen JSON palette, decoded once with the geometry rules.
    static func databaseShades(category:String)->[MakeupShade] {
        (MakeupRuleDatabase.shared?.palettes ?? []).filter { $0.category==category }.map {
            MakeupShade(id:$0.id,name:LocalizedStringResource("\($0.name)"),red:$0.color.value[0],green:$0.color.value[1],blue:$0.color.value[2],opacity:1)
        }
    }
    // -Nimah: Approximate sRGB previews inspired by the supplied photos, not measured product colours.
    static let pink = MakeupShade(id:"blush.pink",name:"01 Pink",red:0.91,green:0.29,blue:0.38,opacity:0.36)
    static let winterPink = MakeupShade(id:"blush.winterPink",name:"03 Winter Pink",red:0.89,green:0.48,blue:0.57,opacity:0.36)
    static let mutedMauve = MakeupShade(id:"blush.mutedMauve",name:"04 Muted Mauve",red:0.70,green:0.29,blue:0.40,opacity:0.36)
    static let bistre = MakeupShade(id:"brow.bistre",name:"B201 Bistre",red:0.29,green:0.23,blue:0.19,opacity:0.5)
    static let referenceBrown = MakeupShade(id:"brow.referenceBrown",name:"B202 Brown",red:0.38,green:0.27,blue:0.20,opacity:0.5)
    static let chocolate = MakeupShade(id:"brow.chocolate",name:"B203 Chocolate",red:0.25,green:0.16,blue:0.13,opacity:0.5)
    static let tan = MakeupShade(id:"brow.tan",name:"B204 Tan",red:0.49,green:0.36,blue:0.26,opacity:0.5)

    static let blonde = MakeupShade(id: "brow.blonde", name: "Blonde", red: 0.62, green: 0.48, blue: 0.34, opacity: 0.5)
    static let taupe = MakeupShade(id: "brow.taupe", name: "Taupe", red: 0.42, green: 0.33, blue: 0.27, opacity: 0.55)
    static let softBrown = MakeupShade(id: "brow.softBrown", name: "Soft brown", red: 0.36, green: 0.25, blue: 0.19,
                                       opacity: 0.5)
    static let darkBrown = MakeupShade(id: "brow.darkBrown", name: "Dark brown", red: 0.22, green: 0.15, blue: 0.12,
                                       opacity: 0.5)
    static let softBlack = MakeupShade(id: "brow.softBlack", name: "Soft black", red: 0.12, green: 0.10, blue: 0.10,
                                       opacity: 0.45)

    static let peach = MakeupShade(id: "blush.peach", name: "02 Peach", red: 0.96, green: 0.55, blue: 0.47, opacity: 0.38)
    static let coral = MakeupShade(id: "blush.coral", name: "Coral", red: 0.97, green: 0.47, blue: 0.40, opacity: 0.36)
    static let rose = MakeupShade(id: "blush.rose", name: "Rose", red: 0.86, green: 0.40, blue: 0.48, opacity: 0.36)
    static let mauve = MakeupShade(id: "blush.mauve", name: "Mauve", red: 0.74, green: 0.47, blue: 0.52, opacity: 0.36)
    static let berry = MakeupShade(id: "blush.berry", name: "Berry", red: 0.70, green: 0.27, blue: 0.40, opacity: 0.32)

    static let brown = MakeupShade(id: "liner.brown", name: "Brown", red: 0.25, green: 0.16, blue: 0.12, opacity: 0.85)
    static let plum = MakeupShade(id: "liner.plum", name: "Plum", red: 0.32, green: 0.13, blue: 0.25, opacity: 0.85)
    static let navy = MakeupShade(id: "liner.navy", name: "Navy", red: 0.10, green: 0.14, blue: 0.32, opacity: 0.85)
    static let black = MakeupShade(id: "liner.black", name: "Black", red: 0.08, green: 0.06, blue: 0.07, opacity: 0.9)
}

/// Brow drawn from the natural brow's inner end to its outer end. Lengths are fractions of the natural brow length.
struct BrowStyle: Hashable, Sendable {
    /// Where the arch peaks, as a fraction of the way from the inner end.
    var archPosition: Float
    /// How far the peak lifts above the straight line between the ends.
    var archHeight: Float
    /// Thickness at the inner end; the brow tapers toward the tail.
    var thickness: Float
    /// Length added past the natural tail.
    var tailExtension: Float
    /// 0 is a smooth curve, 1 a sharp peak.
    var angularity: Float
    var shade: MakeupShade
}

/// Blush patch placed relative to the eye centre, in units of the distance between the eye centres.
struct BlushStyle: Hashable, Sendable {
    /// x outward from the nose, y down from the eye centre.
    var center: SIMD2<Float>
    /// Half-width along the tilted axis and half-height across it.
    var radii: SIMD2<Float>
    /// Degrees; positive lifts the outer end toward the temple.
    var tilt: Float
    var shade: MakeupShade
}

/// Where a liner's wing starts.
enum WingOrigin: String, Hashable, Sendable {
    case outerCorner, underLowerLash
}

/// Which direction a liner's wing follows before `wingAngle` is added.
enum WingBase: String, Hashable, Sendable {
    /// The eye's own axis, inner to outer corner.
    case horizontal
    /// The tangent of the lower lash line at the outer corner.
    case lowerLidTangent
}

/// Liner along the lower lash line. Lengths are fractions of the eye width.
struct LowerLine: Hashable, Sendable {
    var enabled = false
    /// Fraction of the lower lash line, measured from the outer corner inward.
    var extent: Float = 0.5
    /// Total width, as `LinerStyle.innerWidth`.
    var thickness: Float = 0.015
}

/// Liner along the upper lash line. Lengths are fractions of the eye width; widths are total widths, drawn mostly
/// above the lash line (see `LinerGeometry.linerAboveFraction`).
struct LinerStyle: Hashable, Sendable {
    var innerWidth: Float
    var outerWidth: Float
    /// Width halfway along the drawn liner; `nil` is the straight taper between inner and outer.
    var midWidth: Float?
    /// Fraction of the lid, from the inner corner, left bare.
    var start: Float
    /// Wing length past the outer corner; 0 means no wing.
    var wingLength: Float
    /// Wing angle above the wing's base direction, in degrees.
    var wingAngle: Float
    var wingOrigin: WingOrigin
    var wingBase: WingBase
    /// Aims the wing partly toward the brow tail.
    var wingTargetsBrowTail: Bool
    /// A thin line on the inner rim of the upper lid. Modelled, but only drawn when
    /// `MakeupTextureRenderer.drawsTightline` is on.
    var tightline: Bool
    var lowerLine: LowerLine
    var shade: MakeupShade

    init(innerWidth: Float, outerWidth: Float, midWidth: Float? = nil, start: Float, wingLength: Float,
         wingAngle: Float, wingOrigin: WingOrigin = .outerCorner, wingBase: WingBase = .horizontal,
         wingTargetsBrowTail: Bool = false, tightline: Bool = false, lowerLine: LowerLine = LowerLine(),
         shade: MakeupShade) {
        self.innerWidth = innerWidth
        self.outerWidth = outerWidth
        self.midWidth = midWidth
        self.start = start
        self.wingLength = wingLength
        self.wingAngle = wingAngle
        self.wingOrigin = wingOrigin
        self.wingBase = wingBase
        self.wingTargetsBrowTail = wingTargetsBrowTail
        self.tightline = tightline
        self.lowerLine = lowerLine
        self.shade = shade
    }
}

enum MakeupStyle: Hashable, Sendable {
    case eyebrow(BrowStyle)
    case blush(BlushStyle)
    case eyeliner(LinerStyle)

    var category: MakeupCategory {
        switch self {
        case .eyebrow: .eyebrow
        case .blush: .blush
        case .eyeliner: .eyeliner
        }
    }

    var shade: MakeupShade {
        switch self {
        case .eyebrow(let brow): brow.shade
        case .blush(let blush): blush.shade
        case .eyeliner(let liner): liner.shade
        }
    }

    func with(shade: MakeupShade) -> MakeupStyle {
        switch self {
        case .eyebrow(var brow): brow.shade = shade; return .eyebrow(brow)
        case .blush(var blush): blush.shade = shade; return .blush(blush)
        case .eyeliner(var liner): liner.shade = shade; return .eyeliner(liner)
        }
    }
}

struct MakeupRecommendation: Identifiable, Hashable, Sendable {
    let id: String
    let name: LocalizedStringResource
    let detail: LocalizedStringResource
    let style: MakeupStyle

    var category: MakeupCategory { style.category }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
