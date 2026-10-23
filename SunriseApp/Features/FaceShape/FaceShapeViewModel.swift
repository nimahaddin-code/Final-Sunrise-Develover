import ARKit
import AVFoundation
import Combine
import ImageIO
import os

/// Runs an ARKit face tracking session, collects neutral, front-facing mesh samples and classifies the face shape.
/// Every few accepted frames, Vision traces the real face outline to correct the jaw and chin of ARKit's template mesh.
@MainActor final class FaceShapeViewModel: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case unsupported
        case cameraDenied
        case scanning(progress: Double, guidance: ScanGuidance)
        case interrupted
        case finished(FaceShapeResult)
        case failed
    }

    enum ScanGuidance: Equatable {
        case findFace, relaxFace, holdStill
        case turnLeft, turnRight, raisePhone, lowerPhone, moveCloser, moveBack
    }

    /// About 3 seconds of usable frames at ARKit's 60 fps face tracking.
    static let requiredSamples = 180
    /// Run Vision on every n-th accepted frame; about 30 outlines per scan.
    static let contourInterval = 6

    @Published private(set) var phase: Phase = .idle
    /// The scan picture with the measured lines, for the result screen. Held in memory only, never saved.
    @Published private(set) var snapshot: ScanSnapshot?
    let session = ARSession()
    let snapshotter = FaceSnapshotter()
    private var sampler = FaceProportionsSampler(requiredSamples: FaceShapeViewModel.requiredSamples)
    private var classifier: FaceShapeClassifier?
    private var isSessionRunning = false
    private var contourCorrections: [ContourCorrection] = []
    private var contourOrientation: CGImagePropertyOrientation?
    private var isDetectingContour = false
    private var acceptedFrames = 0
    /// Bumped on every new scan so late Vision results from a previous scan are dropped.
    private var scanID = 0

    var result: FaceShapeResult? {
        if case .finished(let result) = phase { result } else { nil }
    }

    func start() async {
        guard ARFaceTrackingConfiguration.isSupported else { phase = .unsupported; return }
        guard await Self.cameraAccessGranted() else { phase = .cameraDenied; return }
        if classifier == nil {
            // ARKit's neutral face is the "average" every measurement is compared against.
            guard let neutral = ARFaceGeometry(blendShapes: [:]),
                  let reference = FaceMeshMeasurer.proportions(of: neutral.vertices) else { phase = .failed; return }
            classifier = FaceShapeClassifier(reference: reference)
        }
        beginScan()
    }

    /// Starts unless a scan is already running or showing its result.
    func startIfNeeded() async {
        switch phase {
        case .idle, .cameraDenied: await start()
        default: break
        }
    }

    /// Measures again; the camera keeps running so the mesh never disappears between scans.
    func scanAgain() {
        guard isSessionRunning else { beginScan(); return }
        resetMeasurements()
    }

    func stop() {
        session.pause()
        isSessionRunning = false
        snapshot = nil
        switch phase {
        case .scanning, .finished, .interrupted: phase = .idle
        default: break
        }
    }

    private func resetMeasurements() {
        sampler.reset()
        contourCorrections.removeAll()
        acceptedFrames = 0
        scanID += 1
        snapshot = nil
        phase = .scanning(progress: 0, guidance: .findFace)
    }

    private func beginScan() {
        resetMeasurements()
        session.delegate = self
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    private func handle(_ sample: FaceSample) {
        guard case .scanning = phase, let classifier else { return }
        let guidance: ScanGuidance
        if !sample.isTracked {
            guidance = .findFace
        } else if let adjustment = sample.pose.adjustment {
            guidance = adjustment
        } else if !sample.isNeutral {
            guidance = .relaxFace
        } else if let proportions = FaceMeshMeasurer.proportions(of: sample.vertices) {
            sampler.add(proportions)
            requestContour(for: sample)
            guidance = .holdStill
        } else {
            guidance = .findFace
        }

        if sampler.isComplete, let median = sampler.median() {
            let correction = ContourCorrection.median(of: contourCorrections)
            var result = classifier.classify(correction?.applied(to: median) ?? median)
            result.contourSamples = contourCorrections.count
            #if DEBUG
            Self.logCorrection(contourCorrections, mesh: median, corrected: correction?.applied(to: median))
            #endif
            snapshot = FaceMeshMeasurer.guide(of: sample.vertices, correction: correction).flatMap(snapshotter.capture)
            phase = .finished(result)
        } else {
            let next = Phase.scanning(progress: sampler.progress, guidance: guidance)
            if next != phase { phase = next }
        }
    }

    #if DEBUG
    /// Debug builds only; stays on the device (Console.app or Xcode). Logs only numbers, never images.
    private static let log = Logger(subsystem: "SunriseApp", category: "FaceContour")

    private static func logCorrection(_ corrections: [ContourCorrection], mesh: FaceProportions, corrected: FaceProportions?) {
        func line(_ p: FaceProportions) -> String {
            String(format: "length=%.3f forehead=%.3f jaw=%.3f chin=%.3f", p.length, p.forehead, p.jaw, p.chin)
        }
        let after = corrected.map(line) ?? "none, no outline found"
        log.debug("Contour correction (ratio = real outline width / mesh width)\n\(ContourCorrection.report(of: corrections))\nmesh only: \(line(mesh))\ncorrected: \(after)")
    }
    #endif

    private func requestContour(for sample: FaceSample) {
        acceptedFrames += 1
        guard !isDetectingContour, acceptedFrames.isMultiple(of: Self.contourInterval),
              let silhouette = sample.contourInput.silhouette(vertices: sample.vertices) else { return }
        isDetectingContour = true
        let input = sample.contourInput, preferred = contourOrientation, scanID = scanID
        Task.detached(priority: .userInitiated) {
            let found = FaceContourDetector.correction(for: input, silhouette: silhouette, preferred: preferred)
            await self.receiveContour(found, scanID: scanID)
        }
    }

    private func receiveContour(_ found: (ContourCorrection, CGImagePropertyOrientation)?, scanID: Int) {
        isDetectingContour = false
        guard let found, scanID == self.scanID, case .scanning = phase else { return }
        contourOrientation = found.1
        contourCorrections.append(found.0)
    }

    private static func cameraAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}

