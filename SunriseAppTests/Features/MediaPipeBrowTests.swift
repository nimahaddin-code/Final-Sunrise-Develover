// MediaPipe brow path: design, brow-local geometry, smoothing, pose and the Metal bake/composite on synthetic data.
// These check the maths and shaders, not on-face quality (that needs a device).
import XCTest
import CoreML
import Metal
import simd
@testable import SunriseApp

final class MediaPipeBrowTests: XCTestCase {
    /// Two arched brows in image pixels (y down), heads near the nose at x = 500 +/- 80.
    private func observation(leftScale: Float = 1, shift: SIMD2<Float> = .zero, jitter: Float = 0, timestamp: TimeInterval = 0,
                             mirrored: Bool = false) -> BrowObservation {
        func contour(_ side: Float, scale: Float) -> BrowContour {
            var upper: [SIMD2<Float>] = [], lower: [SIMD2<Float>] = []
            for i in 0..<5 {
                let t = Float(i) / 4
                let x = 500 + side * (80 + 100 * t * scale), y = 300 - 5 * t - 8 * sin(.pi * t)
                let wobble = jitter * (i % 2 == 0 ? 1 : -1)
                upper.append(SIMD2(x, y - 6 + wobble) + shift)
                lower.append(SIMD2(x, y + 6 - wobble) + shift)
            }
            if mirrored {
                upper = upper.map { SIMD2(1000 - $0.x, $0.y) }; lower = lower.map { SIMD2(1000 - $0.x, $0.y) }
            }
            return BrowContour(upper: upper, lower: lower)
        }
        func eye(_ side: Float) -> BrowEyeMarks {
            BrowEyeMarks(inner: SIMD2(500 + side * 60, 340) + shift, outer: SIMD2(500 + side * 170, 335) + shift,
                         iris: SIMD2(500 + side * 115, 338) + shift, ala: SIMD2(500 + side * 40, 470) + shift)
        }
        return BrowObservation(imageSize: CGSize(width: 1000, height: 800), timestamp: timestamp,
                               brows: [.subjectRight: contour(-1, scale: 1), .subjectLeft: contour(1, scale: leftScale)],
                               eyes: [.subjectRight: eye(-1), .subjectLeft: eye(1)], noseBridge: SIMD2(500, 330) + shift, pose: .frontal)
    }

    @MainActor func testBrowShapeListIsTheNineNewShapesInPickerOrder() throws {
        let rules = try XCTUnwrap(MakeupRuleDatabase.shared)
        XCTAssertEqual(rules.eyebrow_presets.map(\.id), EyebrowStyle.allCases.compactMap(MakeupRuleDatabase.browID))
        XCTAssertEqual(EyebrowStyle.allCases.count, 9)
        let model = EyebrowViewModel(checker: MockFaceTrackingChecker(), assessment: FaceShapeAssessment.standardLook)
        XCTAssertEqual(model.browStyleChoices, EyebrowStyle.allCases)
        let designs = EyebrowStyle.allCases.compactMap(BrowDesign.make)
        XCTAssertEqual(designs.count, 9, "Every shape has a preset")
        XCTAssertEqual(Set(designs.map(\.points)).count, 9, "No two shapes draw the same brow")
    }

