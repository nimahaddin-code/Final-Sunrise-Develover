import CoreImage
import CoreVideo
import Foundation
import MediaPipeTasksVision
import UIKit

enum EyeProviderError: LocalizedError {
    case modelMissing
    var errorDescription: String? { "face_landmarker.task is missing from the app bundle." }
}

/// One camera frame for the landmark provider, copied out of the ARFrame.
struct LandmarkInput: Sendable {
    let pixelBuffer: SendablePixelBuffer
    let timestamp: TimeInterval
    /// The head's up direction in the captured image (pixels), from ARKit; picks the detector's rotation.
    let headUp: CGPoint
    /// The head's left-right axis in the captured image (pixels), from ARKit; tells which space the landmarks are in.
    let headAcross: CGPoint
    let context: FrameContext
}

/// MediaPipe Face Landmarker in live-stream mode, fed with ARKit's camera frames (no second camera session).
/// Results are the eyes' lids, corners and brows in captured-image pixels, plus rigid mid-face anchors.
final class MediaPipeEyeLandmarkProvider: NSObject, @unchecked Sendable {
    struct EyeIndexMap {
        let side: EyeSide
        let outer: Int
        let inner: Int
        let upper: [Int]
        let lower: [Int]
        let browUpper: [Int]
        let browLower: [Int]
        var allIndices: [Int] { [outer, inner] + upper + lower + browUpper + browLower }
    }

    // Verified index maps from the spike.
    static let subjectRightMap = EyeIndexMap(
        side: .subjectRight, outer: 33, inner: 133,
        upper: [246, 161, 160, 159, 158, 157, 173],
        lower: [7, 163, 144, 145, 153, 154, 155],
        browUpper: [70, 63, 105, 66, 107],
        browLower: [46, 53, 52, 65, 55])

    static let subjectLeftMap = EyeIndexMap(
        side: .subjectLeft, outer: 263, inner: 362,
        upper: [466, 388, 387, 386, 385, 384, 398],
        lower: [249, 390, 373, 374, 380, 381, 382],
        browUpper: [300, 293, 334, 296, 336],
        browLower: [276, 283, 282, 295, 285])

    /// Mid-face landmarks used as a rigid reference (unaffected by blinking / eye-skin stretching).
    static let faceAnchorIndices = [168, 6, 197, 195, 5, 4, 1, 129, 358, 98, 327, 234, 454, 127, 356]

    /// A frame that is still unanswered after this long is given up, so a lost callback cannot stall the stream.
    static let inFlightTimeout: CFTimeInterval = 0.5

    /// Called on an arbitrary thread; `nil` = no face found.
    var onFrame: (@Sendable (EyeLandmarkFrame?) -> Void)?

    private struct Pending {
        let start: CFTimeInterval
        let rawSize: CGSize
        let rotation: DetectorRotation
        let headAcross: CGPoint
        let context: FrameContext
    }

    private let queue = DispatchQueue(label: "eyeliner.landmarks", qos: .userInitiated)
    private let lock = NSLock()
    private var landmarker: FaceLandmarker?
    private var pending: [Int: Pending] = [:]
    private var inFlightSince: CFTimeInterval?
    private var lastTimestampMs = -1
    private var space: LandmarkSpace?
    private lazy var ciContext = CIContext()
    private var bgraPool: CVPixelBufferPool?

