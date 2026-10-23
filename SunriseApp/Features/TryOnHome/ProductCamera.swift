@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Keeps the newest camera frame for `ProductCamera.snapshot`. Frames arrive on the camera queue.
private final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var newest: CVPixelBuffer?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); newest = buffer; lock.unlock()
    }

    func latest() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return newest }
    func clear() { lock.lock(); newest = nil; lock.unlock() }
}

/// The back camera, for photographing a makeup product in the colour sheet. Frames stay in memory; nothing is saved.
/// The face camera must be stopped first: ARKit's face session owns the cameras while it runs.
@MainActor final class ProductCamera: ObservableObject {
    enum State: Equatable { case idle, running, denied, unavailable }

    @Published private(set) var state = State.idle
    nonisolated let session = AVCaptureSession()
    private nonisolated let queue = DispatchQueue(label: "SunriseApp.ProductCamera", qos: .userInitiated)
    private nonisolated let sink = FrameSink()
    private nonisolated(unsafe) var isConfigured = false
    private let context = CIContext()

    func start() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else { state = .denied; return }
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard self.configureIfNeeded() else { continuation.resume(returning: false); return }
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: true)
            }
        }
        state = started ? .running : .unavailable
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        if state == .running { state = .idle }
    }

    /// The newest frame, centre-cropped to `aspect` (width / height) so it matches the viewfinder, as JPEG data.
    func snapshot(aspect: CGFloat) -> Data? {
        guard let buffer = sink.latest() else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let full = context.createCGImage(image, from: image.extent) else { return nil }
        let width = CGFloat(full.width), height = CGFloat(full.height)
        var crop = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > aspect {
            crop.size.width = height * aspect
            crop.origin.x = (width - crop.width) / 2
        } else {
            crop.size.height = width / aspect
            crop.origin.y = (height - crop.height) / 2
        }
        guard let cropped = full.cropping(to: crop.integral) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.92)
    }

    private nonisolated func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(sink, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        // Portrait, upright frames, so the snapshot matches what the person sees.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        isConfigured = true
        return true
    }
}

/// Live back-camera picture, filling its frame.
struct ProductCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
