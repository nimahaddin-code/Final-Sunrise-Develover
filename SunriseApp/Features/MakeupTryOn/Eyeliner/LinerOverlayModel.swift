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
    private let tracker = LinerTracker()
    private var spec: LinerSpec?
    private var solution: LinerSolution?
    private var isStarted = false

    /// The reference points whose image and screen positions are compared to check the mapping.
    private static let referencePoints: [SIMD3<Float>] = [
        .zero, SIMD3(0.05, 0, 0), SIMD3(0, 0.05, 0), SIMD3(-0.05, 0, 0), SIMD3(0, -0.05, 0),
    ]

    var hasLiner: Bool { spec != nil }

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
        guard isStarted else { return }
        provider.stop()
        provider.onFrame = nil
        tracker.reset()
        solution = nil
        frame = nil
        isStarted = false
    }

    private func startIfNeeded() {
        guard !isStarted else { return }
        provider.onFrame = { [weak self] landmarks in
            Task { @MainActor in self?.receive(landmarks) }
        }
        do {
            try provider.start()
            isStarted = true
            unavailableReason = nil
        } catch {
            unavailableReason = error.localizedDescription
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
        let context = FrameContext(
            displayTransform: arFrame.displayTransform(for: .portrait, viewportSize: viewport),
            imageSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
            viewportSize: viewport, references: references, headAnchors: headAnchors)
        if !provider.isBusy {
            provider.submit(LandmarkInput(pixelBuffer: contour.pixelBuffer, timestamp: arFrame.timestamp,
                                          headUp: point(raw[2]) - point(raw[0]),
                                          headAcross: point(raw[1]) - point(raw[0]), context: context))
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
        frame = LinerOverlayFrame(eyes: moved.eyes, mapping: ImageToViewMapping.resolve(context), receivedAt: now,
                                  debugRaw: moved.raw, debugSmoothed: moved.smoothed)
    }

    private func receive(_ landmarks: EyeLandmarkFrame?) {
        guard isStarted, let spec else { return }
        guard let landmarks, let context = landmarks.context else {
            // No face in this frame (a hand over it, for example): keep the last measurement on the head for a while,
            // and smooth afresh when the face comes back.
            tracker.reset()
            noteStatus("MediaPipe: no face")
            return
        }
        let eyes = tracker.render(landmarks, spec: spec)
        solution = LinerSolution(eyes: eyes, raw: tracker.lastRaw, smoothed: tracker.lastSmoothed,
                                 references: context.headAnchors.count >= 3 ? context.headAnchors : context.references.map(\.image),
                                 time: CACurrentMediaTime())
        noteStatus(String(format: "MediaPipe: face, %.0f ms, %d eye(s) drawn", landmarks.providerLatencyMs, eyes.count))
    }

    private func noteStatus(_ text: String) {
        #if DEBUG
        debugStatus = text
        #endif
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
    #if DEBUG
    @AppStorage("debugEyeLandmarks") private var showsLandmarks = false
    #endif
    /// `false` hides the liner, for comparing with the bare face.
    let isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, _ in
                guard isVisible, let frame = model.frame, let shade = model.shade else { return }
                let color = Color(red: shade.red, green: shade.green, blue: shade.blue)
                for fill in LinerOverlayRenderer.fills(frame, shade: shade, intensity: model.intensity) {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: fill.blur))
                        layer.fill(Path(fill.path), with: .color(color.opacity(fill.alpha)), style: FillStyle(eoFill: false))
                    }
                }
            }
            .overlay { landmarkDots }
            .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// DEBUG only: red = MediaPipe's points as reported, green = smoothed (what the liner is built from).
    @ViewBuilder private var landmarkDots: some View {
        #if DEBUG
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
        #endif
    }
}
