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
    /// The detectors need not see every 60 Hz frame: `publish` carries the newest result with the head each frame.
    /// Landmarks at up to 30 Hz, the hand mask (which moves slowly) at up to 15 Hz.
    private var landmarkThrottle = FrameThrottle(interval: 1.0 / 30)
    private var occlusionThrottle = FrameThrottle(interval: 1.0 / 15)
    /// Skin tone near the eyes, smoothed; re-read every few frames.
    private var skin: InkColor?
    private var skinCountdown = 0
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

    /// Off unless a developer switches it on: the upper lid follows the skin between detector results (a pulled lid).
    private static var lidTrackingEnabled: Bool { UserDefaults.standard.bool(forKey: "enableLidTracking") }
    /// `true` makes this overlay follow a pulled lid whatever the developer flag says (the tutorial's guide points).
    /// It also smooths less (`OneEuroConfig.responsive`), so the points keep up with a lid that is stretched by hand.
    var followsPulledLid = false { didSet { tracker.filterConfig = followsPulledLid ? .responsive : .steady } }
    private var lidTrackingOn: Bool { followsPulledLid || Self.lidTrackingEnabled }

    /// A nil style hides the overlay; screen deactivation releases the detectors.
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
        // -Nimah: Category switches reuse loaded models. submit() skips all inference while spec is nil.
        // Releasing/reloading both GPU models on every tab switch creates transition stalls.
        if spec != nil { startIfNeeded() }
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
        skin = nil
        landmarkThrottle.reset(); occlusionThrottle.reset()
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
        // Hands near the eye tell lid tracking that a lid may be pulled. Without the model it simply never follows.
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
                guard !Task.isCancelled,self.runID==token else { return }
                // -Nimah: A category can change while loading. Finish warming this screen's model;
                // only stop()/deactivation invalidates this run, so returning cannot leave startup stuck.
                self.isStarted=true; self.unavailableReason=nil
                try? await self.occluder.start()
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
    private var turnedAway = false
    static let turnHideDegrees = 32.0, turnClearDegrees = 25.0

    func submit(_ arFrame: ARFrame, face: ARFaceAnchor) {
        guard isStarted, spec != nil, viewport.width > 1, viewport.height > 1 else { return }
        // Head turned far enough that one eye is hidden: the liner goes away at once (the detector would otherwise
        // put it on the other eye, late) and returns when the face is straight again.
        let relative = simd_inverse(arFrame.camera.transform) * face.transform
        let yaw = Double(atan2(abs(relative.columns.2.y), abs(relative.columns.2.z))) * 180 / .pi
        let turned = turnedAway ? yaw > Self.turnClearDegrees : yaw > Self.turnHideDegrees
        if turned != turnedAway {
            turnedAway = turned
            if turned { solution = nil; frame = nil; tracker.reset() }
        }
        if turned { return }
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
        if lidTrackingOn, headAnchors.count >= 3 {
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
        if !provider.isBusy, landmarkThrottle.allows(arFrame.timestamp) {
            provider.submit(LandmarkInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                          headUp: point(raw[2]) - point(raw[0]),
                                          headAcross: point(raw[1]) - point(raw[0]), context: context))
        }
        if occluder.isAvailable, !occluder.isBusy, occlusionThrottle.allows(arFrame.timestamp) {
            occluder.submit(OcclusionInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                           headUp: point(raw[2]) - point(raw[0]),
                                           headAnchors: headAnchors.count >= 3 ? headAnchors : references.map(\.image)))
        }
        refreshSkin(from: buffer)
        publish(context)
    }

    /// Re-reads the skin around the eyes every few frames, from a few camera pixels, and smooths it.
    private func refreshSkin(from buffer: CVPixelBuffer) {
        skinCountdown -= 1
        guard skinCountdown <= 0, let eyes = frame?.eyes, !eyes.isEmpty else { return }
        skinCountdown = 8
        let readings = eyes.compactMap {
            LinerInk.sampleSkin(in: buffer, aroundEyeFrom: $0.guide.anchors.innerCorner, to: $0.guide.anchors.outerCorner)
        }
        guard let reading = LinerInk.skinTone(of: readings) else { return }
        skin = skin.map { $0.mixed(toward: reading, by: 0.3) } ?? reading
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
                                  occlusion: occlusionMask?.placement(headAnchors: head, mapping: mapping, at: now),
                                  skin: skin)
    }

    private func receive(_ landmarks: EyeLandmarkFrame?) {
        guard isStarted, !turnedAway, let spec else { return }
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
        let fused = lidTrackingOn ? lidFollower.fuse(landmarks, now: landmarks.timestamp, hand: hand) : landmarks
        let eyes = tracker.render(fused, spec: spec)
        solution = LinerSolution(eyes: eyes, raw: landmarks.eyes, smoothed: tracker.lastSmoothed,
                                 references: context.headAnchors.count >= 3 ? context.headAnchors : context.references.map(\.image),
                                 time: CACurrentMediaTime())
        debugStatus = String(format: "MediaPipe: face, %.0f ms, %d eye(s) drawn%@", landmarks.providerLatencyMs, eyes.count,
                             lidTrackingOn
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
    @AppStorage(DeveloperTools.key) private var developerMode = false
    /// `false` hides the liner, for comparing with the bare face.
    let isVisible: Bool
    /// Draws only on this half of the view (the tutorial's side-by-side comparison). Clipping inside the canvas keeps the
    /// multiply blend against the camera, which a mask outside the view would break.
    var visibleSide: HorizontalEdge?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard isVisible, let frame = model.frame, let shade = model.shade else { return }
                if let visibleSide {
                    let half = size.width / 2
                    context.clip(to: Path(CGRect(x: visibleSide == .leading ? 0 : half, y: 0, width: half, height: size.height)))
                }
                let ink = LinerOverlayRenderer.ink(shade, skin: frame.skin)
                let color = Color(red: ink.red, green: ink.green, blue: ink.blue)
                context.drawLayer { layer in
                    let fills = LinerOverlayRenderer.fills(frame, shade: shade, intensity: model.intensity)
                    for fill in fills {
                        // The faint bleed first, then the liner on top of it.
                        layer.drawLayer { bleed in
                            bleed.addFilter(.blur(radius: fill.haloBlur))
                            bleed.fill(Path(fill.path), with: .color(color.opacity(fill.haloAlpha)), style: FillStyle(eoFill: false))
                        }
                        layer.drawLayer { liner in
                            liner.addFilter(.blur(radius: fill.blur))
                            liner.fill(Path(fill.path), with: .color(color.opacity(fill.alpha)), style: FillStyle(eoFill: false))
                        }
                    }
                    // Skin texture shows through the ink in faint speckles that stay with the eye.
                    if let tile = LinerInk.grainTile {
                        let grain = Image(decorative: tile, scale: 1)
                        layer.blendMode = .destinationOut
                        for fill in fills {
                            for rect in LinerInk.grainTiles(covering: fill.grainBox, anchoredAt: fill.anchor) {
                                layer.draw(grain, in: rect)
                            }
                        }
                    }
                }
                if developerMode, showsMask, let occlusion = frame.occlusion {
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
            // Multiply over the camera picture, like ink: the skin's texture, shading and light show through the liner
            // instead of a flat colour sitting on top of it.
            .blendMode(.multiply)
            .overlay { landmarkDots }
            .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Developer tools: red = MediaPipe's points as reported, green = smoothed (what the liner is built from).
    @ViewBuilder private var landmarkDots: some View {
        if developerMode, showsLandmarks, isVisible, let frame = model.frame {
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

/// Lets a frame through at most once per `interval` seconds of camera time.
struct FrameThrottle {
    let interval: TimeInterval
    private var last: TimeInterval?

    init(interval: TimeInterval) { self.interval = interval }

    /// `true` (and remembers `timestamp`) when enough time has passed since the last accepted frame.
    mutating func allows(_ timestamp: TimeInterval) -> Bool {
        if let last, timestamp >= last, timestamp - last < interval { return false }
        last = timestamp
        return true
    }

    mutating func reset() { last = nil }
}
