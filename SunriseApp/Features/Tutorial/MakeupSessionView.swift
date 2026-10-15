// -Nimah: MakeupSessionView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct MakeupSessionView: View {
    let reference: MakeupReference
    let store: any SavedLooksStoring
    let inspiration: UIImage?
    var onFinish: () -> Void
    @StateObject private var availability: FaceCalibrationViewModel
    @StateObject private var camera = FaceCameraState()
    @StateObject private var tutorial: TutorialViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var manual = false
    @State private var started = false
    @State private var comparing = false
    @State private var before: UIImage?
    @State private var after: UIImage?
    @State private var captureError: String?
    init(reference: MakeupReference, checker: any FaceTrackingAvailabilityChecking, store: any SavedLooksStoring,
         inspiration: UIImage? = nil, onFinish: @escaping () -> Void) {
        self.reference = reference; self.store = store; self.inspiration = inspiration; self.onFinish = onFinish
        _availability = StateObject(wrappedValue: FaceCalibrationViewModel(checker: checker))
        _tutorial = StateObject(wrappedValue: TutorialViewModel(tutorial: Tutorial(referenceID: reference.id, steps: TutorialStep.allCases)))
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack { Text(reference.name).font(AppTypography.heading); Spacer(); Text("YOUR GLOW SESSION").font(.caption2).foregroundStyle(AppColors.rose) }
            if manual { LookArtwork(referenceID: reference.id); Text("Manual tutorial · camera is off").font(.caption).foregroundStyle(AppColors.subtle) }
            else if availability.availability == .supported && camera.authorized && camera.failure == nil {
                LiveGuideView(camera: camera, color: UIColor(LookArtwork.color(for: reference.id)), active: visible && scenePhase == .active && !comparing)
                    .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    .overlay(alignment: .bottom) { Text(camera.message).font(.caption).multilineTextAlignment(.center).padding().background(.ultraThinMaterial, in: Capsule()).padding() }
            } else { cameraFallback }
            if let inspiration { DisclosureGroup("My inspiration · manually selected") { Image(uiImage: inspiration).resizable().scaledToFit().frame(maxHeight: 220) } }
            if !started {
                FaceCalibrationView(calibrated: camera.calibrated, tracked: camera.tracked, onCapture: captureBefore) { beginManual() }
            } else {
                TutorialView(model: tutorial, referenceID: reference.id, manual: manual, overlay: $camera.overlay,
                             canCapture: camera.tracked && !camera.overlay, onCapture: captureAfter, onFinishManual: onFinish)
                if !manual { Button("Switch to manual tutorial") { beginManual() } }
            }
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink)
        .navigationTitle("My tutorial").navigationBarTitleDisplayMode(.inline)
        .task { await availability.loadAvailability(); if availability.availability == .supported { await camera.requestPermission() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { camera.suspend() }
            else if !manual && availability.availability == .supported { Task { await camera.requestPermission() } }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; camera.stopSession?(); camera.suspend() }
        .alert("Camera capture", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) { Button("OK") { captureError = nil } } message: { Text(captureError ?? "") }
        .sheet(isPresented: $comparing) {
            if let before, let after {
                NavigationStack { ComparisonView(referenceID: reference.id, before: before, after: after, store: store) { comparing = false; onFinish() } }
            }
        }
    }
    private var cameraFallback: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label("Live camera guide", systemImage: "faceid").font(AppTypography.heading)
            if case .unsupported(let reason) = availability.availability { Text(reason) }
            else if camera.denied {
                Text("Camera access is off. Allow access in Settings or continue with the manual tutorial.")
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } else if let failure = camera.failure {
                Text("Camera session stopped: \(failure)")
                Button("Retry camera") { camera.failure = nil; camera.suspend() }
            } else { Text("Preparing your camera. You can also continue manually.") }
        }.padding(AppSpacing.large).frame(maxWidth: .infinity, alignment: .leading).background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }
    private func beginManual() { manual = true; started = true; camera.overlay = false; camera.stopSession?(); camera.suspend(); before = nil; after = nil }
    private func captureBefore() {
        guard camera.calibrated, let photo = camera.capture() else { captureError = "Face tracking is not ready. Face the camera and try again."; return }
        before = photo; started = true; camera.overlay = true
    }
    private func captureAfter() {
        guard let photo = camera.capture() else { captureError = "Face tracking was lost. Face the camera and try again."; return }
        after = photo; comparing = true
    }
}
