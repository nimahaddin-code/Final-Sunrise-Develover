import ARKit
import SwiftUI
import UIKit

/// The rounded camera card on the Try On home screen. One ARKit face session fills it: blush is drawn on the face mesh,
/// the eyebrow follows MediaPipe landmarks on the same frames, and the eyeliner overlay sits on top.
struct TryOnLiveCard: View {
    @ObservedObject var home: TryOnHomeModel
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    @StateObject private var advisor = CameraAdvisor(context: .tryOn)
    @StateObject private var light = ScreenLight()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(home: TryOnHomeModel) {
        self.home = home
        camera = home.camera
        brow = home.brow
    }

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if home.isComparing {
                Text("Without makeup")
                    .font(AppTypography.caption.weight(.semibold))
                    .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                    .background(AppColors.wine.opacity(0.85), in: Capsule())
                    .foregroundStyle(AppColors.snow)
                    .padding(.bottom, AppSpacing.medium)
            }
        }
        // Hold to see the bare face; VoiceOver users toggle it with the action below.
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 60, perform: {},
                            onPressingChanged: { home.isComparing = $0 })
        // The camera checks and the light run only while this card is on screen with the app in front.
        .onChange(of: scenePhase == .active && home.active, initial: true) { _, running in
            if running { advisor.start(); light.resume() } else { advisor.stop(); light.suspend() }
        }
        .onDisappear { advisor.stop(); light.turnOff() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Compare without makeup") { home.isComparing.toggle() }
        .animation(.easeInOut(duration: 0.2), value: home.isComparing)
    }

    @ViewBuilder private var content: some View {
        switch brow.availability {
        case .notChecked:
            ProgressView().tint(AppColors.snow)
        case .unsupported:
            CardMessage(symbol: "faceid", title: "Live try-on unavailable",
                        message: "Live try-on needs an iPhone with a TrueDepth front camera.")
        case .supported:
            if camera.denied {
                CardMessage(symbol: "camera", title: "I need your camera to be your mirror.",
                            message: "Nothing is saved or uploaded.",
                            actionTitle: "Turn on camera", action: openSettings)
            } else if camera.failure != nil {
                CardMessage(symbol: "exclamationmark.triangle", title: "Camera stopped",
                            message: "Face tracking stopped unexpectedly.")
            } else if camera.authorized {
                live
            } else {
                ProgressView().tint(AppColors.snow)
            }
        }
    }

    private var live: some View {
        ZStack {
            LiveGuideView(camera: camera, referenceID: "eyebrows", active: home.active && scenePhase == .active && !advisor.pausesSession,
                          // Brow/blush preview, faded to 30% while a camera message shows.
                          eyebrowConfiguration: previewConfiguration, onFrame: { [relay = home.relay] frame, face in
                              relay.deliver(frame, face)
                          }, reducedFrameRate: advisor.reducesLoad)
            LinerOverlayView(model: home.liner, isVisible: !home.isComparing)
                .opacity(advisor.isDimmed ? Self.dimmedOpacity : 1)
                .animation(.easeInOut(duration: 0.25), value: advisor.isDimmed)
            if home.tool == .eyebrow && EyebrowConfiguration.showsBrowTracking && home.browLandmarksVisible
                && !home.isOff && !home.isComparing {
                BrowTrackingOverlayView(feed: camera.browTracking)
            }
        }
        // Pinch or tap the chip to zoom the picture and its overlays together; the light and captions stay put.
        .cameraZoom()
        .overlay {
            ScreenLightGlow(light: light)
        }
        .overlay {
            if let status {
                StatusPill(text: status)
            }
        }
        .overlay(alignment: .leading) {
            ScreenLightButton(light: light, pulse: advisor.darkPulse).padding(.leading, AppSpacing.small)
        }
        .overlay(alignment: .bottom) {
            CameraGuidanceCaption(advisor: advisor, lightOn: light.isOn, stepLabel: nil, stepText: nil)
                .padding(.bottom, AppSpacing.large)
        }
    }

    static let dimmedOpacity = 0.3

    /// The brow/blush preview, faded to 30% while a camera message shows.
    private var previewConfiguration: EyebrowConfiguration {
        var value = home.liveConfiguration
        guard advisor.isDimmed else { return value }
        let factor = Float(Self.dimmedOpacity)
        value.previewIntensity *= factor
        value.browLayer.intensity *= factor
        value.blushLayer.intensity *= factor
        return value
    }

    /// Brow/blush status for the selected tool only. Blush shows a prompt until the live camera has fitted the cheeks,
    /// then the renderer's status; the eyebrow follows MediaPipe landmarks, so the renderer reports when it has a face.
    /// Eyeliner follows the eyes on its own, so it never shows these messages.
    private var status: String? {
        guard home.tool == .blush || home.tool == .eyebrow, home.canTry(home.tool), !home.isOff else { return nil }
        if home.tool == .eyebrow { return camera.beautyStatus }
        return camera.eyebrowGuideReady ? camera.beautyStatus : String(localized: "Look straight at the camera to place your makeup")
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct StatusPill: View {
    let text: String

    var body: some View {
        VStack {
            Text(text)
                .font(AppTypography.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                .background(AppColors.wine.opacity(0.85), in: Capsule())
                .foregroundStyle(AppColors.snow)
                .padding(.top, AppSpacing.medium)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer()
        }
    }
}

private struct CardMessage: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(AppTypography.heading)
            Text(message).font(AppTypography.body).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent).tint(AppColors.flamingo)
            }
        }
        .foregroundStyle(AppColors.snow)
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.cocoa)
    }
}

