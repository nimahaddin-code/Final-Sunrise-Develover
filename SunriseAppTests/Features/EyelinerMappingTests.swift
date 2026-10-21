import XCTest
@testable import SunriseApp

final class EyelinerMappingTests: XCTestCase {
    // A portrait phone showing the landscape front-camera image rotated a quarter turn, cropped to fill the screen.
    private let imageSize = CGSize(width: 1280, height: 720)
    private let viewport = CGSize(width: 390, height: 844)

    /// ARKit's display transform for that setup (normalized image -> normalized view): rotate 90 degrees clockwise,
    /// then scale the upright image (720 x 1280) up to cover the view and centre-crop the sides.
    private var displayTransform: CGAffineTransform {
        let scale = max(viewport.width / imageSize.height, viewport.height / imageSize.width)
        let widthRatio = imageSize.height * scale / viewport.width       // > 1: the image is wider than the view
        let offset = (viewport.width - imageSize.height * scale) / 2 / viewport.width
        // u' = 1 - v, v' = u; then x = u' * widthRatio + offset.
        return CGAffineTransform(a: 0, b: 1, c: -widthRatio, d: 0, tx: widthRatio + offset, ty: 0)
    }

    private func expectedView(_ p: CGPoint) -> CGPoint {
        let scale = max(viewport.width / imageSize.height, viewport.height / imageSize.width)
        let upright = CGPoint(x: imageSize.height - p.y, y: p.x)            // 90 degrees clockwise
        let ox = (viewport.width - imageSize.height * scale) / 2, oy = (viewport.height - imageSize.width * scale) / 2
        return CGPoint(x: upright.x * scale + ox, y: upright.y * scale + oy)
    }

    private func context(mirrored: Bool = false, references: Bool = true) -> FrameContext {
        var context = FrameContext(displayTransform: displayTransform, imageSize: imageSize, viewportSize: viewport)
        guard references else { return context }
        for image in [CGPoint(x: 640, y: 360), CGPoint(x: 700, y: 300), CGPoint(x: 560, y: 420), CGPoint(x: 800, y: 380)] {
            var view = expectedView(image)
            if mirrored { view.x = viewport.width - view.x }
            context.references.append(MappingReference(image: image, view: view))
        }
        return context
    }

    // MARK: Image to view

    func testDisplayTransformMapsImagePixelsToViewPoints() {
        let mapping = ImageToViewMapping.displayTransform(context(), mirrored: false)
        for image in [CGPoint(x: 0, y: 0), CGPoint(x: 1280, y: 720), CGPoint(x: 640, y: 360), CGPoint(x: 900, y: 100)] {
            let mapped = mapping.map(image), expected = expectedView(image)
            XCTAssertEqual(mapped.x, expected.x, accuracy: 1e-6)
            XCTAssertEqual(mapped.y, expected.y, accuracy: 1e-6)
        }
        // The image centre lands on the view centre (aspect-fill crops evenly on both sides).
        let centre = mapping.map(CGPoint(x: 640, y: 360))
        XCTAssertEqual(centre.x, viewport.width / 2, accuracy: 1e-6)
        XCTAssertEqual(centre.y, viewport.height / 2, accuracy: 1e-6)
    }

    func testMirroringFlipsTheViewHorizontally() {
        let plain = ImageToViewMapping.displayTransform(context(), mirrored: false)
        let mirrored = ImageToViewMapping.displayTransform(context(), mirrored: true)
        for image in [CGPoint(x: 100, y: 200), CGPoint(x: 1000, y: 500)] {
            XCTAssertEqual(mirrored.map(image).x, viewport.width - plain.map(image).x, accuracy: 1e-6)
            XCTAssertEqual(mirrored.map(image).y, plain.map(image).y, accuracy: 1e-6)
        }
    }

    func testResolvePrefersTheDisplayTransformWhenTheFaceAgrees() {
        let mapping = ImageToViewMapping.resolve(context())
        XCTAssertEqual(mapping.source, .displayTransform)
        XCTAssertLessThan(mapping.residual(context().references), 1e-6)
    }

    func testResolveSwitchesToTheMirroredTransformWhenTheFaceIsMirrored() {
        let mapping = ImageToViewMapping.resolve(context(mirrored: true))
        XCTAssertEqual(mapping.source, .mirroredDisplayTransform)
        XCTAssertLessThan(mapping.residual(context(mirrored: true).references), 1e-6)
    }

