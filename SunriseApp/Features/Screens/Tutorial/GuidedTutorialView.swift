// -Nimah: GuidedTutorialView.swift — camera-first tutorial for brows, eyeliner and blush. It has no settings of its own:
// shade and strength are handed over from the Try On screen, and changing them means going back there.
import ARKit
import Combine
import SceneKit
import SwiftUI

/// What the Try On screen hands to the tutorial: the tool that was open, every tool's shade and strength, and the
/// brow picture the user chose (nil: none) with whether their own brow was hidden under it.
struct TutorialHandoff: Hashable {
    var tool: TryOnTool
    var shades: [TryOnTool: MakeupShade]
    var intensities: [TryOnTool: Double]
    /// Which eyeliner look the person was trying: the tutorial guides that same shape.
    var linerLook: LinerLook = .classic
    var blushStyle: BlushPlacementStyle? = nil
    var browOverlay: BrowOverlay? = nil
    var hideNaturalBrow = false
    /// The tools with makeup on when Try On was left. The photo shows exactly these, each as last chosen; a tab for a
    /// tool that was off still guides, without a makeup preview.
    var enabled: Set<TryOnTool> = Set(TryOnTool.allCases)
}

/// What one half of the camera shows in the comparison.
enum TutorialHalf { case tryOn, guide, plain }

/// What the bottom-left button shows, in the order it cycles: the finished look on one half and the step guide on the
/// other (either way round), the look beside the plain camera (either way round), then the plain camera alone.
/// `guidePlain` / `plainGuide` are the one-side-at-a-time tutorial's layouts (the guide on the side being done, nothing
/// on the other); the compare button never cycles to them.
enum TutorialCompare: CaseIterable {
    case tryOnGuide, guideTryOn, tryOnPlain, plainTryOn, plain, guidePlain, plainGuide

    static let cycle: [TutorialCompare] = [.tryOnGuide, .guideTryOn, .tryOnPlain, .plainTryOn, .plain]

    var next: TutorialCompare {
        guard let index = Self.cycle.firstIndex(of: self) else { return Self.cycle[0] }
        return Self.cycle[(index + 1) % Self.cycle.count]
    }
    var left: TutorialHalf {
        switch self {
        case .tryOnGuide, .tryOnPlain: .tryOn
        case .guideTryOn, .guidePlain: .guide
        case .plainTryOn, .plain, .plainGuide: .plain
        }
    }
    var right: TutorialHalf {
        switch self {
        case .guideTryOn, .plainTryOn: .tryOn
        case .tryOnGuide, .plainGuide: .guide
        case .tryOnPlain, .plain, .guidePlain: .plain
        }
    }
    var showsGuide: Bool { left == .guide || right == .guide }
    var showsTryOn: Bool { left == .tryOn || right == .tryOn }
    /// Which side of the screen a half sits on; nil when this layout has no such half.
    func side(of half: TutorialHalf) -> HorizontalEdge? {
        if left == half { return .leading }
        if right == half { return .trailing }
        return nil
    }
    /// The side showing the plain camera next to the look, nil when both halves are plain (or none is).
    var plainBesideLook: HorizontalEdge? { showsTryOn ? side(of: .plain) : nil }
    var symbol: String {
        switch self {
        case .tryOnGuide: "square.lefthalf.filled"
        case .guideTryOn: "square.righthalf.filled"
        case .tryOnPlain: "circle.lefthalf.filled"
        case .plainTryOn: "circle.righthalf.filled"
        case .plain: "circle"
        case .guidePlain: "rectangle.lefthalf.inset.filled"
        case .plainGuide: "rectangle.righthalf.inset.filled"
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .tryOnGuide: "Look on the left, guide on the right"
        case .guideTryOn: "Guide on the left, look on the right"
        case .tryOnPlain: "Look on the left, plain camera on the right"
        case .plainTryOn: "Plain camera on the left, look on the right"
        case .plain: "Plain camera"
        case .guidePlain: "Guide on the left"
        case .plainGuide: "Guide on the right"
        }
    }
}