/// Digital zoom for the live camera card: pinch, or tap the chip to step through 1x / 1.5x / 2x / 3x. Everything inside
/// (camera picture and overlays) scales together around the upper middle of the card, where the eyes are, so overlays
/// stay on the face. Face tracking is unchanged: only what is shown is enlarged, so nobody has to lean into the phone.
struct CameraZoomModifier: ViewModifier {
    static let steps: [CGFloat] = [1, 1.5, 2, 3]
    static let range: ClosedRange<CGFloat> = 1...3

    var enabled = true
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private var current: CGFloat { !enabled ? 1 : min(max(zoom * pinch, Self.range.lowerBound), Self.range.upperBound) }

    func body(content: Content) -> some View {
        content
            .environment(\.cameraZoom, current)
            .scaleEffect(current, anchor: UnitPoint(x: 0.5, y: 0.42))
            .clipped()
            .gesture(MagnificationGesture()
                .updating($pinch) { value, state, _ in state = value }
                .onEnded { value in zoom = min(max(zoom * value, Self.range.lowerBound), Self.range.upperBound) })
            .overlay(alignment: .trailing) {
                if enabled { Button {
                    let next = Self.steps.first { $0 > zoom + 0.01 } ?? Self.steps[0]
                    withAnimation(.easeOut(duration: 0.2)) { zoom = next }
                } label: {
                    Text(String(format: current.rounded() == current ? "%.0f×" : "%.1f×", current))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(AppColors.wine.opacity(0.75), in: Capsule())
                        .foregroundStyle(AppColors.snow)
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppSpacing.small)
                .accessibilityLabel("Zoom")
                .accessibilityValue(String(format: "%.1f times", current)) }
            }
    }
}

extension View {
    func cameraZoom(_ enabled: Bool = true) -> some View { modifier(CameraZoomModifier(enabled: enabled)) }
}

private struct CameraZoomKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
    /// The current camera zoom, so thin overlay strokes can stay the same on-screen width while the picture scales.
    var cameraZoom: CGFloat {
        get { self[CameraZoomKey.self] }
        set { self[CameraZoomKey.self] = newValue }
    }
}