    func start() throws {
        guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
            throw EyeProviderError.modelMissing
        }
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .liveStream
        options.numFaces = 1
        // Lower than the defaults (0.5) so tracking survives a hand or a pulled lid in front of part of the face.
        options.minFaceDetectionConfidence = 0.3
        options.minFacePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3
        options.faceLandmarkerLiveStreamDelegate = self
        landmarker = try FaceLandmarker(options: options)
    }

    func stop() {
        lock.lock()
        landmarker = nil
        pending.removeAll()
        inFlightSince = nil
        space = nil
        lastTimestampMs = -1
        lock.unlock()
    }

    /// `false` while the previous frame is still being processed: frames are dropped, never queued.
    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let since = inFlightSince else { return false }
        return CACurrentMediaTime() - since < Self.inFlightTimeout
    }

    @discardableResult
    func submit(_ input: LandmarkInput) -> Bool {
        lock.lock()
        if let since = inFlightSince, CACurrentMediaTime() - since < Self.inFlightTimeout {
            lock.unlock()
            return false
        }
        // MediaPipe needs strictly increasing timestamps.
        var ms = Int((input.timestamp * 1000).rounded())
        if ms <= lastTimestampMs { ms = lastTimestampMs + 1 }
        lastTimestampMs = ms
        let raw = CGSize(width: CVPixelBufferGetWidth(input.pixelBuffer.buffer),
                         height: CVPixelBufferGetHeight(input.pixelBuffer.buffer))
        let rotation = DetectorRotation.forHeadUp(input.headUp)
        let now = CACurrentMediaTime()
        inFlightSince = now
        pending[ms] = Pending(start: now, rawSize: raw, rotation: rotation, headAcross: input.headAcross,
                              context: input.context)
        if pending.count > 30 { pending = pending.filter { $0.key > ms - 2000 } }
        lock.unlock()

        queue.async { [self] in
            guard let landmarker, let buffer = bgra(from: input.pixelBuffer.buffer) else { return finish(ms, delivered: nil) }
            do {
                let image = try MPImage(pixelBuffer: buffer, orientation: rotation.uiOrientation)
                try landmarker.detectAsync(image: image, timestampInMilliseconds: ms)
            } catch {
                finish(ms, delivered: nil)
            }
        }
        return true
    }

    /// Clears the in-flight state for `ms` and reports `frame` (or "no face").
    private func finish(_ ms: Int, delivered frame: EyeLandmarkFrame?) {
        lock.lock()
        pending[ms] = nil
        inFlightSince = nil
        lock.unlock()
        onFrame?(frame)
    }

    /// MediaPipe's live stream wants BGRA; ARKit delivers YCbCr.
    private func bgra(from source: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA { return source }
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        if bgraPool == nil {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                               kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                                               kCVPixelBufferIOSurfacePropertiesKey: [:]]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &bgraPool)
        }
        var output: CVPixelBuffer?
        guard let bgraPool, CVPixelBufferPoolCreatePixelBuffer(nil, bgraPool, &output) == kCVReturnSuccess,
              let output else { return nil }
        ciContext.render(CIImage(cvPixelBuffer: source), to: output)
        return output
    }
}

private extension DetectorRotation {
    var uiOrientation: UIImage.Orientation {
        switch self {
        case .up: .up
        case .right: .right
        case .left: .left
        case .down: .down
        }
    }
}

extension MediaPipeEyeLandmarkProvider: FaceLandmarkerLiveStreamDelegate {
    func faceLandmarker(_ faceLandmarker: FaceLandmarker, didFinishDetection result: FaceLandmarkerResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        let info = pending[timestampInMilliseconds]
        let known = space
        lock.unlock()
        guard let info else { return }
        guard error == nil, let landmarks = result?.faceLandmarks.first, landmarks.count >= 468 else {
            return finish(timestampInMilliseconds, delivered: nil)
        }

        let right = Self.subjectRightMap, left = Self.subjectLeftMap
        func normalized(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(landmarks[i].x), y: CGFloat(landmarks[i].y)) }
        let chosen = LandmarkSpace.choose(leftEye: normalized(left.inner), rightEye: normalized(right.inner),
                                          rotation: info.rotation, raw: info.rawSize, expectedAxis: info.headAcross,
                                          previous: known)
        lock.lock(); space = chosen; lock.unlock()

        func point(_ i: Int) -> CGPoint {
            LandmarkSpace.rawPixel(normalized(i), space: chosen, rotation: info.rotation, raw: info.rawSize)
        }
        func eye(_ m: EyeIndexMap) -> EyeLandmarks {
            EyeGeometry.makeEyeLandmarks(side: m.side, inner: point(m.inner), outer: point(m.outer),
                                         upper: m.upper.map(point), lower: m.lower.map(point),
                                         brow: (m.browUpper + m.browLower).map(point))
        }
        let frame = EyeLandmarkFrame(imageSize: info.rawSize,
                                     timestamp: TimeInterval(timestampInMilliseconds) / 1000,
                                     subjectLeft: eye(left), subjectRight: eye(right),
                                     providerLatencyMs: (CACurrentMediaTime() - info.start) * 1000,
                                     faceAnchors: Self.faceAnchorIndices.map(point), context: info.context)
        finish(timestampInMilliseconds, delivered: frame)
    }
}
