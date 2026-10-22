// -Nimah: Reuse saved face classification and its one assigned reference per category.
import SwiftUI

@MainActor final class EyebrowViewModel:ObservableObject {
    @Published var configuration=EyebrowConfiguration()
    @Published var phase:FaceGuidePhase = .positionFace
    @Published private(set) var stepIndex=0
    @Published private(set) var assessment=FaceShapeAssessment(shape:.unknown)
    @Published private(set) var browPreferenceID:String?
    @Published private(set) var blushPreferenceID:String?
    var browOptions:[BrowPreference] { assessment.origin == .analysis ? MakeupPreferenceCatalog.assignedBrow(for:assessment.shape).map { [$0] } ?? [] : [] }
    var blushOptions:[BlushPreference] { assessment.origin == .analysis ? MakeupPreferenceCatalog.assignedBlush(for:assessment.shape).map { [$0] } ?? [] : [] }
    var selectedBrow:BrowPreference? { browOptions.first { $0.id==browPreferenceID } }
    var selectedBlush:BlushPreference? { blushOptions.first { $0.id==blushPreferenceID } }
    // -Nimah: Missing scan/catalog coverage must not silently render the default configuration.
    var hasRecommendation:Bool {
        switch configuration.region {
        case .eyebrows:return selectedBrow != nil
        case .blush:return selectedBlush != nil
        case .forehead:return true
        }
    }
    var sourceNote:String {
        switch configuration.region {
        case .eyebrows:return selectedBrow.map { "Reference \($0.source) · \($0.evidence.title)" } ?? "No saved recommendation for this face shape"
        case .blush:return selectedBlush.map { "Reference \($0.source) · \($0.evidence.title)" } ?? "No saved recommendation for this face shape"
        case .forehead:return "Forehead placement estimate"
        }
    }
    var lessons:[FaceGuideLesson] {
        if configuration.region == .blush {
            return [.init(title:"Check cheek placement",instruction:configuration.blushStyle.instruction),
                    .init(title:"Apply & blend",instruction:"Use a small amount. Follow the direction arrows when shown, then soften the boundary. The preview is a simulation."),
                    .init(title:"Review",instruction:"Switch to Before to see the original camera. Hide the guide to review your actual makeup. Steps advance manually.")]
        }
        return FaceGuideLesson.steps(region:configuration.region,brow:configuration.style,forehead:configuration.foreheadStyle)
    }
    var title:String {
        switch configuration.region {
        case .eyebrows:return configuration.style.title+" Brow"
        case .blush:return configuration.blushStyle.title
        case .forehead:return configuration.foreheadStyle.title
        }
    }
    var liveConfiguration:EyebrowConfiguration {
        var value=configuration
        value.showTrackingPoints=phase == .tracking && value.showGuide
        value.showAllRegions=phase == .chooseRegion
        value.showGuide=value.showGuide && (phase == .chooseRegion || phase == .chooseStyle || phase == .tutorial)
        value.tutorialStep=phase == .tutorial && value.region == .eyebrows ? stepIndex : nil
        value.showMakeupPreview=(phase == .chooseStyle || phase == .tutorial) && value.previewAfter
        if !value.previewAfter && (phase == .chooseStyle || phase == .tutorial) { value.showGuide=false; value.debugMesh=false; value.showTrackingPoints=false }
        if !hasRecommendation { value.showMakeupPreview=false; value.showGuide=false; value.showAllRegions=false }
        return value
    }
    // -Nimah: Consume Holly/Khalish analysis; manual labels never create scan recommendations.
    func applyAssessment(_ value:FaceShapeAssessment) {
        assessment=value; browPreferenceID=nil; blushPreferenceID=nil
        if let first=browOptions.first { choose(first) } else { configuration.style = .natural }
        if let first=blushOptions.first { choose(first) } else { configuration.blushStyle = .apple }
        stepIndex=0
    }
    func chooseFaceShape(_ shape:MakeupFaceShape) { applyAssessment(.init(shape:shape)); phase = entryRegion == nil ? .chooseRegion : .chooseStyle }
    // -Nimah: A new try explicitly restores visible preview; Before/Hide from the previous try must not silently carry over.
    func restorePreview() {
        configuration.previewAfter=true; configuration.showGuide=true
        if configuration.previewIntensity<=0 { configuration.previewIntensity=0.65 }
    }
    func choose(_ preference:BrowPreference) {
        guard browOptions.contains(where:{ $0.id==preference.id }) else { return }
        restorePreview(); browPreferenceID=preference.id; configuration.style=preference.style
    }
    func choose(_ preference:BlushPreference) {
        guard blushOptions.contains(where:{ $0.id==preference.id }) else { return }
        restorePreview(); blushPreferenceID=preference.id; configuration.blushStyle=preference.style
    }
    // -Nimah: Stale exploration actions cannot override the scan assignment.
    func explore(_ style:EyebrowStyle) {}
    func explore(_ style:BlushPlacementStyle) {}
    func select(_ region:FaceGuideRegion) { restorePreview(); configuration.region=region; phase = .chooseStyle; stepIndex=0 }
    func beginTutorial() { guard hasRecommendation else { return }; stepIndex=0; phase = .tutorial }
    func nextStep() { if stepIndex+1<lessons.count { stepIndex += 1 } else { phase = .chooseStyle; stepIndex=0 } }
    func previousStep() { if stepIndex>0 { stepIndex -= 1 } else { phase = .chooseStyle } }
    func back() {
        switch phase {
        case .tutorial:phase = .chooseStyle
        case .chooseStyle:phase = .chooseRegion
        case .chooseRegion:phase = .chooseFaceShape
        case .chooseFaceShape:phase = .tracking
        case .tracking,.positionFace:phase = .positionFace
        }
    }
    @Published private(set) var availability:FaceTrackingAvailability = .notChecked
    private let checker:any FaceTrackingAvailabilityChecking
    private let entryRegion:FaceGuideRegion?
    // -Nimah: Back from the entry screen returns home instead of walking into old scan screens.
    var backLeavesStudio:Bool {
        switch phase {
        case .tutorial:return false
        case .chooseStyle:return entryRegion != nil
        default:return true
        }
    }
    init(checker:any FaceTrackingAvailabilityChecking,assessment:FaceShapeAssessment? = nil,initialRegion:FaceGuideRegion? = nil,initialShade:MakeupShade? = nil,initialIntensity:Double? = nil,startTutorial:Bool = false) {
        self.checker=checker; self.entryRegion=initialRegion
        if let assessment { applyAssessment(assessment) }
        if let initialRegion { configuration.region=initialRegion }
        // -Nimah: Preserve the coloured try-on when opening its tutorial.
        if let shade=initialShade { configuration.shadeTint=SIMD3(Float(shade.red),Float(shade.green),Float(shade.blue)) }
        if let intensity=initialIntensity,intensity.isFinite { configuration.previewIntensity=Float(min(max(intensity,0),1)) }
        // -Nimah: Reuse onboarding analysis and enter preview directly, without another scan flow.
        if assessment != nil { phase=initialRegion == nil ? .chooseRegion : .chooseStyle }
        if startTutorial { beginTutorial() }
    }
    // -Nimah: Face-shape classification is reused; eye/brow fitting remains a separate live calibration.
    func nextAfterScan() {
        if assessment.origin == .analysis { phase=entryRegion == nil ? .chooseRegion : .chooseStyle }
        else { phase = .chooseFaceShape }
    }
    func prepare() async { availability=await checker.availability() }
    func trackingState(camera:FaceCameraState) -> FaceTrackingState {
        if case .unsupported=availability { return .unsupported }
        if camera.denied { return .denied }
        if camera.tracked { return .detected }
        return camera.eyebrowWasTracked ? .lost : .searching
    }
}
