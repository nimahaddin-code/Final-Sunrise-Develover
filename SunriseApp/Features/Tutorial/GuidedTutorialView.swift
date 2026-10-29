// -Nimah: GuidedTutorialView.swift — camera-first tutorial for brows, eyeliner and blush. It has no settings of its own:
// shade and strength are handed over from the Try On screen, and changing them means going back there.
import ARKit
import Combine
import SceneKit
import SwiftUI

/// What the Try On screen hands to the tutorial: the tool that was open, and every tool's shade and strength.
struct TutorialHandoff: Hashable {
    var tool: TryOnTool
    var shades: [TryOnTool: MakeupShade]
    var intensities: [TryOnTool: Double]
    /// Which eyeliner look the person was trying: the tutorial guides that same shape.
    var linerLook: LinerLook = .classic
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
    case brows, eyeliner, blush
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
        // The brow model owns the step index for brows/blush; forward its changes so the screen redraws.
        brow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var stepIndex: Int { tab == .eyeliner ? linerStep : brow.stepIndex }

    /// False when the tab has no reference (nothing is drawn rather than a default).
    var hasGuide: Bool { tab == .eyeliner ? linerStyle != nil : brow.hasRecommendation }

    var lessons: [FaceGuideLesson] {
        guard hasGuide else {
            return [FaceGuideLesson(title: "No guide yet", instruction: "This step has no reference yet. Use the other tabs.")]
        }
        if tab == .eyeliner { return Self.linerLessons }
        return brow.lessons
    }

    func cycleCompare() { compare = compare.next }

    /// The brow/blush preview configuration for the camera. Eyeliner is drawn by its own overlay, so the face-mesh
    /// guide is off on that tab.
    var liveConfiguration: EyebrowConfiguration {
        if photoMode { return photoConfiguration }
        var value = brow.liveConfiguration
        value.showMappingFormula = tab == .brows
        // The eyeliner tab needs no brow/blush fit. Marking it "launch fit" keeps the brow pipeline from scanning every frame
        // with Vision on the camera's session queue, which delays the frames the eyeliner reads.
        if tab == .eyeliner {
            value.usesLaunchFit = true
            value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil
            return value
        }
        if !hasGuide || compare == .plain { value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil }
        // Brow and blush are drawn on the face mesh, one configuration for the whole view, so the guide and the look cannot
        // share the screen: the guide wins when it is in the layout, otherwise the look (beside the plain camera).
        else if !compare.showsGuide { return photoConfiguration }
        return value
    }

    /// Brow and blush together, in the shades carried over from Try On, like the home preview.
    private var photoConfiguration: EyebrowConfiguration {
        var value = brow.liveConfiguration
        let hasFit = LaunchMakeupFit.shared.hasFit
        if !hasFit { value.usesLaunchFit = true }
        value.layered = true
        value.showGuide = false
        value.showTrackingPoints = false
        value.showAllRegions = false
        value.debugMesh = false
        value.tutorialStep = nil
        value.showMakeupPreview = true
        value.previewAfter = true
        value.browLayer = photoLayer(.eyebrow, available: hasFit && brow.selectedBrow != nil)
        value.blushLayer = photoLayer(.blush, available: hasFit && brow.selectedBlush != nil)
        return value
    }

