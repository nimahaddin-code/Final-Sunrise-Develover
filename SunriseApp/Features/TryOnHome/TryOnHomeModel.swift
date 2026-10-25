import ARKit
import SwiftUI

/// The three makeup tools on the Try On home screen.
enum TryOnTool: CaseIterable, Identifiable, Hashable {
    case blush, eyeliner, eyebrow

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .blush: "Blush"
        case .eyeliner: "Eyeliner"
        case .eyebrow: "Eyebrow"
        }
    }

    var symbol: String {
        switch self {
        case .blush: "paintbrush.pointed"
        case .eyeliner: "eye"
        case .eyebrow: "eyebrow"
        }
    }

    var category: MakeupCategory {
        switch self {
        case .blush: .blush
        case .eyeliner: .eyeliner
        case .eyebrow: .eyebrow
        }
    }
}

extension MakeupShade {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

// -Nimah: Budget overlay work, not camera tracking; no backlog and recover from a new session clock.
struct LiveOverlayBudget {
    private var last:TimeInterval?
    mutating func accepts(_ timestamp:TimeInterval)->Bool {
        guard timestamp.isFinite else { return false }
        if let last,timestamp>=last,timestamp-last<1.0/30.0-0.000001 { return false }
        last=timestamp;return true
    }
}

/// Hands ARKit frames from the shared camera session to the eyeliner overlay. Frames that arrive while the previous one
/// is still being handed over are dropped, so ARKit never waits on the main thread.
final class LinerFrameRelay: @unchecked Sendable {
    private struct Box: @unchecked Sendable { let frame: ARFrame; let face: ARFaceAnchor }
    private let lock = NSLock()
    private var pending = false
    private var isEnabled = false
    private var budget=LiveOverlayBudget()
    private weak var model: LinerOverlayModel?

    @MainActor init(model: LinerOverlayModel) { self.model = model }

    /// Frames are only handed over while the eyeliner is on; otherwise 60 main-thread hops a second would do nothing.
    func setEnabled(_ value: Bool) { lock.lock(); isEnabled = value; lock.unlock() }

    func deliver(_ frame: ARFrame, _ face: ARFaceAnchor) {
        lock.lock()
        if pending || !isEnabled || !budget.accepts(frame.timestamp) { lock.unlock(); return }
        pending = true
        lock.unlock()
        let box = Box(frame: frame, face: face)
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { model?.submit(box.frame, face: box.face) }
            lock.lock(); pending = false; lock.unlock()
        }
    }
}

/// Drives the Try On home screen. There is one camera: Nimah's ARKit face session (`LiveGuideView`) draws blush and
/// eyebrow on the face mesh, and the same frames feed Hanum's eyeliner overlay (`LinerOverlayModel`) drawn on top.
/// Each tool has its own on/off state, shade and intensity, so the looks can be switched on and off together.
@MainActor final class TryOnHomeModel: ObservableObject {
    // -Nimah: Start with a clearly visible simulation; the slider can soften it.
    static let defaultIntensity = 0.85

    /// The tool the shade row and intensity bar currently control.
    @Published private(set) var tool: TryOnTool = .blush
    @Published private(set) var enabled: Set<TryOnTool> = Set(TryOnTool.allCases)
    @Published private(set) var shades: [TryOnTool: MakeupShade]
    /// Colours picked from a product photo, kept per tool so they stay in the shade row after another swatch is chosen.
    @Published private(set) var customShades: [TryOnTool: [MakeupShade]] = [:]
    static let maxCustomShades = 3
    @Published private(set) var intensities: [TryOnTool: Double]
    /// Held down on the camera card to see the bare face.
    @Published var isComparing = false

    /// Blush/eyebrow style choices and availability; its configuration is only used as the base for the live preview.
    let brow: EyebrowViewModel
    let camera = FaceCameraState()
    let liner = LinerOverlayModel()
    let relay: LinerFrameRelay
    // -Nimah: Refresh assignments after a rescan; no camera/model recreation is needed.
    @Published private(set) var hasLaunchFit:Bool
    private var linerStyle: LinerStyle?
    private var linerIsNeutral = true
    @Published private(set) var linerRecommendation: MakeupRecommendation?
    private var activation: Task<Void,Never>?
    private var active = false
    private var hasAppliedAnalysis=false
    private var appliedFace:FaceShapeResult?
    private var appliedEyes:EyeShapeResult?

    init(plan: MakeupPlan, assessment: FaceShapeAssessment, checker: any FaceTrackingAvailabilityChecking,hasLaunchFit:Bool? = nil) {
        self.hasLaunchFit=hasLaunchFit ?? LaunchMakeupFit.shared.hasFit
        let recommendation = plan.madeForYou.first { $0.category == .eyeliner }
        // A thin natural line is used when the eye scan is missing or unclear, so the colour can still be tried.
        linerIsNeutral = plan.eyeliner.isNeutral
        if case .eyeliner(let style)? = recommendation?.style { linerStyle = style; linerRecommendation = recommendation } else { linerStyle = nil }
        brow = EyebrowViewModel(checker: checker, assessment: assessment, initialRegion: .blush)
        relay = LinerFrameRelay(model: liner)
        shades = [.blush: MakeupPalette.pink, .eyebrow: MakeupPalette.referenceBrown,
                  .eyeliner: recommendation?.style.shade ?? MakeupPalette.brown]
        intensities = [.blush: Self.defaultIntensity, .eyebrow: Self.defaultIntensity,
                       .eyeliner: MakeupTextureRenderer.startingIntensity(for: .eyeliner)]
    }

