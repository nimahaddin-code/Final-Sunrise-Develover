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
        CaptureCameraCard(home: home, light: light, captured: captured, active: visible && scenePhase == .active)
            .ignoresSafeArea()
            .overlay { if captured == nil { FaceOvalGuide() } }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 28) {
                    if captured == nil { hint }
                    CaptureControls(camera: home.camera, brow: home.brow, captured: $captured, onShoot: shoot, onNext: next)
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
            .onChange(of: captured == nil) { _, retake in if retake && visible { activate() } }
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
        Label(stage == .desired ? "Fit your whole face inside the line" : "Both sides done. Look at you! Let's take your after photo.",
              systemImage: "face.smiling")
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

    /// The camera picture as shown. The eyeliner is a SwiftUI overlay, so it is drawn into the picture here.
    private func shoot() {
        guard var image = home.camera.view?.snapshot() else { return }
        if stage == .desired && handoff.tool == .eyeliner { image = home.liner.composed(image) }
        captured = image
        // The still replaces the camera until Retake.
        home.deactivate()
    }

    private func next() {
        store.store(captured, for: stage)
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
    let active: Bool
    @Environment(\.openURL) private var openURL

    init(home: TryOnHomeModel, light: ScreenLight, captured: UIImage?, active: Bool) {
        self.home = home
        camera = home.camera
        brow = home.brow
        self.light = light
        self.captured = captured
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
                                  eyebrowConfiguration: home.liveConfiguration, onFrame: { [relay = home.relay] frame, face in
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