    func testDesignKeepsObservedHeadAndMovesArchByStyle() throws {
        for design in EyebrowStyle.allCases.compactMap(BrowDesign.make) {
            XCTAssertEqual(design.points.count, BrowDesign.sampleCount)
            XCTAssertEqual(design.points[0].x, 0, accuracy: 0.0001)
            XCTAssertEqual(design.points[0].y, 0, accuracy: 0.0001, "The design starts on the observed brow head")
            XCTAssertEqual(design.points[40].x, 1, accuracy: 0.0001)
            XCTAssertLessThan(design.points[0].z, design.points[26].z, "Head is tapered")
            XCTAssertLessThan(design.points[40].z, design.points[26].z * 0.2, "Tail is tapered")
        }
        func design(_ style: EyebrowStyle) throws -> BrowDesign { try XCTUnwrap(BrowDesign.make(style: style)) }
        func peak(_ style: EyebrowStyle) throws -> Float { try design(style).points.map(\.y).max() ?? 0 }
        func body(_ style: EyebrowStyle) throws -> Float { try design(style).points.map(\.z).max() ?? 0 }
        XCTAssertGreaterThan(try peak(.fullArch), try peak(.boldArch))
        XCTAssertGreaterThan(try peak(.boldArch), try peak(.softNatural))
        XCTAssertLessThan(try design(.flatStraight).points.map(\.y).min() ?? 0, -0.01, "Straight shapes flatten the arch")
        XCTAssertLessThan(try design(.boldStraight).points.map(\.y).min() ?? 0, -0.005)
        XCTAssertGreaterThan(try body(.boldArch), try body(.slimArch) * 1.5, "Bold shapes are thicker than slim ones")
        XCTAssertGreaterThan(try body(.boldStraight), try body(.slimStraight) * 1.5)
        let peakT = { (style: EyebrowStyle) throws -> Float in
            let points = try design(style).points
            return points.max { $0.y < $1.y }?.x ?? 0
        }
        XCTAssertGreaterThan(try peakT(.peakedAngle), try peakT(.curvedArch) + 0.1, "Peaked angle peaks further out")
    }

    func testGeometryFollowsObservedBrowAndAcrossAxisPointsToForehead() throws {
        for mirrored in [false, true] {
            let brow = try XCTUnwrap(observation(mirrored: mirrored).brows[.subjectRight])
            let g = try XCTUnwrap(BrowGeometry(contour: brow))
            let head = (brow.upper[0] + brow.lower[0]) / 2, tail = (brow.upper[4] + brow.lower[4]) / 2
            XCTAssertLessThan(simd_distance(g.point(u: 0, w: 0), head), 0.01)
            XCTAssertLessThan(simd_distance(g.point(u: 1, w: 0), tail), 0.01)
            XCTAssertLessThan(g.point(u: 0.5, w: 0.1).y, g.point(u: 0.5, w: 0).y - 5, "Positive offsets go up the forehead")
            XCTAssertEqual(g.observedHalf(0.5), 6 / g.width, accuracy: 0.01)
        }
    }

    func testStripCoversBothBrowsAndFadesATurnedAwayBrow() throws {
        let level = try XCTUnwrap(BeautyBlushEngine.browStripFixture(observation()))
        XCTAssertEqual(level.count, BeautyBlushEngine.browVertexCount * 2)
        XCTAssertTrue(level.allSatisfy { $0.brow.w > 0.99 })
        XCTAssertTrue(level.allSatisfy { abs($0.position.x) < 1 && abs($0.position.y) < 1 })
        let turned = try XCTUnwrap(BeautyBlushEngine.browStripFixture(observation(leftScale: 0.4)))
        XCTAssertGreaterThan(turned[0].brow.w, 0.99)
        XCTAssertLessThan(turned[BeautyBlushEngine.browVertexCount].brow.w, 0.2)
    }

