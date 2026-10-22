import CoreImage
import CoreVideo
import Foundation
import MediaPipeTasksVision
import UIKit

/// One camera frame for the occlusion segmenter.
struct OcclusionInput: Sendable {
    let pixelBuffer: SendablePixelBuffer
    let timestamp: TimeInterval
    let headUp: CGPoint
    let headAnchors: [CGPoint]
}

/// MediaPipe's multiclass selfie segmenter (background, hair, body skin, face skin, clothes, others). Body skin that
/// is not the face is a hand or a finger, which should be in front of the liner. The frame is rotated upright and
/// shrunk before segmenting, so the mask is in a known orientation and the model stays cheap.
final class HandOcclusionSegmenter: NSObject, @unchecked Sendable {
    static let modelName = "selfie_multiclass_256x256"
    /// Long side of the image given to the model.
    static let longSide: CGFloat = 512
    static let inFlightTimeout: CFTimeInterval = 0.5

    /// Called on an arbitrary thread; `nil` = no mask for that frame.
    var onMask: (@Sendable (OcclusionMask?) -> Void)?

    private struct Pending {
        let rawSize: CGSize
        let rotation: DetectorRotation
        let headAnchors: [CGPoint]
        let time: CFTimeInterval
    }

    private let queue = DispatchQueue(label: "eyeliner.occlusion", qos: .userInitiated)
    private let lock = NSLock()
    private var segmenter: ImageSegmenter?
    private var occluders: Set<UInt8> = [2]
    private var pending: [Int: Pending] = [:]
    private var inFlightSince: CFTimeInterval?
    private var lastTimestampMs = -1
    private lazy var ciContext = CIContext()
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    var isAvailable: Bool { segmenter != nil }

    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let since = inFlightSince else { return false }
        return CACurrentMediaTime() - since < Self.inFlightTimeout
    }

    func start() throws {
        guard let path = Bundle.main.path(forResource: Self.modelName, ofType: "tflite") else {
            throw EyeProviderError.modelMissing
        }
        let options = ImageSegmenterOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .liveStream
        options.shouldOutputCategoryMask = true
        options.shouldOutputConfidenceMasks = false
        options.imageSegmenterLiveStreamDelegate = self
        let made = try ImageSegmenter(options: options)
        // The class ids come from the model's own labels; "body-skin" is a hand, "face-skin" is not.
        let body = made.labels.enumerated().filter { $0.element.lowercased().contains("body") }.map { UInt8($0.offset) }
        lock.lock()
        segmenter = made
        if !body.isEmpty { occluders = Set(body) }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        segmenter = nil
        pending.removeAll()
        inFlightSince = nil
        lastTimestampMs = -1
        lock.unlock()
    }

    func submit(_ input: OcclusionInput) {
        lock.lock()
        guard segmenter != nil else { lock.unlock(); return }
        if let since = inFlightSince, CACurrentMediaTime() - since < Self.inFlightTimeout { lock.unlock(); return }
        var ms = Int((input.timestamp * 1000).rounded())
        if ms <= lastTimestampMs { ms = lastTimestampMs + 1 }
        lastTimestampMs = ms
        let raw = CGSize(width: CVPixelBufferGetWidth(input.pixelBuffer.buffer),
                         height: CVPixelBufferGetHeight(input.pixelBuffer.buffer))
        let rotation = DetectorRotation.forHeadUp(input.headUp)
        let now = CACurrentMediaTime()
        inFlightSince = now
        pending[ms] = Pending(rawSize: raw, rotation: rotation, headAnchors: input.headAnchors, time: now)
        lock.unlock()

        queue.async { [self] in
            lock.lock(); let segmenter = segmenter; lock.unlock()
            guard let segmenter, let upright = uprightBuffer(input.pixelBuffer.buffer, rotation: rotation) else {
                return finish(ms, mask: nil)
            }
            do {
                try segmenter.segmentAsync(image: try MPImage(pixelBuffer: upright), timestampInMilliseconds: ms)
            } catch {
                finish(ms, mask: nil)
            }
        }
    }

    private func finish(_ ms: Int, mask: OcclusionMask?) {
        lock.lock()
        pending[ms] = nil
        inFlightSince = nil
        lock.unlock()
        onMask?(mask)
    }

    /// The frame rotated upright and shrunk, as BGRA.
    private func uprightBuffer(_ source: CVPixelBuffer, rotation: DetectorRotation) -> CVPixelBuffer? {
        let orientation: CGImagePropertyOrientation = switch rotation {
        case .up: .up
        case .right: .right
        case .left: .left
        case .down: .down
        }
        var image = CIImage(cvPixelBuffer: source).oriented(orientation)
        let scale = Self.longSide / max(image.extent.width, image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let size = CGSize(width: image.extent.width.rounded(), height: image.extent.height.rounded())
        if pool == nil || poolSize != size {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                               kCVPixelBufferWidthKey: Int(size.width),
                                               kCVPixelBufferHeightKey: Int(size.height),
                                               kCVPixelBufferIOSurfacePropertiesKey: [:]]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            poolSize = size
        }
        var output: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else {
            return nil
        }
        ciContext.render(image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }
}

extension HandOcclusionSegmenter: ImageSegmenterLiveStreamDelegate {
    func imageSegmenter(_ imageSegmenter: ImageSegmenter, didFinishSegmentation result: ImageSegmenterResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        let info = pending[timestampInMilliseconds]
        let occluders = occluders
        lock.unlock()
        guard let info else { return }
        guard error == nil, let category = result?.categoryMask else { return finish(timestampInMilliseconds, mask: nil) }
        let width = category.width, height = category.height
        // The pointer is only valid inside this callback.
        let categories = Array(UnsafeBufferPointer(start: category.uint8Data, count: width * height))
        guard let image = OcclusionMask.alphaImage(categories: categories, width: width, height: height, occluders: occluders)
        else { return finish(timestampInMilliseconds, mask: nil) }
        finish(timestampInMilliseconds, mask: OcclusionMask(
            image: image, size: CGSize(width: width, height: height),
            uprightSize: info.rotation.uprightSize(raw: info.rawSize), rotation: info.rotation, rawSize: info.rawSize,
            headAnchors: info.headAnchors, time: info.time))
    }
}
