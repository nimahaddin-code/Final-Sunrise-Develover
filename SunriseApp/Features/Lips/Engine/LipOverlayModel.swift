import ARKit
import Combine
import SwiftUI

/// Runs the lipstick overlay, the way `LinerOverlayModel` runs the eyeliner: ARKit's camera frames go to MediaPipe, the
/// lip points it returns are carried with the head on every frame and published in view points for the 2D overlay above
/// the camera. Only runs while a lip style is set.
@MainActor final class LipOverlayModel: ObservableObject {
    @Published private(set) var frame: LipOverlayFrame?
    /// Set when the detector could not start (for example the model file is missing).
    @Published private(set) var unavailableReason: String?
    private(set) var style: LipStyle?
    private(set) var shade: MakeupShade?
    private(set) var intensity: Double = 1

    /// Size of the view the overlay is drawn in, in points. Set by `LipOverlayView` and `LipStepGuide`.
    var viewport: CGSize = .zero

    private let provider = MediaPipeEyeLandmarkProvider()
    /// The detector need not see every 60 Hz frame: `publish` carries the newest result with the head each frame.
    private var throttle = FrameThrottle(interval: 1.0 / 30)
    /// The newest detector result, with where the head's mouth anchors were in that camera frame (image pixels).
    private var measured: (lips: LipLandmarks, anchors: [CGPoint], time: CFTimeInterval)?
    private var isStarted = false
    private var startupTask: Task<Void, Never>?
    private var runID = UUID()

    /// Without a newer result (a hand over the mouth, the face lost) the lips stay on the head this long, then go.
    static let holdDuration: CFTimeInterval = 0.8
    /// How far a new result moves the lips from where they were (0...1): takes the detector's jitter off a still mouth
    /// while a talking mouth is still followed within two or three results.
    static let follow: CGFloat = 0.65

    /// The reference points whose image and screen positions are compared to check the mapping (as for the eyeliner).
    private static let referencePoints: [SIMD3<Float>] = [
        .zero, SIMD3(0.05, 0, 0), SIMD3(0, 0.05, 0), SIMD3(-0.05, 0, 0), SIMD3(0, -0.05, 0),
    ]
    /// Points round the mouth at about its depth in ARKit's face space (metres), so they follow head turns the way the
    /// lips do. Rough values: they only carry a result over the one or two frames until the next one.
    private static let mouthAnchors: [SIMD3<Float>] = [
        SIMD3(-0.025, -0.04, 0.05), SIMD3(0.025, -0.04, 0.05), SIMD3(0, -0.025, 0.055), SIMD3(0, -0.055, 0.045),
    ]

    /// A nil style hides the overlay; `stop()` releases the detector.
    func setStyle(_ style: LipStyle?, shade: MakeupShade?, intensity: Double) {
        self.style = style
        self.shade = shade
        self.intensity = intensity
        if style == nil {
            measured = nil
            frame = nil
        } else {
            startIfNeeded()
        }
        objectWillChange.send()
    }

    func stop() {
        runID = UUID(); startupTask?.cancel(); startupTask = nil
        provider.stop()
        provider.onFrame = nil
        measured = nil
        frame = nil
        throttle.reset()
        isStarted = false
    }

