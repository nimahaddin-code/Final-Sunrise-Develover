import ARKit
import AVFoundation
import Combine
import ImageIO

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
        /// Eye phase: face the camera, keep the eyes relaxed and open, then hold still while they are measured.
        case lookStraight, openEyes, measuringEyes
    }

    /// About 3 seconds of usable frames at ARKit's 60 fps face tracking.
    static let requiredSamples = 180
    /// Run Vision on every n-th accepted frame; about 30 outlines per scan.
    static let contourInterval = 6
    /// The face phase takes this share of the progress bar; the eye phase the rest.
    static let faceProgressShare = 0.85
    /// The eye phase gives up after this long and finishes without eye measurements.
    static let eyePhaseTimeout: TimeInterval = 8
    /// Fewest Vision readings still worth keeping when the eye phase times out.
    static let minimumEyeSamples = 3

    @Published private(set) var phase: Phase = .idle
    let session = ARSession()
    private var sampler = FaceProportionsSampler(requiredSamples: FaceShapeViewModel.requiredSamples)
    private var classifier: FaceShapeClassifier?
    private var isSessionRunning = false
    private var contourCorrections: [ContourCorrection] = []
    private var contourOrientation: CGImagePropertyOrientation?
    private var isDetectingContour = false
    private var acceptedFrames = 0
    /// Bumped on every new scan so late Vision results from a previous scan are dropped.
    private var scanID = 0
    /// The classified face while the eye phase runs; published only once the eyes are measured.
    private var pendingFace: FaceShapeResult?
    private var eyeMaps: [FaceFeatureMap] = []
    private var eyeOrientation: CGImagePropertyOrientation?
    private var eyeDeadline = Date.distantFuture
    private var isLocatingEyes = false
    private var eyeFrames = 0

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

    /// Records the person's answer about their lids; the made-for-you eyeliner follows it.
    func setLidType(_ lidType: LidType) {
        guard case .finished(var result) = phase, var eyes = result.eyes, eyes.lidType != lidType else { return }
        eyes.lidType = lidType
        result.eyes = eyes
        phase = .finished(result)
    }

    func stop() {
        session.pause()
        isSessionRunning = false
        switch phase {
        case .scanning, .finished, .interrupted: phase = .idle
        default: break
        }
    }

    private func resetMeasurements() {
        sampler.reset()
        contourCorrections.removeAll()
        acceptedFrames = 0
        pendingFace = nil
        eyeMaps.removeAll()
        isLocatingEyes = false
        eyeFrames = 0
        scanID += 1
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
        if pendingFace != nil {
            handleEyes(sample)
            return
        }
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
            // The face is done; the eyes are measured next, in the same session.
            pendingFace = result
            eyeDeadline = Date().addingTimeInterval(Self.eyePhaseTimeout)
            phase = .scanning(progress: Self.faceProgressShare, guidance: .lookStraight)
        } else {
            let next = Phase.scanning(progress: sampler.progress * Self.faceProgressShare, guidance: guidance)
            if next != phase { phase = next }
        }
    }

    // MARK: - Eye phase

    private func handleEyes(_ sample: FaceSample) {
        guard let face = pendingFace else { return }
        if Date() > eyeDeadline {
            finishEyes(face)
            return
        }
        let guidance: ScanGuidance
        switch EyeSampleGate.verdict(isTracked: sample.isTracked, headIsStraight: sample.pose.adjustment == nil,
                                     blinkLeft: sample.blinkLeft, blinkRight: sample.blinkRight,
                                     squintLeft: sample.squintLeft, squintRight: sample.squintRight) {
        case .lookStraight:
            guidance = sample.isTracked ? sample.pose.adjustment ?? .lookStraight : .findFace
        case .openEyes:
            guidance = .openEyes
        case .accept:
            guidance = .measuringEyes
            requestEyes(sample)
        }
        let share = 1 - Self.faceProgressShare
        let progress = Self.faceProgressShare + share * Double(eyeMaps.count) / Double(EyeSampleGate.requiredSamples)
        let next = Phase.scanning(progress: min(progress, 1), guidance: guidance)
        if next != phase { phase = next }
    }

    private func requestEyes(_ sample: FaceSample) {
        eyeFrames += 1
        guard !isLocatingEyes, eyeFrames.isMultiple(of: EyeSampleGate.visionInterval),
              let input = sample.locatorInput else { return }
        isLocatingEyes = true
        let preferred = eyeOrientation, scanID = scanID
        Task.detached(priority: .userInitiated) {
            let found = FaceFeatureLocator.features(for: input, preferred: preferred)
            await self.receiveEyes(found, scanID: scanID)
        }
    }

    private func receiveEyes(_ found: (FaceFeatureMap, CGImagePropertyOrientation)?, scanID: Int) {
        isLocatingEyes = false
        guard scanID == self.scanID, let face = pendingFace, case .scanning = phase, let found else { return }
        eyeOrientation = found.1
        // Vision can still read a blink the blend shapes missed; a barely open eye measures nothing useful.
        guard let fit = FaceFit(features: found.0), fit.eyeOpenness >= EyeScan.minimumOpenness else { return }
        eyeMaps.append(found.0)
        if eyeMaps.count >= EyeSampleGate.requiredSamples { finishEyes(face) }
    }

    /// Publishes the face result with the averaged eye measurements, or without them when too few readings came in.
    private func finishEyes(_ face: FaceShapeResult) {
        var result = face
        if eyeMaps.count >= Self.minimumEyeSamples, let average = FaceFeatureMap.average(eyeMaps),
           let fit = FaceFit(features: average) {
            result.eyes = fit.eyeScan(samples: eyeMaps.count)
        }
        pendingFace = nil
        eyeMaps.removeAll()
        phase = .finished(result)
    }

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
    let blinkLeft: Float
    let blinkRight: Float
    let squintLeft: Float
    let squintRight: Float
    /// Camera frame and mesh for Vision's eye landmarks; only copied out during the eye phase.
    let locatorInput: FeatureLocatorInput?

    init(face: ARFaceAnchor, frame: ARFrame, includesLocatorInput: Bool) {
        isTracked = face.isTracked
        vertices = face.geometry.vertices

        let cameraTransform = frame.camera.transform
        pose = HeadPose(face: face.transform, camera: cameraTransform)
        let contour = ContourInput(pixelBuffer: SendablePixelBuffer(buffer: frame.capturedImage),
                                   cameraTransform: cameraTransform, intrinsics: frame.camera.intrinsics,
                                   faceTransform: face.transform)
        contourInput = contour

        func weight(_ location: ARFaceAnchor.BlendShapeLocation) -> Float {
            face.blendShapes[location]?.floatValue ?? 0
        }
        blinkLeft = weight(.eyeBlinkLeft)
        blinkRight = weight(.eyeBlinkRight)
        squintLeft = weight(.eyeSquintLeft)
        squintRight = weight(.eyeSquintRight)
        locatorInput = includesLocatorInput
            ? FeatureLocatorInput(contour: contour, vertices: face.geometry.vertices,
                                  textureCoordinates: face.geometry.textureCoordinates,
                                  triangleIndices: FilledFaceMesh.triangleIndices(
                                      vertexCount: face.geometry.vertices.count,
                                      fallback: face.geometry.triangleIndices))
            : nil
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
        let measuringEyes = MainActor.assumeIsolated { pendingFace != nil }
        let sample = FaceSample(face: face, frame: frame, includesLocatorInput: measuringEyes)
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