    func testHeadPoseReadsYawPitchAndRollFromTransformationMatrix() throws {
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -40, 0, 0, 0, 1]
        let still = try XCTUnwrap(BrowHeadPose(rowMajor: identity))
        XCTAssertEqual(still.yaw, 0, accuracy: 0.01); XCTAssertEqual(still.pitch, 0, accuracy: 0.01); XCTAssertEqual(still.roll, 0, accuracy: 0.01)
        let a: Float = 20 * .pi / 180
        let turned = try XCTUnwrap(BrowHeadPose(rowMajor: [cos(a), 0, sin(a), 0, 0, 1, 0, 0, -sin(a), 0, cos(a), -40, 0, 0, 0, 1]))
        XCTAssertEqual(abs(turned.yaw), 20, accuracy: 0.01); XCTAssertEqual(turned.roll, 0, accuracy: 0.01)
        let r: Float = 10 * .pi / 180
        let tilted = try XCTUnwrap(BrowHeadPose(rowMajor: [cos(r), -sin(r), 0, 0, sin(r), cos(r), 0, 0, 0, 0, 1, -40, 0, 0, 0, 1]))
        XCTAssertEqual(abs(tilted.roll), 10, accuracy: 0.01); XCTAssertEqual(tilted.yaw, 0, accuracy: 0.01)
        XCTAssertNil(BrowHeadPose(rowMajor: [1, 2, 3]))
        // The same 20° head turn seen by a sensor turned 90° (portrait front camera) reads as roll ±90; turned back to
        // the screen it is a yaw again.
        let q: Float = -.pi / 2
        let rz = simd_float3x3(rows: [SIMD3(cos(q), -sin(q), 0), SIMD3(sin(q), cos(q), 0), SIMD3(0, 0, 1)])
        let ry = simd_float3x3(rows: [SIMD3(cos(a), 0, sin(a)), SIMD3(0, 1, 0), SIMD3(-sin(a), 0, cos(a))])
        let sensor = rz * ry
        let rows: [Float] = (0..<3).flatMap { r -> [Float] in [sensor[0][r], sensor[1][r], sensor[2][r], 0] } + [0, 0, 0, 1]
        let raw = try XCTUnwrap(BrowHeadPose(rowMajor: rows))
        XCTAssertEqual(abs(raw.roll), 90, accuracy: 0.01)
        let screen = raw.turned(toRoll: 0)
        XCTAssertEqual(abs(screen.yaw), 20, accuracy: 0.01); XCTAssertEqual(screen.pitch, 0, accuracy: 0.01)
    }

    func testSmootherCalmsStillJitterFollowsHeadAndResetsAfterGap() throws {
        var smoother = BrowObservationSmoother(), tops: [Float] = []
        for i in 0..<90 {
            let out = smoother.smooth(observation(jitter: 1, timestamp: Double(i) / 30))
            if i > 30 { tops.append(try XCTUnwrap(out.brows[.subjectRight]).upper[0].y) }
        }
        XCTAssertLessThan((tops.max() ?? 9) - (tops.min() ?? 0), 0.6, "A still face gives a still brow")
        var moved = observation()
        for i in 90..<105 { moved = smoother.smooth(observation(shift: SIMD2(50, 0), timestamp: Double(i) / 30)) }
        let expected = try XCTUnwrap(observation(shift: SIMD2(50, 0)).brows[.subjectRight]).upper[2]
        XCTAssertLessThan(simd_distance(try XCTUnwrap(moved.brows[.subjectRight]).upper[2], expected), 2, "Head movement is followed")
        let after = smoother.smooth(observation(shift: SIMD2(-40, 10), timestamp: 5))
        let fresh = try XCTUnwrap(observation(shift: SIMD2(-40, 10)).brows[.subjectRight]).upper[3]
        XCTAssertEqual(try XCTUnwrap(after.brows[.subjectRight]).upper[3], fresh, "A tracking gap restarts the filter")
    }

    func testHidingTheNaturalBrowReplacesDarkHairWithSurroundingSkin() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let shown = try BeautyBlushEngine.renderBrowStripFixture(obstructed: false, intensity: 0, darkBrow: true)
        let hidden = try BeautyBlushEngine.renderBrowStripFixture(obstructed: false, intensity: 0, darkBrow: true, hideNatural: true)
        let covered = try BeautyBlushEngine.renderBrowStripFixture(obstructed: true, intensity: 0, darkBrow: true, hideNatural: true)
        let brow = (16 * 32 + 16) * 4, skin = (4 * 32 + 16) * 4
        XCTAssertLessThan(Int(shown[brow + 1]), Int(shown[skin + 1]) - 40, "The natural brow is dark in the camera")
        XCTAssertEqual(Int(hidden[brow + 1]), Int(shown[skin + 1]), accuracy: 3, "Hidden brow takes the fill (skin) colour")
        XCTAssertEqual(Int(hidden[skin + 1]), Int(shown[skin + 1]), accuracy: 1, "Skin is left unchanged")
        XCTAssertEqual(Int(covered[brow + 1]), Int(shown[brow + 1]), accuracy: 1, "A hand over the brow stays in front")
    }

    func testHiddenBrowAreaStopsShortOfTheEyelidWithASoftFade() throws {
        let free = try XCTUnwrap(BeautyBlushEngine.browConcealLowerFixture(observation()))
        var close = observation()
        // An upper eyelid only ~20 px below the right brow's centerline (brow width ~100 px).
        close.eyes[.subjectRight]?.lid = (0...6).map { SIMD2(500 - 60 - Float($0) * 25, 310) }
        let bounded = try XCTUnwrap(BeautyBlushEngine.browConcealLowerFixture(close))
        let middle = free.count / 2 + 4 // a column near u = 0.5
        XCTAssertLessThan(bounded[middle].y, free[middle].y, "A close eyelid pulls the lower edge up")
        let g = try XCTUnwrap(BrowGeometry(contour: try XCTUnwrap(close.brows[.subjectRight])))
        let lid = try XCTUnwrap(g.depth(of: try XCTUnwrap(close.eyes[.subjectRight]).lid, at: 0.5))
        XCTAssertLessThan(lid, 0, "The eyelid is below the brow")
        let bound = BeautyBlushEngine.concealLower(half: 0.06, lidDepth: lid)
        XCTAssertEqual(bound.end, -lid * 0.85, accuracy: 0.0001, "Ends at most 85% of the way to the eyelid")
        XCTAssertLessThanOrEqual(bound.core, bound.end * 0.6 + 0.0001, "The fade keeps at least the lower 40%")
        XCTAssertEqual(BeautyBlushEngine.concealLower(half: 0.06, lidDepth: nil).end, 0.06 * 2.0 + 0.10, accuracy: 0.0001)
    }

    func testPushPullFillsTheHoleSmoothlyFromTheSkinAroundIt() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue(), let library = BeautyBlushShaders.library else {
            throw XCTSkip("Metal unavailable")
        }
        let eraser = try BrowEraser(device: device, library: library, inpainter: BrowInpainter(bundle: Bundle(for: Self.self)))
        let w = BrowEraser.width, h = BrowEraser.height
        // Two skin tones of equal brightness, so the forehead-texture term sees no edge and only the fill is measured.
        let a = SIMD3<Float>(0.6, 0.3, 0.2), b = SIMD3<Float>(0.2, 0.36, 0.62)
        func inHole(_ x: Int, _ y: Int) -> Bool { (64..<192).contains(x) && (40..<88).contains(y) }
        var known = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w where !inHole(x, y) {
            let c = x < w / 2 ? a : b
            known.replaceSubrange((y * w + x) * 4..<(y * w + x) * 4 + 4, with: [c.x, c.y, c.z, 1])
        } }
        let out = try eraser.fillFixture(known: known, device: device, commands: commands)
        func pixel(_ x: Int, _ y: Int) -> SIMD3<Float> { let i = (y * w + x) * 4; return SIMD3(out[i], out[i + 1], out[i + 2]) }
        XCTAssertLessThan(simd_distance(pixel(10, 10), a), 0.01, "Known skin is kept")
        XCTAssertLessThan(simd_distance(pixel(70, 64), a), simd_distance(pixel(70, 64), b), "The hole takes the colour of its nearer side")
        XCTAssertLessThan(simd_distance(pixel(186, 64), b), simd_distance(pixel(186, 64), a))
        let middle = pixel(128, 64)
        XCTAssertGreaterThan(middle.x, 0.25); XCTAssertLessThan(middle.x, 0.55, "The middle blends both sides")
        for x in 65..<191 { XCTAssertLessThan(simd_distance(pixel(x, 64), pixel(x + 1, 64)), 0.03, "No seam inside the hole at x=\(x)") }
    }

    func testDetectedBrowEdgeJoinsTheHiddenArea() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        // Landmark rows sit 0.06 brow widths either side of the centerline; real hair reaching 0.24 above them must be
        // hidden at 0.2, where the landmark area alone has faded out.
        let landmarksOnly = try BeautyBlushEngine.browHideFixture(observation(), hairAbove: 0.06, w: 0.2)
        let fullBrow = try BeautyBlushEngine.browHideFixture(observation(), hairAbove: 0.24, w: 0.2)
        XCTAssertLessThan(landmarksOnly, 0.2, "Skin above a brow that ends at its landmarks stays visible")
        XCTAssertGreaterThan(fullBrow, 0.5, "Hair past the landmark rows is found and hidden")
        let forehead = try BeautyBlushEngine.browHideFixture(observation(), hairAbove: 0.24, w: 0.4)
        XCTAssertLessThan(forehead, 0.1, "The search stops before the forehead")
    }

    func testInpainterInputAndOutputFollowMIGAN() throws {
        let n = BrowInpainter.side * BrowInpainter.side
        var rgba = [UInt8](repeating: 255, count: n * 4), hole = [UInt8](repeating: 0, count: n)
        rgba[0] = 0; hole[1] = 255
        let input = try BrowInpainter.input(rgba: rgba, hole: hole)
        XCTAssertEqual(input.shape, [1, 4, 256, 256])
        XCTAssertEqual(input[[0, 0, 0, 0]].floatValue, 0.5, accuracy: 1e-6, "Known pixel: mask - 0.5")
        XCTAssertEqual(input[[0, 0, 0, 1]].floatValue, -0.5, accuracy: 1e-6, "Hole pixel")
        XCTAssertEqual(input[[0, 1, 0, 0]].floatValue, -1, accuracy: 1e-6, "Image in -1...1")
        XCTAssertEqual(input[[0, 1, 0, 2]].floatValue, 1, accuracy: 1e-6)
        XCTAssertEqual(input[[0, 1, 0, 1]].floatValue, 0, accuracy: 1e-6, "Image is zero in the hole")
        let output = try MLMultiArray(shape: [1, 3, 256, 256], dataType: .float32)
        for i in 0..<output.count { output[i] = 0 }
        let result = BrowInpainter.output(output, rgba: rgba, hole: hole)
        XCTAssertEqual(result[0], 0, "Known pixels unchanged"); XCTAssertEqual(result[4], 128, "Hole takes the model output")
        XCTAssertFalse(BrowInpainter(bundle: Bundle(for: Self.self)).isAvailable, "No model in the test bundle")
    }

    func testBundledMIGANFillsOnlyTheHole() throws {
        let inpainter = BrowInpainter()
        XCTAssertTrue(inpainter.isAvailable, "MIGANFace256 is bundled with the app")
        let n = BrowInpainter.side * BrowInpainter.side
        var rgba = [UInt8](repeating: 0, count: n * 4), hole = [UInt8](repeating: 0, count: n)
        for i in 0..<n {
            rgba[i * 4] = 200; rgba[i * 4 + 1] = 150; rgba[i * 4 + 2] = 120; rgba[i * 4 + 3] = 255
            let x = i % BrowInpainter.side, y = i / BrowInpainter.side
            if (100..<156).contains(x) && (70..<90).contains(y) { hole[i] = 255; rgba[i * 4] = 20; rgba[i * 4 + 1] = 20; rgba[i * 4 + 2] = 20 }
        }
        let out = try inpainter.inpaint(rgba: rgba, hole: hole)
        XCTAssertEqual(out.count, n * 4)
        XCTAssertEqual(out[0], 200, "Known pixels are unchanged")
        let centre = (80 * BrowInpainter.side + 128) * 4
        XCTAssertGreaterThan(Int(out[centre]), 120, "The dark hole is filled with the surrounding skin tone")
        XCTAssertGreaterThan(Int(out[centre]), Int(out[centre + 2]), "and keeps its warm hue")
    }

    func testFaceCropIsUprightAndHoldsBothBrows() throws {
        let o = observation()
        let crop = try XCTUnwrap(BrowEraser.faceCrop(o))
        func uv(_ p: SIMD2<Float>) -> SIMD2<Float> { BrowEraser.cropPoint(p, imageSize: o.imageSize, cropToRaw: crop) }
        let right = try XCTUnwrap(o.eyes[.subjectRight]), left = try XCTUnwrap(o.eyes[.subjectLeft])
        XCTAssertEqual(uv(right.outer).y, uv(left.outer).y, accuracy: 0.001, "Eyes level")
        XCTAssertEqual(uv((right.outer + left.outer) / 2).y, 0.4, accuracy: 0.001, "Eyes about 40% from the top")
        XCTAssertLessThan(uv(right.outer).x, uv(left.outer).x, "Subject's right on the left, like a photo")
        for contour in o.brows.values { for p in contour.upper + contour.lower {
            let q = uv(p)
            XCTAssertTrue((0.05...0.95).contains(q.x) && (0.05...0.4).contains(q.y), "Brow point inside the crop, above the eyes")
        } }
    }

    func testTrackingViewLabelsEveryBrowPointWithItsMediaPipeIndex() {
        var o = observation()
        o.mesh = (0..<478).map { SIMD2(Float($0 % 40) * 20, Float($0 / 40) * 50) }
        let fixture = BeautyBlushEngine.browTrackingFixture(o)
        XCTAssertGreaterThan(fixture.vertices, 478 * 12, "Every landmark is drawn")
        for index in [70, 63, 105, 66, 107, 46, 53, 52, 65, 55, 300, 293, 334, 296, 336, 276, 283, 282, 295, 285, 33, 133, 263, 362, 168] {
            XCTAssertTrue(fixture.labels.contains("\(index)"), "Label \(index)")
        }
        XCTAssertTrue(EyebrowConfiguration().browTrackingOverlay, "Tracking view is on while shapes are hidden")
        XCTAssertFalse(EyebrowConfiguration().hideNaturalBrow, "The natural brow shows until the toggle hides it")
    }

    func testBrowTextureBakeHasStrandsTaperAndClearForehead() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let width = 256, height = 128
        let pixels = try BeautyBlushEngine.renderBrowTextureFixture(style: .softNatural, width: width, height: height)
        let extent = BeautyBlushEngine.browExtent
        func x(_ u: Float) -> Int { Int((u - extent.x) / (extent.y - extent.x) * Float(width)) }
        func y(_ w: Float) -> Int { min(height - 1, Int((extent.z - w) / (2 * extent.z) * Float(height))) }
        func channel(_ px: Int, _ py: Int, _ c: Int) -> Float { pixels[(py * width + px) * 4 + c] }
        XCTAssertGreaterThan(channel(x(0.5), y(0), 0), 0.1, "Pigment along the observed centerline")
        XCTAssertLessThan(channel(x(0.02), y(0), 0), channel(x(0.5), y(0), 0), "Head fades in")
        var strand = 0, gap = 0, outline = 0
        for px in x(0.2)..<x(0.8) {
            for py in y(0.04)...y(-0.04) where channel(px, py, 0) > 0.1 {
                if channel(px, py, 1) > 0.15 { strand += 1 } else { gap += 1 }
            }
            for py in 0..<height where channel(px, py, 2) > 0.5 { outline += 1 }
        }
        XCTAssertGreaterThan(strand, 30); XCTAssertGreaterThan(gap, 30)
        XCTAssertGreaterThan(outline, 20, "Design outline for the tutorial guide")
        // Overlay only: nothing on the forehead or past the tail.
        for py in 0..<y(0.2) { for px in 0..<width { XCTAssertEqual(channel(px, py, 0) + channel(px, py, 1), 0, accuracy: 0.0001) } }
        for py in 0..<height { for px in x(1.04)..<width { XCTAssertEqual(channel(px, py, 0), 0, accuracy: 0.0001) } }

        let high = try BeautyBlushEngine.renderBrowTextureFixture(style: .boldArch, width: width, height: height)
        func centroid(_ data: [Float], _ px: Int) -> Float {
            var sum: Float = 0, weight: Float = 0
            for py in 0..<height { let a = data[(py * width + px) * 4]; sum += a * Float(py); weight += a }
            return sum / max(weight, 0.0001)
        }
        XCTAssertLessThan(centroid(high, x(0.65)), centroid(pixels, x(0.65)) - 1, "High arch lifts the arch")
    }

    func testBrowStripIsOverlayOnlyAndHiddenWhereOccluded() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let bare = try BeautyBlushEngine.renderBrowStripFixture(obstructed: false, intensity: 0)
        let ink = try BeautyBlushEngine.renderBrowStripFixture(obstructed: false, intensity: 0.9)
        let covered = try BeautyBlushEngine.renderBrowStripFixture(obstructed: true, intensity: 0.9)
        let i = (16 * 32 + 16) * 4
        XCTAssertLessThan(Int(ink[i + 1]), Int(bare[i + 1]))
        for c in 0..<3 { XCTAssertEqual(Int(covered[i + c]), Int(bare[i + c]), accuracy: 1) }
        // Where the brow texture is empty, every pixel stays the camera pixel.
        let outside = try BeautyBlushEngine.renderBrowStripFixture(obstructed: false, intensity: 0.9, textureValue: 0)
        for j in stride(from: 0, to: outside.count, by: 4) { for c in 0..<3 { XCTAssertEqual(Int(outside[j + c]), Int(bare[j + c]), accuracy: 1) } }
    }
}
