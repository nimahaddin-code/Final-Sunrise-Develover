import ARKit
import Combine
import SwiftUI

/// Runs the eyeliner overlay: feeds ARKit's camera frames to MediaPipe, turns the landmarks into liner geometry and
/// publishes it for the 2D overlay above the AR view. Only runs while an eyeliner is selected.
@MainActor final class LinerOverlayModel: ObservableObject {
    @Published private(set) var frame: LinerOverlayFrame?
    /// Set when the detector could not start (for example the model file is missing).
    @Published private(set) var unavailableReason: String?
    /// DEBUG: what the detector last reported.
    @Published private(set) var debugStatus = ""
    private(set) var shade: MakeupShade?
    private(set) var intensity: Double = 1

    /// Size of the view the overlay is drawn in, in points. Set by `LinerOverlayView`.
    var viewport: CGSize = .zero

    private let provider = MediaPipeEyeLandmarkProvider()
    private let occluder = HandOcclusionSegmenter()
    private var occlusionMask: OcclusionMask?
    private let tracker = LinerTracker()
    private let lidFollower = LidFollower()
    private let lidQueue = DispatchQueue(label: "sunrise.lidflow", qos: .userInitiated)
    private var lidBusy = false
    private var lastHand = 0.0
    private var spec: LinerSpec?
    private var solution: LinerSolution?
    private var isStarted = false
    // -Nimah: Cancel a pending model load when the screen/style stops using it.
    private var startupTask:Task<Void,Never>?
    private var runID=UUID()

    /// The reference points whose image and screen positions are compared to check the mapping.
    private static let referencePoints: [SIMD3<Float>] = [
        .zero, SIMD3(0.05, 0, 0), SIMD3(0, 0.05, 0), SIMD3(-0.05, 0, 0), SIMD3(0, -0.05, 0),
    ]

    var hasLiner: Bool { spec != nil }

    /// Developer tools can switch the hand cut-out off, to tell whether it is what hides the liner.
    private static var handOcclusionDisabled: Bool { UserDefaults.standard.bool(forKey: "disableOcclusion") }
    /// Off unless a developer switches it on: the upper lid follows the skin between detector results (a pulled lid).
    private static var lidTrackingEnabled: Bool { UserDefaults.standard.bool(forKey: "enableLidTracking") }

    /// `style == nil` switches the overlay off and stops the detector.
    func setStyle(_ style: LinerStyle?, shade: MakeupShade?, intensity: Double) {
        self.shade = shade
        self.intensity = intensity
        let newSpec = style.map(LinerSpec.init(style:))
        if newSpec != spec {
            spec = newSpec
            // Geometry for the old style must not linger.
            solution = nil
            frame = nil
        }
        if spec == nil { stop() } else { startIfNeeded() }
        objectWillChange.send()
    }

    func stop() {
        runID=UUID(); startupTask?.cancel(); startupTask=nil
        provider.stop()
        provider.onFrame = nil
        tracker.reset()
        lidFollower.reset()
        occluder.stop()
        occluder.onMask = nil
        occlusionMask = nil
        solution = nil
        frame = nil
        isStarted = false
    }

    private func startIfNeeded() {
        guard !isStarted,startupTask==nil else { return }
        let token=runID
        provider.onFrame = { [weak self] landmarks in
            Task { @MainActor in
                guard let self,self.runID==token,self.isStarted else { return }
                self.receive(landmarks)
            }
        }
        // Without the segmentation model the liner simply is not hidden behind hands.
        occluder.onMask = { [weak self] mask in
            Task { @MainActor in
                guard let self,self.runID==token,self.isStarted else { return }
                self.occlusionMask=mask
            }
        }
        startupTask=Task { [weak self] in
            guard let self,!Task.isCancelled,self.runID==token else { return }
            do {
                try await self.provider.start()
                guard !Task.isCancelled,self.runID==token,self.spec != nil else { return }
                self.isStarted=true; self.unavailableReason=nil
                if !Self.handOcclusionDisabled { try? await self.occluder.start() }
                guard !Task.isCancelled,self.runID==token else { return }
                self.startupTask=nil
            } catch {
                guard self.runID==token else { return }
                self.startupTask=nil
                if !(error is CancellationError) { self.unavailableReason=error.localizedDescription }
            }

        }
    }