enum TutorialTab: CaseIterable, Identifiable {
    /// In the bottom bar's order.
    case blush, brows, eyeliner
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self { case .brows: "Brows"; case .eyeliner: "Eyeliner"; case .blush: "Blush" }
    }
    var tool: TryOnTool {
        switch self { case .brows: .eyebrow; case .eyeliner: .eyeliner; case .blush: .blush }
    }
    init(tool: TryOnTool) {
        switch tool { case .eyebrow: self = .brows; case .eyeliner: self = .eyeliner; case .blush: self = .blush }
    }
}

@MainActor final class GuidedTutorialModel: ObservableObject {
    let brow: EyebrowViewModel
    let camera = FaceCameraState()
    let liner = LinerOverlayModel()
    let relay: LinerFrameRelay
    let handoff: TutorialHandoff
    @Published private(set) var tab: TutorialTab
    @Published private(set) var linerStep = 0
    /// The Brows tab's own step (its five steps are the tutorial's, not the brow model's).
    @Published private(set) var browStep = 0
    @Published private(set) var blushStep = 0
    @Published private(set) var compare = TutorialCompare.tryOnGuide
    /// After the last step: the camera shows the whole assigned look, with no guide, for taking a photo.
    @Published private(set) var photoMode = false
    /// One side at a time (the one-tool flow): every step on `side`, then every step again on the other side.
    let perSide: Bool
    /// The half of the screen being done. The front camera is mirrored, so `.leading` is the user's right side.
    @Published private(set) var side = HorizontalEdge.leading
    /// Per side: the desired look on the other half instead of the plain camera.
    @Published private(set) var showsLookBeside = false
    private let linerStyle: LinerStyle?
    private var bag = Set<AnyCancellable>()
    // -Nimah: Hidden tutorial tabs must not start a second detector during navigation.
    private var active = false