    private func startIfNeeded() {
        guard !isStarted, startupTask == nil else { return }
        let token = runID
        provider.onFrame = { [weak self] landmarks in
            Task { @MainActor in
                guard let self, self.runID == token, self.isStarted else { return }
                self.receive(landmarks)
            }
        }
        startupTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.runID == token else { return }
            do {
                try await self.provider.start()
                guard !Task.isCancelled, self.runID == token else { return }
                self.isStarted = true; self.unavailableReason = nil; self.startupTask = nil
            } catch {
                guard self.runID == token else { return }
                self.startupTask = nil
                if !(error is CancellationError) { self.unavailableReason = error.localizedDescription }
            }
        }
    }

    /// Called for every ARKit frame while the face is tracked. The detector gets a frame when it is idle; every frame the
    /// newest lips are carried to the head's current position.
    func submit(_ arFrame: ARFrame, face: ARFaceAnchor) {
        guard isStarted, style != nil, viewport.width > 1, viewport.height > 1 else { return }
        let contour = ContourInput(pixelBuffer: SendablePixelBuffer(buffer: arFrame.capturedImage),
                                   cameraTransform: arFrame.camera.transform, intrinsics: arFrame.camera.intrinsics,
                                   faceTransform: face.transform)
        guard let raw = contour.project(Self.referencePoints), raw.count == Self.referencePoints.count,
              let mouth = contour.project(Self.mouthAnchors) else { return }
        func point(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)) }
        let references = zip(Self.referencePoints, raw).map { local, image -> MappingReference in
            let world = face.transform * SIMD4(local, 1)
            let view = arFrame.camera.projectPoint(SIMD3(world.x, world.y, world.z), orientation: .portrait,
                                                   viewportSize: viewport)
            return MappingReference(image: point(image), view: view)
        }
        let buffer = arFrame.capturedImage
        let context = FrameContext(
            displayTransform: arFrame.displayTransform(for: .portrait, viewportSize: viewport),
            imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
            viewportSize: viewport, references: references, headAnchors: mouth.map(point))
        if !provider.isBusy, throttle.allows(arFrame.timestamp) {
            provider.submit(LandmarkInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                          headUp: point(raw[2]) - point(raw[0]),
                                          headAcross: point(raw[1]) - point(raw[0]), context: context))
        }
        publish(context)
    }

    /// Draws the newest lips, moved with the head, with this frame's screen mapping.
    private func publish(_ context: FrameContext) {
        let now = CACurrentMediaTime()
        guard let measured, now - measured.time <= Self.holdDuration else {
            if frame != nil { frame = nil }
            return
        }
        let lips = Self.moved(measured.lips, from: measured.anchors, to: context.headAnchors)
        let mapping = ImageToViewMapping.resolve(context)
        frame = LipOverlayFrame(outer: lips.outer.map(mapping.map), inner: lips.inner.map(mapping.map), receivedAt: now)
    }

    private func receive(_ landmarks: EyeLandmarkFrame?) {
        // No face in this frame: the last lips stay on the head until `holdDuration`.
        guard style != nil, let landmarks, let context = landmarks.context, var lips = landmarks.lips, lips.isComplete else { return }
        let now = CACurrentMediaTime()
        if let measured, now - measured.time < 0.2 {
            let previous = Self.moved(measured.lips, from: measured.anchors, to: context.headAnchors)
            lips = LipLandmarks(outer: zip(previous.outer, lips.outer).map { $0.lerp(to: $1, Self.follow) },
                                inner: zip(previous.inner, lips.inner).map { $0.lerp(to: $1, Self.follow) })
        }
        measured = (lips, context.headAnchors, now)
    }

    /// `lips` carried from where the head's anchors were (`from`) to where they are now (`to`): turn, scale and shift.
    /// Left as they are when the anchors give no sane fit (a head cannot double or halve between two frames).
    nonisolated static func moved(_ lips: LipLandmarks, from: [CGPoint], to: [CGPoint]) -> LipLandmarks {
        guard let transform = SimilarityTransform(from: from, to: to) else { return lips }
        let scale = (transform.zr * transform.zr + transform.zi * transform.zi).squareRoot()
        guard scale > 0.5, scale < 2 else { return lips }
        return LipLandmarks(outer: lips.outer.map(transform.apply), inner: lips.inner.map(transform.apply))
    }

    /// `snapshot` with the lipstick on it, for photos.
    func composed(_ snapshot: UIImage) -> UIImage {
        guard let frame, let style, let shade else { return snapshot }
        return LipShape.compose(snapshot, frame: frame, style: style, shade: shade, intensity: intensity)
    }
}

/// The lipstick layer above the camera view, the same size as it (both ignore the safe area).
struct LipOverlayView: View {
    @ObservedObject var model: LipOverlayModel
    /// `false` hides the lipstick, for comparing with the bare face.
    let isVisible: Bool
    /// Draws only on this half of the lips (the tutorial's side-by-side comparison).
    var visibleSide: HorizontalEdge?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard isVisible, let frame = model.frame, let style = model.style, let shade = model.shade else { return }
                if let visibleSide {
                    let cut = frame.splitX
                    context.clip(to: Path(CGRect(x: visibleSide == .leading ? 0 : cut, y: 0,
                                                 width: visibleSide == .leading ? cut : size.width - cut, height: size.height)))
                }
                for layer in LipShape.layers(frame, style: style, shade: shade, intensity: model.intensity) {
                    context.drawLayer { paint in
                        if let clip = layer.clip { paint.clip(to: Path(clip), style: FillStyle(eoFill: true)) }
                        paint.addFilter(.blur(radius: layer.blur))
                        paint.fill(Path(layer.path), with: .color(shade.color.opacity(layer.alpha)), style: FillStyle(eoFill: true))
                    }
                }
            }
            .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
