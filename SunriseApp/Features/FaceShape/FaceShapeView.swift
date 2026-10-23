import SwiftUI
import UIKit

struct FaceShapeView: View {
    @ObservedObject var store: FaceShapeStore
    /// Opens the makeup recommendations for the scanned face shape.
    var onShowMakeup: () -> Void = {}
    /// Label of the result popup's main button.
    var continueTitle: LocalizedStringKey = "Try on recommended makeup"
    /// Called with the scan picture when a scan finishes (before the result popup's button is used). Debug tools only.
    var onResult: (ScanSnapshot?) -> Void = { _ in }
    @StateObject private var model = FaceShapeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .background(AppColors.background)
            .foregroundStyle(AppColors.ink)
            .navigationTitle("Face Shape")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.startIfNeeded() }
            .onDisappear { model.stop() }
            .sheet(isPresented: resultPresented) {
                if let result = model.result {
                    FaceShapeResultView(result: result, snapshot: model.snapshot, continueTitle: continueTitle,
                                        onScanAgain: model.scanAgain) {
                        // Stopping clears the result, which closes this popup before leaving the scan.
                        model.stop()
                        onShowMakeup()
                    }
                        .background(AppColors.background)
                        .foregroundStyle(AppColors.ink)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: model.result) { _, result in
                if let result { store.latest = result; onResult(model.snapshot) }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-check camera access after returning from Settings.
                if newPhase == .active, model.phase == .cameraDenied { Task { await model.start() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ProgressView("Starting camera")
        case .scanning, .interrupted, .finished:
            // One branch so the camera view keeps its identity while the result popup is shown.
            scanner
        case .unsupported:
            ContentUnavailableView("Face scanning unavailable", systemImage: "faceid",
                description: Text("Face shape detection needs an iPhone with a TrueDepth front camera."))
        case .cameraDenied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "camera")
            } description: {
                Text("Allow camera access in Settings to scan your face. No photos are saved or uploaded.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("Scan failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Face tracking stopped unexpectedly.")
            } actions: {
                Button("Try again") { Task { await model.start() } }
            }
        }
    }

    /// Dismissing the popup starts a new measurement on the still-running camera.
    private var resultPresented: Binding<Bool> {
        Binding(get: { model.result != nil }, set: { presented in
            if !presented, model.result != nil { model.scanAgain() }
        })
    }

    private var scanStatus: (progress: Double, message: LocalizedStringKey) {
        switch model.phase {
        case .scanning(let progress, let guidance): (progress, guidance.message)
        case .finished(let result): (1, "Your face shape: \(Text(result.shape.title))")
        default: (0, "Camera paused. Scanning resumes when the camera is available.")
        }
    }

    private var scanner: some View {
        let (progress, message) = scanStatus
        return ZStack(alignment: .bottom) {
            FaceMeshARView(session: model.session, snapshotter: model.snapshotter).ignoresSafeArea()
            VStack(spacing: AppSpacing.medium) {
                Text(message).font(AppTypography.body).multilineTextAlignment(.center)
                ProgressView(value: progress).tint(AppColors.rose)
                Text("Keep a neutral face and look straight at the camera.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.large)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .padding(AppSpacing.large)
            .accessibilityElement(children: .combine)
        }
    }
}

private extension FaceShapeViewModel.ScanGuidance {
    var message: LocalizedStringKey {
        switch self {
        case .findFace: "Position your face in the frame"
        case .turnLeft: "Turn your head slightly to your left"
        case .turnRight: "Turn your head slightly to your right"
        case .raisePhone: "Raise the phone to eye level"
        case .lowerPhone: "Lower the phone to eye level"
        case .moveCloser: "Bring the phone a little closer"
        case .moveBack: "Hold the phone a little farther away"
        case .relaxFace: "Relax your face and close your mouth"
        case .holdStill: "Hold still, measuring…"
        }
    }
}

#Preview { NavigationStack { FaceShapeView(store: FaceShapeStore()) } }