    private func photoLayer(_ tool: TryOnTool, available: Bool) -> PreviewLayer {
        PreviewLayer(on: available, intensity: Float(handoff.intensities[tool] ?? TryOnHomeModel.defaultIntensity),
                     tint: handoff.shades[tool].map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) })
    }

    func enterPhoto() { photoMode = true; syncLiner() }
    func leavePhoto() { photoMode = false; syncLiner() }

    /// The camera picture as shown, with the liner on it. Nil until the camera has produced a picture.
    func takePhoto() -> UIImage? {
        guard let image = camera.view?.snapshot() else { return nil }
        return liner.composed(image)
    }

    func select(_ new: TutorialTab) {
        guard new != tab else { return }
        tab = new
        linerStep = 0
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
        if tab == .eyeliner { linerStep += 1 } else { brow.nextStep() }
        return false
    }

    /// Previous step. Returns true when already on the first step, so the screen should close.
    func retreat() -> Bool {
        guard stepIndex > 0 else { return true }
        if tab == .eyeliner { linerStep -= 1 } else { brow.previousStep() }
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
        brow.configuration.shadeTint = handoff.shades[tool].map { SIMD3(Float($0.red), Float($0.green), Float($0.blue)) }
        let strength = handoff.intensities[tool] ?? TryOnHomeModel.defaultIntensity
        brow.configuration.previewIntensity = Float(min(max(strength, 0), 1))
    }

    private func syncLiner() {
        guard active, tab == .eyeliner || photoMode, let linerStyle else {
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
        .background((model.photoMode ? theme.background : AppColors.screen).ignoresSafeArea())
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
        .overlay(alignment: .leading) {
            if !model.photoMode, model.brow.availability == .supported, camera.authorized {
                ScreenLightButton(light: light, pulse: advisor.darkPulse).padding(.leading, AppSpacing.small)
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
                    if model.tab == .brows && EyebrowConfiguration.showsBrowTracking && model.compare != .plain && !model.photoMode {
                        BrowTrackingOverlayView(feed: camera.browTracking)
                    }
                    if model.photoMode {
                        LinerOverlayView(model: model.liner, isVisible: true)
                    } else if model.tab == .eyeliner, model.hasGuide {
                        // Each half is clipped inside its own canvas: a mask would make an offscreen pass every frame.
                        if let side = model.compare.side(of: .tryOn) {
                            LinerOverlayView(model: model.liner, isVisible: true, visibleSide: side)
                        }
                        if let side = model.compare.side(of: .guide) {
                            LinerStepGuide(model: model.liner, step: LinerTutorialStep(rawValue: index) ?? .markDots,
                                           paused: advisor.pausesAnimation, dimmed: advisor.isDimmed, side: side)
                                .id(index)
                        }
                    } else if model.tab != .eyeliner, let side = model.compare.plainBesideLook {
                        // The same camera without the look, covering its half.
                        RealCameraView(session: camera.trackingManager.session)
                            .mask(alignment: side == .leading ? .leading : .trailing) { halfMask(left: side == .leading) }
                    }
                }
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

    private var header: some View {
        ZStack {
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .frame(maxWidth: 140, maxHeight: 40)
                .shadow(color: AppColors.snow.opacity(0.7), radius: 4)
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button {
                    if model.retreat() { dismiss() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.subheadline.weight(.semibold))
                        Text("Back").font(.headline)
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .frame(height: 52)
                    .background(AppColors.snow.opacity(0.85), in: Capsule())
                    .foregroundStyle(AppColors.wine)
                }
                .accessibilityLabel(index == 0 ? "Back to try on" : "Previous step")
                Spacer()
                Button {
                    if model.advance() { model.enterPhoto() }
                } label: {
                    if isLast {
                        // Done goes on to the photo step.
                        Text("Done")
                            .font(.headline)
                            .padding(.horizontal, AppSpacing.large)
                            .frame(height: 52)
                            .background(AppColors.flamingo, in: Capsule())
                            .foregroundStyle(AppColors.snow)
                    } else {
                        HStack(spacing: 6) {
                            Text("Next").font(.headline)
                            Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, AppSpacing.medium)
                        .frame(height: 52)
                        .background(AppColors.flamingo, in: Capsule())
                        .foregroundStyle(AppColors.snow)
                    }
                }
                .accessibilityLabel(isLast ? "Done" : "Next step")
            }
        }
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

    private var wording: some View {
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

    private var tabBar: some View {
        HStack(spacing: AppSpacing.small) {
            Button { model.cycleCompare() } label: {
                Image(systemName: model.compare.symbol)
                    .font(.title3)
                    .foregroundStyle(AppColors.snow)
                    .frame(width: 52, height: 52)
                    .background(LinearGradient(colors: [AppColors.flamingo, AppColors.wine], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .overlay(Circle().strokeBorder(AppColors.snow.opacity(0.8), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compare")
            .accessibilityValue(model.compare.label)
            ForEach(TutorialTab.allCases) { tab in
                let selected = tab == model.tab
                Button { model.select(tab) } label: {
                    Text(tab.title)
                        .font(.headline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(AppColors.snow.opacity(selected ? 1 : 0.55))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Plain camera picture from the shared face session, with no content: the "real" side of the comparison.
private struct RealCameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}
