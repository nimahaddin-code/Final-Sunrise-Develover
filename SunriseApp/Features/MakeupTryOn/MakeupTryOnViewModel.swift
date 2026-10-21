import ARKit
import AVFoundation
import Combine
import ImageIO
import UIKit

/// Runs ARKit face tracking for the live try-on. While the user looks straight at the camera, Vision locates the
/// brows and eyes a few times; the averaged positions are mapped onto the face mesh's texture so the makeup,
/// drawn into that texture, follows the face.
@MainActor final class MakeupTryOnViewModel: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case unsupported
        case cameraDenied
        case locating(Guidance)
        case ready
        case interrupted
        case failed
    }

    enum Guidance: Equatable { case findFace, lookStraight, holdStill }

    /// Vision results averaged before the makeup is placed.
    static let requiredSamples = 4
    /// Run Vision on every n-th front-facing frame.
    static let sampleInterval = 8

    /// While the liner is on, run Vision on every n-th front-facing frame to keep it on the moving eyes.
    static let liveEyeInterval = 2
    /// How far each new eye reading moves the liner's eye points (1 follows instantly, lower is steadier).
    static let liveEyeWeight: Float = 0.85

    let plan: MakeupPlan
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var selection: [MakeupCategory: MakeupRecommendation]
    /// Shades the user picked; categories without one use the recommendation's own shade.
    @Published private(set) var shadeChoices: [MakeupCategory: MakeupShade] = [:]
    @Published private(set) var intensities: [MakeupCategory: Double] = [:]
    @Published private(set) var textures: [MakeupCategory: UIImage] = [:]
    /// The person's measured features once makeup is placed; brows and blush are fitted to them. The eyeliner follows
    /// the eye shape measured in the face scan instead.
    @Published private(set) var fit: FaceFit?
    let session = ARSession()

    private var features: FaceFeatureMap?
    /// `features` with the eyes following the person's current eyes; only the liner is drawn from it.
    private var liveFeatures: FaceFeatureMap?
    private var isLocatingLive = false
    private var samples: [FaceFeatureMap] = []
    private var orientation: CGImagePropertyOrientation?
    private var isLocating = false
    private var facingFrames = 0
    private var isSessionRunning = false
    private var renderTasks: [MakeupCategory: Task<Void, Never>] = [:]
    /// Bumped whenever placement restarts so late Vision results are dropped.
    private var locateID = 0

    init(plan: MakeupPlan, applied: [MakeupRecommendation]) {
        self.plan = plan
        selection = Dictionary(applied.map { ($0.category, $0) }, uniquingKeysWith: { _, last in last })
    }

    func recommendations(in category: MakeupCategory) -> [MakeupRecommendation] {
        plan.recommendations(in: category)
    }

    func select(_ recommendation: MakeupRecommendation?, in category: MakeupCategory) {
        guard selection[category] != recommendation else { return }
        selection[category] = recommendation
        redraw(category)
    }

    func shade(for category: MakeupCategory) -> MakeupShade? {
        shadeChoices[category] ?? selection[category]?.style.shade
    }

    func select(_ shade: MakeupShade, in category: MakeupCategory) {
        guard self.shade(for: category) != shade else { return }
        shadeChoices[category] = shade
        redraw(category)
    }

    func intensity(for category: MakeupCategory) -> Double {
        intensities[category] ?? MakeupTextureRenderer.startingIntensity(for: category)
    }

    func setIntensity(_ intensity: Double, for category: MakeupCategory) {
        intensities[category] = min(max(intensity, 0), 1)
    }

    /// What the AR view draws: only categories with a finished texture.
    var layers: [MakeupCategory: MakeupLayer] {
        textures.reduce(into: [:]) { layers, entry in
            layers[entry.key] = MakeupLayer(texture: entry.value, intensity: intensity(for: entry.key))
        }
    }

    var hasMakeup: Bool { !textures.isEmpty }

    func start() async {
        guard ARFaceTrackingConfiguration.isSupported else { phase = .unsupported; return }
        guard await Self.cameraAccessGranted() else { phase = .cameraDenied; return }
        session.delegate = self
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        // Placement is kept across pauses; the same person is most likely still in front of the camera.
        if features == nil { resetPlacement() } else { phase = .ready }
    }

    func startIfNeeded() async {
        switch phase {
        case .idle, .cameraDenied: await start()
        default: break
        }
    }

    func stop() {
        session.pause()
        isSessionRunning = false
        switch phase {
        case .locating, .ready, .interrupted: phase = .idle
        default: break
        }
    }

    /// Locates the brows and eyes again, for example after someone else steps in front of the camera.
    func relocate() {
        guard isSessionRunning else { return }
        resetPlacement()
    }

    private func resetPlacement() {
        features = nil
        liveFeatures = nil
        isLocatingLive = false
        samples.removeAll()
        facingFrames = 0
        locateID += 1
        renderTasks.values.forEach { $0.cancel() }
        renderTasks.removeAll()
        textures.removeAll()
        fit = nil
        phase = .locating(.findFace)
    }

    private func redrawAll() {
        MakeupCategory.allCases.forEach(redraw)
    }

    /// Draws one category's texture in the background; a newer request for the same category replaces it.
    private func redraw(_ category: MakeupCategory) {
        renderTasks[category]?.cancel()
        let drawn = category == .eyeliner ? liveFeatures ?? features : features
        guard let features = drawn, let recommendation = selection[category] else {
            renderTasks[category] = nil
            textures[category] = nil
            return
        }
        let style = shade(for: category).map(recommendation.style.with(shade:)) ?? recommendation.style
        renderTasks[category] = Task {
            let image = await Task.detached(priority: .userInitiated) {
                MakeupTextureRenderer.image(for: style, features: features)
            }.value
            guard !Task.isCancelled else { return }
            textures[category] = image
            renderTasks[category] = nil
        }
    }

    private func handle(_ sample: TryOnSample?) {
        if phase == .ready, let sample, sample.isTracked, sample.isFacingCamera { followEyes(with: sample.input) }
        guard case .locating = phase else { return }
        let guidance: Guidance
        if let sample, sample.isTracked {
            guidance = sample.isFacingCamera ? .holdStill : .lookStraight
            if sample.isFacingCamera { requestFeatures(for: sample.input) }
        } else {
            guidance = .findFace
        }
        if phase != .locating(guidance) { phase = .locating(guidance) }
    }

    /// Keeps the liner on the person's actual eyes, so it follows when they squint, stretch the lid or blink.
    private func followEyes(with input: FeatureLocatorInput) {
        facingFrames += 1
        guard selection[.eyeliner] != nil, features != nil, !isLocatingLive, renderTasks[.eyeliner] == nil,
              facingFrames.isMultiple(of: Self.liveEyeInterval) else { return }
        isLocatingLive = true
        let preferred = orientation, locateID = locateID
        Task.detached(priority: .userInitiated) {
            let found = FaceFeatureLocator.features(for: input, preferred: preferred)
            await self.receiveLive(found?.0, locateID: locateID)
        }
    }

    private func receiveLive(_ found: FaceFeatureMap?, locateID: Int) {
        isLocatingLive = false
        guard locateID == self.locateID, phase == .ready, let found, let base = liveFeatures ?? features,
              let blended = base.replacingEyes(blending: found, weight: Self.liveEyeWeight),
              blended.isPlausible else { return }
        liveFeatures = blended
        redraw(.eyeliner)
    }

    private func requestFeatures(for input: FeatureLocatorInput) {
        facingFrames += 1
        guard !isLocating, facingFrames.isMultiple(of: Self.sampleInterval) else { return }
        isLocating = true
        let preferred = orientation, locateID = locateID
        Task.detached(priority: .userInitiated) {
            let found = FaceFeatureLocator.features(for: input, preferred: preferred)
            await self.receive(found, locateID: locateID)
        }
    }

    private func receive(_ found: (FaceFeatureMap, CGImagePropertyOrientation)?, locateID: Int) {
        isLocating = false
        guard let found, locateID == self.locateID, case .locating = phase else { return }
        orientation = found.1
        samples.append(found.0)
        guard samples.count >= Self.requiredSamples else { return }
        if let average = FaceFeatureMap.average(samples), average.isPlausible {
            features = average
            fit = FaceFit(features: average)
            phase = .ready
            redrawAll()
        } else {
            // Vision returned different point layouts; start over with fresh samples.
            samples.removeAll()
        }
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
private struct TryOnSample: Sendable {
    static let maxHeadTurn = Float.pi / 12 // 15°

    let isTracked: Bool
    let isFacingCamera: Bool
    let input: FeatureLocatorInput

    init(face: ARFaceAnchor, frame: ARFrame) {
        isTracked = face.isTracked
        let cameraTransform = frame.camera.transform
        let facePosition = simd_make_float3(face.transform.columns.3)
        let faceForward = simd_normalize(simd_make_float3(face.transform.columns.2))
        let toCamera = simd_normalize(simd_make_float3(cameraTransform.columns.3) - facePosition)
        isFacingCamera = simd_dot(faceForward, toCamera) > cos(Self.maxHeadTurn)
        let contour = ContourInput(pixelBuffer: SendablePixelBuffer(buffer: frame.capturedImage),
                                   cameraTransform: cameraTransform, intrinsics: frame.camera.intrinsics,
                                   faceTransform: face.transform)
        input = FeatureLocatorInput(contour: contour, vertices: face.geometry.vertices,
                                    textureCoordinates: face.geometry.textureCoordinates,
                                    triangleIndices: FilledFaceMesh.triangleIndices(
                                        vertexCount: face.geometry.vertices.count,
                                        fallback: face.geometry.triangleIndices))
    }
}

extension MakeupTryOnViewModel: ARSessionDelegate {
    // ARSession calls its delegate on the main queue unless a delegateQueue is set.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let face = frame.anchors.lazy.compactMap { $0 as? ARFaceAnchor }.first
        let sample = face.map { TryOnSample(face: $0, frame: frame) }
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
            switch phase {
            case .locating, .ready: phase = .interrupted
            default: break
            }
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            if phase == .interrupted { Task { await start() } }
        }
    }
}