    init(checker: any FaceTrackingAvailabilityChecking, assessment: FaceShapeAssessment, plan: MakeupPlan, handoff: TutorialHandoff,
         perSide: Bool = false) {
        self.handoff = handoff
        self.perSide = perSide
        let start = TutorialTab(tool: handoff.tool)
        tab = start
        if case .eyeliner(let style)? = plan.madeForYou.first(where: { $0.category == .eyeliner })?.style {
            linerStyle = EyelinerPlanner.style(style, look: handoff.linerLook)
        } else { linerStyle = nil }
        brow = EyebrowViewModel(checker: checker, assessment: assessment, initialRegion: start == .blush ? .blush : .eyebrows, startTutorial: true)
        relay = LinerFrameRelay(model: liner)
        // The guide points follow the skin when the person pulls the lid or the corner of the eye outward.
        liner.followsPulledLid = true
        applyShade(for: start == .blush ? .blush : .eyebrow)
        // Bake the chosen brow picture (and the 3D hair) now, so it is ready by the first drawn frame.
        if let overlay = handoff.browOverlay {
            BrowSpriteStore.shared.prepare(overlay)
            if overlay.is3D { BrowHairStore.shared.prepare() }
        }
        if perSide { compare = Self.sideLayout(side: .leading, lookBeside: false) }
        // The brow model owns the step index for brows/blush; forward its changes so the screen redraws.
        brow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var stepIndex: Int {
        switch tab { case .eyeliner: linerStep; case .brows: browStep; case .blush: blushStep }
    }

    /// False when the tab has no reference (nothing is drawn rather than a default).
    var hasGuide: Bool { tab == .eyeliner ? linerStyle != nil : brow.hasRecommendation }

    var lessons: [FaceGuideLesson] {
        guard hasGuide else {
            return [FaceGuideLesson(title: "No guide yet", instruction: "This step has no reference yet. Use the other tabs.")]
        }
        if tab == .eyeliner { return Self.linerLessons }
        if tab == .brows { return Self.browLessons }
        if tab == .blush { return Self.blushLessons }
        return brow.lessons
    }

    func cycleCompare() {
        guard perSide else { compare = compare.next; return }
        showsLookBeside.toggle()
        compare = Self.sideLayout(side: side, lookBeside: showsLookBeside)
    }

    /// The guide on the side being done; the plain camera, or the desired look, on the other.
    private static func sideLayout(side: HorizontalEdge, lookBeside: Bool) -> TutorialCompare {
        switch (side, lookBeside) {
        case (.leading, false): .guidePlain
        case (.leading, true): .guideTryOn
        case (.trailing, false): .plainGuide
        case (.trailing, true): .tryOnGuide
        }
    }

    /// The step the tool's guide overlay animates for the current lesson.
    var guideStep: Int {
        let steps = switch tab { case .brows: Self.browGuideSteps; case .blush: Self.blushGuideSteps; case .eyeliner: Array(lessons.indices) }
        return steps.indices.contains(stepIndex) ? steps[stepIndex] : stepIndex
    }

    /// True on the last step of the side being done (Next reads "Finish").
    var isSideLastStep: Bool { stepIndex + 1 >= lessons.count }

    /// True on the first side's last step: Finish shows the side-done card before the other side.
    var finishesFirstSide: Bool { perSide && side == .leading && isSideLastStep }

    /// The side-done card's "Replay": the same side again from its first step.

    /// True on the second side's last step (or the last step when not per side): Next finishes the tutorial.
    var isFinalStep: Bool { stepIndex + 1 >= lessons.count && (!perSide || side == .trailing) }

    private func moveTo(side new: HorizontalEdge, step: Int) {
        side = new
        compare = Self.sideLayout(side: new, lookBeside: showsLookBeside)
        switch tab { case .eyeliner: linerStep = step; case .brows: browStep = step; case .blush: blushStep = step }
    }

    /// The brow/blush preview configuration for the camera. Eyeliner is drawn by its own overlay, so the face-mesh
    /// guide is off on that tab.
    var liveConfiguration: EyebrowConfiguration {
        if photoMode { return photoConfiguration }
        var value = brow.liveConfiguration
        // Brows and blush draw on one face mesh: a look beside the plain camera is the renderer's own left-half split.
        value.comparisonSplit = tab == .blush && compare.plainBesideLook != nil
        // The brow overlay draws its own dots on the guide (`BrowTutorialOverlay`), so the engine's dashed mapping lines stay off.
        value.showMappingFormula = false
        // The tutorial shows dashed nose-to-brow lines, not MediaPipe's landmark view.
        value.browTrackingOverlay = false
        // The filter the user picked on Try On, with its shade and strength (`applyShade`), is what the tutorial shows.
        if tab == .brows {
            value.browOverlay = handoff.browOverlay
            // The comparison cuts at the face's midline, and each brow is on one side of it: the look is drawn on the brow on
            // its half only (the front camera is mirrored: the screen's left half is the user's right brow).
            value.browOnlySide = compare.side(of: .tryOn).map { $0 == .leading ? EyeSide.subjectRight : .subjectLeft }
            value.hideNaturalBrow = compare.showsTryOn && handoff.hideNaturalBrow
            // No look half (e.g. the guide beside the plain camera): no brow picture on either brow.
            if !compare.showsTryOn { value.browOverlay = nil }
        }
        // The eyeliner tab needs no brow/blush fit. Marking it "launch fit" keeps the brow pipeline from scanning every frame
        // with Vision on the camera's session queue, which delays the frames the eyeliner reads.
        if tab == .eyeliner {
            value.usesLaunchFit = true
            value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil
            return value
        }
        if !hasGuide || compare == .plain { value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil }
        // No brow chosen on Try On: the brow guide is still drawn by the makeup engine, so it stays on, with no brow
        // picture and the natural brow left alone. (Turning the preview off stopped the engine and took the guide with it.)
        if tab == .brows && !handoff.enabled.contains(.eyebrow) { value.browOverlay = nil; value.hideNaturalBrow = false }
        if tab == .blush && hasGuide {
            // Like the eyeliner: the look on its half, the step guide on the other half over the bare camera, the plain
            // camera on either side. The Metal camera stays on in every layout and only the pigment is clipped, so the
            // halves never come from different cameras.
            let look = compare.side(of: .tryOn)
            value.pigmentHalf = !handoff.enabled.contains(.blush) ? PigmentHalf.none : (look.map { $0 == .leading ? PigmentHalf.left : .right } ?? PigmentHalf.none)
            value.showMakeupPreview = true
            value.showGuide = compare.showsGuide
            value.comparisonSplit = false
        }
        // A look beside the plain camera has no guide outline over it.
        else if tab != .brows && compare.plainBesideLook != nil { value.showGuide = false; value.showMappingFormula = false }
        return value
    }

    /// The photo is a plain camera: no brow, blush or eyeliner, and the natural brow stays.
    private var photoConfiguration: EyebrowConfiguration {
        var value = brow.liveConfiguration
        value.usesLaunchFit = true
        value.showGuide = false
        value.showTrackingPoints = false
        value.showAllRegions = false
        value.debugMesh = false
        value.tutorialStep = nil
        value.showMakeupPreview = false
        value.showMappingFormula = false
        value.browTrackingOverlay = false
        value.browOverlay = nil
        value.hideNaturalBrow = false
        value.comparisonSplit = false
        value.browLayer = PreviewLayer(on: false, intensity: 0, tint: nil)
        value.blushLayer = PreviewLayer(on: false, intensity: 0, tint: nil)
        return value
    }

    func enterPhoto() { photoMode = true; syncLiner() }
    func leavePhoto() { photoMode = false; syncLiner() }

    /// The camera picture as shown, with the liner on it. Nil until the camera has produced a picture.
    func takePhoto() -> UIImage? {
        camera.view?.snapshot()
    }

    func select(_ new: TutorialTab) {
        guard new != tab else { return }
        tab = new
        linerStep = 0
        browStep = 0
        blushStep = 0
        if new != .eyeliner {
            brow.select(new == .blush ? .blush : .eyebrows)
            applyShade(for: new.tool)
            brow.beginTutorial()
        }
        syncLiner()
    }

    /// Next step. Returns true when the last step was already showing, so the screen should close.
    func advance() -> Bool {
        if perSide && stepIndex + 1 >= lessons.count && side == .leading { moveTo(side: .trailing, step: 0); return false }
        guard stepIndex + 1 < lessons.count else { return true }
        switch tab { case .eyeliner: linerStep += 1; case .brows: browStep += 1; case .blush: blushStep += 1 }
        return false
    }

    /// Previous step. Returns true when already on the first step, so the screen should close.
    func retreat() -> Bool {
        if perSide && stepIndex == 0 && side == .trailing { moveTo(side: .leading, step: lessons.count - 1); return false }
        guard stepIndex > 0 else { return true }
        switch tab { case .eyeliner: linerStep -= 1; case .brows: browStep -= 1; case .blush: blushStep -= 1 }
        return false
    }

    func activate() { active = true; camera.overlay = true; syncLiner() }

    func deactivate() {
        active = false
        relay.setEnabled(false)
        liner.stop()
        camera.stopSession?()
        camera.suspend()
    }

    private func applyShade(for tool: TryOnTool) {
        if tool == .blush,let style=handoff.blushStyle {brow.configuration.blushStyle=style}
        brow.configuration.shadeTint = handoff.shades[tool].map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) }
        let strength = handoff.intensities[tool] ?? TryOnHomeModel.defaultIntensity
        brow.configuration.previewIntensity = Float(min(max(strength, 0), 1))
    }

    private func syncLiner() {
        guard active, tab == .eyeliner, !photoMode, let linerStyle else {
            relay.setEnabled(false)
            liner.setStyle(nil, shade: nil, intensity: 1)
            return
        }
        relay.setEnabled(true)
        liner.setStyle(linerStyle, shade: handoff.shades[.eyeliner], intensity: handoff.intensities[.eyeliner] ?? 1)
    }
}