    /// Called for every ARKit frame while the face is tracked. The detector gets a frame when it is idle (frames are
    /// dropped while it is busy); every frame the newest measurement is carried to the head's current position.
    func submit(_ arFrame: ARFrame, face: ARFaceAnchor) {
        guard isStarted, spec != nil, viewport.width > 1, viewport.height > 1 else { return }
        let contour = ContourInput(pixelBuffer: SendablePixelBuffer(buffer: arFrame.capturedImage),
                                   cameraTransform: arFrame.camera.transform, intrinsics: arFrame.camera.intrinsics,
                                   faceTransform: face.transform)
        guard let raw = contour.project(Self.referencePoints), raw.count == Self.referencePoints.count else { return }
        func point(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }
        let references = zip(Self.referencePoints, raw).map { local, image -> MappingReference in
            let world = face.transform * SIMD4(local, 1)
            let view = arFrame.camera.projectPoint(SIMD3(world.x, world.y, world.z), orientation: .portrait,
                                                   viewportSize: viewport)
            return MappingReference(image: point(image), view: view)
        }
        // Points at the depth of the eyes (the eyeballs' centres, 2 cm above and below), so they follow head turns the
        // way the eyelids do; the face origin sits behind the head's middle and would not.
        let eyePositions = [face.leftEyeTransform, face.rightEyeTransform].map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
        let headAnchors = contour.project(eyePositions.flatMap { [$0 + SIMD3(0, 0.02, 0), $0 - SIMD3(0, 0.02, 0)] })?
            .map(point) ?? []
        let buffer = arFrame.capturedImage
        if Self.lidTrackingEnabled, headAnchors.count >= 3 {
            // Off the main thread, one frame at a time; frames that arrive meanwhile are skipped.
            if !lidBusy {
                lidBusy = true
                let frame = SendablePixelBuffer(buffer: buffer), follower = lidFollower
                lidQueue.async { [weak self] in
                    follower.advance(frame.buffer, headAnchors: headAnchors)
                    Task { @MainActor in self?.lidBusy = false }
                }
            }
        } else if lidFollower.followingCount > 0 {
            lidFollower.reset()
        }
        let context = FrameContext(
            displayTransform: arFrame.displayTransform(for: .portrait, viewportSize: viewport),
            imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
            viewportSize: viewport, references: references, headAnchors: headAnchors)
        if !provider.isBusy {
            provider.submit(LandmarkInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                          headUp: point(raw[2]) - point(raw[0]),
                                          headAcross: point(raw[1]) - point(raw[0]), context: context))
        }
        if occluder.isAvailable, !occluder.isBusy {
            occluder.submit(OcclusionInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                           headUp: point(raw[2]) - point(raw[0]),
                                           headAnchors: headAnchors.count >= 3 ? headAnchors : references.map(\.image)))
        }
        publish(context)
    }

    /// Draws the newest measurement, moved with the head, with this frame's screen mapping.
    private func publish(_ context: FrameContext) {
        let now = CACurrentMediaTime()
        let head = context.headAnchors.count >= 3 ? context.headAnchors : context.references.map(\.image)
        guard let solution, let moved = solution.moved(to: head, now: now) else {
            if frame != nil { frame = nil }
            return
        }
        let mapping = ImageToViewMapping.resolve(context)
        frame = LinerOverlayFrame(eyes: moved.eyes, mapping: mapping, receivedAt: now, debugRaw: moved.raw,
                                  debugSmoothed: moved.smoothed,
                                  occlusion: Self.handOcclusionDisabled ? nil
                                      : occlusionMask?.placement(headAnchors: head, mapping: mapping, at: now))
    }

    private func receive(_ landmarks: EyeLandmarkFrame?) {
        guard isStarted, let spec else { return }
        guard let landmarks, let context = landmarks.context else {
            // No face in this frame (a hand over it, for example): keep the last measurement on the head for a while,
            // and smooth afresh when the face comes back.
            tracker.reset()
            lidFollower.reset()
            debugStatus = "MediaPipe: no face"
            return
        }
        var hand: [EyeSide: Double] = [:]
        if let mask = occlusionMask, let anchors = context.headAnchors.count >= 3 ? context.headAnchors : nil {
            let now = CACurrentMediaTime()
            for eye in landmarks.eyes {
                let width = hypot(eye.outerCorner.x - eye.innerCorner.x, eye.outerCorner.y - eye.innerCorner.y)
                let middle = CGPoint(x: (eye.outerCorner.x + eye.innerCorner.x) / 2, y: (eye.outerCorner.y + eye.innerCorner.y) / 2)
                hand[eye.side] = mask.handFraction(around: middle, radius: width * 1.2, headAnchors: anchors, at: now)
            }
        }
        lastHand = hand.values.max() ?? 0
        let fused = Self.lidTrackingEnabled ? lidFollower.fuse(landmarks, now: landmarks.timestamp, hand: hand) : landmarks
        let eyes = tracker.render(fused, spec: spec)
        solution = LinerSolution(eyes: eyes, raw: landmarks.eyes, smoothed: tracker.lastSmoothed,
                                 references: context.headAnchors.count >= 3 ? context.headAnchors : context.references.map(\.image),
                                 time: CACurrentMediaTime())
        debugStatus = String(format: "MediaPipe: face, %.0f ms, %d eye(s) drawn%@", landmarks.providerLatencyMs, eyes.count,
                             Self.lidTrackingEnabled
                                 ? ", lid tracking \(lidFollower.followingCount)/2, hand \(Int(lastHand * 100))%" : "")
    }

    /// `snapshot` with the liner on it, for photos.
    func composed(_ snapshot: UIImage) -> UIImage {
        guard let frame, let shade else { return snapshot }
        // The photo is taken now; the newest landmarks are at most a frame old.
        return LinerOverlayRenderer.compose(snapshot, overlay: frame, shade: shade, intensity: intensity)
    }
}

