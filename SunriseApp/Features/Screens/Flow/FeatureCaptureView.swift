import ARKit
import SwiftUI
import UIKit

/// "Before photo": the camera fills the page with a dashed oval for the whole face; back, the style's name and the screen
/// light sit in the top safe area, the hint and a round shutter at the bottom, then Retake / Next. `.desired` draws the
/// look chosen on Try On (the picture the result is compared with); `.result` is the plain camera after the tutorial.
/// Both photos are taken in the same fixed position (`CapturePoseCheck`): an outline follows the face in 3D, a hint says what
/// to fix, and once the face is square to the phone, filling and centred in the oval with the eyes on the camera, the oval
/// turns green and the phone taps; the person then takes the photo (the shutter works only then).
/// Without a usable camera (Simulator, no TrueDepth, permission denied) it can continue without a photo, so the flow
/// still runs end to end.
struct FeatureCaptureView: View {
    let stage: CaptureStage
    let handoff: TutorialHandoff
    @ObservedObject var store: MakeupFlowStore
    let onBack: () -> Void
    let onNext: () -> Void
    @StateObject private var home: TryOnHomeModel
    @StateObject private var light = ScreenLight()
    @State private var captured: UIImage?
    /// -Nimah: the face measured at the shutter, for the blush feedback.
    @State private var scanned: FaceScan?
    @State private var shooting = false
    @State private var diagnostics: CaptureDiagnostics?
    @State private var bareImage: UIImage?
    @State private var visible = false
    @StateObject private var pose = CapturePoseTracker()
    /// Where the eyes were at the shutter, for lining the result up with the desired photo.
    @State private var shotEyes: EyePair?
    @State private var shotPose: CapturePoseReading?
    @Environment(\.scenePhase) private var scenePhase

    init(stage: CaptureStage, handoff: TutorialHandoff, plan: MakeupPlan, assessment: FaceShapeAssessment,
         checker: any FaceTrackingAvailabilityChecking, store: MakeupFlowStore,
         onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.stage = stage
        self.handoff = handoff
        self.store = store
        self.onBack = onBack
        self.onNext = onNext
        _home = StateObject(wrappedValue: TryOnHomeModel(tool: handoff.tool, plan: plan, assessment: assessment, checker: checker))
    }

