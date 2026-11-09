import SwiftUI
import UIKit

/// "Take a picture": the live camera with the face feature's frame, a shutter, then Retake / Next. `.desired` draws the
/// look chosen on Try On (the picture the result is compared with); `.result` is the plain camera after the tutorial.
/// Without a usable camera (Simulator, no TrueDepth, permission denied) it can continue without a photo, so the flow
/// still runs end to end.
struct FeatureCaptureView: View {
    let stage: CaptureStage
    let handoff: TutorialHandoff
    @ObservedObject var store: MakeupFlowStore
    let onBack: () -> Void
    let onNext: () -> Void
    @StateObject private var home: TryOnHomeModel
    @State private var captured: UIImage?
    /// -Nimah: the face measured at the shutter, for the blush feedback.
    @State private var scanned: FaceScan?
    @State private var shooting = false
    @State private var diagnostics: CaptureDiagnostics?
    @State private var bareImage: UIImage?
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    init(stage: CaptureStage, handoff: TutorialHandoff, plan: MakeupPlan, assessment: FaceShapeAssessment,
         checker: any FaceTrackingAvailabilityChecking, store: MakeupFlowStore,
         onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.stage = stage
        self.handoff = handoff
        self.store = store
        self.onBack = onBack
        self.onNext = onNext
        _home = StateObject(wrappedValue: TryOnHomeModel(tool: handoff.tool, plan: plan, assessment: assessment, checker: checker))
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            ZStack {
                Text("Take a picture")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    GlassCircleButton(symbol: "chevron.left", size: 44, tint: AppColors.glassLight, label: "Back") {
                        home.deactivate()
                        onBack()
                    }
                    Spacer()
                }
            }
            CaptureCameraCard(home: home, tool: handoff.tool, captured: captured, configuration: cameraConfiguration,
                              active: visible && scenePhase == .active)
                .frame(maxHeight: .infinity)
            VStack(spacing: 2) {
                Text(handoff.styleTitle).font(.title3.weight(.semibold))
                Text(stage == .desired ? "Your desired look" : "Both sides done. Look at you! Let's take your after photo.")
                    .multilineTextAlignment(.center)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.snow.opacity(0.75))
            }
            CaptureControls(camera: home.camera, brow: home.brow, captured: $captured, onShoot: shoot, onNext: next)
                .disabled(shooting)
        }
        .foregroundStyle(AppColors.snow)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: captured != nil)
        // Retake: back to the live camera.
        .onChange(of: captured == nil) { _, retake in
            if retake { scanned = nil; diagnostics = nil; bareImage = nil; if visible { activate() } }
        }
        .onAppear { visible = true; activate() }
        .onDisappear { visible = false; home.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible { activate() } else { home.deactivate() }
        }
    }

    private func activate() {
        guard captured == nil else { return }
        home.activate()
        if stage == .desired { home.apply(handoff) }
    }

    /// -Nimah: blush also measures its target area: on the desired look with the virtual blush, on the result with the
    /// engine running but no pigment drawn (the photo stays the plain camera).
    private var cameraConfiguration: EyebrowConfiguration {
        var configuration = home.liveConfiguration
        guard handoff.tool == .blush, let style = handoff.blushStyle, style.isReferenceLook else { return configuration }
        configuration.blushStyle = style
        configuration.measuresBlushTarget = true
        if stage == .result {
            configuration.layered = false
            configuration.region = .blush
            configuration.showMakeupPreview = true
            configuration.previewAfter = true
            configuration.pigmentHalf = PigmentHalf.none
        }
        return configuration
    }

    /// The camera picture as shown. The makeup engine's own layer is read back (`ARSCNView.snapshot()` has only the
    /// camera under it); the eyeliner is a SwiftUI overlay, so it is drawn into the picture here.
    private func shoot() {
        guard let view = home.camera.view, !shooting else { return }
        shooting = true
        Task { @MainActor in
            defer { shooting = false }
            var pixels: ScreenPixels?
            var report = CaptureDiagnostics()
            // The bare camera of this moment (SceneKit draws nothing for the capture): the feedback's "Before".
            let bare = view.snapshot()
            // The picture on screen is the engine's layer when it is on: on the desired look it has the virtual makeup.
            let makeup = view as? BeautyBlushARView
            report.engine = makeup?.beauty != nil
            report.layerShown = makeup.map { !$0.beautyLayer.isHidden } ?? false
            report.engineOn = makeup?.beauty?.isDrawing ?? false
            report.framesBefore = makeup?.beauty?.presentedFrames ?? 0
            if let makeup, let engine = makeup.beauty, report.layerShown {
                let started = Date()
                pixels = await engine.readScreen()
                if pixels == nil { report.readTries += 1; pixels = await engine.readScreen() }
                report.readTries += 1
                report.readMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
                report.read = pixels != nil ? .read : .timedOut
            }
            var image = pixels?.image(scale: view.window?.screen.scale ?? 3) ?? bare
            if stage == .desired && handoff.tool == .eyeliner {
                image = home.liner.composed(image)
                // The eyeliner is drawn by SwiftUI, not the engine: its target is read from the composed picture.
                pixels = ScreenPixels(image: image)
            }
            let outline = handoff.tool == .blush ? home.camera.blushGuide.snapshot : nil
            scanned = FaceScan.measure(view: view, outline: outline, rendered: pixels)
            report.outline = outline != nil
            report.face = scanned != nil
            diagnostics = report
            if stage == .desired { bareImage = bare }
            captured = image
            // The still replaces the camera until Retake.
            home.deactivate()
        }
    }

    private func next() {
        store.store(captured, for: stage)
        store.store(scanned, for: stage)
        store.diagnostics[stage] = diagnostics
        if stage == .desired { store.bare = bareImage }
        home.deactivate()
        onNext()
    }
}