/// With `onFinished` (the one-tool flow): only the handed-over tool, one side then the other, a steps sheet open at the
/// start, and Done calls `onFinished` instead of opening the photo step.
struct GuidedTutorialView: View {
    @StateObject private var model: GuidedTutorialModel
    private let onFinished: (() -> Void)?

    init(checker: any FaceTrackingAvailabilityChecking, assessment: FaceShapeAssessment?, plan: MakeupPlan, handoff: TutorialHandoff,
         onFinished: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: GuidedTutorialModel(checker: checker, assessment: assessment ?? FaceShapeAssessment(shape: .unknown),
                                                              plan: plan, handoff: handoff, perSide: onFinished != nil))
        self.onFinished = onFinished
    }

    var body: some View { TutorialScreen(model: model, onFinished: onFinished) }
}

private struct TutorialScreen: View {
    @ObservedObject var model: GuidedTutorialModel
    let onFinished: (() -> Void)?
    @ObservedObject private var camera: FaceCameraState
    /// The steps sheet ("Tutorial"). Opens by itself once, at the start, showing the current step only.
    @State private var showsSteps = false
    @State private var stepsDetent = TutorialStepsSheet.compact
    @State private var openedSteps = false
    /// The first side is finished: the side-done card is up until "Do my right …" or "Replay left …".
    @State private var sideDone = false
    @State private var visible = false
    @State private var theme = PhotoTheme.pink
    @State private var flashOn = false
    @State private var flashing = false
    @State private var captured: UIImage?
    @StateObject private var advisor = CameraAdvisor(context: .tutorial)
    @StateObject private var light = ScreenLight()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(model: GuidedTutorialModel, onFinished: (() -> Void)?) {
        self.model = model
        self.onFinished = onFinished
        camera = model.camera
    }