    func testResolveFallsBackToAFitWhenNeitherTransformAgrees() {
        // Screen positions produced by some other affine map (rotated and shifted).
        let truth = CGAffineTransform(a: 0.3, b: -0.5, c: 0.5, d: 0.3, tx: 40, ty: 200)
        var context = context(references: false)
        for image in [CGPoint(x: 600, y: 300), CGPoint(x: 700, y: 360), CGPoint(x: 650, y: 450), CGPoint(x: 720, y: 280)] {
            context.references.append(MappingReference(image: image, view: image.applying(truth)))
        }
        let mapping = ImageToViewMapping.resolve(context)
        XCTAssertEqual(mapping.source, .fitted)
        XCTAssertLessThan(mapping.residual(context.references), 1e-3)
        let probe = CGPoint(x: 660, y: 340)
        XCTAssertEqual(mapping.map(probe).x, probe.applying(truth).x, accuracy: 1e-3)
    }

    func testWithoutReferencesTheDisplayTransformIsUsed() {
        XCTAssertEqual(ImageToViewMapping.resolve(context(references: false)).source, .displayTransform)
    }

    func testFitNeedsThreePointsThatSpanAPlane() {
        XCTAssertNil(ImageToViewMapping.fit([]))
        let collinear = (0..<4).map { MappingReference(image: CGPoint(x: CGFloat($0), y: CGFloat($0)), view: .zero) }
        XCTAssertNil(ImageToViewMapping.fit(collinear))
    }

    // MARK: Detector rotation and landmark space

    func testRotationFollowsTheHeadsUpDirection() {
        XCTAssertEqual(DetectorRotation.forHeadUp(CGPoint(x: 0, y: -1)), .up)
        XCTAssertEqual(DetectorRotation.forHeadUp(CGPoint(x: 0, y: 1)), .down)
        XCTAssertEqual(DetectorRotation.forHeadUp(CGPoint(x: -1, y: 0.2)), .right)
        XCTAssertEqual(DetectorRotation.forHeadUp(CGPoint(x: 1, y: -0.2)), .left)
    }

    func testUprightPointsMapBackToTheRawImage() {
        let raw = CGSize(width: 1280, height: 720)
        // Forward maps (raw -> upright), as the spike's provider defined them.
        func upright(_ p: CGPoint, _ rotation: DetectorRotation) -> CGPoint {
            switch rotation {
            case .up: p
            case .right: CGPoint(x: raw.height - p.y, y: p.x)
            case .left: CGPoint(x: p.y, y: raw.width - p.x)
            case .down: CGPoint(x: raw.width - p.x, y: raw.height - p.y)
            }
        }
        for rotation in DetectorRotation.allCases {
            for p in [CGPoint(x: 10, y: 20), CGPoint(x: 1200, y: 600), CGPoint(x: 640, y: 360)] {
                let back = rotation.rawPoint(fromUpright: upright(p, rotation), raw: raw)
                XCTAssertEqual(back.x, p.x, accuracy: 1e-9, "\(rotation)")
                XCTAssertEqual(back.y, p.y, accuracy: 1e-9, "\(rotation)")
            }
        }
        XCTAssertEqual(DetectorRotation.right.uprightSize(raw: raw), CGSize(width: 720, height: 1280))
    }

