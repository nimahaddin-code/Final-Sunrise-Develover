// -Nimah: Shared, source-aware preferences. Face shape is input, not an invented classifier.
import Foundation

enum MakeupFaceShape:String,CaseIterable,Codable,Identifiable,Sendable {
    case oval,round,square,oblong,rectangle,heart,diamond,pear,unknown
    var id:String { rawValue }
    var title:String {
        switch self {
        case .oval:return "Oval"
        case .round:return "Round / Bulat"
        case .square:return "Square / Persegi"
        case .oblong:return "Oblong / Lonjong"
        case .rectangle:return "Rectangle"
        case .heart:return "Heart / Hati"
        case .diamond:return "Diamond"
        case .pear:return "Triangle / Pear"
        case .unknown:return "Not sure · explore"
        }
    }
}
struct FaceShapeAssessment:Equatable,Sendable {
    enum Origin:String,Sendable { case manual,analysis }
    let shape:MakeupFaceShape
    let origin:Origin
    let confidence:Float?
    init(shape:MakeupFaceShape,origin:Origin = .manual,confidence:Float? = nil) {
        self.shape=shape; self.origin=origin
        self.confidence=confidence.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
    }
    /// With the face/eye scans removed, everyone gets the oval assignment (natural brow, cheekbone blush);
    /// no face shape is shown. `.analysis` makes try-on follow the live-camera fit.
    static let standardLook=FaceShapeAssessment(shape:.oval,origin:.analysis)
}
enum PreferenceEvidence:String,Sendable {
    case stated,visualInterpretation,cheekOnlyInterpretation
    var title:String {
        switch self {
        case .stated:return "From reference"
        case .visualInterpretation:return "Visual interpretation"
        case .cheekOnlyInterpretation:return "Cheeks only · interpretation"
        }
    }
}
struct BrowPreference:Identifiable,Sendable {
    let id:String
    let shape:MakeupFaceShape
    let source:String
    let style:EyebrowStyle
    let evidence:PreferenceEvidence
    var title:String { "\(source) · \(style.title)" }
}
struct BlushPreference:Identifiable,Sendable {
    let id:String
    let shape:MakeupFaceShape
    let source:String
    let style:BlushPlacementStyle
    let evidence:PreferenceEvidence
    var title:String { "\(source) · \(style.title)" }
}
enum MakeupPreferenceCatalog {
    static let brows:[BrowPreference] = [
        .init(id:"brow-oval-a",shape:.oval,source:"A",style:.lifted,evidence:.stated),
        .init(id:"brow-oval-b",shape:.oval,source:"B",style:.softArch,evidence:.visualInterpretation),
        .init(id:"brow-oval-c",shape:.oval,source:"C",style:.natural,evidence:.stated),
        .init(id:"brow-round-a",shape:.round,source:"A",style:.angular,evidence:.stated),
        .init(id:"brow-round-b",shape:.round,source:"B",style:.highArch,evidence:.visualInterpretation),
        .init(id:"brow-round-c",shape:.round,source:"C",style:.highArch,evidence:.stated),
        .init(id:"brow-square-a",shape:.square,source:"A",style:.rounded,evidence:.stated),
        .init(id:"brow-square-b",shape:.square,source:"B",style:.angular,evidence:.visualInterpretation),
        .init(id:"brow-square-c",shape:.square,source:"C",style:.rounded,evidence:.stated),
        .init(id:"brow-oblong-b",shape:.oblong,source:"B",style:.straight,evidence:.visualInterpretation),
        .init(id:"brow-oblong-c",shape:.oblong,source:"C",style:.straight,evidence:.stated),
        .init(id:"brow-heart-b",shape:.heart,source:"B",style:.lowArch,evidence:.visualInterpretation),
        .init(id:"brow-heart-c",shape:.heart,source:"C · inverted triangle",style:.thin,evidence:.stated),
        .init(id:"brow-diamond-a",shape:.diamond,source:"A",style:.softArch,evidence:.stated),
        .init(id:"brow-diamond-b",shape:.diamond,source:"B",style:.softArch,evidence:.visualInterpretation),
        .init(id:"brow-diamond-c",shape:.diamond,source:"C",style:.softArch,evidence:.stated)
    ]
    static let blush:[BlushPreference] = [
        .init(id:"blush-oval-a",shape:.oval,source:"A",style:.outerSweep,evidence:.visualInterpretation),
        .init(id:"blush-oval-b",shape:.oval,source:"B",style:.cheekbone,evidence:.stated),
        .init(id:"blush-oval-c",shape:.oval,source:"C",style:.cheekbone,evidence:.stated),
        .init(id:"blush-oval-d",shape:.oval,source:"D",style:.apple,evidence:.stated),
        .init(id:"blush-round-a",shape:.round,source:"A",style:.apple,evidence:.visualInterpretation),
        .init(id:"blush-round-b",shape:.round,source:"B",style:.cheekbone,evidence:.stated),
        .init(id:"blush-round-c",shape:.round,source:"C",style:.cheekbone,evidence:.stated),
        .init(id:"blush-round-d",shape:.round,source:"D",style:.highLift,evidence:.stated),
        .init(id:"blush-round-e",shape:.round,source:"E",style:.apple,evidence:.cheekOnlyInterpretation),
        .init(id:"blush-square-a",shape:.square,source:"A",style:.placementDots,evidence:.visualInterpretation),
        .init(id:"blush-square-b",shape:.square,source:"B",style:.apple,evidence:.stated),
        .init(id:"blush-square-c",shape:.square,source:"C",style:.apple,evidence:.stated),
        .init(id:"blush-square-d",shape:.square,source:"D",style:.diagonalBlend,evidence:.stated),
        .init(id:"blush-square-e",shape:.square,source:"E",style:.wideHorizontal,evidence:.cheekOnlyInterpretation),
        .init(id:"blush-oblong-b",shape:.oblong,source:"B",style:.wideHorizontal,evidence:.stated),
        .init(id:"blush-oblong-c",shape:.oblong,source:"C",style:.wideHorizontal,evidence:.stated),
        .init(id:"blush-oblong-d",shape:.oblong,source:"D",style:.wideHorizontal,evidence:.stated),
        .init(id:"blush-heart-a",shape:.heart,source:"A",style:.upperInner,evidence:.visualInterpretation),
        .init(id:"blush-heart-b",shape:.heart,source:"B",style:.centerCheek,evidence:.stated),
        .init(id:"blush-heart-c",shape:.heart,source:"C",style:.centerCheek,evidence:.stated),
        .init(id:"blush-heart-d",shape:.heart,source:"D",style:.centerDown,evidence:.stated),
        .init(id:"blush-heart-e",shape:.heart,source:"E · inverted triangle",style:.innerCheek,evidence:.cheekOnlyInterpretation),
        .init(id:"blush-diamond-a",shape:.diamond,source:"A",style:.templeSweep,evidence:.visualInterpretation),
        .init(id:"blush-diamond-e",shape:.diamond,source:"E",style:.templeSweep,evidence:.cheekOnlyInterpretation)
    ]
    // -Nimah: One explicit assignment per covered shape; A/B/C remain source IDs, not user choices.
    // Keep research variants in the catalog for provenance, but never expose the whole catalog as recommendations.
    static let assignedBrowIDs: [MakeupFaceShape:String] = Dictionary(uniqueKeysWithValues: MakeupFaceShape.allCases.compactMap { shape in
        MakeupRuleDatabase.shared?.assignment(shape)?.eyebrow_preset_id.map { (shape,$0) }
    })
    static let assignedBlushIDs: [MakeupFaceShape:String] = Dictionary(uniqueKeysWithValues: MakeupFaceShape.allCases.compactMap { shape in
        MakeupRuleDatabase.shared?.assignment(shape)?.blush_preset_id.map { (shape,$0) }
    })
    static func assignedBrow(for shape:MakeupFaceShape)->BrowPreference? {
        guard let a=MakeupRuleDatabase.shared?.assignment(shape),let id=a.eyebrow_preset_id,
              let historical=brows.first(where: { $0.shape==shape && MakeupRuleDatabase.browID($0.style)==id }) else { return nil }
        let source=a.selected_reference_ids.first(where:{$0.hasPrefix("brow_")})?.replacingOccurrences(of:"brow_",with:"") ?? historical.source
        return .init(id:id,shape:shape,source:source,style:historical.style,evidence:historical.evidence)
    }
    static func assignedBlush(for shape:MakeupFaceShape)->BlushPreference? {
        guard let a=MakeupRuleDatabase.shared?.assignment(shape),let id=a.blush_preset_id,
              let historical=blush.first(where: { $0.shape==shape && MakeupRuleDatabase.blushID($0.style)==id }) else { return nil }
        let source=a.selected_reference_ids.first(where:{$0.hasPrefix("blush_")})?.replacingOccurrences(of:"blush_",with:"") ?? historical.source
        return .init(id:id,shape:shape,source:source,style:historical.style,evidence:historical.evidence)
    }
    static func browOptions(for shape:MakeupFaceShape) -> [BrowPreference] { brows.filter { $0.shape==shape } }
    static func blushOptions(for shape:MakeupFaceShape) -> [BlushPreference] { blush.filter { $0.shape==shape } }
    static func coverageNote(for shape:MakeupFaceShape) -> String {
        switch shape {
        case .rectangle:return "Rectangle is not separated in these references. Explore manually; no shape-specific recommendation is claimed."
        case .pear:return "Pear is not clearly covered. Ambiguous triangle labels are not assigned to this shape. Explore manually."
        case .unknown:return "Choose a face shape for reference options, or explore styles without a recommendation."
        default:return "Reference options are preferences, not a rule. Check the fit on your own face."
        }
    }
}
