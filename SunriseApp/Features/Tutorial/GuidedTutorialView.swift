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
enum TutorialCompare: CaseIterable {
    case tryOnGuide, guideTryOn, tryOnPlain, plainTryOn, plain

    var next: TutorialCompare {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    var left: TutorialHalf {
        switch self { case .tryOnGuide, .tryOnPlain: .tryOn; case .guideTryOn: .guide; case .plainTryOn, .plain: .plain }
    }
    var right: TutorialHalf {
        switch self { case .guideTryOn, .plainTryOn: .tryOn; case .tryOnGuide: .guide; case .tryOnPlain, .plain: .plain }
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
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .tryOnGuide: "Look on the left, guide on the right"
        case .guideTryOn: "Guide on the left, look on the right"
        case .tryOnPlain: "Look on the left, plain camera on the right"
        case .plainTryOn: "Plain camera on the left, look on the right"
        case .plain: "Plain camera"
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
    private let linerStyle: LinerStyle?
    private var bag = Set<AnyCancellable>()
    // -Nimah: Hidden tutorial tabs must not start a second detector during navigation.
    private var active = false

    init(checker: any FaceTrackingAvailabilityChecking, assessment: FaceShapeAssessment, plan: MakeupPlan, handoff: TutorialHandoff) {
        self.handoff = handoff
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
        // The brow model owns the step index for brows/blush; forward its changes so the screen redraws.
        brow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var stepIndex: Int {
        switch tab { case .eyeliner: linerStep; case .brows: browStep; case .blush: blushStep }
    }

    /// The Blush tab's two steps (UX spec 3.5). "Dab" works for cream and powder alike; the caption is the whole instruction.
    static let blushLessons = [
        FaceGuideLesson(title: String(localized: "Dab a little blush inside the small circle."), instruction: ""),
        FaceGuideLesson(title: String(localized: "Dab outward to blend it into your skin."), instruction: ""),
    ]

    /// The Brows tab's steps, as a brow is drawn with a pencil after brow mapping.
    static let browLessons = [
        FaceGuideLesson(title: String(localized: "Brush your brows up with a spoolie"),
                        instruction: String(localized: "Brush every hair upward and a little outward, so the real edge of your brow shows.")),
        FaceGuideLesson(title: String(localized: "Mark three dots along the guide"),
                        instruction: String(localized: "Make a small dot where each dashed line meets your brow: where it starts, its arch and where it ends.")),
        FaceGuideLesson(title: String(localized: "Connect the dots into an outline"),
                        instruction: String(localized: "Draw a light line from the start through the arch to the end along the top edge, then along the bottom.")),
        FaceGuideLesson(title: String(localized: "Fill in with short, hair-like strokes"),
                        instruction: String(localized: "Start at the arch and work toward the end, then go lighter toward the start.")),
        FaceGuideLesson(title: String(localized: "Brush through to soften"),
                        instruction: String(localized: "Brush the start upward with the spoolie so the front stays soft, then check that both brows match.")),
    ]
    /// The brow steps that show the mapping lines: marking the dots and outlining between them.
    static let browMappingSteps = 1...2

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

    func cycleCompare() { compare = compare.next }

    /// The brow/blush preview configuration for the camera. Eyeliner is drawn by its own overlay, so the face-mesh
    /// guide is off on that tab.
    var liveConfiguration: EyebrowConfiguration {
        if photoMode { return photoConfiguration }
        var value = brow.liveConfiguration
        // Brows and blush draw on one face mesh: a look beside the plain camera is the renderer's own left-half split.
        value.comparisonSplit = tab != .eyeliner && compare.plainBesideLook != nil
        value.showMappingFormula = tab == .brows && Self.browMappingSteps.contains(browStep)
        // The tutorial shows dashed nose-to-brow lines, not MediaPipe's landmark view.
        value.browTrackingOverlay = false
        // The filter the user picked on Try On, with its shade and strength (`applyShade`), is what the tutorial shows.
        if tab == .brows {
            value.browOverlay = handoff.browOverlay
            value.hideNaturalBrow = compare != .plain && handoff.hideNaturalBrow
        }
        // The eyeliner tab needs no brow/blush fit. Marking it "launch fit" keeps the brow pipeline from scanning every frame
        // with Vision on the camera's session queue, which delays the frames the eyeliner reads.
        if tab == .eyeliner {
            value.usesLaunchFit = true
            value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil
            return value
        }
        if !hasGuide || compare == .plain { value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil }
        // No makeup was chosen for this tool on Try On: guide only.
        if !handoff.enabled.contains(tab.tool) { value.showMakeupPreview = false }
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
        else if compare.plainBesideLook != nil { value.showGuide = false; value.showMappingFormula = false }
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

    /// Only the Arabian look has a lower line to mark and fill.
    var linerShowsLower: Bool { handoff.linerLook == .arabian }

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
        guard stepIndex + 1 < lessons.count else { return true }
        switch tab { case .eyeliner: linerStep += 1; case .brows: browStep += 1; case .blush: blushStep += 1 }
        return false
    }

    /// Previous step. Returns true when already on the first step, so the screen should close.
    func retreat() -> Bool {
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

    /// Three steps for every look (`LinerTutorialStep`). The screen takes its wording from the step, so these only count
    /// the steps; where the dots sit is what changes with the look.
    static let linerLessons: [FaceGuideLesson] = LinerTutorialStep.allCases.map {
        FaceGuideLesson(title: "Step \($0.rawValue + 1)", instruction: "")
    }
}

struct GuidedTutorialView: View {
    @StateObject private var model: GuidedTutorialModel

    init(checker: any FaceTrackingAvailabilityChecking, assessment: FaceShapeAssessment?, plan: MakeupPlan, handoff: TutorialHandoff) {
        _model = StateObject(wrappedValue: GuidedTutorialModel(checker: checker, assessment: assessment ?? FaceShapeAssessment(shape: .unknown),
                                                              plan: plan, handoff: handoff))
    }

    var body: some View { TutorialScreen(model: model) }
}

private struct TutorialScreen: View {
    @ObservedObject var model: GuidedTutorialModel
    @ObservedObject private var camera: FaceCameraState
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

    init(model: GuidedTutorialModel) {
        self.model = model
        camera = model.camera
    }

    private var lessons: [FaceGuideLesson] { model.lessons }
    private var index: Int { min(model.stepIndex, lessons.count - 1) }
    private var isLast: Bool { index + 1 >= lessons.count }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: AppSpacing.medium) {
                if model.photoMode { PhotoHeader(theme: theme) { model.leavePhoto() } }
                // Tutorial: the card fills the screen. Photo: a fixed portrait frame (208:300 in the design) with the controls
                // right below it.
                card.frame(maxHeight: model.photoMode ? photoHeight(in: proxy.size) : .infinity)
                if model.photoMode {
                    PhotoControls(theme: theme, flashOn: $flashOn, onTheme: { theme = theme.next }, onShutter: takePhoto)
                    Spacer(minLength: 0)
                } else {
                    tabBar
                }
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .background((model.photoMode ? theme.background : AppColors.wine).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: theme)
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
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.selection, trigger: model.tab)
        .sensoryFeedback(.selection, trigger: model.stepIndex)
        .sensoryFeedback(.selection, trigger: model.compare)
        .sensoryFeedback(.selection, trigger: light.isOn)
        .task {
            await model.brow.prepare()
            if model.brow.availability == .supported { await camera.requestPermission() }
        }
        .onAppear { visible = true; model.activate(); advisor.start(); light.resume() }
        .onDisappear { visible = false; model.deactivate(); advisor.stop(); light.turnOff() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible {
                model.activate(); advisor.start(); light.resume()
                Task { await camera.requestPermission() }
            } else {
                model.deactivate(); advisor.stop(); light.suspend()
            }
        }
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

    private var card: some View {
        ZStack {
            Color.black
            cameraContent
            if flashing { Color.white.ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: AppSpacing.small) {
                if !model.photoMode { header }
                Spacer()
                if !model.photoMode { bottomCaption }
            }
            .padding(AppSpacing.small)
            if !model.photoMode, model.brow.availability == .supported, camera.authorized {
                ScreenLightGlow(light: light)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: model.photoMode ? 10 : AppSpacing.cornerRadius, style: .continuous))
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
                        BlushTutorialOverlay(feed: camera.blushGuide, step: index)
                            .mask { halfMask(left: side == .leading) }
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
                    } else if model.tab == .brows, model.compare.plainBesideLook != nil {
                        // The same camera without the look, covering its half.
                        RealCameraView(session: camera.trackingManager.session)
                            .mask(alignment: .trailing) { halfMask(left: false) }
                            .transition(.opacity)
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

    /// A mask covering the whole view, or only its left / right half.
    private func halfMask(left: Bool) -> some View {
        GeometryReader { proxy in
            Rectangle().frame(width: proxy.size.width / 2).frame(maxWidth: .infinity, alignment: left ? .leading : .trailing)
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
        .background(AppColors.cocoa)
    }

    /// Round frosted back button on the left; a frosted "Next" capsule on the right that turns into a pink "Done" on the last step.
    private var header: some View {
        HStack {
            Button {
                if model.retreat() { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(AppColors.snow.opacity(0.8), in: Circle())
                    .foregroundStyle(AppColors.wine)
            }
            .accessibilityLabel(index == 0 ? "Back to try on" : "Previous step")
            Spacer()
            Button {
                if model.advance() { model.enterPhoto() }
            } label: {
                HStack(spacing: 6) {
                    Text(isLast ? "Done" : "Next")
                    if !isLast { Image(systemName: "chevron.right").fontWeight(.medium) }
                }
                .font(.body.weight(isLast ? .semibold : .regular))
                .padding(.horizontal, isLast ? 24 : 18)
                .frame(height: 44)
                .background(isLast ? AnyShapeStyle(AppColors.flamingo) : AnyShapeStyle(AppColors.snow.opacity(0.8)), in: Capsule())
                .foregroundStyle(isLast ? AppColors.snow : AppColors.wine)
            }
            .accessibilityLabel(isLast ? "Done" : "Next step")
        }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .animation(.easeInOut(duration: 0.2), value: isLast)
        .buttonStyle(.plain)
    }

    /// The brow/blush preview configuration, with the guide hidden while a camera message shows.
    private var guideConfiguration: EyebrowConfiguration {
        var value = model.liveConfiguration
        if advisor.isDimmed && !model.photoMode && model.tab != .eyeliner { value.showGuide = false }
        return value
    }

    /// Over the camera: a camera message when there is one; otherwise the eyeliner step caption, or (brows, blush) the
    /// lesson card.
    @ViewBuilder private var bottomCaption: some View {
        if model.tab == .eyeliner, model.hasGuide {
            let step = LinerTutorialStep(rawValue: index) ?? .markDots
            CameraGuidanceCaption(advisor: advisor, lightOn: light.isOn, stepLabel: step.label, stepText: step.caption)
                .padding(.bottom, AppSpacing.medium)
        } else if advisor.message != nil {
            CameraGuidanceCaption(advisor: advisor, lightOn: light.isOn, stepLabel: nil, stepText: nil)
                .padding(.bottom, AppSpacing.medium)
        } else {
            wording
        }
    }

    /// Brows: a small spaced "STEP 1 OF 5" over one short instruction in a pill, like a camera effect's caption.
    @ViewBuilder private var wording: some View {
        switch model.tab {
        case .brows: browCaption
        case .blush: stepCaption
        case .eyeliner: lessonCard
        }
    }

    private var browCaption: some View {
        VStack(spacing: AppSpacing.small) {
            Text("Step \(index + 1) of \(lessons.count)")
                .textCase(.uppercase)
                .font(.subheadline.weight(.medium))
                .tracking(3)
                .foregroundStyle(AppColors.snow.opacity(0.8))
                .monospacedDigit()
            Text(lessons[index].title)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.snow)
                .padding(.horizontal, AppSpacing.large).padding(.vertical, AppSpacing.small)
                .background(AppColors.wine.opacity(0.55), in: Capsule())
        }
        .shadow(color: .black.opacity(0.35), radius: 3)
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppSpacing.medium)
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(index + 1) of \(lessons.count)"))
        .accessibilityValue(Text(lessons[index].title + ". " + lessons[index].instruction))
    }

    /// UX spec 1.1: "STEP 1 OF 2" (17 pt, 2 pt tracking, 70%, drop shadow), 4 pt gap, then the caption in a #370B21 rounded
    /// rectangle (15 pt, -0.43 tracking, 22 pt lines, radius 18, padding 22 x 4, hugging the text up to 300 pt wide).
    private var stepCaption: some View {
        VStack(spacing: 4) {
            Text("Step \(index + 1) of \(lessons.count)")
                .textCase(.uppercase)
                .font(.body)
                .tracking(2)
                .monospacedDigit()
                .foregroundStyle(AppColors.snow.opacity(0.7))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            Text(lessons[index].title)
                .font(.subheadline)
                .tracking(-0.43)
                .lineSpacing(2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.snow)
                .padding(.horizontal, 22).padding(.vertical, 4)
                .background(AppColors.captionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppSpacing.medium)
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(index + 1) of \(lessons.count)"))
        .accessibilityValue(Text(lessons[index].title))
    }

    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lessons[index].title).font(.headline)
                Spacer()
                Text("\(index + 1)/\(lessons.count)").font(.caption.monospacedDigit())
            }
            Text(lessons[index].instruction).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.wine.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Tabs

    /// Compare on the left, the three tabs, the screen light on the right (as on Try On).
    private var tabBar: some View {
        HStack(spacing: AppSpacing.small) {
            CameraBarButton(symbol: model.compare.symbol) { model.cycleCompare() }
                .accessibilityLabel("Compare")
                .accessibilityValue(model.compare.label)
            ForEach(TutorialTab.allCases) { tab in
                let selected = tab == model.tab
                Button { model.select(tab) } label: {
                    Text(tab.title)
                        .font(.title3.weight(selected ? .semibold : .regular))
                        .foregroundStyle(AppColors.snow.opacity(selected ? 1 : 0.55))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            CameraBarButton(symbol: light.isOn ? "bolt.fill" : "bolt.slash.fill") { light.toggle() }
                .accessibilityLabel("Light")
                .accessibilityValue(light.isOn ? Text("On") : Text("Off"))
        }
    }
}

/// Plain camera picture from the shared face session, with no content: the "real" side of the comparison.
private struct RealCameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        // Giving a view the session makes the view its delegate. The filtered camera's coordinator is the delegate that
        // feeds the brow, blush and eyeliner frames, so it is put back: otherwise the filter stops updating in split view.
        let delegate = session.delegate
        let delegateQueue = session.delegateQueue
        view.session = session
        session.delegate = delegate
        session.delegateQueue = delegateQueue
        view.preferredFramesPerSecond = 60
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}

/// Blush tutorial overlay (UX spec 3.2 and 3.5), anchored to each cheek through `BlushGuideFeed`.
/// Step 1: the inner dotted circle, and a fingertip dabbing inside it with a pink tap ring.
/// Step 2: the outer dotted line too, the ring between them pulsing 20%-50% every 2 s, and the fingertip dabbing outward.
/// The dab animation runs 3 s, rests 2 s and repeats. Reduce Motion shows its last frame and a still 40% highlight.
private struct BlushTutorialOverlay: View {
    @ObservedObject var feed: BlushGuideFeed
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thermal = ProcessInfo.processInfo.thermalState

    static let cycle: Double = 5, animation: Double = 3, pulsePeriod: Double = 2
    /// Three dabs start at these times within the cycle, each `dab` seconds long.
    static let dabStarts: [Double] = [0.25, 1.15, 2.05], dab: Double = 0.8

    var body: some View {
        // Only a critical phone pauses the loop: AR plus MediaPipe reach `.serious` quickly, and a still guide reads as
        // broken. The overlay itself stays.
        let paused = reduceMotion || thermal == .critical
        TimelineView(.animation(paused: paused)) { context in
            let t = paused ? Self.animation - 0.001 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Canvas { g, _ in draw(&g, time: t, still: paused) }
                if let cheeks = feed.snapshot?.cheeks {
                    ForEach(cheeks.indices, id: \.self) { i in fingertip(cheeks[i], time: t, still: paused) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ProcessInfo.processInfo.thermalState
        }
    }

    private func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }
    private var dotted: StrokeStyle { StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 7]) }

    private func draw(_ g: inout GraphicsContext, time t: Double, still: Bool) {
        guard let cheeks = feed.snapshot?.cheeks else { return }
        for c in cheeks {
            let inner = path(c.inner), outer = path(c.outer)
            if step >= 1 {
                // The ring between the two lines: 20% to 50% and back every 2 s, or a still 40%.
                let wave = 0.5 - 0.5 * cos(2 * .pi * t / Self.pulsePeriod)
                var ring = outer; ring.addPath(inner)
                g.fill(ring, with: .color(AppColors.flamingo.opacity(still ? 0.4 : 0.2 + 0.3 * wave)), style: FillStyle(eoFill: true))
                g.stroke(outer, with: .color(AppColors.snow.opacity(0.95)), style: dotted)
            }
            g.stroke(inner, with: .color(AppColors.snow.opacity(step >= 1 ? 0.7 : 0.95)), style: dotted)
        }
    }

    /// Where each of the three dabs lands: around the centre of the small circle, or stepping outward to the outer line.
    private func targets(_ c: BlushGuideSnapshot.Cheek) -> [CGPoint] {
        let d = CGPoint(x: c.outward.x - c.center.x, y: c.outward.y - c.center.y)
        func along(_ k: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: c.center.x + d.x * k - d.y * side, y: c.center.y + d.y * k + d.x * side)
        }
        return step == 0 ? [along(0), along(0.25, 0.2), along(-0.2, -0.15)] : [along(0.65), along(0.95, 0.15), along(1.25, -0.1)]
    }

    static func fingerPosition(_ points: [CGPoint], local: Double, index: Int, u: Double) -> CGPoint {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
        if local < dabStarts[0] { return lerp(points[points.count - 1], points[0], local / dabStarts[0]) }
        return lerp(index > 0 ? points[index - 1] : points[0], points[index], min(1, u * 3))
    }

    @ViewBuilder private func fingertip(_ c: BlushGuideSnapshot.Cheek, time t: Double, still: Bool) -> some View {
        let points = targets(c)
        let local = still ? Self.animation - 0.001 : t.truncatingRemainder(dividingBy: Self.cycle)
        // Which dab, how far into it (0...1), and how hard the finger presses (0 up, 1 on the skin).
        let index = Self.dabStarts.lastIndex { $0 <= local } ?? 0
        let u = max(0, min(1, (local - Self.dabStarts[index]) / Self.dab))
        let press = local < Self.dabStarts[0] ? 0 : sin(Double.pi * min(1, u * 1.25))
        // Before the first dab the finger glides back from where the last cycle ended; it never disappears, and it rests on
        // the last dab through the 2 s pause.
        let target = Self.fingerPosition(points, local: local, index: index, u: u)
        let visible: Double = 1
        let ringProgress = still ? 0.6 : max(0, min(1, (u - 0.35) / 0.65))
        ZStack {
            Circle()
                .stroke(AppColors.flamingo, lineWidth: 2.5)
                .frame(width: 10 + 30 * ringProgress, height: 10 + 30 * ringProgress)
                .opacity((still ? 0.6 : (u > 0.35 && local < Self.animation ? 1 - ringProgress : 0)) * visible)
                .position(points[index])
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.snow)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .scaleEffect(1 - 0.08 * press)
                // The symbol's fingertip is near its top left: put that point on the cheek, lifted while not pressing.
                .position(x: target.x + 9, y: target.y + 15 - 14 * (1 - press))
                .opacity(visible)
        }
    }
}

