import AVFoundation
import SwiftUI

/// Live front-camera picture for the eye scan, upright in portrait. AVFoundation mirrors it for the person, like a mirror.
struct CameraPreviewView: UIViewRepresentable {
    let camera: EyeCameraSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.camera = camera
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) { uiView.updateRotation() }

    final class PreviewUIView: UIView {
        var camera: EyeCameraSession?
        private var startObserver: NSObjectProtocol?
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            // The camera is attached to the session after this view exists, so the rotation can only be set once the
            // session is running. Without it the preview shows the sensor's own landscape orientation.
            startObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateRotation() }
                }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        deinit { startObserver.map(NotificationCenter.default.removeObserver) }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateRotation()
        }

        /// Asks the system which rotation makes the picture upright for this camera and how the phone is held, and keeps
        /// following it.
        func updateRotation() {
            if coordinator == nil, let device = camera?.device {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                self.coordinator = coordinator
                rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.applyRotation() }
                }
            }
            applyRotation()
        }

        private func applyRotation() {
            guard let coordinator, let connection = previewLayer.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
    }
}