    var body: some View {
        CaptureCameraCard(home: home, light: light, captured: captured, configuration: cameraConfiguration,
                          active: visible && scenePhase == .active)
            .ignoresSafeArea()
            .overlay {
                if captured == nil {
                    FaceFollowOutline(reading: pose.reading, aligned: pose.aligned)
                    FaceOvalGuide(aligned: pose.aligned)
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: AppSpacing.small) {
                    topBar
                    // The hint sits at the top, near the camera, where the eyes already are.
                    if captured == nil { hint }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 28) {
                    CaptureControls(camera: home.camera, brow: home.brow, captured: $captured, ready: pose.aligned,
                                    onShoot: shoot, onNext: next)
                        .disabled(shooting)
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.bottom, AppSpacing.medium)
            }
            .background { (light.isOn ? AppColors.ringLight : Color.black).ignoresSafeArea() }
            .environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.25), value: light.isOn)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
            .sensoryFeedback(.success, trigger: captured != nil)
            .sensoryFeedback(trigger: pose.aligned) { _, inPosition in inPosition ? .impact(weight: .medium) : nil }
            .animation(.easeInOut(duration: 0.2), value: pose.aligned)

            // Retake: back to the live camera.
            .onChange(of: captured == nil) { _, retake in
                if retake { scanned = nil; diagnostics = nil; bareImage = nil; shotEyes = nil; if visible { activate() } }
            }
            .onAppear {
                visible = true; activate(); light.resume()
                pose.reference = stage == .result ? store.poses[.desired] : nil
                pose.start { [weak camera = home.camera] in camera?.view?.bounds.size }
            }
            .onDisappear { visible = false; home.deactivate(); light.turnOff(); pose.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && visible { activate(); light.resume() } else { home.deactivate(); light.suspend() }
            }
    }

    /// Back, the style's name and the screen light.
    private var topBar: some View {
        HStack {
            Button {
                home.deactivate()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            StylePill(handoff: handoff, onGlass: true)
            Spacer()
            ScreenLightButton(light: light, pulse: 0, plainGlass: true)
        }
        .padding(AppSpacing.small)
    }

    private var hint: some View {
        Label(pose.hint?.text ?? "Fit your whole face inside the line",
              systemImage: pose.aligned ? "checkmark.circle.fill" : pose.hint == .lookAtCamera ? "eye" : "face.smiling")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.snow)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background((pose.aligned ? CaptureColors.aligned : Color.black.opacity(0.35)), in: Capsule())
            .contentTransition(.opacity)
    }

    private func activate() {
        guard captured == nil else { return }
        home.activate()
        if stage == .desired { home.apply(handoff) }
    }

    /// -Nimah: blush also measures its target area: on the desired look with the virtual blush, on the result with the
    /// engine running but no pigment drawn (the photo stays the plain camera).
    private var cameraConfiguration: EyebrowConfiguration {
        var configuration = home.liveConfiguration
        guard handoff.tool == .blush, let style = handoff.blushStyle, style.isReferenceLook else { return configuration }
        configuration.blushStyle = style
        configuration.measuresBlushTarget = true
        if stage == .result {
            configuration.layered = false
            configuration.region = .blush
            configuration.showMakeupPreview = true
            configuration.previewAfter = true
            configuration.pigmentHalf = PigmentHalf.none
        }
        return configuration
    }

    /// The camera picture as shown. The makeup engine's own layer is read back (`ARSCNView.snapshot()` has only the
    /// camera under it); the eyeliner is a SwiftUI overlay, so it is drawn into the picture here.
    private func shoot() {
        guard let view = home.camera.view, !shooting else { return }
        shooting = true
        shotEyes = pose.reading?.eyes
        shotPose = pose.reading
        Task { @MainActor in
            defer { shooting = false }
            var pixels: ScreenPixels?
            var report = CaptureDiagnostics()
            // The bare camera of this moment (SceneKit draws nothing for the capture): the Before's fallback when the try-on photo is missing.
            // `ARSCNView.snapshot()` comes at scale 1 (one point per pixel); the eyeliner is drawn in view points, so
            // at that scale it landed a third of the way, top left. Give it the view's size in points.
            let bare = Self.inPoints(view.snapshot(), of: view.bounds.size)
            // The picture on screen is the engine's layer when it is on: on the desired look it has the virtual makeup.
            let makeup = view as? BeautyBlushARView
            report.engine = makeup?.beauty != nil
            report.layerShown = makeup.map { !$0.beautyLayer.isHidden } ?? false
            report.engineOn = makeup?.beauty?.isDrawing ?? false
            report.framesBefore = makeup?.beauty?.presentedFrames ?? 0
            if let makeup, let engine = makeup.beauty, report.layerShown {
                let started = Date()
                pixels = await engine.readScreen()
                if pixels == nil { report.readTries += 1; pixels = await engine.readScreen() }
                report.readTries += 1
                report.readMilliseconds = Int(Date().timeIntervalSince(started) * 1000)
                report.read = pixels != nil ? .read : .timedOut
            }
            var image = pixels?.image(scale: view.window?.screen.scale ?? 3) ?? bare
            if stage == .desired && handoff.tool == .eyeliner {
                image = home.liner.composed(image)
                // The eyeliner is drawn by SwiftUI, not the engine: its target is read from the composed picture.
                pixels = ScreenPixels(image: image)
            }
            let outline = handoff.tool == .blush ? home.camera.blushGuide.snapshot : nil
            scanned = FaceScan.measure(view: view, outline: outline, rendered: pixels)
            report.outline = outline != nil
            report.face = scanned != nil
            diagnostics = report
            if stage == .desired { bareImage = bare }
            captured = image
            // The still replaces the camera until Retake.
            home.deactivate()
        }
    }

    /// The same pixels, with the scale that makes the picture `size` points wide.
    private static func inPoints(_ image: UIImage, of size: CGSize) -> UIImage {
        guard let cg = image.cgImage, size.width > 0, abs(image.size.width - size.width) > 0.5 else { return image }
        return UIImage(cgImage: cg, scale: CGFloat(cg.width) / size.width, orientation: image.imageOrientation)
    }

    private func next() {
        store.store(captured, for: stage)
        store.store(scanned, for: stage)
        store.diagnostics[stage] = diagnostics
        if stage == .desired { store.bare = bareImage }
        store.eyes[stage] = shotEyes
        store.poses[stage] = shotPose
        if stage == .result {
            // The face mesh (about 200 matching points, also takes out small turn and nod), else the two eyes.
            let byMesh = zip3(captured, shotPose, store.poses[.desired]).flatMap { image, result, desired in
                FaceHomography.fit(result: result, desired: desired)?.warp(image)
            }
            store.alignedResult = byMesh
                ?? zip3(captured, shotEyes, store.eyes[.desired]).flatMap { EyePair.align($0, from: $1, to: $2) }
        }
        home.deactivate()
        onNext()
    }
}