/// Sendable snapshot of one face anchor update.
private struct FaceSample: Sendable {
    let isTracked: Bool
    let pose: HeadPose
    let isNeutral: Bool
    let vertices: [SIMD3<Float>]
    let contourInput: ContourInput

    init(face: ARFaceAnchor, frame: ARFrame) {
        isTracked = face.isTracked
        vertices = face.geometry.vertices

        let cameraTransform = frame.camera.transform
        pose = HeadPose(face: face.transform, camera: cameraTransform)
        contourInput = ContourInput(pixelBuffer: SendablePixelBuffer(buffer: frame.capturedImage),
                                    cameraTransform: cameraTransform, intrinsics: frame.camera.intrinsics,
                                    faceTransform: face.transform)

        func weight(_ location: ARFaceAnchor.BlendShapeLocation) -> Float {
            face.blendShapes[location]?.floatValue ?? 0
        }
        isNeutral = weight(.jawOpen) < 0.2
            && max(weight(.mouthSmileLeft), weight(.mouthSmileRight)) < 0.4
            && max(weight(.cheekPuff), weight(.mouthPucker)) < 0.4
    }
}

/// Where the camera sits as seen from the face. Turned or tilted heads change the 2D outline Vision measures,
/// so the scan only uses frames taken from straight ahead at arm's length.
struct HeadPose: Equatable, Sendable {
    static let maxYaw = Float.pi / 18 // 10°
    static let maxPitch = Float.pi / 18
    /// Closer than this, the wide-angle front camera exaggerates the nose and narrows the visible outline.
    static let distanceRange: ClosedRange<Float> = 0.25...0.65

    /// Radians; positive when the camera is toward the person's own left (ARKit face +x).
    let yaw: Float
    /// Radians; positive when the camera is above the face's straight-ahead line.
    let pitch: Float
    /// Face to camera, in meters.
    let distance: Float

    init(face: simd_float4x4, camera: simd_float4x4) {
        let position = simd_make_float3(simd_inverse(face) * camera.columns.3)
        distance = simd_length(position)
        yaw = atan2(position.x, position.z)
        pitch = atan2(position.y, simd_length(SIMD2(position.x, position.z)))
    }

    /// What the person should do first, or `nil` when the pose is good enough to measure.
    var adjustment: FaceShapeViewModel.ScanGuidance? {
        if distance < Self.distanceRange.lowerBound { return .moveBack }
        if distance > Self.distanceRange.upperBound { return .moveCloser }
        if yaw > Self.maxYaw { return .turnLeft }
        if yaw < -Self.maxYaw { return .turnRight }
        if pitch > Self.maxPitch { return .lowerPhone }
        if pitch < -Self.maxPitch { return .raisePhone }
        return nil
    }
}

extension FaceShapeViewModel: ARSessionDelegate {
    // ARSession calls its delegate on the main queue unless a delegateQueue is set.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let sample = FaceSample(face: face, frame: frame)
        MainActor.assumeIsolated { handle(sample) }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        let cameraDenied = (error as? ARError)?.code == .cameraUnauthorized
        MainActor.assumeIsolated {
            isSessionRunning = false
            phase = cameraDenied ? .cameraDenied : .failed
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            if case .scanning = phase { phase = .interrupted }
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            if phase == .interrupted { beginScan() }
        }
    }
}
