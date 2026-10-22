// -Nimah: Style mengubah geometry guide; bukan hanya judul pada UI.
import Foundation

enum EyebrowStyle: String, CaseIterable, Identifiable, Sendable {
    case straight, softArch, highArch, feathered, natural, lifted, angular, rounded, lowArch, thin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .straight: return "Straight"
        case .softArch: return "Soft Arch"
        case .highArch: return "High Arch"
        case .feathered: return "Feathered"
        case .natural:return "Natural"
        case .lifted:return "Upward brow"
        case .angular:return "Defined angle"
        case .rounded:return "Rounded curve"
        case .lowArch:return "Low arch"
        case .thin:return "Thin brow"
        }
    }
    var archRatio: Float {
        switch self { case .straight: return 0.025; case .softArch: return 0.13; case .highArch: return 0.24; case .feathered: return 0.16; case .natural:return 0.10; case .lifted:return 0.04; case .angular:return 0.20; case .rounded:return 0.14; case .lowArch:return 0.06; case .thin:return 0.08 }
    }
}
enum EyebrowGuideMode: String, CaseIterable, Identifiable, Sendable {
    case dots, dashed, both
    var id: String { rawValue }
    var title: String { switch self { case .dots: return "Dots"; case .dashed: return "Dashed"; case .both: return "Both" } }
}
struct EyebrowConfiguration: Equatable, Sendable {
    // -Nimah: Region/style selection untuk dua modul pada shared tracking pipeline.
    var region:FaceGuideRegion = .eyebrows
    var foreheadStyle:ForeheadStyle = .hairline
    var foreheadHeight:Float = 0.8
    var blushStyle:BlushPlacementStyle = .apple
    var tutorialStep:Int? = nil
    var showMappingFormula=false
    var showTrackingPoints=false
    var showAllRegions=false
    var style: EyebrowStyle = .straight
    var mode: EyebrowGuideMode = .dashed
    var showGuide = true
    // -Nimah: Before hides every guide/effect; After is a live simulation.
    var previewAfter = true
    var previewIntensity:Float = 0.65
    var showMakeupPreview = false
    var debugMesh = false
}
