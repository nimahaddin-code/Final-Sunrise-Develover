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
    @Published private(set) var position = AVCaptureDevice.Position.back
    @Published private(set) var hasTorch = false
    @Published private(set) var torchOn = false
    @Published private(set) var zoomed = false
    private nonisolated(unsafe) var currentDevice: AVCaptureDevice?

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
        refreshDeviceInfo()
    }

    func stop() {
        queue.async {
            self.setTorchLocked(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
        torchOn = false
        if state == .running { state = .idle }
    }

    /// Swaps between the back and front camera. The front picture is mirrored so the snapshot matches the preview.
    func flip() {
        guard state == .running else { return }
        let target: AVCaptureDevice.Position = position == .back ? .front : .back
        queue.async {
            self.setTorchLocked(false)
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for old in self.session.inputs { self.session.removeInput(old) }
            if self.session.canAddInput(input) { self.session.addInput(input); self.currentDevice = device }
            if let connection = self.session.outputs.first?.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = target == .front
                }
            }
            self.session.commitConfiguration()
        }
        torchOn = false; zoomed = false
        position = target
        Task { try? await Task.sleep(for: .milliseconds(150)); refreshDeviceInfo() }
    }

    func toggleTorch() { setTorch(!torchOn) }

    func setTorch(_ on: Bool) {
        guard hasTorch else { return }
        torchOn = on
        queue.async { self.setTorchLocked(on) }
    }

    /// Toggles between 1x and 2x (clamped to what the camera allows).
    func toggleZoom() {
        let next = !zoomed
        zoomed = next
        queue.async {
            guard let device = self.currentDevice, (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = next ? min(2, device.activeFormat.videoMaxZoomFactor) : 1
            device.unlockForConfiguration()
        }
    }

    private func refreshDeviceInfo() {
        queue.async {
            let torch = self.currentDevice?.hasTorch ?? false
            Task { @MainActor in self.hasTorch = torch }
        }
    }

    private nonisolated func setTorchLocked(_ on: Bool) {
        guard let device = currentDevice, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
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
        currentDevice = device
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
