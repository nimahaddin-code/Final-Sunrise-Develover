import SwiftUI
import UIKit

/// "Before photo": the camera fills the page with a dashed oval for the whole face; back, the style's name and the screen
/// light sit in the top safe area, the hint and a round shutter at the bottom, then Retake / Next. `.desired` draws the
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
    @StateObject private var light = ScreenLight()
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
        CaptureCameraCard(home: home, light: light, captured: captured, configuration: cameraConfiguration,
                          active: visible && scenePhase == .active)
            .ignoresSafeArea()
            .overlay { if captured == nil { FaceOvalGuide() } }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 28) {
                    if captured == nil { hint }
                    CaptureControls(camera: home.camera, brow: home.brow, captured: $captured, onShoot: shoot, onNext: next)
                        .disabled(shooting)
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.bottom, AppSpacing.medium)
            }
            .background { (light.isOn ? AppColors.ringLight : Color.black).ignoresSafeArea() }
            .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.25), value: light.isOn)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .sensoryFeedback(.success, trigger: captured != nil)
            // Retake: back to the live camera.
            .onChange(of: captured == nil) { _, retake in
                if retake { scanned = nil; diagnostics = nil; bareImage = nil; if visible { activate() } }
            }
            .onAppear { visible = true; activate(); light.resume() }
            .onDisappear { visible = false; home.deactivate(); light.turnOff() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && visible { activate(); light.resume() } else { home.deactivate(); light.suspend() }
            }
    }

    /// Back, the style's name and the screen light.
    private var topBar: some View {
        HStack {
            Button {
                home.deactivate()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            StylePill(handoff: handoff, onGlass: true)
            Spacer()
            ScreenLightButton(light: light, pulse: 0, plainGlass: true)
        }
        .padding(AppSpacing.small)
    }

    private var hint: some View {
        Label("Fit your whole face inside the line", systemImage: "face.smiling")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppColors.snow)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.35), in: Capsule())
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
            // The bare camera of this moment (SceneKit draws nothing for the capture): the Before's fallback when the try-on photo is missing.
            // `ARSCNView.snapshot()` comes at scale 1 (one point per pixel); the eyeliner is drawn in view points, so
            // at that scale it landed a third of the way, top left. Give it the view's size in points.
            let bare = Self.inPoints(view.snapshot(), of: view.bounds.size)
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

    /// The same pixels, with the scale that makes the picture `size` points wide.
    private static func inPoints(_ image: UIImage, of size: CGSize) -> UIImage {
        guard let cg = image.cgImage, size.width > 0, abs(image.size.width - size.width) > 0.5 else { return image }
        return UIImage(cgImage: cg, scale: CGFloat(cg.width) / size.width, orientation: image.imageOrientation)
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
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retake photo")
                CaptureCapsuleButton(title: "Next", action: onNext)
            }
        } else if !noCamera {
            Button(action: onShoot) {
                Circle()
                    .fill(AppColors.snow)
                    .padding(6)
                    .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: 4))
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!camera.authorized)
            .accessibilityLabel("Take picture")
        } else {
            // Simulator or no camera: keep the flow going without a photo.
            CaptureCapsuleButton(title: "Continue without photo", action: onNext)
        }
    }
}

/// Full-width dark glass capsule, like Try On's Continue.
private struct CaptureCapsuleButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.snow)
                .frame(maxWidth: .infinity, minHeight: 56)
                .glassEffect(.regular.tint(AppColors.buttonInk).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The dashed oval the whole face goes inside.
private struct FaceOvalGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.78
            let height = min(width * 1.42, proxy.size.height * 0.56)
            Ellipse()
                .stroke(AppColors.snow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [10, 8]))
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                .shadow(color: .black.opacity(0.25), radius: 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The full-page camera, or the still once taken.
private struct CaptureCameraCard: View {
    @ObservedObject var home: TryOnHomeModel
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    @ObservedObject var light: ScreenLight
    let captured: UIImage?
    let configuration: EyebrowConfiguration
    let active: Bool
    @Environment(\.openURL) private var openURL

    init(home: TryOnHomeModel, light: ScreenLight, captured: UIImage?, configuration: EyebrowConfiguration, active: Bool) {
        self.home = home
        camera = home.camera
        brow = home.brow
        self.light = light
        self.captured = captured
        self.configuration = configuration
        self.active = active
    }

    var body: some View {
        ZStack {
            if !light.isOn { Color.black }
            if let captured {
                Color.clear.overlay { Image(uiImage: captured).resizable().scaledToFill() }.clipped()
            } else {
                content
            }
        }
        // The screen light: the picture's edge melts into the white screen, which is what lights the face.
        .mask {
            Rectangle()
                .padding(light.isOn ? 26 : 0)
                .blur(radius: light.isOn ? 26 : 0)
        }
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