/// Shutter; Retake and Next once taken; "Continue without photo" when there is no usable camera.
private struct CaptureControls: View {
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    @Binding var captured: UIImage?
    /// The face is in position: only then does the shutter work.
    let ready: Bool
    let onShoot: () -> Void
    let onNext: () -> Void

    private var noCamera: Bool {
        if case .unsupported = brow.availability { return true }
        return camera.denied || camera.failure != nil
    }

    var body: some View {
        if captured != nil {
            HStack(spacing: AppSpacing.medium) {
                Button { captured = nil } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retake photo")
                CaptureCapsuleButton(title: "Next", action: onNext)
            }
        } else if !noCamera {
            Button(action: onShoot) {
                Circle()
                    .fill(AppColors.snow)
                    .padding(6)
                    .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: 4))
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .opacity(ready ? 1 : 0.4)
            .disabled(!camera.authorized || !ready)
            .accessibilityLabel("Take picture")
            .accessibilityHint(ready ? Text("") : Text("Fit your face in the oval first"))
        } else {
            // Simulator or no camera: keep the flow going without a photo.
            CaptureCapsuleButton(title: "Continue without photo", action: onNext)
        }
    }
}

/// Full-width dark glass capsule, like Try On's Continue.
private struct CaptureCapsuleButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.snow)
                .frame(maxWidth: .infinity, minHeight: 56)
                .glassEffect(.regular.tint(AppColors.buttonInk).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The dashed oval the whole face goes inside; green once the face is in position.
private struct FaceOvalGuide: View {
    let aligned: Bool

    var body: some View {
        GeometryReader { proxy in
            let oval = CapturePoseCheck.oval(in: proxy.size)
            Ellipse()
                .stroke(aligned ? CaptureColors.aligned : AppColors.snow,
                        style: StrokeStyle(lineWidth: aligned ? 4 : 2.5, lineCap: .round, dash: [10, 8]))
                .frame(width: oval.width, height: oval.height)
                .position(x: oval.midX, y: oval.midY)
                .shadow(color: .black.opacity(0.25), radius: 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The full-page camera, or the still once taken.
private struct CaptureCameraCard: View {
    @ObservedObject var home: TryOnHomeModel
    @ObservedObject var camera: FaceCameraState
    @ObservedObject var brow: EyebrowViewModel
    @ObservedObject var light: ScreenLight
    let captured: UIImage?
    let configuration: EyebrowConfiguration
    let active: Bool
    @Environment(\.openURL) private var openURL

    init(home: TryOnHomeModel, light: ScreenLight, captured: UIImage?, configuration: EyebrowConfiguration, active: Bool) {
        self.home = home
        camera = home.camera
        brow = home.brow
        self.light = light
        self.captured = captured
        self.configuration = configuration
        self.active = active
    }

    var body: some View {
        ZStack {
            if !light.isOn { Color.black }
            if let captured {
                Color.clear.overlay { Image(uiImage: captured).resizable().scaledToFill() }.clipped()
            } else {
                content
            }
        }
        // The screen light: the picture's edge melts into the white screen, which is what lights the face.
        .mask {
            Rectangle()
                .padding(light.isOn ? 26 : 0)
                .blur(radius: light.isOn ? 26 : 0)
        }
    }

    @ViewBuilder private var content: some View {
        switch brow.availability {
        case .notChecked:
            ProgressView().tint(AppColors.snow)
        case .unsupported:
            message(symbol: "faceid", title: "Camera unavailable", text: "The photo needs an iPhone with a TrueDepth front camera.")
        case .supported:
            if camera.denied {
                VStack(spacing: AppSpacing.medium) {
                    message(symbol: "camera", title: "I need your camera to be your mirror.", text: "Nothing is saved or uploaded.")
                    Button("Turn on camera") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent).tint(AppColors.flamingo)
                }
            } else if camera.failure != nil {
                message(symbol: "exclamationmark.triangle", title: "Camera stopped", text: "Face tracking stopped unexpectedly.")
            } else if camera.authorized {
                ZStack {
                    LiveGuideView(camera: camera, referenceID: "eyebrows", active: home.active && active,
                                  eyebrowConfiguration: configuration, onFrame: { [relay = home.relay] frame, face in
                                      relay.deliver(frame, face)
                                  })
                    LinerOverlayView(model: home.liner, isVisible: true)
                }
            } else {
                ProgressView().tint(AppColors.snow)
            }
        }
    }

    private func message(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.small) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).font(AppTypography.heading)
            Text(text).font(AppTypography.body).multilineTextAlignment(.center)
        }
        .foregroundStyle(AppColors.snow)
        .padding(AppSpacing.large)
    }
}

// MARK: Face position

/// Where the face is for the capture screen, read from one ARKit frame: an outline that follows the face in 3D, how far the
/// head is turned or tilted, and where the eyes are. View points.
struct CapturePoseReading: Equatable {
    /// An ellipse round the face, on the face itself, projected to the screen: it moves, grows and turns with the head.
    var outline: [CGPoint]
    /// Degrees between the face's forward direction and the camera (turned, nodding, or both).
    var offAxisDegrees: Double
    /// Degrees the eye line leans on the screen.
    var rollDegrees: Double
    /// From the face centre towards the nose tip, on the screen: which way the head points.
    var noseOffset: CGVector
    /// Degrees between where the eyes look (`ARFaceAnchor.lookAtPoint`) and the camera: 0 when looking into the lens.
    var gazeDegrees: Double = 0
    var eyes: EyePair
    /// The head's turn relative to the camera, and its distance in metres: compared between the two photos.
    var orientation = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
    var distance: Float = 0.3
    /// The face's centre on the screen.
    var centre: CGPoint = .zero
    /// Every `meshStride`-th vertex of ARKit's face mesh on the screen (the mesh has the same vertices on every face and
    /// frame, so index i is the same spot of skin in both photos), and whether it faces the camera. Lines the photos up.
    var meshPoints: [CGPoint] = []
    var meshFront: [Bool] = []

    var bounds: CGRect {
        let xs = outline.map(\.x), ys = outline.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// The one thing to fix before the photo, the biggest first. Directions are as seen in the mirrored picture.
enum CaptureHint: Equatable {
    case closer, farther, left, right, up, down, turnLeft, turnRight, chinUp, chinDown, straighten, lookAtCamera, ready

    var text: LocalizedStringKey {
        switch self {
        case .closer: "Move a little closer"
        case .farther: "Move back a little"
        case .left: "Move a little to the left"
        case .right: "Move a little to the right"
        case .up: "Move up a little"
        case .down: "Move down a little"
        case .turnLeft: "Turn your face a little to the left"
        case .turnRight: "Turn your face a little to the right"
        case .chinUp: "Lift your chin a little"
        case .chinDown: "Lower your chin a little"
        case .straighten: "Keep your head straight"
        case .lookAtCamera: "Look at the camera, at the top of the screen"
        case .ready: "Perfect, take the photo"
        }
    }
}

/// The fixed position both photos must be taken in (the same for the desired look and the result): facing the camera,
/// the face filling the oval, centred in it, the eyes on the camera. Within it the oval turns green, the phone taps and the
/// shutter works (the person takes the photo).
enum CapturePoseCheck {
    /// Off-axis and roll limits in degrees; size as outline width / oval width; centre as a share of the oval's size.
    /// Once inside, the looser `clear` values keep it from flickering on the edge. Untuned guesses: check on a device.
    // Tight: two photos each allowed 6° off could still differ by 12°, which the slider showed.
    // Easy enough to reach and hold: what is left between the two photos is taken out afterwards by redrawing the result
    // through the face mesh (`FaceHomography`), so the live limits no longer need to be pixel-strict.
    static let offAxis = (show: 5.0, clear: 6.5)
    static let roll = (show: 5.0, clear: 6.5)
    static let size = (show: 0.08, clear: 0.1)
    static let centreX = (show: 0.06, clear: 0.075)
    static let centreY = (show: 0.05, clear: 0.065)
    static let gaze = (show: 10.0, clear: 12.0)
    /// The result photo against the desired photo's own pose: the head's turn in degrees (all axes), the distance as a
    /// share, and the face centre as a share of the oval. Two photos inside the fixed limits could still differ by twice
    /// those limits; these keep the pair within a few degrees and millimetres of each other.
    static let matchTurn = (show: 4.0, clear: 5.0)
    static let matchDistance = (show: 0.06, clear: 0.075)
    static let matchCentre = (show: 0.05, clear: 0.065)
    /// Readings in a row that must pass before the oval turns green (about 0.2 s): one lucky noisy frame is not enough.
    static let steadyReadings = 3

    /// Whether `reading` is in the position, and else what to fix (distance, centre, turn, tilt, then where the eyes look).
    static func evaluate(_ reading: CapturePoseReading, oval: CGRect, wasAligned: Bool,
                         reference: CapturePoseReading? = nil) -> (aligned: Bool, hint: CaptureHint) {
        func limit(_ pair: (show: Double, clear: Double)) -> Double { wasAligned ? pair.clear : pair.show }
        let box = reading.bounds
        guard !box.isNull, oval.width > 0, oval.height > 0 else { return (false, .closer) }
        let ratio = box.width / oval.width
        if ratio < 1 - limit(size) { return (false, .closer) }
        if ratio > 1 + limit(size) { return (false, .farther) }
        let dx = (box.midX - oval.midX) / oval.width, dy = (box.midY - oval.midY) / oval.height
        if abs(dx) > limit(centreX) { return (false, dx > 0 ? .left : .right) }
        if abs(dy) > limit(centreY) { return (false, dy > 0 ? .up : .down) }
        if reading.offAxisDegrees > limit(offAxis) {
            let nose = reading.noseOffset
            if abs(nose.dx) >= abs(nose.dy) { return (false, nose.dx < 0 ? .turnRight : .turnLeft) }
            return (false, nose.dy > 0 ? .chinUp : .chinDown)
        }
        if abs(reading.rollDegrees) > limit(roll) { return (false, .straighten) }
        if reading.gazeDegrees > limit(gaze) { return (false, .lookAtCamera) }
        if let reference { return match(reading, to: reference, oval: oval, wasAligned: wasAligned) }
        return (true, .ready)
    }

    /// The result photo: the same distance, place and head turn as the desired photo was taken with.
    static func match(_ reading: CapturePoseReading, to reference: CapturePoseReading, oval: CGRect,
                      wasAligned: Bool) -> (aligned: Bool, hint: CaptureHint) {
        func limit(_ pair: (show: Double, clear: Double)) -> Double { wasAligned ? pair.clear : pair.show }
        let distance = Double(reading.distance / max(reference.distance, 0.01)) - 1
        if abs(distance) > limit(matchDistance) { return (false, distance > 0 ? .closer : .farther) }
        let dx = (reading.centre.x - reference.centre.x) / oval.width, dy = (reading.centre.y - reference.centre.y) / oval.height
        if abs(dx) > limit(matchCentre) { return (false, dx > 0 ? .left : .right) }
        if abs(dy) > limit(matchCentre) { return (false, dy > 0 ? .up : .down) }
        let turn = Double((reference.orientation.inverse * reading.orientation).angle) * 180 / .pi
        if min(turn, 360 - turn) > limit(matchTurn) {
            let nose = CGVector(dx: reading.noseOffset.dx - reference.noseOffset.dx, dy: reading.noseOffset.dy - reference.noseOffset.dy)
            let rollDelta = reading.rollDegrees - reference.rollDegrees
            if abs(rollDelta) > 1.5 && abs(rollDelta) * 4 > max(abs(nose.dx), abs(nose.dy)) { return (false, .straighten) }
            if abs(nose.dx) >= abs(nose.dy) { return (false, nose.dx < 0 ? .turnRight : .turnLeft) }
            return (false, nose.dy > 0 ? .chinUp : .chinDown)
        }
        return (true, .ready)
    }

    /// The oval the face goes in, for a full-screen view of `size` (also drawn by `FaceOvalGuide`).
    static func oval(in size: CGSize) -> CGRect {
        // 0.78 of the screen width: 0.68 and 0.74 were tried and felt too far to hold the phone steady.
        let width = size.width * 0.78
        let height = min(width * 1.42, size.height * 0.56)
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.42 - height / 2, width: width, height: height)
    }

    /// The outline's size on the face, in metres (half width, half height, centre height, depth): roughly the whole face
    /// with the hairline, so a face that fills the oval also fills the outline. Tune with the oval on a device.
    static let face = (halfWidth: Float(0.082), halfHeight: Float(0.118), centreY: Float(0.008), depth: Float(0.02))
    /// Every 6th mesh vertex (about 200 of ARKit's 1220) for lining the photos up.
    static let meshStride = 6

    /// Reads the face of `frame` for a portrait view of `size`; nil without a tracked face.
    static func read(_ frame: ARFrame, viewSize size: CGSize) -> CapturePoseReading? {
        guard size.width > 0, let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, anchor.isTracked else { return nil }
        let raw = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage))
        let display = frame.displayTransform(for: .portrait, viewportSize: size)
        // Same projection as the makeup engine (raw camera image, then the display transform), so the outline sits on the
        // picture the way the makeup does.
        func project(_ local: SIMD3<Float>) -> CGPoint {
            let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            let p = frame.camera.projectPoint(SIMD3(world.x, world.y, world.z), orientation: .landscapeRight, viewportSize: raw)
            let n = CGPoint(x: p.x / raw.width, y: p.y / raw.height).applying(display)
            return CGPoint(x: n.x * size.width, y: n.y * size.height)
        }
        let outline = (0..<48).map { i -> CGPoint in
            let t = Float(i) / 48 * 2 * .pi
            return project(SIMD3(face.halfWidth * cos(t), face.centreY + face.halfHeight * sin(t), face.depth))
        }
        // The face's forward axis in camera space: straight at the camera when the face is square to the phone.
        let relative = simd_mul(frame.camera.transform.inverse, anchor.transform)
        let forward = simd_normalize(SIMD3(relative.columns.2.x, relative.columns.2.y, relative.columns.2.z))
        let offAxis = Double(acos(min(1, max(-1, forward.z)))) * 180 / .pi
        let centre = project(SIMD3(0, 0, 0)), nose = project(SIMD3(0, 0, 0.1))
        func eye(_ transform: simd_float4x4) -> CGPoint {
            project(SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z))
        }
        let left = eye(anchor.leftEyeTransform), right = eye(anchor.rightEyeTransform)
        let pair = left.x <= right.x ? EyePair(left: left, right: right) : EyePair(left: right, right: left)
        let roll = Double(atan2(pair.right.y - pair.left.y, pair.right.x - pair.left.x)) * 180 / .pi
        // Gaze, in face space: from between the eyes to where they look, against from there to the camera.
        let between = (SIMD3(anchor.leftEyeTransform.columns.3.x, anchor.leftEyeTransform.columns.3.y, anchor.leftEyeTransform.columns.3.z)
            + SIMD3(anchor.rightEyeTransform.columns.3.x, anchor.rightEyeTransform.columns.3.y, anchor.rightEyeTransform.columns.3.z)) / 2
        let camera4 = anchor.transform.inverse * frame.camera.transform.columns.3
        let toCamera = simd_normalize(SIMD3(camera4.x, camera4.y, camera4.z) - between)
        let look = simd_normalize(anchor.lookAtPoint - between)
        let gaze = Double(acos(min(1, max(-1, simd_dot(look, toCamera))))) * 180 / .pi
        let translation = SIMD3(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z)
        let vertices = anchor.geometry.vertices
        let sampled = stride(from: 0, to: vertices.count, by: meshStride).map { vertices[$0] }
        return CapturePoseReading(outline: outline, offAxisDegrees: offAxis, rollDegrees: roll,
                                  noseOffset: CGVector(dx: nose.x - centre.x, dy: nose.y - centre.y), gazeDegrees: gaze, eyes: pair,
                                  orientation: simd_quatf(relative), distance: simd_length(translation), centre: centre,
                                  meshPoints: sampled.map(project), meshFront: sampled.map { $0.z > 0.005 })
    }
}

