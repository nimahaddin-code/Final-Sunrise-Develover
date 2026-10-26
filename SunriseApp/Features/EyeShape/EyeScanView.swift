import SwiftUI
import UIKit

/// The eye scan screen: the front camera, guidance while measuring, and a result sheet. Writes the result to `store`.
struct EyeScanView: View {
    @ObservedObject var store: FaceShapeStore
    /// Label of the result sheet's main button.
    var continueTitle: LocalizedStringKey = "See my makeup"
    var onFinish: () -> Void = {}
    /// Called with the scan picture when a scan finishes (before the result sheet's button is used). Debug tools only.
    var onResult: (ScanSnapshot?) -> Void = { _ in }
    @StateObject private var model = EyeScanViewModel()
    @State private var resultReady = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .background(AppColors.background)
            .foregroundStyle(AppColors.ink)
            .navigationTitle("Eye Shape")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.startIfNeeded() }
            .onDisappear { model.stop() }
            // Let the "done" badge show for a moment before the result sheet covers the camera.
            .task(id: model.result != nil) {
                guard model.result != nil else { resultReady = false; return }
                try? await Task.sleep(for: .seconds(1.1))
                if !Task.isCancelled { resultReady = true }
            }
            .sheet(isPresented: resultPresented) {
                if let result = model.result {
                    EyeShapeResultView(result: result, snapshot: model.snapshot, continueTitle: continueTitle, onChooseLid: model.chooseLid,
                                       onScanAgain: model.scanAgain) {
                        // Stopping clears the result, which closes this popup before leaving the scan.
                        model.stop()
                        onFinish()
                    }
                    .background(AppColors.background)
                    .foregroundStyle(AppColors.ink)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: model.result) { _, result in
                if let result { store.eyes = result; onResult(model.snapshot) }
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
        case .scanning, .finished:
            // One branch so the camera view keeps its identity while the result popup is shown.
            scanner
        case .unavailable:
            ContentUnavailableView("Eye scanning unavailable", systemImage: "eye.slash",
                description: Text("This device has no front camera available. Real eye scanning needs an iPhone."))
        case .cameraDenied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "camera")
            } description: {
                Text("Allow camera access in Settings to scan your eyes. No photos are saved or uploaded.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("Scan failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The eye scan could not start. Try again.")
            } actions: {
                Button("Try again") { Task { await model.start() } }
            }
        }
    }

    /// Dismissing the popup starts a new measurement.
    private var resultPresented: Binding<Bool> {
        Binding(get: { model.result != nil && resultReady }, set: { presented in
            if !presented, model.result != nil { model.scanAgain() }
        })
    }

    private var scanStatus: (progress: Double, message: LocalizedStringKey) {
        switch model.phase {
        case .scanning(let progress, let guidance): (progress, guidance.message)
        case .finished: (1, "Done. Your eye shape is ready.")
        default: (0, "Position your face in the frame")
        }
    }

    private var scanner: some View {
        let (progress, message) = scanStatus
        return ZStack {
            CameraPreviewView(camera: model.camera).ignoresSafeArea()
            // Centered on the screen, a little above the middle so the card below never covers it.
            Ellipse().stroke(AppColors.rose.opacity(0.8), style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                .frame(width: 260, height: 340).offset(y: -40).accessibilityHidden(true)
            VStack {
                Spacer()
                HStack(spacing: AppSpacing.medium) {
                    ScanProgressRing(progress: progress)
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(message).font(AppTypography.body)
                        Text("Look straight at the camera with your eyes open and relaxed.")
                            .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpacing.large)
                .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                .padding(AppSpacing.large)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay { doneBadge }
        .animation(.spring(duration: 0.35), value: model.result != nil)
    }

    @ViewBuilder private var doneBadge: some View {
        if model.result != nil {
            ScanDoneBadge().transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

private extension EyeScanGuidance {
    var message: LocalizedStringKey {
        switch self {
        case .findFace: "Position your face in the frame"
        case .moveCloser: "Bring the phone a little closer"
        case .moveBack: "Hold the phone a little farther away"
        case .lookStraight: "Face the camera straight on"
        case .openEyes: "Open your eyes a little wider"
        case .holdStill: "Hold still, measuring…"
        }
    }
}

#Preview { NavigationStack { EyeScanView(store: FaceShapeStore()) } }
