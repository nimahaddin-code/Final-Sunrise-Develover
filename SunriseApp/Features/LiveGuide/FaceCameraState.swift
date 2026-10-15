// -Nimah: FaceCameraState.swift — implementasi MVP SunriseApp.
import SwiftUI
import ARKit
import AVFoundation

@MainActor final class FaceCameraState: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published var tracked = false
    @Published var calibrated = false
    @Published var message = "Position your face in the frame"
    @Published var failure: String?
    @Published var overlay = false
    weak var view: ARSCNView?
    var stopSession: (() -> Void)?
    private var lastTrackedAt: Date?
    func requestPermission() async {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let result: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: result = true
        case .notDetermined: result = await AVCaptureDevice.requestAccess(for: .video)
        default: result = false
        }
        authorized = result; denied = !result
    }
    func report(tracked: Bool, ready: Bool) {
        self.tracked = tracked
        if tracked { lastTrackedAt = Date() }
        if !tracked { calibrated = false } else if ready { calibrated = true }
        message = tracked ? (calibrated ? "Face tracked · ready to glow" : "Hold still for 2 seconds") : "Face not tracked · face the camera in good light"
    }
    func suspend() { tracked = false; calibrated = false; lastTrackedAt = nil }
    // -Nimah: Foto hanya boleh diambil saat tracking masih fresh dan overlay sudah mati.
    func capture() -> UIImage? {
        guard authorized, failure == nil, tracked, !overlay,
              let lastTrackedAt, Date().timeIntervalSince(lastTrackedAt) < 0.8, let view,
              view.session.currentFrame?.anchors.contains(where: { ($0 as? ARFaceAnchor)?.isTracked == true }) == true else { return nil }
        return view.snapshot()
    }
}