    func testLandmarkSpaceIsChosenFromTheEyeAxis() {
        let raw = CGSize(width: 1280, height: 720)
        // A face whose eyes sit left-right along the raw image's y axis (portrait phone, head up = raw -x).
        let rotation = DetectorRotation.right
        let acrossInRaw = CGPoint(x: 0, y: 1)
        // Eyes reported relative to the raw image:
        let rawEyes = (CGPoint(x: 0.5, y: 0.35), CGPoint(x: 0.5, y: 0.65))
        XCTAssertEqual(LandmarkSpace.choose(leftEye: rawEyes.0, rightEye: rawEyes.1, rotation: rotation, raw: raw,
                                            expectedAxis: acrossInRaw, previous: nil), .rawImage)
        // The same eyes reported relative to the rotated (upright) image: along its x axis.
        let uprightEyes = (CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0.65, y: 0.5))
        XCTAssertEqual(LandmarkSpace.choose(leftEye: uprightEyes.0, rightEye: uprightEyes.1, rotation: rotation,
                                            raw: raw, expectedAxis: acrossInRaw, previous: nil), .rotatedImage)
        // A clear reading is not overturned by a marginal one.
        XCTAssertEqual(LandmarkSpace.choose(leftEye: rawEyes.0, rightEye: rawEyes.1, rotation: rotation, raw: raw,
                                            expectedAxis: CGPoint(x: 0.2, y: 1), previous: .rawImage), .rawImage)
    }

    func testNormalizedLandmarksBecomeRawPixels() {
        let raw = CGSize(width: 1280, height: 720)
        XCTAssertEqual(LandmarkSpace.rawPixel(CGPoint(x: 0.25, y: 0.5), space: .rawImage, rotation: .right, raw: raw),
                       CGPoint(x: 320, y: 360))
        // Upright image is 720 x 1280: (0.25, 0.5) is (180, 640); .right maps it back to (640, 720 - 180).
        XCTAssertEqual(LandmarkSpace.rawPixel(CGPoint(x: 0.25, y: 0.5), space: .rotatedImage, rotation: .right, raw: raw),
                       CGPoint(x: 640, y: 540))
    }

    // MARK: Drawing

    private func overlayFrame(receivedAt: CFTimeInterval = 100) throws -> LinerOverlayFrame {
        let tracker = LinerTracker()
        var eyes: [RenderedEye] = []
        for i in 0..<5 {
            eyes = tracker.render(SyntheticEye.frame(t: Double(i) / 30), spec: LinerSpec(style: EyelinerPlanner.variant(for: .almond)))
        }
        return LinerOverlayFrame(eyes: eyes, mapping: ImageToViewMapping.displayTransform(context(), mirrored: false),
                                 receivedAt: receivedAt)
    }

    func testFillsFollowShadeIntensityAndAge() throws {
        let frame = try overlayFrame()
        let black = MakeupPalette.black
        let full = LinerOverlayRenderer.fills(frame, shade: black, intensity: 1, now: 100.1)
        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(full[0].alpha, MakeupTextureRenderer.drawnOpacity(black), accuracy: 1e-9)
        let half = LinerOverlayRenderer.fills(frame, shade: black, intensity: 0.5, now: 100.1)
        XCTAssertEqual(half[0].alpha, full[0].alpha / 2, accuracy: 1e-9)
        XCTAssertTrue(LinerOverlayRenderer.fills(frame, shade: black, intensity: 0, now: 100.1).isEmpty)
        XCTAssertTrue(LinerOverlayRenderer.fills(frame, shade: black, intensity: 1, now: 100 + LinerOverlayRenderer.maxAge + 0.1).isEmpty,
                      "A stale frame (face lost) is not drawn")
    }

    func testFillsLandOnTheMappedEyes() throws {
        let frame = try overlayFrame()
        let fills = LinerOverlayRenderer.fills(frame, shade: MakeupPalette.black, intensity: 1, now: 100.1)
        let eyeFrame = SyntheticEye.frame(t: 0)
        for (fill, eye) in zip(fills, [eyeFrame.subjectLeft!, eyeFrame.subjectRight!]) {
            let corner = frame.mapping.map(eye.outerCorner)
            let bounds = fill.path.boundingBox.insetBy(dx: -30, dy: -30)
            XCTAssertTrue(bounds.contains(corner), "The liner is drawn around the eye it belongs to")
        }
    }

    func testPhotoCompositionKeepsTheSnapshotAndAddsTheLiner() throws {
        let frame = try overlayFrame(receivedAt: CACurrentMediaTime())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let blank = UIGraphicsImageRenderer(size: viewport, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: viewport))
        }
        let composed = LinerOverlayRenderer.compose(blank, overlay: frame, shade: MakeupPalette.black, intensity: 1)
        XCTAssertEqual(composed.size, blank.size)
        XCTAssertNotEqual(composed.pngData(), blank.pngData(), "The liner is in the photo")
        let none = LinerOverlayRenderer.compose(blank, overlay: frame, shade: MakeupPalette.black, intensity: 0)
        XCTAssertEqual(none.pngData(), blank.pngData())
    }
}
