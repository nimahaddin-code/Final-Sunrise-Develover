// -Nimah: Style mengubah geometry guide; bukan hanya judul pada UI.
import Foundation

/// The brow shapes offered in try-on, in picker order. Their geometry comes from the matching `brow.*` preset in
/// makeup-reference.database.json (see `MakeupRuleDatabase.browID`).
enum EyebrowStyle: String, CaseIterable, Identifiable, Sendable {
    case boldArch, slimArch, softNatural, flatStraight, curvedArch, peakedAngle, slimStraight, fullArch, boldStraight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .boldArch: return String(localized: "Bold arch")
        case .slimArch: return String(localized: "Slim arch")
        case .softNatural: return String(localized: "Soft natural")
        case .flatStraight: return String(localized: "Flat straight")
        case .curvedArch: return String(localized: "Curved arch")
        case .peakedAngle: return String(localized: "Peaked angle")
        case .slimStraight: return String(localized: "Slim straight")
        case .fullArch: return String(localized: "Full arch")
        case .boldStraight: return String(localized: "Bold straight")
        }
    }
    /// Arch height of the mesh guide's generic target curve, as a fraction of brow width.
    var archRatio: Float {
        switch self {
        case .boldArch: return 0.20; case .slimArch: return 0.14; case .softNatural: return 0.10
        case .flatStraight: return 0.025; case .curvedArch: return 0.18; case .peakedAngle: return 0.20
        case .slimStraight: return 0.05; case .fullArch: return 0.24; case .boldStraight: return 0.04
        }
    }
}
enum EyebrowGuideMode: String, CaseIterable, Identifiable, Sendable {
    case dots, dashed, both
    var id: String { rawValue }
    var title: String { switch self { case .dots: return "Dots"; case .dashed: return "Dashed"; case .both: return "Both" } }
}
/// One makeup layer in the layered preview (home screen), where eyebrow and blush can show together.
struct PreviewLayer: Equatable, Sendable {
    var on = false
    var intensity: Float = 0.85
    var tint: SIMD3<Float>? = nil
}

struct EyebrowConfiguration: Equatable, Sendable {
    var comparisonSplit=false
    // -Nimah: Region/style selection untuk dua modul pada shared tracking pipeline.
    var region:FaceGuideRegion = .eyebrows
    var foreheadStyle:ForeheadStyle = .hairline
    var foreheadHeight:Float = 0.8
    var blushStyle:BlushPlacementStyle = .apple
    var tutorialStep:Int? = nil
    var showMappingFormula=false
    var showTrackingPoints=false
    var showAllRegions=false
    var style: EyebrowStyle = .softNatural
    var mode: EyebrowGuideMode = .dashed
    var showGuide = true
    // -Nimah: Before hides every guide/effect; After is a live simulation.
    var previewAfter = true
    var previewIntensity:Float = 0.85
    // Optional shade (RGB 0...1) for the brow/blush preview; nil keeps the built-in tint.
    var shadeTint:SIMD3<Float>? = nil
    // Layered preview: brow and blush are drawn together from these layers, and `region` is ignored.
    // -Nimah: Saved launch fitting replaces the old per-feature calibration flow.
    var usesLaunchFit=false
    var layered = false
    var browLayer = PreviewLayer()
    var blushLayer = PreviewLayer()
    var needsBrow: Bool { layered ? browLayer.on : (region == .eyebrows || showAllRegions) }
    var needsBlush: Bool { layered ? blushLayer.on : region == .blush }
    var showMakeupPreview = false
    var debugMesh = false
    /// While on, the eyebrow tool shows MediaPipe's tracking (every landmark, the brow points and contours, the fitted
    /// centerline and brow frame) instead of a brow shape, and the shape picker is hidden. The shapes stay in the app.
    static let showsBrowTracking = true
    /// Tracking view: every landmark, contour, line and label MediaPipe tracking draws, plus its readout.
    var browTrackingOverlay = EyebrowConfiguration.showsBrowTracking
    /// Hides the user's own eyebrow: hair between the tracked upper and lower brow contours is replaced by skin.
    var hideNaturalBrow = false
    /// A brow picture drawn over the (hidden) natural brow; nil draws no brow shape at all.
    var browOverlay: BrowOverlay? = nil
}
