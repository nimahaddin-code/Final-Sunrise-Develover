import CoreImage
import CoreVideo
import Foundation
import MediaPipeTasksVision
import QuartzCore
import UIKit
import simd

/// One camera frame for the brow tracker. `token` comes back with the result, so the renderer can draw the very
/// frame the landmarks were found in.
struct BrowTrackerInput: Sendable {
    let pixelBuffer: SendablePixelBuffer
    let timestamp: TimeInterval
    /// The screen's up and left-right directions in the captured image (pixels). They pick the detector's rotation
    /// and tell which space its landmarks are in; they come from the camera's display transform, not a face tracker.
    let headUp: CGPoint
    let headAcross: CGPoint
    let token: UInt64
}

struct BrowTrackerResult: Sendable {
    let token: UInt64
    /// `nil` = no face found.
    let observation: BrowObservation?
}

/// MediaPipe Face Landmarker in live-stream mode for the eyebrow try-on: brow contours, eye and nose points and the
/// head pose, from the shared camera's frames. It replaces the ARKit mesh + Vision brow fit.
final class MediaPipeBrowTracker: NSObject, @unchecked Sendable {
    /// MediaPipe does not need the full ARKit camera resolution. Keeping the
    /// detector input bounded avoids a full-resolution YCbCr -> BGRA conversion
    /// on every accepted frame while preserving the source aspect ratio.
    static let detectorLongSide: CGFloat = 512
    /// Iris centres, only present in the 478-point model; assigned to an eye by distance.
    static let irisCenters = [468, 473]
    /// Alar points beside the nostrils, the origin of the tutorial's nose-eye mapping lines.
    static let alae = [98, 327]
    /// Between the eyes; the rigid point the smoother follows.
    static let noseBridge = 168

    var onResult: (@Sendable (BrowTrackerResult) -> Void)?

    private struct Pending {
        let start: CFTimeInterval
        let rawSize: CGSize
        let rotation: DetectorRotation
        let headAcross: CGPoint
        let token: UInt64
    }

    private let queue = DispatchQueue(label: "sunrise.brow-landmarks", qos: .userInitiated)
    private let lock = NSLock()
    private var landmarker: FaceLandmarker?
    private var pending: [Int: Pending] = [:]
    private var inFlightSince: CFTimeInterval?
    private var lastTimestampMs = -1
    private var space: LandmarkSpace?
    private var lifecycleID = UUID()
    private lazy var ciContext = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var bgraPool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private(set) var lastLatencyMs: Double = 0

    var isAvailable: Bool { lock.lock(); defer { lock.unlock() }; return landmarker != nil }

    /// `true` while the previous frame is still being processed: frames are dropped, never queued.
    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let since = inFlightSince else { return false }
        return CACurrentMediaTime() - since < MediaPipeEyeLandmarkProvider.inFlightTimeout
    }

    private func beginLifecycle() -> UUID { lock.lock(); defer { lock.unlock() }; lifecycleID = UUID(); return lifecycleID }

    func start() async throws {
        let token = beginLifecycle()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else { throw EyeProviderError.modelMissing }
                    let options = FaceLandmarkerOptions()
                    options.baseOptions.modelAssetPath = path
                    options.runningMode = .liveStream
                    options.numFaces = 1
                    options.outputFacialTransformationMatrixes = true
                    options.faceLandmarkerLiveStreamDelegate = self
                    let detector = try FaceLandmarker(options: options)
                    lock.lock()
                    guard lifecycleID == token else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                    landmarker = detector
                    lock.unlock()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        lock.lock()
        lifecycleID = UUID()
        let retired = landmarker
        landmarker = nil; pending.removeAll(); inFlightSince = nil; space = nil
        lock.unlock()
        queue.async { withExtendedLifetime(retired) {} }
    }

    @discardableResult
    func submit(_ input: BrowTrackerInput) -> Bool {
        lock.lock()
        if landmarker == nil || (inFlightSince.map { CACurrentMediaTime() - $0 < MediaPipeEyeLandmarkProvider.inFlightTimeout } ?? false) {
            lock.unlock(); return false
        }
        // MediaPipe needs strictly increasing timestamps.
        var ms = Int((input.timestamp * 1000).rounded())
        if ms <= lastTimestampMs { ms = lastTimestampMs + 1 }
        lastTimestampMs = ms
        let raw = CGSize(width: CVPixelBufferGetWidth(input.pixelBuffer.buffer), height: CVPixelBufferGetHeight(input.pixelBuffer.buffer))
        let rotation = DetectorRotation.forHeadUp(input.headUp)
        let now = CACurrentMediaTime()
        inFlightSince = now
        pending[ms] = Pending(start: now, rawSize: raw, rotation: rotation, headAcross: input.headAcross, token: input.token)
        if pending.count > 30 { pending = pending.filter { $0.key > ms - 2000 } }
        let token = lifecycleID, timestampMs = ms
        lock.unlock()

        queue.async { [self] in
            lock.lock(); let detector = lifecycleID == token ? landmarker : nil; lock.unlock()
            guard let detector, let buffer = bgra(from: input.pixelBuffer.buffer) else { return finish(timestampMs, nil) }
            do {
                let image = try MPImage(pixelBuffer: buffer, orientation: rotation.imageOrientation)
                try detector.detectAsync(image: image, timestampInMilliseconds: timestampMs)
            } catch { finish(timestampMs, nil) }
        }
        return true
    }

    private func finish(_ ms: Int, _ observation: BrowObservation?) {
        lock.lock()
        guard let info = pending.removeValue(forKey: ms) else { lock.unlock(); return }
        inFlightSince = nil
        lastLatencyMs = (CACurrentMediaTime() - info.start) * 1000
        lock.unlock()
        onResult?(BrowTrackerResult(token: info.token, observation: observation))
    }

    /// MediaPipe's live stream wants BGRA; ARKit delivers YCbCr.
    private func bgra(from source: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceSize = CGSize(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source))
        let scale = min(1, Self.detectorLongSide / max(sourceSize.width, sourceSize.height))
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA && scale == 1 { return source }
        let size = CGSize(width: max(1, (sourceSize.width * scale).rounded()),
                          height: max(1, (sourceSize.height * scale).rounded()))
        if bgraPool == nil || poolSize != size {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                               kCVPixelBufferWidthKey: Int(size.width), kCVPixelBufferHeightKey: Int(size.height),
                                               kCVPixelBufferIOSurfacePropertiesKey: [:]]
            bgraPool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &bgraPool)
            poolSize = size
        }
        var output: CVPixelBuffer?
        guard let bgraPool, CVPixelBufferPoolCreatePixelBuffer(nil, bgraPool, &output) == kCVReturnSuccess, let output else { return nil }
        let image = CIImage(cvPixelBuffer: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        ciContext.render(image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: colorSpace)
        return output
    }
}

