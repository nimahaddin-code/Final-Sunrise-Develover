import AVFoundation
import Combine

/// Runs the eye scan: starts the front camera, finds the eye landmarks in every frame with MediaPipe, keeps the good
/// frames and classifies their median. The ARKit face session must already be stopped (see `EyeCameraSession`).
@MainActor final class EyeScanViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// No front camera, as in the Simulator.
        case unavailable
        case cameraDenied
        case failed
        case scanning(progress: Double, guidance: EyeScanGuidance)
        case finished(EyeShapeResult)
    }

    /// About 1 to 2 seconds of good frames at the camera's frame rate.
    static let requiredSamples = 30

    @Published private(set) var phase: Phase = .idle
    let camera = EyeCameraSession()
    private var sampler = EyeMeasurementsSampler(requiredSamples: EyeScanViewModel.requiredSamples)
    private let classifier = EyeShapeClassifier()

    var result: EyeShapeResult? {
        if case .finished(let result) = phase { result } else { nil }
    }

    func start() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard EyeCameraSession.isAuthorized else { phase = .cameraDenied; return }
        let detector: MediaPipeEyeDetector
        do { detector = try MediaPipeEyeDetector() } catch { phase = .failed; return }
        resetMeasurements()
        do {
            try await camera.start { [weak self] buffer, time in
                // Runs on the camera queue, which is the only place the detector is used.
                let timestamp = Int((CMTimeGetSeconds(time) * 1000).rounded())
                guard let outcome = detector.detect(pixelBuffer: buffer, timestampMs: timestamp) else { return }
                let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
                let frame = EyeScanGuide.evaluate(outcome.landmarks, imageWidth: Float(width))
                // Good frames carry their picture, so the one that completes the scan can become the profile photo.
                let snapshot = frame.measurements == nil ? nil
                    : outcome.landmarks.flatMap { ScanSnapshots.eyeCrop($0, imageSize: CGSize(width: width, height: height)) }
                    .map { Snapshot(buffer: SendablePixelBuffer(buffer: buffer), crop: $0) }
                Task { @MainActor in self?.handle(frame, snapshot: snapshot) }
            }
        } catch EyeCameraSession.Failure.cameraDenied {
            phase = .cameraDenied
        } catch EyeCameraSession.Failure.noCamera {
            phase = .unavailable
        } catch {
            phase = .failed
        }
    }

    /// Starts unless a scan is already running or showing its result.
    func startIfNeeded() async {
        switch phase {
        case .idle, .cameraDenied, .unavailable, .failed: await start()
        default: break
        }
    }

    /// Measures again; the camera is restarted if the last scan stopped it.
    func scanAgain() {
        resetMeasurements()
        Task { await start() }
    }

    func stop() {
        camera.stop()
        switch phase {
        case .scanning, .finished: phase = .idle
        default: break
        }
    }

    /// The person's answer to "which eyelid looks like yours?".
    func chooseLid(_ lid: EyeLid?) {
        guard case .finished(var result) = phase else { return }
        result.lid = lid
        phase = .finished(result)
    }

    func resetMeasurements() {
        sampler.reset()
        phase = .scanning(progress: 0, guidance: .findFace)
    }

    /// An upright camera frame and the part of it around the eyes.
    struct Snapshot: Sendable {
        let buffer: SendablePixelBuffer
        let crop: CGRect
    }

    func handle(_ frame: EyeScanFrame, snapshot: Snapshot? = nil) {
        guard case .scanning = phase else { return }
        if let measurements = frame.measurements { sampler.add(measurements) }
        if sampler.isComplete, let median = sampler.median() {
            camera.stop()
            if let snapshot {
                Task.detached(priority: .utility) { ScanSnapshots.save(snapshot.buffer, crop: snapshot.crop, as: .eyes) }
            }
            phase = .finished(classifier.classify(median))
        } else {
            let next = Phase.scanning(progress: sampler.progress, guidance: frame.guidance)
            if next != phase { phase = next }
        }
    }
}