    private var lessons: [FaceGuideLesson] { model.lessons }
    private var index: Int { min(model.stepIndex, lessons.count - 1) }
    /// The button reads "Finish" on the last step of each side.
    private var finishes: Bool { model.perSide ? model.isSideLastStep : model.isFinalStep }
    /// The screen light is on: white screen, dark labels (the design's "tutorial w flash").
    private var lit: Bool { light.isOn && !model.photoMode }
    private var ink: Color { lit ? .black : AppColors.snow }

    var body: some View {
        Group {
            if model.photoMode { photoLayout } else { tutorialLayout }
        }
        .background {
            if model.photoMode { theme.background.ignoresSafeArea() }
            else if lit { Color.white.ignoresSafeArea() }
            else { Color.black.ignoresSafeArea() }
        }
        .animation(.easeInOut(duration: 0.25), value: theme)
        .animation(.easeInOut(duration: 0.25), value: lit)
        .animation(.easeInOut(duration: 0.25), value: sideDone)
        .preferredColorScheme(lit ? .light : nil)
        .foregroundStyle(AppColors.snow)
        .overlay {
            if let captured {
                PolaroidResultView(image: captured, onRetake: { self.captured = nil }, onDone: { dismiss() })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: captured != nil)
        .sensoryFeedback(.selection, trigger: theme)
        .sensoryFeedback(.success, trigger: captured != nil)
        .sensoryFeedback(.success, trigger: sideDone)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.selection, trigger: model.tab)
        .sensoryFeedback(.selection, trigger: model.stepIndex)
        .sensoryFeedback(.selection, trigger: model.compare)
        .sensoryFeedback(.selection, trigger: light.isOn)
        .onChange(of: flashOn) { _, on in light.set(on) }
        .onChange(of: model.photoMode) { _, entered in if entered { flashOn = light.isOn } }
        .task {
            await model.brow.prepare()
            if model.brow.availability == .supported { await camera.requestPermission() }
        }
        .sheet(isPresented: $showsSteps) {
            TutorialStepsSheet(steps: stepTexts, current: currentStepInSheet, expanded: stepsDetent == .large) { showsSteps = false }
                .presentationDetents([TutorialStepsSheet.compact, .large], selection: $stepsDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: TutorialStepsSheet.compact))
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            visible = true; model.activate(); advisor.start(); light.resume()
            if model.perSide && !openedSteps { openedSteps = true; showsSteps = true }
        }
        .onDisappear { visible = false; showsSteps = false; model.deactivate(); advisor.stop(); light.turnOff() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible {
                model.activate(); advisor.start(); light.resume()
                Task { await camera.requestPermission() }
            } else {
                model.deactivate(); advisor.stop(); light.suspend()
            }
        }
    }

    /// The camera card fills the page above the bottom bar.
    private var tutorialLayout: some View {
        VStack(spacing: 0) {
            card
                .frame(maxHeight: .infinity)
            bottomBar
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
        }
    }

    /// Photo (tutorial without the one-tool flow): a fixed portrait frame (208:300 in the design) with the controls below.
    private var photoLayout: some View {
        GeometryReader { proxy in
            VStack(spacing: AppSpacing.medium) {
                PhotoHeader(theme: theme) { model.leavePhoto() }
                card.frame(maxHeight: photoHeight(in: proxy.size))
                PhotoControls(theme: theme, flashOn: $flashOn, onTheme: { theme = theme.next }, onShutter: takePhoto)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
    }

    /// Closes the steps sheet first: navigating while it is up can leave the push or pop undone.
    private func leave(_ action: @escaping () -> Void) {
        guard showsSteps else { action(); return }
        showsSteps = false
        Task { try? await Task.sleep(for: .milliseconds(350)); action() }
    }

    /// The steps sheet's rows: each step's title and its instruction.
    private var stepTexts: [TutorialStepsSheet.Step] {
        lessons.map { TutorialStepsSheet.Step(title: Text($0.title), detail: $0.instruction.isEmpty ? nil : Text($0.instruction)) }
    }

    /// Past the last step once the side is finished, so every step reads "Done".
    private var currentStepInSheet: Int { sideDone ? lessons.count : index }

    private func next() {
        if model.finishesFirstSide { leave { sideDone = true }; return }
        if model.advance() { finish() }
    }

    /// The tutorial is over: the result photo in the flow, the photo screen otherwise.
    private func finish() {
        if let onFinished { leave(onFinished) } else { model.enterPhoto() }
    }

    private func back() {
        if sideDone { sideDone = false; return }
        if model.retreat() { leave(dismiss.callAsFunction) }
    }

    /// Photographs the camera as shown. With the flash on, the screen goes white for a moment first.
    private func takePhoto() {
        Task {
            if flashOn {
                flashing = true
                try? await Task.sleep(for: .milliseconds(180))
            }
            let image = model.takePhoto()
            flashing = false
            if let image { captured = image }
        }
    }

    /// The photo frame's height: 208:300 of the width, but never more than 65% of the screen.
    private func photoHeight(in size: CGSize) -> CGFloat {
        min(size.width * 300 / 208, size.height * 0.65)
    }

    // MARK: Camera card

    private var cornerRadius: CGFloat { model.photoMode ? 10 : 28 }

    private var card: some View {
        ZStack {
            Group {
                if !lit { Color.black }
                // Light on: the picture fades softly into the white screen instead of ending in a hard edge.
                cameraContent
                    .mask {
                        if fullBleed && !lit {
                            bottomRounded
                        } else {
                            RoundedRectangle(cornerRadius: lit ? cornerRadius * 2 : cornerRadius, style: .continuous)
                                .padding(lit ? 26 : 0)
                                .blur(radius: lit ? 26 : 0)
                        }
                    }
            }
            .ignoresSafeArea(edges: fullBleed ? .top : [])
            if flashing { Color.white.ignoresSafeArea().allowsHitTesting(false) }
            if !model.photoMode {
                VStack(spacing: AppSpacing.small) {
                    topButtons
                    Spacer()
                    bottomCaption
                }
                .padding(AppSpacing.small)
                .opacity(sideDone ? 0 : 1)
                if sideDone {
                    bottomRounded.fill(.ultraThinMaterial).ignoresSafeArea(edges: .top).transition(.opacity)
                    SideDoneCard(tool: model.tab, onNext: {
                        sideDone = false
                        _ = model.advance()
                    }, onDone: {
                        sideDone = false
                        finish()
                    })
                    .padding(.horizontal, 40)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lit)
        // The flash on the photo screen is the screen light: full brightness and a warm ring round the picture.
        .overlay { if model.photoMode { ScreenLightGlow(light: light, cornerRadius: 10) } }
        // Full bleed: clipping to the card's own frame would cut the camera off at the safe area; the mask rounds it.
        .clipShape(fullBleed ? AnyShape(Rectangle().inset(by: -1000)) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius,
                                                                                                    style: .continuous)))
    }

    /// The tutorial's camera runs from the top edge under the status bar (the buttons stay in the safe area) and is
    /// rounded only above the bottom bar; the photo screen keeps its framed picture.
    private var fullBleed: Bool { !model.photoMode }

    private var bottomRounded: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder private var cameraContent: some View {
        switch model.brow.availability {
        case .notChecked:
            ProgressView().tint(AppColors.snow)
        case .unsupported:
            message(symbol: "faceid", title: "Live guide unavailable",
                    text: "The live guide needs an iPhone with a TrueDepth front camera.")
        case .supported:
            if camera.denied {
                message(symbol: "camera", title: "I need your camera to be your mirror.",
                        text: "Nothing is saved or uploaded.",
                        actionTitle: "Turn on camera") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if camera.failure != nil {
                message(symbol: "exclamationmark.triangle", title: "Camera stopped", text: "Face tracking stopped unexpectedly.")
            } else if camera.authorized {
                ZStack {
                    LiveGuideView(camera: camera, referenceID: "eyebrows", active: visible && scenePhase == .active && !advisor.pausesSession,
                                  // Always a configuration, never nil: nil falls back to the old per-frame blush surface renderer.
                                  eyebrowConfiguration: guideConfiguration, onFrame: { [relay = model.relay] frame, face in
                                      relay.deliver(frame, face)
                                  }, reducedFrameRate: advisor.reducesLoad)
                    if model.tab == .blush, model.hasGuide, !model.photoMode, let side = model.compare.side(of: .guide) {
                        // The guide's half only, over the bare camera; the look is on the other half.
                        BlushTutorialOverlay(feed: camera.blushGuide, step: model.guideStep)
                            .mask { FaceHalfMask(feed: camera.faceSplit, left: side == .leading) }
                    }
                    if model.tab == .brows, model.hasGuide, !model.photoMode, let side = model.compare.side(of: .guide) {
                        // The guide's brow only; the look is on the other one.
                        BrowTutorialOverlay(feed: camera.browGuide, step: model.guideStep, paused: advisor.pausesAnimation, side: side)
                    }
                    if model.photoMode {
                        // Plain camera: nothing drawn on the face.
                    } else if model.tab == .eyeliner, model.hasGuide {
                        // Each half is clipped inside its own canvas: a mask would make an offscreen pass every frame.
                        if let side = model.compare.side(of: .tryOn) {
                            LinerOverlayView(model: model.liner, isVisible: true, visibleSide: side)
                        }
                        if let side = model.compare.side(of: .guide) {
                            LinerStepGuide(model: model.liner, step: LinerTutorialStep(rawValue: index) ?? .markDots,
                                           paused: advisor.pausesAnimation, dimmed: advisor.isDimmed, side: side,
                                           showsLower: model.linerShowsLower)
                                .id(index)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: model.compare)
                // The photo is taken from the unzoomed camera, so zoom is off while framing it.
                .cameraZoom(!model.photoMode)
            } else {
                ProgressView().tint(AppColors.snow)
            }
        }
    }

    private func message(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey,
                         actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(AppTypography.heading)
            Text(text).font(AppTypography.body).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(AppColors.flamingo)
            }
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Compare (left), the style's name, the screen light (right), as on the capture screen.
    private var topButtons: some View {
        HStack {
            Button { model.cycleCompare() } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compare")
            .accessibilityValue(model.compare.label)
            Spacer()
            StylePill(handoff: model.handoff, onGlass: true)
            Spacer()
            ScreenLightButton(light: light, pulse: advisor.darkPulse, plainGlass: true)
        }
        .environment(\.colorScheme, lit ? .light : .dark)
    }

    /// The brow/blush preview configuration, with the guide hidden while a camera message shows.
    private var guideConfiguration: EyebrowConfiguration {
        var value = model.liveConfiguration
        if advisor.isDimmed && !model.photoMode && model.tab != .eyeliner { value.showGuide = false }
        return value
    }

    /// Over the bottom of the camera: a camera message when there is one, else the step's instruction; then the step dots.
    private var bottomCaption: some View {
        VStack(spacing: 12) {
            if advisor.message != nil {
                CameraGuidanceCaption(advisor: advisor, lightOn: light.isOn, stepLabel: nil, stepText: nil)
            } else {
                Text(lessons[index].instruction)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(lit ? Color.black : AppColors.snow)
                    .shadow(color: .black.opacity(lit ? 0 : 0.45), radius: 3, y: 1)
                    .frame(maxWidth: 260)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index)
                    .transition(.opacity)
            }
            HStack(spacing: 5) {
                ForEach(lessons.indices, id: \.self) { step in
                    Capsule()
                        .fill((lit ? Color.black : AppColors.snow).opacity(step == index ? 1 : 0.55))
                        .frame(width: step == index ? 22 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppSpacing.medium)
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(index + 1) of \(lessons.count)"))
    }

    // MARK: Bottom bar

    /// Back (left), "Tutorial" (the steps sheet) in the middle, Next / Finish (right).
    private var bottomBar: some View {
        ZStack {
            Button { stepsDetent = TutorialStepsSheet.compact; showsSteps = true } label: {
                Text("Tutorial")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Capsule().fill(ink.opacity(0.28)))
            }
            .accessibilityHint("Shows all steps")
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(ink.opacity(0.45), lineWidth: 1))
                }
                .accessibilityLabel(index == 0 && !sideDone ? "Back" : "Previous step")
                Spacer()
                Button(action: next) {
                    Text(finishes ? "Finish" : "Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .overlay(Capsule().strokeBorder(ink.opacity(0.45), lineWidth: 1))
                }
                .disabled(sideDone)
                .opacity(sideDone ? 0.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: finishes)
    }
}

/// "Left cheek done!": the first side is finished. On to the other side, or the same side again.
private struct SideDoneCard: View {
    let tool: TutorialTab
    let onNext: () -> Void
    /// "Done": ends the tutorial here (on to the result photo) without the other side.
    let onDone: () -> Void

    private var copy: (title: LocalizedStringKey, text: LocalizedStringKey, next: LocalizedStringKey) {
        switch tool {
        case .blush: ("Left cheek done!", "Now the same on your right cheek, so both sides match.", "Do my right cheek")
        case .brows: ("Left brow done!", "Now the same on your right brow, so both sides match.", "Do my right brow")
        case .eyeliner: ("Left eye done!", "Now the same on your right eye, so both sides match.", "Do my right eye")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AppColors.dandanPink, in: Circle())
                .frame(width: 52, height: 52)
                .background(.white, in: Circle())
                .accessibilityHidden(true)
            Text(copy.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.onboardingInk)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text(copy.text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.onboardingBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button(action: onNext) {
                Text(copy.next)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppColors.buttonInk, in: Capsule())
            }
            .padding(.top, 18)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
                    .frame(minHeight: 44)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}

/// A mask covering the whole view, or only the part left / right of the face's midline.
private struct FaceHalfMask: View {
    @ObservedObject var feed: FaceSplitFeed
    let left: Bool

    var body: some View {
        GeometryReader { proxy in
            let cut = proxy.size.width * feed.x
            Rectangle().frame(width: left ? cut : proxy.size.width - cut)
                .frame(maxWidth: .infinity, alignment: left ? .leading : .trailing)
        }
    }
}