/// Reads the shared ARKit session about 15 times a second while the capture screen is live.
@MainActor final class CapturePoseTracker: ObservableObject {
    @Published private(set) var reading: CapturePoseReading?
    @Published private(set) var aligned = false
    @Published private(set) var hint: CaptureHint?
    /// The desired photo's pose, when taking the result photo: the result must match it.
    var reference: CapturePoseReading?
    private var loop: Task<Void, Never>?
    private var passes = 0

    func start(viewSize: @escaping @MainActor () -> CGSize?) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick(viewSize())
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        reading = nil; aligned = false; hint = nil; passes = 0
    }

    private func tick(_ size: CGSize?) {
        guard let size, let frame = ARFaceTrackingManager.shared.session.currentFrame,
              ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.5,
              let next = CapturePoseCheck.read(frame, viewSize: size) else {
            reading = nil; aligned = false; hint = nil; passes = 0
            return
        }
        let result = CapturePoseCheck.evaluate(next, oval: CapturePoseCheck.oval(in: size), wasAligned: aligned, reference: reference)
        reading = next
        passes = result.aligned ? passes + 1 : 0
        let steady = aligned ? result.aligned : passes >= CapturePoseCheck.steadyReadings
        if aligned != steady { aligned = steady }
        // While the position is still settling, the last hint stays up rather than flashing "Perfect".
        let shownHint = result.aligned && !steady ? (hint ?? result.hint) : result.hint
        if hint != shownHint { hint = shownHint }
    }
}

/// The outline that follows the face, drawn over the camera so it can be laid onto the oval.
private struct FaceFollowOutline: View {
    let reading: CapturePoseReading?
    let aligned: Bool

    var body: some View {
        Canvas { context, _ in
            guard let points = reading?.outline, let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
            context.stroke(path, with: .color((aligned ? CaptureColors.aligned : AppColors.snow).opacity(0.75)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum CaptureColors {
    /// The oval once the face is in position.
    static let aligned = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
}

private func zip3<A, B, C>(_ a: A?, _ b: B?, _ c: C?) -> (A, B, C)? {
    guard let a, let b, let c else { return nil }
    return (a, b, c)
}
