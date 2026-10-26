import ARKit
import SwiftUI
import UIKit

/// The rounded camera card on the Try On home screen. One ARKit face session fills it: blush and eyebrow are drawn on
/// the face mesh, and the eyeliner overlay sits on top and is fed the same camera frames.
struct TryOnLiveCard: View {
    @ObservedObject var home: TryOnHomeModel
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
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
                CardMessage(symbol: "camera", title: "Camera access needed",
                            message: "Allow camera access in Settings to try on makeup. Nothing is saved or uploaded.",
                            actionTitle: "Open Settings", action: openSettings)
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
            LiveGuideView(camera: camera, referenceID: "eyebrows", active: home.active && scenePhase == .active,
                          eyebrowConfiguration: home.liveConfiguration, onFrame: { [relay = home.relay] frame, face in
                              relay.deliver(frame, face)
                          })
            LinerOverlayView(model: home.liner, isVisible: !home.isComparing)
            if let status {
                StatusPill(text: status)
            }
        }
    }

    /// Tells the person what the face scan is waiting for, for the selected tool only. Eyeliner follows the eyes on its own,
    /// so it never shows the blush/eyebrow scan messages, even while those looks are on.
    // -Nimah: Launch already handles scanning. Live tracking has no calibration prompts or scan controls.
    private var status: String? {home.tool == .blush ? camera.beautyStatus:nil}

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
