// -Nimah: FaceCameraState.swift — implementasi MVP SunriseApp.
import SwiftUI
import ARKit
import AVFoundation
import CoreImage
import ImageIO

@MainActor final class FaceCameraState: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published var tracked = false
    @Published var calibrated = false
    @Published var message = "Position your face in the frame"
    @Published var failure: String?
    @Published var overlay = false
    @Published var guideStep: TutorialStep = .blush
    @Published var previewMode: MakeupPreviewMode = .pointsAndLook
    // -Nimah: Tutorial default satu layer; full look harus dipilih secara eksplisit.
    @Published var previewFullLook = false
    @Published var showPreviousSteps = false
    @Published var eyelinerStyle = EyelinerStyle()
    @Published var debugMode: LiveGuideDebugMode = .off
    @Published var renderMessage = "Preview not started"
    @Published var debugMessage = ""
    @Published var beautyStatus:String?
    @Published var previewStrength: Float = 0.8
    // -Nimah: Shared session + eyebrow module status; tidak menyimpan gambar atau landmark ke disk.
    let trackingManager=ARFaceTrackingManager.shared
    @Published var eyebrowWasTracked=false
    @Published var eyebrowGuideReady=false
    @Published var eyebrowMessage="Hold still with both eyebrows visible"
    @Published var eyebrowDebug="Waiting for Vision mapping"
    @Published var fitReady = false
    @Published var fitMessage = "Look straight ahead to fit the face surface"
    @Published var distanceMeters: Double?
    var distanceHint: String? {
        guard let distanceMeters else { return nil }
        let distance = "Distance: \(Int(distanceMeters * 100)) cm"
        if distanceMeters < 0.18 { return distance + " · move slightly farther if tracking is lost" }
        if distanceMeters > 0.70 { return distance + " · move closer for a larger face view" }
        return distance
    }
    // -Nimah: Practical positioning hints, not a validated hardware distance limit.
    var scanInstruction:String {
        if !tracked { return "Hadapkan wajah ke kamera depan, tampilkan kedua mata dan alis. Coba mulai dari jarak satu lengan pendek dengan cahaya dari depan." }
        if let d=distanceMeters, d<0.25 { return "Wajah terlalu dekat untuk posisi awal. Mundurkan iPhone sedikit, lalu tahan stabil." }
        if let d=distanceMeters, d>0.60 { return "Wajah terlihat jauh. Dekatkan iPhone sedikit agar kedua mata dan alis terlihat jelas." }
        return eyebrowMessage
    }
    func refitFace() {
        stopSession?(); fitReady = false; calibrated = false; eyebrowGuideReady=false
        eyebrowMessage="Hold still with both eyebrows visible"
        fitMessage = "Look straight ahead with relaxed eyes and lips"
    }
    private let imageContext = CIContext()
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
    /// Assigns only when the value changed: `@Published` publishes on every assignment, and the session reports 10 times a second.
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<FaceCameraState, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
    func report(tracked: Bool, ready: Bool) {
        update(\.tracked, tracked)
        if tracked { lastTrackedAt = Date() }
        if !tracked { update(\.calibrated, false) } else if ready && fitReady { update(\.calibrated, true) }
        update(\.message, tracked ? (calibrated ? "Tracking active · check makeup alignment" : (fitReady ? "Hold still for 2 seconds" : "Hold still · fitting your face surface")) : "Face not tracked · face the camera in good light")
    }
    func suspend() { update(\.tracked, false); update(\.calibrated, false); lastTrackedAt = nil; update(\.distanceMeters, nil) }
    // -Nimah: Capture dari buffer kamera asli, sehingga titik/mesh render tidak pernah masuk foto.
    func capture() -> UIImage? {
        guard authorized, failure == nil, tracked,
              let lastTrackedAt, Date().timeIntervalSince(lastTrackedAt) < 0.8, let view, let frame = view.session.currentFrame,
              frame.anchors.contains(where: { ($0 as? ARFaceAnchor)?.isTracked == true }) else { return nil }
        // -Nimah: Portrait front-camera orientation; verifikasi mirroring di iPhone fisik tetap wajib.
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.leftMirrored)
        guard let rendered = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
