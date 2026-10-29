import ARKit
import Vision

/// Turns the shared ARKit camera frames into `CameraSignals`. It only reads: it never owns the session or its delegate,
/// and nothing it sees is stored. Thresholds live in `CameraMessageEngine`; real-device tuning is still to be done.
final class CameraSignalSampler: @unchecked Sendable {
    struct FrameBox: @unchecked Sendable { let frame: ARFrame }

    private let queue = DispatchQueue(label: "sunrise.camera-guidance", qos: .utility)
    private let visionQueue = DispatchQueue(label: "sunrise.camera-guidance.vision", qos: .utility)
    private let detectsCoverage: Bool

    // Used only on `queue`.
    private var history: [(time: TimeInterval, position: SIMD3<Float>, rotation: simd_quatf)] = []
    private var lumaRatio: Double?
    private var lastLuma: TimeInterval = -1
    private var lastVision: TimeInterval = -1

    // Shared with `visionQueue`.
    private let lock = NSLock()
    private var visionBusy = false
    private var faceCount = 1
    private var covered = false

    /// `detectsCoverage` adds the face-capture-quality request that backs "Move your hair or hands" (Try On only).
    init(detectsCoverage: Bool) { self.detectsCoverage = detectsCoverage }

    func sample(_ box: FrameBox, visionEnabled: Bool) async -> CameraSignals {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.read(box.frame, visionEnabled: visionEnabled)) }
        }
    }

    func reset() { queue.async { self.history.removeAll(); self.lumaRatio = nil } }

    // MARK: Reading a frame (on `queue`)

    private func read(_ frame: ARFrame, visionEnabled: Bool) -> CameraSignals {
        var signals = CameraSignals()
        signals.ambientIntensity = frame.lightEstimate.map { Double($0.ambientIntensity) }
        let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        guard let face, face.isTracked else {
            history.removeAll()
            runVisionIfDue(frame, enabled: visionEnabled)
            return withVision(signals)
        }
        signals.faceTracked = true

        let relative = simd_inverse(frame.camera.transform) * face.transform
        let position = SIMD3(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z)
        signals.distance = Double(simd_length(position))

        // The face's outward axis against the camera's: turned left/right moves its y (sensor axes).
        let outward = SIMD3(relative.columns.2.x, relative.columns.2.y, relative.columns.2.z)
        signals.yawDegrees = Double(atan2(abs(outward.y), abs(outward.z))) * 180 / .pi

        let motion = movement(time: frame.timestamp, position: position, rotation: simd_quatf(relative))
        signals.speed = motion?.speed
        signals.turnRate = motion?.turnRate

        if frame.timestamp - lastLuma >= 0.2 {
            lastLuma = frame.timestamp
            lumaRatio = faceLumaRatio(frame, face: face)
        }
        signals.faceLumaRatio = lumaRatio
        runVisionIfDue(frame, enabled: visionEnabled)
        return withVision(signals)
    }

    private func withVision(_ signals: CameraSignals) -> CameraSignals {
        var signals = signals
        lock.lock(); signals.faceCount = faceCount; signals.faceCovered = covered; lock.unlock()
        return signals
    }

    /// Average speed and turn rate over the last ~0.3 s.
    private func movement(time: TimeInterval, position: SIMD3<Float>, rotation: simd_quatf) -> (speed: Double, turnRate: Double)? {
        history.append((time, position, rotation))
        history.removeAll { time - $0.time > 0.3 }
        guard let first = history.first, let last = history.last, last.time - first.time >= 0.1 else { return nil }
        let dt = last.time - first.time
        let speed = Double(simd_distance(first.position, last.position)) / dt
        let dot = min(abs(simd_dot(first.rotation.vector, last.rotation.vector)), 1)
        let turn = Double(2 * acos(dot)) * 180 / .pi / dt
        return (speed, turn)
    }

    // MARK: Light behind her

    /// Mean brightness of a box around the face divided by the mean of the whole frame (the Y plane of the camera image).
    private func faceLumaRatio(_ frame: ARFrame, face: ARFaceAnchor) -> Double? {
        let buffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let size = CGSize(width: width, height: height)

        // The face box: a head-sized rectangle around the face anchor, projected into the camera image.
        let camera = frame.camera.transform
        let right = SIMD3(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z)
        let upAxis = SIMD3(camera.columns.1.x, camera.columns.1.y, camera.columns.1.z)
        let center = SIMD3(face.transform.columns.3.x, face.transform.columns.3.y, face.transform.columns.3.z)
        let corners = [(-1, -1), (1, -1), (-1, 1), (1, 1)].map { x, y -> CGPoint in
            let world = center + right * (0.08 * Float(x)) + upAxis * (0.10 * Float(y))
            return frame.camera.projectPoint(world, orientation: .landscapeRight, viewportSize: size)
        }
        let box = CGRect(x: corners.map(\.x).min() ?? 0, y: corners.map(\.y).min() ?? 0,
                         width: (corners.map(\.x).max() ?? 0) - (corners.map(\.x).min() ?? 0),
                         height: (corners.map(\.y).max() ?? 0) - (corners.map(\.y).min() ?? 0))
            .intersection(CGRect(origin: .zero, size: size))
        guard box.width > 8, box.height > 8 else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

        func mean(_ rect: CGRect, step: Int) -> Double {
            var total = 0.0, count = 0.0
            var y = Int(rect.minY)
            while y < Int(rect.maxY) {
                var x = Int(rect.minX)
                while x < Int(rect.maxX) { total += Double(base[y * stride + x]); count += 1; x += step }
                y += step
            }
            return count > 0 ? total / count : 0
        }
        let frameMean = mean(CGRect(origin: .zero, size: size), step: 16)
        guard frameMean > 1 else { return nil }
        return mean(box, step: 8) / frameMean
    }

    // MARK: More than one face, face covered (Vision, about every 0.5 s)

    private func runVisionIfDue(_ frame: ARFrame, enabled: Bool) {
        guard enabled, frame.timestamp - lastVision >= 0.5 else { return }
        lock.lock(); let busy = visionBusy; if !busy { visionBusy = true }; lock.unlock()
        guard !busy else { return }
        lastVision = frame.timestamp
        let buffer = frame.capturedImage
        let detectsCoverage = detectsCoverage
        visionQueue.async {
            let rectangles = VNDetectFaceRectanglesRequest()
            var requests: [VNRequest] = [rectangles]
            let quality = VNDetectFaceCaptureQualityRequest()
            if detectsCoverage { requests.append(quality) }
            // Same upright, mirrored orientation the app uses for the front camera elsewhere.
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored)
            try? handler.perform(requests)
            let count = rectangles.results?.count ?? 0
            let lowest = quality.results?.compactMap { $0.faceCaptureQuality }.min()
            self.lock.lock()
            self.faceCount = max(count, 1)
            // Hysteresis: low score to start, a clearly higher one to stop. A guess until tuned on real faces.
            if let lowest { self.covered = self.covered ? lowest < 0.25 : lowest < 0.15 } else if !detectsCoverage { self.covered = false }
            self.visionBusy = false
            self.lock.unlock()
        }
    }
}