private extension DetectorRotation {
    var imageOrientation: UIImage.Orientation {
        switch self {
        case .up: .up
        case .right: .right
        case .left: .left
        case .down: .down
        }
    }
}

extension MediaPipeBrowTracker: FaceLandmarkerLiveStreamDelegate {
    func faceLandmarker(_ faceLandmarker: FaceLandmarker, didFinishDetection result: FaceLandmarkerResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        lock.lock(); let info = pending[timestampInMilliseconds], known = space; lock.unlock()
        guard let info else { return }
        guard error == nil, let landmarks = result?.faceLandmarks.first, landmarks.count >= 468 else {
            return finish(timestampInMilliseconds, nil)
        }
        let right = MediaPipeEyeLandmarkProvider.subjectRightMap, left = MediaPipeEyeLandmarkProvider.subjectLeftMap
        func normalized(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(landmarks[i].x), y: CGFloat(landmarks[i].y)) }
        let chosen = LandmarkSpace.choose(leftEye: normalized(left.inner), rightEye: normalized(right.inner), rotation: info.rotation,
                                          raw: info.rawSize, expectedAxis: info.headAcross, previous: known)
        lock.lock(); space = chosen; lock.unlock()
        func point(_ i: Int) -> SIMD2<Float> {
            let p = LandmarkSpace.rawPixel(normalized(i), space: chosen, rotation: info.rotation, raw: info.rawSize)
            return SIMD2(Float(p.x), Float(p.y))
        }
        // The index rows run outer to inner; brow contours here run head (inner) to tail.
        func brow(_ m: MediaPipeEyeLandmarkProvider.EyeIndexMap) -> BrowContour {
            BrowContour(upper: m.browUpper.reversed().map(point), lower: m.browLower.reversed().map(point))
        }
        func nearest(_ indices: [Int], to target: SIMD2<Float>) -> SIMD2<Float>? {
            indices.filter { $0 < landmarks.count }.map(point).min { simd_distance($0, target) < simd_distance($1, target) }
        }
        func eye(_ m: MediaPipeEyeLandmarkProvider.EyeIndexMap) -> BrowEyeMarks? {
            let inner = point(m.inner), outer = point(m.outer)
            guard let ala = nearest(Self.alae, to: inner) else { return nil }
            return BrowEyeMarks(inner: inner, outer: outer, iris: nearest(Self.irisCenters, to: (inner + outer) / 2), ala: ala,
                                lid: m.upper.map(point))
        }
        guard let rightEye = eye(right), let leftEye = eye(left) else { return finish(timestampInMilliseconds, nil) }
        var pose = BrowHeadPose.frontal
        if let matrix = result?.facialTransformationMatrixes.first, matrix.rows == 4, matrix.columns == 4 {
            let values = (0..<4).flatMap { row in (0..<4).map { matrix.value(atRow: UInt(row), column: UInt($0)) } }
            pose = BrowHeadPose(rowMajor: values) ?? .frontal
        }
        let observation = BrowObservation(imageSize: info.rawSize, timestamp: TimeInterval(timestampInMilliseconds) / 1000,
                                          brows: [.subjectRight: brow(right), .subjectLeft: brow(left)],
                                          eyes: [.subjectRight: rightEye, .subjectLeft: leftEye],
                                          noseBridge: point(Self.noseBridge), pose: pose,
                                          mesh: (0..<landmarks.count).map(point))
        finish(timestampInMilliseconds, observation)
    }
}