/// Shutter; Retake and Next once taken; "Continue without photo" when there is no usable camera.
private struct CaptureControls: View {
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    @Binding var captured: UIImage?
    let onShoot: () -> Void
    let onNext: () -> Void

    private var noCamera: Bool {
        if case .unsupported = brow.availability { return true }
        return camera.denied || camera.failure != nil
    }

    var body: some View {
        if captured != nil {
            HStack(spacing: AppSpacing.medium) {
                Button { captured = nil } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3.weight(.medium))
                        .frame(width: 60, height: 60)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retake photo")
                FlowPrimaryButton(title: "Next", action: onNext)
            }
        } else if !noCamera {
            FlowPrimaryButton(title: "Take picture", symbol: "camera", action: onShoot)
                .disabled(!camera.authorized)
        } else {
            // Simulator or no camera: keep the flow going without a photo.
            FlowPrimaryButton(title: "Continue without photo", action: onNext)
        }
    }
}

/// The camera card of the capture screen, or the still once taken, with the feature frame over either.
private struct CaptureCameraCard: View {
    @ObservedObject var home: TryOnHomeModel
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    let tool: TryOnTool
    let captured: UIImage?
    let configuration: EyebrowConfiguration
    let active: Bool
    @Environment(\.openURL) private var openURL

    init(home: TryOnHomeModel, tool: TryOnTool, captured: UIImage?, configuration: EyebrowConfiguration, active: Bool) {
        self.home = home
        camera = home.camera
        brow = home.brow
        self.tool = tool
        self.captured = captured
        self.configuration = configuration
        self.active = active
    }

    var body: some View {
        ZStack {
            Color.black
            if let captured {
                Image(uiImage: captured).resizable().scaledToFill()
            } else {
                content
            }
            FeatureFrameOverlay(tool: tool, highlight: captured == nil ? AppColors.snow : AppColors.flamingo,
                                showsHint: captured == nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch brow.availability {
        case .notChecked:
            ProgressView().tint(AppColors.snow)
        case .unsupported:
            message(symbol: "faceid", title: "Camera unavailable", text: "The photo needs an iPhone with a TrueDepth front camera.")
        case .supported:
            if camera.denied {
                VStack(spacing: AppSpacing.medium) {
                    message(symbol: "camera", title: "I need your camera to be your mirror.", text: "Nothing is saved or uploaded.")
                    Button("Turn on camera") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent).tint(AppColors.flamingo)
                }
            } else if camera.failure != nil {
                message(symbol: "exclamationmark.triangle", title: "Camera stopped", text: "Face tracking stopped unexpectedly.")
            } else if camera.authorized {
                ZStack {
                    LiveGuideView(camera: camera, referenceID: "eyebrows", active: home.active && active,
                                  eyebrowConfiguration: configuration, onFrame: { [relay = home.relay] frame, face in
                                      relay.deliver(frame, face)
                                  })
                    LinerOverlayView(model: home.liner, isVisible: true)
                }
            } else {
                ProgressView().tint(AppColors.snow)
            }
        }
    }

    private func message(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.small) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(AppTypography.heading)
            Text(text).font(AppTypography.body).multilineTextAlignment(.center)
        }
        .foregroundStyle(AppColors.snow)
        .padding(AppSpacing.large)
    }
}