    // -Nimah: Database/catalog selection is automatic; tools only switch category, never placement style.
    func canTry(_ tool: TryOnTool)->Bool {
        switch tool {
        case .eyebrow:return hasLaunchFit && brow.selectedBrow != nil
        case .blush:return hasLaunchFit && brow.selectedBlush != nil
        case .eyeliner:return linerStyle != nil
        }
    }
    var recommendationTitle: String {
        if tool != .eyeliner && !hasLaunchFit { return String(localized:"Brow and blush unavailable: initial contour fitting was not captured") }
        switch tool {
        case .eyebrow:return brow.selectedBrow?.title ?? String(localized:"No saved recommendation for this face shape")
        case .blush:return brow.selectedBlush?.title ?? String(localized:"No saved recommendation for this face shape")
        case .eyeliner:return linerIsNeutral ? String(localized:"Natural line · scan your eyes for a fitted style") : String(localized:"Eyeliner fitted to your eye scan")
        }
    }
    func updateRecommendations(face: FaceShapeResult?, eyes: EyeShapeResult?) {
        // -Nimah: SwiftUI can resubscribe to @Published outputs; identical scans must not republish/reset the entire home.
        let prepared=LaunchMakeupFit.shared.hasFit
        guard !hasAppliedAnalysis || appliedFace != face || appliedEyes != eyes || prepared != hasLaunchFit else { return }
        hasAppliedAnalysis=true;appliedFace=face;appliedEyes=eyes
        hasLaunchFit=prepared
        let shape=face.map { $0.shape == .triangle ? MakeupFaceShape.pear : MakeupFaceShape(rawValue:$0.shape.rawValue) ?? .unknown } ?? .unknown
        brow.applyAssessment(FaceShapeAssessment(shape:shape,origin:.analysis,confidence:face.map { Float($0.confidence) }))
        let plan=face.map { MakeupPlan(scan:$0,eyeScan:eyes) } ?? MakeupPlan(shape:.oval,eyeScan:eyes)
        linerIsNeutral=plan.eyeliner.isNeutral
        linerRecommendation=plan.madeForYou.first
        if case .eyeliner(let style)? = linerRecommendation?.style { linerStyle=style } else { linerStyle=nil }
        enabled=Set(enabled.filter { canTry($0) })
        if canTry(tool) { enabled.insert(tool) }
        syncLiner()
    }

    var isOff: Bool { !enabled.contains(tool) }

    var intensity: Double { intensities[tool] ?? Self.defaultIntensity }

    /// The highlighted swatch; nil when the tool is off or its shade is not one of the row's swatches.
    var currentShade: MakeupShade? { isOff ? nil : shades[tool] }

    var swatches: [MakeupShade] { MakeupPalette.shades(for: tool.category) + (customShades[tool] ?? []) }

    /// The brow/blush preview configuration for the shared camera view: both layers are drawn together.
    var liveConfiguration: EyebrowConfiguration {
        var configuration = brow.liveConfiguration
        configuration.layered = true
        configuration.showGuide = false
        configuration.showTrackingPoints = false
        configuration.showAllRegions = false
        configuration.debugMesh = false
        configuration.tutorialStep = nil
        configuration.previewAfter = !isComparing
        configuration.browLayer = layer(.eyebrow)
        configuration.blushLayer = layer(.blush)
        return configuration
    }

    /// Selecting a tool also switches its makeup on.
    func choose(_ newTool: TryOnTool) {
        tool = newTool
        if canTry(newTool) { enabled.insert(newTool) }
        if newTool == .eyeliner { syncLiner() }
    }

    func choose(shade: MakeupShade) {
        guard canTry(tool) else { return }
        if shade.id.hasPrefix("custom.") {
            var picked = customShades[tool] ?? []
            if !picked.contains(shade) { picked.append(shade) }
            customShades[tool] = Array(picked.suffix(Self.maxCustomShades))
        }
        shades[tool] = shade
        enabled.insert(tool)
        if tool == .eyeliner { syncLiner() }
    }

    func turnOff() {
        enabled.remove(tool)
        if tool == .eyeliner { syncLiner() }
    }

    func setIntensity(_ value: Double) {
        guard canTry(tool) else { return }
        intensities[tool] = min(max(value, 0.1), 1)
        enabled.insert(tool)
        if tool == .eyeliner { syncLiner() }
    }

    /// Starts the one camera. Blush and eyebrow are placed as soon as it runs, whichever tools are on, so switching a
    /// look on later is immediate.
    func activate() {
        // -Nimah: A late permission response must not revive the home camera behind a scan/tutorial.
        guard !active else { return }
        active=true
        syncLiner()
        activation=Task {
            await brow.prepare()
            guard !Task.isCancelled else { return }
            await camera.requestPermission()
            guard !Task.isCancelled,active else { return }
            camera.overlay = true
        }
    }

    func deactivate() {
        active=false; activation?.cancel(); activation=nil
        relay.setEnabled(false)
        liner.stop()
        camera.stopSession?()
        camera.suspend()
    }

    private func layer(_ tool: TryOnTool) -> PreviewLayer {
        PreviewLayer(on: canTry(tool) && enabled.contains(tool), intensity: Float(intensities[tool] ?? Self.defaultIntensity),
                     tint: shades[tool].map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) })
    }

    /// The liner is a 2D overlay fed by MediaPipe; it runs only while the eyeliner is on.
    private func syncLiner() {
        guard enabled.contains(.eyeliner), let linerStyle else {
            relay.setEnabled(false)
            liner.setStyle(nil, shade: nil, intensity: 1)
            return
        }
        relay.setEnabled(true)
        liner.setStyle(linerStyle, shade: shades[.eyeliner], intensity: intensities[.eyeliner] ?? 1)
    }
}