/// The 2D layer above `MakeupARView`. Pixel-for-pixel the same size as the AR view (both ignore the safe area).
struct LinerOverlayView: View {
    @ObservedObject var model: LinerOverlayModel
    @AppStorage("debugEyeLandmarks") private var showsLandmarks = false
    @AppStorage("debugOcclusionMask") private var showsMask = false
    /// `false` hides the liner, for comparing with the bare face.
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, _ in
                guard isVisible, let frame = model.frame, let shade = model.shade else { return }
                let color = Color(red: shade.red, green: shade.green, blue: shade.blue)
                context.drawLayer { layer in
                    for fill in LinerOverlayRenderer.fills(frame, shade: shade, intensity: model.intensity) {
                        layer.drawLayer { liner in
                            liner.addFilter(.blur(radius: fill.blur))
                            liner.fill(Path(fill.path), with: .color(color.opacity(fill.alpha)), style: FillStyle(eoFill: false))
                        }
                    }
                    // A hand in front of the eye: erase the liner where the segmenter found body skin.
                    if let occlusion = frame.occlusion {
                        layer.blendMode = .destinationOut
                        layer.concatenate(occlusion.transform)
                        layer.draw(Image(decorative: occlusion.image, scale: 1),
                                   in: CGRect(origin: .zero, size: occlusion.size))
                    }
                }
                if showsMask, let occlusion = frame.occlusion {
                    context.drawLayer { layer in
                        layer.clipToLayer { mask in
                            mask.concatenate(occlusion.transform)
                            mask.draw(Image(decorative: occlusion.image, scale: 1),
                                      in: CGRect(origin: .zero, size: occlusion.size))
                        }
                        layer.fill(Path(CGRect(x: -2000, y: -2000, width: 6000, height: 6000)), with: .color(.red.opacity(0.4)))
                    }
                }
            }
            .overlay { landmarkDots }
            .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Developer tools: red = MediaPipe's points as reported, green = smoothed (what the liner is built from).
    @ViewBuilder private var landmarkDots: some View {
        if showsLandmarks, isVisible, let frame = model.frame {
            Canvas { context, _ in
                func dots(_ eyes: [EyeLandmarks], _ color: Color, _ radius: CGFloat) {
                    for eye in eyes {
                        for point in eye.flattened {
                            let p = frame.mapping.map(point)
                            context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2,
                                                                height: radius * 2)), with: .color(color))
                        }
                    }
                }
                dots(frame.debugRaw, .red, 2)
                dots(frame.debugSmoothed, .green, 2.5)
            }
        }
    }
}
