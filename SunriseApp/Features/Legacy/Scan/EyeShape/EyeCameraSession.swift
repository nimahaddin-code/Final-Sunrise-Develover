import AVFoundation

/// The front camera for the eye scan, delivering upright BGRA frames on its own queue (never the main thread).
///
/// ARKit's face session owns the camera during the mesh scan, so stop that session (`FaceShapeViewModel.stop()`)
/// before calling `start()`; the two never run at the same time. Camera permission is asked in the mesh scan
/// step, so this only checks it.
final class EyeCameraSession: NSObject, @unchecked Sendable {
    enum Failure: Error, Equatable { case cameraDenied, noCamera, cannotConfigure }

    /// Called on the camera queue for every frame, with the buffer and its presentation time.
    typealias FrameHandler = @Sendable (CVPixelBuffer, CMTime) -> Void

    /// Shown with `AVCaptureVideoPreviewLayer`, which mirrors the front camera for the person automatically.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "SunriseApp.EyeCameraSession", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var frameHandler: FrameHandler?
    private var isConfigured = false
    private var captureCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureObservation: NSKeyValueObservation?

    /// The front camera, once `start` has configured it. The preview needs it to find its own rotation.
    private(set) var device: AVCaptureDevice?

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    /// Configures the camera on first use and starts it. Throws instead of showing a black screen.
    func start(onFrame: @escaping FrameHandler) async throws {
        guard Self.isAuthorized else { throw Failure.cameraDenied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    self.frameHandler = onFrame
                    try self.configureIfNeeded()
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.frameHandler = nil
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw Failure.noCamera
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input), session.canAddOutput(output) else {
            throw Failure.cannotConfigure
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        // Upright frames, so landmark coordinates are upright. The system says which angle that is for this camera and
        // how the phone is held, instead of guessing. Mirroring is left off: the measurements do not care.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        captureCoordinator = coordinator
        applyCaptureRotation()
        captureObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            self?.queue.async { self?.applyCaptureRotation() }
        }
        device = camera
        isConfigured = true
    }
}

extension EyeCameraSession {
    private func applyCaptureRotation() {
        guard let coordinator = captureCoordinator, let connection = output.connection(with: .video) else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }
    }
}

extension EyeCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameHandler?(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
