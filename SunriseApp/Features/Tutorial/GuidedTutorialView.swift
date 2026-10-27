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
    var linerLook: LinerLook = .winged
}

/// What the bottom-left button shows: the full filter, half filter / half real camera, or no filter.
enum TutorialCompare: CaseIterable {
    case filter, split, off
    var next: TutorialCompare {
        switch self { case .filter: .split; case .split: .off; case .off: .filter }
    }
    var symbol: String {
        switch self { case .filter: "circle.fill"; case .split: "circle.lefthalf.filled"; case .off: "circle" }
    }
    var label: LocalizedStringKey {
        switch self { case .filter: "Filter on"; case .split: "Half filter, half real"; case .off: "Filter off" }
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
    @Published private(set) var compare = TutorialCompare.filter
    /// After the last step: the camera shows the whole assigned look, with no guide, for taking a photo.
    @Published private(set) var photoMode = false
    private let linerStyle: LinerStyle?
    private let linerIsNeutral: Bool
    private var bag = Set<AnyCancellable>()

    init(checker: any FaceTrackingAvailabilityChecking, assessment: FaceShapeAssessment, plan: MakeupPlan, handoff: TutorialHandoff) {
        self.handoff = handoff
        let start = TutorialTab(tool: handoff.tool)
        tab = start
        if case .eyeliner(let style)? = plan.madeForYou.first(where: { $0.category == .eyeliner })?.style {
            linerStyle = EyelinerPlanner.style(style, look: handoff.linerLook)
        } else { linerStyle = nil }
        linerIsNeutral = plan.eyeliner.isNeutral
        brow = EyebrowViewModel(checker: checker, assessment: assessment, initialRegion: start == .blush ? .blush : .eyebrows, startTutorial: true)
        relay = LinerFrameRelay(model: liner)
        // The guide points follow the skin when the person pulls the lid or the corner of the eye outward.
        liner.followsPulledLid = true
        applyShade(for: start == .blush ? .blush : .eyebrow)
        // The brow model owns the step index for brows/blush; forward its changes so the screen redraws.
        brow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
    }

    var stepIndex: Int { tab == .eyeliner ? linerStep : brow.stepIndex }

    /// False when this face shape has no saved reference for the tab (nothing is drawn rather than a default).
    var hasGuide: Bool { tab == .eyeliner ? linerStyle != nil : brow.hasRecommendation }

    var lessons: [FaceGuideLesson] {
        guard hasGuide else {
            return [FaceGuideLesson(title: "No guide yet", instruction: "This face shape has no saved reference for this step. Scan your face again from your profile, or use the other tabs.")]
        }
        if tab == .eyeliner, let linerStyle { return Self.linerLessons(linerStyle, neutral: linerIsNeutral) }
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
        if tab == .eyeliner { value.usesLaunchFit = true }
        if tab == .eyeliner || !hasGuide || compare == .off { value.showGuide = false; value.showMakeupPreview = false; value.tutorialStep = nil }
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

    func activate() { camera.overlay = true; syncLiner() }

    func deactivate() {
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
        guard tab == .eyeliner || photoMode, let linerStyle else {
            relay.setEnabled(false)
            liner.setStyle(nil, shade: nil, intensity: 1)
            return
        }
        relay.setEnabled(true)
        liner.setStyle(linerStyle, shade: handoff.shades[.eyeliner], intensity: handoff.intensities[.eyeliner] ?? 1)
    }

    /// One step: the guide shows only the key points of the liner, and the wording says how to join them.
    static func linerLessons(_ style: LinerStyle, neutral: Bool) -> [FaceGuideLesson] {
        let ending = style.wingLength > 0.02
            ? "Join the dots along your upper lash line from the inner start to the outer corner, then flick out to the last dot to make the wing."
            : "Join the dots along your upper lash line from the inner start to the outer corner, ending at the last dot."
        let fitted = neutral ? " This is a natural line; scan your eyes from your profile for a fitted style." : ""
        return [FaceGuideLesson(title: "Follow the dots", instruction: "\(ending) Keep it close to the lashes, then soften any hard edge with a cotton swab.\(fitted)")]
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
        .task {
            await model.brow.prepare()
            if model.brow.availability == .supported { await camera.requestPermission() }
        }
        .onAppear { visible = true; model.activate() }
        .onDisappear { visible = false; model.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible { model.activate(); Task { await camera.requestPermission() } } else { model.deactivate() }
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
                if !model.photoMode, model.brow.availability == .supported, camera.authorized, !camera.tracked {
                    Text("Position your face in the frame")
                        .font(AppTypography.body).multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                        .background(AppColors.wine.opacity(0.85), in: Capsule())
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer()
                if !model.photoMode { wording }
            }
            .padding(AppSpacing.small)
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
                message(symbol: "camera", title: "Camera access needed",
                        text: "Allow camera access in Settings to follow the tutorial. Nothing is saved or uploaded.",
                        actionTitle: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else if camera.failure != nil {
                message(symbol: "exclamationmark.triangle", title: "Camera stopped", text: "Face tracking stopped unexpectedly.")
            } else if camera.authorized {
                ZStack {
                    LiveGuideView(camera: camera, referenceID: "eyebrows", active: visible && scenePhase == .active,
                                  // Always a configuration, never nil: nil falls back to the old per-frame blush surface renderer.
                                  eyebrowConfiguration: model.liveConfiguration, onFrame: { [relay = model.relay] frame, face in
                                      relay.deliver(frame, face)
                                  })
                    if model.photoMode {
                        LinerOverlayView(model: model.liner, isVisible: true)
                    } else if model.tab == .eyeliner && model.compare != .off {
                        ZStack {
                            LinerGuideOutline(model: model.liner)
                        }
                        .mask(alignment: .leading) { halfMask(left: true, half: model.compare == .split) }
                    }
                    if model.compare == .split {
                        // The same camera without the filter, covering the right half.
                        RealCameraView(session: camera.trackingManager.session)
                            .mask(alignment: .trailing) { halfMask(left: false) }
                        Rectangle().fill(AppColors.snow.opacity(0.85)).frame(width: 1.5).allowsHitTesting(false)
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
    private func halfMask(left: Bool, half: Bool = true) -> some View {
        GeometryReader { proxy in
            Rectangle().frame(width: half ? proxy.size.width / 2 : proxy.size.width).frame(maxWidth: .infinity, alignment: left ? .leading : .trailing)
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
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .background(AppColors.snow.opacity(0.85), in: Circle())
                        .foregroundStyle(AppColors.wine)
                }
                .accessibilityLabel(index == 0 ? "Back to try on" : "Previous step")
                Spacer()
                Button {
                    if model.advance() { model.enterPhoto() }
                } label: {
                    Image(systemName: isLast ? "camera" : "arrow.right")
                        .font(.title3.weight(.medium))
                        .frame(width: 52, height: 52)
                        .background(AppColors.flamingo, in: Circle())
                        .foregroundStyle(AppColors.snow)
                }
                .accessibilityLabel(isLast ? "Take a photo" : "Next step")
            }
        }
        .buttonStyle(.plain)
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

/// The key points of the eyeliner on each eye: where the line starts, where it ends and, when the look has a wing, the
/// wing's tip. Drawn from the same geometry as the liner overlay; they are only marks to
/// join with the product, so nothing covers the lid.
private struct LinerGuideOutline: View {
    @ObservedObject var model: LinerOverlayModel
    @Environment(\.cameraZoom) private var zoom
    private let pink = Color(red: 0.93, green: 0.38, blue: 0.68)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                canvas
                if let reason = model.unavailableReason {
                    // The eye detector could not start: say so instead of silently drawing nothing.
                    Text(reason).font(.footnote).padding(8).background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white).frame(maxHeight: .infinity, alignment: .center)
                }
            }
                // The overlay model builds the liner in this view's size, so it must be told before it can run.
                .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The three key points: where the line starts, where it ends at the outer corner and, when the look has a wing, the
    /// wing's tip.
    static func keyPoints(of guide: LinerGuide) -> [CGPoint] {
        // `upperLiner` is the lash-line side followed by the outer edge reversed, so its first half is the lash line.
        let lash = guide.upperLiner.prefix(guide.upperLiner.count / 2)
        var points = [lash.first ?? guide.anchors.upperStart, lash.last ?? guide.anchors.outerCorner]
        if let tip = guide.anchors.wingTip { points.append(tip) }
        return points
    }

    private var canvas: some View {
        Canvas { context, _ in
            guard let frame = model.frame, CACurrentMediaTime() - frame.receivedAt <= LinerOverlayRenderer.maxAge else { return }
            let thin = 1 / zoom
            for eye in frame.eyes where eye.alpha > 0.05 {
                let points = Self.keyPoints(of: eye.guide)
                for (index, point) in points.enumerated() {
                    let p = frame.mapping.map(point)
                    // The wing tip, the last point of a winged look, is a little bigger.
                    let radius = (eye.guide.anchors.wingTip != nil && index == points.count - 1 ? 5.0 : 3.5) * thin
                    let dot = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(pink))
                    context.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 1.4 * thin))
                }
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
