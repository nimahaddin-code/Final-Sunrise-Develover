import XCTest
@testable import SunriseApp

/// Synthetic eye landmarks in captured-image pixels, so the overlay's geometry runs without a camera.
enum SyntheticEye {
    /// An eye `width` pixels wide at `center`, turned by `angle` radians (0 = inner corner left, outer corner right,
    /// brow above). `mirrored` is the other eye of the face. `open` is the lid gap as a fraction of the width.
    static func landmarks(side: EyeSide = .subjectRight, center: CGPoint = CGPoint(x: 300, y: 400), width: CGFloat = 100,
                          angle: CGFloat = 0, mirrored: Bool = false, open: CGFloat = 0.32) -> EyeLandmarks {
        let ex = CGPoint(x: cos(angle) * (mirrored ? -1 : 1), y: sin(angle) * (mirrored ? -1 : 1))
        let ey = CGPoint(x: -sin(angle), y: cos(angle))
        let origin = center - ex * (width / 2)
        func world(_ x: CGFloat, _ y: CGFloat) -> CGPoint { origin + (ex * x + ey * y) * width }
        let xs: [CGFloat] = [0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9]
        let upper = xs.map { world($0, -open * 0.62 * 4 * $0 * (1 - $0)) }
        let lower = xs.map { world($0, open * 0.38 * 4 * $0 * (1 - $0)) }
        let brow = [0.0, 0.25, 0.5, 0.75, 1.05].map { world($0, -0.35 - 0.05 * $0) }
        return EyeGeometry.makeEyeLandmarks(side: side, inner: world(0, 0), outer: world(1, 0), upper: upper,
                                            lower: lower, brow: brow)
    }

    /// Both eyes of a face looking at the camera; rigid anchors between them.
    static func frame(t: TimeInterval, open: CGFloat = 0.32, shift: CGPoint = .zero, headShift: CGPoint? = nil,
                      noise: CGPoint = .zero) -> EyeLandmarkFrame {
        // `headShift`: the head's motion as ARKit reports it (steady); `noise`: the detector's own error on the eyes.
        let shift = (headShift ?? shift)
        let right = landmarks(side: .subjectRight, center: CGPoint(x: 220, y: 400) + shift, open: open)
        let left = landmarks(side: .subjectLeft, center: CGPoint(x: 380, y: 400) + shift, mirrored: true, open: open)
        let anchors = [CGPoint(x: 300, y: 380), CGPoint(x: 300, y: 430), CGPoint(x: 300, y: 480),
                       CGPoint(x: 250, y: 520), CGPoint(x: 350, y: 520)].map { $0 + shift }
        var frame = EyeLandmarkFrame(imageSize: CGSize(width: 640, height: 480), timestamp: t, subjectLeft: left,
                                     subjectRight: right, providerLatencyMs: 10, faceAnchors: anchors)
        if headShift != nil {
            let head = [CGPoint(x: 220, y: 380), CGPoint(x: 220, y: 420), CGPoint(x: 380, y: 380), CGPoint(x: 380, y: 420)]
                .map { $0 + shift }
            frame.context = FrameContext(displayTransform: .identity, imageSize: frame.imageSize,
                                         viewportSize: frame.imageSize, headAnchors: head)
            // The detector's own error on the eyes (its face anchors are no better).
            frame.subjectLeft = frame.subjectLeft?.replacingPoints(with: frame.subjectLeft!.flattened.map { $0 + noise })
            frame.subjectRight = frame.subjectRight?.replacingPoints(with: frame.subjectRight!.flattened.map { $0 + noise })
        }
        return frame
    }
}

final class EyelinerGeometryTests: XCTestCase {
    private func spec(_ shape: EyeShape) -> LinerSpec { LinerSpec(style: EyelinerPlanner.variant(for: shape)) }

    private func build(_ eye: EyeLandmarks, _ spec: LinerSpec,
                       options: LinerBuildOptions = LinerBuildOptions()) throws -> LinerGuide {
        try XCTUnwrap(LinerPathBuilder.build(landmarks: eye, spec: spec, options: options))
    }

    /// Distance of `point` above the eye's lash line axis, in eye widths (positive toward the brow).
    private func height(_ point: CGPoint, of eye: EyeLandmarks) -> CGFloat {
        let frame = EyeCoordinateFrame(inner: eye.innerCorner, outer: eye.outerCorner, upper: eye.upperLid,
                                       lower: eye.lowerLid, brow: eye.browPoints)!
        return -frame.toLocal(point).y
    }

    // MARK: Shape model

    func testLinerSpecKeepsTheStylesNumbers() {
        let style = EyelinerPlanner.variant(for: .almond)
        let spec = LinerSpec(style: style)
        XCTAssertEqual(spec.upperThickness, [Double(style.innerWidth), Double(style.midWidth!), Double(style.outerWidth)])
        XCTAssertEqual(spec.wingLength, Double(style.wingLength))
        XCTAssertEqual(spec.wingAngleDeg, Double(style.wingAngle))
        XCTAssertEqual(spec.lowerLine.enabled, style.lowerLine.enabled)
        XCTAssertEqual(spec.wingBase, style.wingBase)
    }

    /// How far above the eye's own lash line a liner point lies, in eye widths (only meaningful between the corners).
    private func gapAboveLashLine(_ point: CGPoint, of eye: EyeLandmarks) -> CGFloat? {
        let frame = EyeCoordinateFrame(inner: eye.innerCorner, outer: eye.outerCorner, upper: eye.upperLid,
                                       lower: eye.lowerLid, brow: eye.browPoints)!
        let local = frame.toLocal(point)
        guard local.x > 0.1, local.x < 0.9 else { return nil }
        let line = EyeGeometry.localLashLine(eye.upperLid, frame: frame)
        return EyeGeometry.yAt(local.x, line) - local.y
    }

    func testUpperLinerSitsAboveTheLashLineWithTheNamedOffset() throws {
        let eye = SyntheticEye.landmarks()
        func gaps(_ options: LinerBuildOptions) throws -> [CGFloat] {
            try build(eye, spec(.almond), options: options).upperLiner.compactMap { gapAboveLashLine($0, of: eye) }
        }
        let near = try gaps(LinerBuildOptions())
        XCTAssertFalse(near.isEmpty)
        XCTAssertEqual(near.min() ?? 0, LinerBuildOptions.defaultLashOffset, accuracy: 0.006,
                       "The liner's base starts one named offset above the lash line, never inside the eye")
        XCTAssertGreaterThan(near.max() ?? 0, 0.03, "and it has real thickness")
        let far = try gaps(LinerBuildOptions(lashOffset: 0.05))
        XCTAssertEqual(far.min() ?? 0, 0.05, accuracy: 0.006)
        XCTAssertEqual((far.max() ?? 0) - (far.min() ?? 0), (near.max() ?? 0) - (near.min() ?? 0), accuracy: 0.01,
                       "Moving the liner off the lash line does not thin it")
        XCTAssertLessThanOrEqual(LinerBuildOptions.defaultLashOffset, LinerBuildOptions.spikeLashOffset,
                                 "The liner sits on the lash roots, with no strip of skin under it")
        XCTAssertEqual(LinerBuildOptions().lashOffset, LinerBuildOptions.defaultLashOffset)
    }

    func testWingTipFollowsItsSkinAnchor() throws {
        let eye = SyntheticEye.landmarks()
        let frame = try XCTUnwrap(EyeCoordinateFrame(inner: eye.innerCorner, outer: eye.outerCorner, upper: eye.upperLid,
                                                     lower: eye.lowerLid, brow: eye.browPoints))
        func tip(anchorLocal: CGPoint?) throws -> CGPoint {
            var e = eye
            e.wingAnchor = anchorLocal.map(frame.toWorld)
            return try XCTUnwrap(try build(e, spec(.upturned)).anchors.wingTip)
        }
        let rigid = try tip(anchorLocal: nil)
        let atRest = try tip(anchorLocal: LinerBuildOptions.wingAnchorLocal)
        XCTAssertEqual((atRest - rigid).length, 0, accuracy: 1e-6, "An anchor that has not moved changes nothing")
        let stretched = try tip(anchorLocal: LinerBuildOptions.wingAnchorLocal + CGPoint(x: 0.2, y: -0.15))
        // The tip moves by the anchor's stretch, in the eye's own frame (100 px wide here), up to `wingAnchorReach`.
        let moved = frame.toLocal(stretched) - frame.toLocal(rigid)
        XCTAssertEqual(moved.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(moved.y, -0.15, accuracy: 1e-6)
        let far = try tip(anchorLocal: LinerBuildOptions.wingAnchorLocal + CGPoint(x: 2, y: 0))
        XCTAssertEqual((frame.toLocal(far) - frame.toLocal(rigid)).length, LinerBuildOptions.wingAnchorReach, accuracy: 1e-6,
                       "A huge stretch is capped")
    }

    func testGeometryDoesNotDependOnHeadRollOrScale() throws {
        let upright = try build(SyntheticEye.landmarks(), spec(.almond))
        let rolled = try build(SyntheticEye.landmarks(center: CGPoint(x: 150, y: 90), width: 220, angle: .pi / 2),
                               spec(.almond))
        let a = SyntheticEye.landmarks(), b = SyntheticEye.landmarks(center: CGPoint(x: 150, y: 90), width: 220, angle: .pi / 2)
        let frameA = EyeCoordinateFrame(inner: a.innerCorner, outer: a.outerCorner, upper: a.upperLid, lower: a.lowerLid, brow: a.browPoints)!
        let frameB = EyeCoordinateFrame(inner: b.innerCorner, outer: b.outerCorner, upper: b.upperLid, lower: b.lowerLid, brow: b.browPoints)!
        let localA = upright.upperLiner.map(frameA.toLocal), localB = rolled.upperLiner.map(frameB.toLocal)
        XCTAssertEqual(localA.count, localB.count)
        for (p, q) in zip(localA, localB) {
            XCTAssertEqual(p.x, q.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, q.y, accuracy: 1e-6)
        }
    }

    func testBothEyesGetALinerOfTheSameShape() throws {
        let frame = SyntheticEye.frame(t: 0)
        let left = try XCTUnwrap(frame.subjectLeft), right = try XCTUnwrap(frame.subjectRight)
        let guideL = try build(left, spec(.downturned)), guideR = try build(right, spec(.downturned))
        XCTAssertEqual(guideL.upperLiner.count, guideR.upperLiner.count)
        let tipL = try XCTUnwrap(guideL.anchors.wingTip), tipR = try XCTUnwrap(guideR.anchors.wingTip)
        XCTAssertEqual((tipL - guideL.anchors.outerCorner).length, (tipR - guideR.anchors.outerCorner).length,
                       accuracy: 1e-6)
        // The wing leaves each eye on its outer side.
        XCTAssertLessThan(guideL.anchors.wingTip!.x - left.outerCorner.x, 0)
        XCTAssertGreaterThan(guideR.anchors.wingTip!.x - right.outerCorner.x, 0)
    }

    // MARK: Wing, lower line, tightline

    func testDownturnedWingStartsFromTheLowerLashLineAndLifts() throws {
        let eye = SyntheticEye.landmarks()
        let downturned = spec(.downturned)
        // "Lifting wing" in the reference sheet: it leaves along the lower lid and rises above it.
        XCTAssertEqual(downturned.wingAngleDeg, 18)
        XCTAssertEqual(downturned.wingBase, .lowerLidTangent)
        let wing = try XCTUnwrap(try build(eye, downturned).anchors.wingTip)
        var flat = downturned
        flat.wingAngleDeg = 0
        let flatTip = try XCTUnwrap(try build(eye, flat).anchors.wingTip)
        XCTAssertGreaterThan(height(wing, of: eye), height(flatTip, of: eye) + 0.005)
    }

    func testNoWingWhenTheStyleHasNone() throws {
        for shape in [EyeShape.wideSet] {
            let guide = try build(SyntheticEye.landmarks(), spec(shape))
            XCTAssertTrue(guide.wing.isEmpty, "\(shape)")
            XCTAssertNil(guide.anchors.wingTip)
        }
        let natural = try build(SyntheticEye.landmarks(), LinerSpec(style: EyelinerPlanner.naturalLine))
        XCTAssertTrue(natural.wing.isEmpty)
        XCTAssertEqual(natural.outlines.count, 1)
    }

    func testLowerLinerAndTightlineOnlyWhenAsked() throws {
        let eye = SyntheticEye.landmarks()
        XCTAssertFalse(try build(eye, spec(.upturned)).lowerLiner.isEmpty)
        XCTAssertTrue(try build(eye, spec(.closeSet)).lowerLiner.isEmpty)
        XCTAssertFalse(try build(eye, spec(.hooded)).tightline.isEmpty)
        XCTAssertTrue(try build(eye, spec(.almond)).tightline.isEmpty)
    }

    func testCloseSetWingAimsTowardTheBrowTail() throws {
        let eye = SyntheticEye.landmarks()
        var aimed = spec(.closeSet), level = spec(.closeSet)
        aimed.wingTargetsBrowTail = true
        level.wingTargetsBrowTail = false
        let tipAimed = try XCTUnwrap(try build(eye, aimed).anchors.wingTip)
        let tipLevel = try XCTUnwrap(try build(eye, level).anchors.wingTip)
        XCTAssertGreaterThan(height(tipAimed, of: eye), height(tipLevel, of: eye))
    }

    // MARK: Selection to geometry

    func testEyeShapeSelectionDrivesTheDrawnWing() throws {
        let wide = EyeScan(tiltLeft: 4, tiltRight: 4, spacing: 1.15, openness: 0.25, samples: 8)
        let style = EyelinerPlanner.plan(for: wide).style
        XCTAssertTrue(try build(SyntheticEye.landmarks(), LinerSpec(style: style)).wing.isEmpty, "R4: wide-set, no wing")

        let unclear = EyelinerPlanner.plan(for: EyeScan(tiltLeft: 4, tiltRight: 4, spacing: 1, openness: 0.05, samples: 8))
        XCTAssertTrue(unclear.isNeutral, "R7: eyes closed during the scan")
        XCTAssertTrue(try build(SyntheticEye.landmarks(), LinerSpec(style: unclear.style)).wing.isEmpty)

        let almond = EyelinerPlanner.plan(for: EyeScan(tiltLeft: 4, tiltRight: 4, spacing: 1, openness: 0.25, samples: 8))
        XCTAssertFalse(try build(SyntheticEye.landmarks(), LinerSpec(style: almond.style)).wing.isEmpty)
    }

    // MARK: Tracker: smoothing and the open-eye baseline

    func testLinerStaysOnAClosedEye() {
        let tracker = LinerTracker()
        var t = 0.0
        for _ in 0..<30 {
            t += 1.0 / 30
            _ = tracker.render(SyntheticEye.frame(t: t), spec: spec(.almond))
        }
        var closed: [RenderedEye] = []
        for _ in 0..<15 {
            t += 1.0 / 30
            closed = tracker.render(SyntheticEye.frame(t: t, open: 0.02), spec: spec(.almond))
        }
        XCTAssertEqual(closed.count, 2, "A closed eye keeps its liner on the closed lash line")
        XCTAssertEqual(closed.first?.alpha ?? 0, 1, accuracy: 1e-9)
    }

    func testLinerGetsThickerAsTheEyeCloses() throws {
        func area(_ guide: LinerGuide) -> CGFloat { abs(signedArea(guide.upperLiner)) }
        let tracker = LinerTracker()
        var t = 0.0
        var open: [RenderedEye] = []
        for _ in 0..<30 {
            t += 1.0 / 30
            open = tracker.render(SyntheticEye.frame(t: t), spec: spec(.almond))
        }
        var closed: [RenderedEye] = []
        for _ in 0..<15 {
            t += 1.0 / 30
            closed = tracker.render(SyntheticEye.frame(t: t, open: 0.02), spec: spec(.almond))
        }
        let ratio = area(try XCTUnwrap(closed.first?.guide)) / area(try XCTUnwrap(open.first?.guide))
        XCTAssertGreaterThan(ratio, 1.5, "A closed eye shows a clearly thicker liner")
        XCTAssertLessThan(ratio, 2.6)
    }

    func testLinerFadesWhenTheEyeClosesAndReturnsWhenItReopens() {
        let tracker = LinerTracker()
        tracker.keepsLinerWhenClosed = false
        let almond = spec(.almond)
        var t = 0.0
        for _ in 0..<30 {
            t += 1.0 / 30
            XCTAssertEqual(tracker.render(SyntheticEye.frame(t: t), spec: almond).count, 2)
        }
        for _ in 0..<15 {
            t += 1.0 / 30
            _ = tracker.render(SyntheticEye.frame(t: t, open: 0.02), spec: almond)
        }
        XCTAssertTrue(tracker.render(SyntheticEye.frame(t: t + 1.0 / 30, open: 0.02), spec: almond).isEmpty,
                      "A closed eye shows no liner")
        var reopened: [RenderedEye] = []
        for _ in 0..<15 {
            t += 1.0 / 30
            reopened = tracker.render(SyntheticEye.frame(t: t), spec: almond)
        }
        XCTAssertEqual(reopened.count, 2)
        XCTAssertGreaterThan(reopened.first?.alpha ?? 0, 0.9)
    }

    func testHoodedEyesWithASmallOpeningStillCountAsOpen() {
        // The baseline is per person, so a small absolute opening is not "closed".
        let tracker = LinerTracker()
        var shown: [RenderedEye] = []
        for i in 0..<30 { shown = tracker.render(SyntheticEye.frame(t: Double(i) / 30, open: 0.12), spec: spec(.hooded)) }
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(shown.first?.alpha ?? 0, 1, accuracy: 1e-6)
    }

    func testLinerKeepsUpWithABlink() throws {
        // The lid closes in 3 frames (100 ms at 30 fps), as a real blink does.
        let tracker = LinerTracker()
        var t = 0.0
        for _ in 0..<30 {
            t += 1.0 / 30
            _ = tracker.render(SyntheticEye.frame(t: t), spec: spec(.almond))
        }
        func lidMiddle(_ eyes: [EyeLandmarks]) -> CGFloat { eyes.first { $0.side == .subjectRight }!.upperLid[3].y }
        let openY = lidMiddle(tracker.lastSmoothed)
        let closedY = lidMiddle(SyntheticEye.frame(t: 0, open: 0.02).eyes)
        for open in [0.22, 0.12, 0.02] as [CGFloat] {
            t += 1.0 / 30
            _ = tracker.render(SyntheticEye.frame(t: t, open: open), spec: spec(.almond))
        }
        let covered = (lidMiddle(tracker.lastSmoothed) - openY) / (closedY - openY)
        XCTAssertGreaterThan(covered, 0.8, "Right after the lid closes, the liner has gone most of the way with it (the steady config alone: 67%)")
    }

    func testSmoothingKeepsAStillFaceStill() {
        let tracker = LinerTracker()
        var last: [RenderedEye] = []
        var previous: CGPoint?
        for i in 0..<40 {
            // Landmark noise of about a pixel around the true position.
            let noise = CGPoint(x: i.isMultiple(of: 2) ? 0.8 : -0.8, y: i.isMultiple(of: 3) ? 0.6 : -0.6)
            last = tracker.render(SyntheticEye.frame(t: Double(i) / 30, shift: noise), spec: spec(.almond))
            if i == 38 { previous = last.first?.guide.anchors.outerCorner }
        }
        let now = last.first?.guide.anchors.outerCorner
        XCTAssertNotNil(previous)
        XCTAssertLessThan(((now ?? .zero) - (previous ?? .zero)).length, 0.5, "Jitter is filtered out")
    }

    func testHeadMotionComesFromARKitSoItNeitherLagsNorJitters() {
        let tracker = LinerTracker()
        var errors: [CGFloat] = []
        var corner = CGPoint.zero
        for i in 0..<90 {
            // The head moves 2 px per frame (ARKit knows exactly); the detector's eye points jitter by about a pixel.
            let head = CGPoint(x: CGFloat(i) * 2, y: 0)
            let noise = CGPoint(x: i.isMultiple(of: 2) ? 1.0 : -1.0, y: i.isMultiple(of: 3) ? 0.8 : -0.8)
            corner = tracker.render(SyntheticEye.frame(t: Double(i) / 30, headShift: head, noise: noise), spec: spec(.almond))
                .first { $0.side == .subjectRight }?.guide.anchors.outerCorner ?? corner
            let truth = SyntheticEye.frame(t: 0, shift: head).subjectRight!.outerCorner
            if i >= 30 { errors.append((corner - truth).length) }
        }
        XCTAssertLessThan(errors.max() ?? 99, 2.5, "No lag behind the head, and the detector's jitter is filtered out")
        // Frame to frame the liner moves by the head's 2 px, not by the jitter on top of it.
        var steps: [CGFloat] = []
        var last: CGPoint?
        let tracker2 = LinerTracker()
        for i in 0..<60 {
            let head = CGPoint(x: CGFloat(i) * 2, y: 0)
            let noise = CGPoint(x: i.isMultiple(of: 2) ? 1.0 : -1.0, y: i.isMultiple(of: 3) ? 0.8 : -0.8)
            let c = tracker2.render(SyntheticEye.frame(t: Double(i) / 30, headShift: head, noise: noise), spec: spec(.almond))
                .first { $0.side == .subjectRight }?.guide.anchors.outerCorner
            if i >= 20, let c, let last { steps.append(abs((c - last).length - 2)) }
            last = c
        }
        XCTAssertLessThan(steps.max() ?? 99, 0.8)
    }

    func testTrackerFollowsRealMotion() {
        let tracker = LinerTracker()
        var corner = CGPoint.zero
        for i in 0..<60 {
            let shift = CGPoint(x: CGFloat(i) * 2, y: 0)
            corner = tracker.render(SyntheticEye.frame(t: Double(i) / 30, shift: shift), spec: spec(.almond))
                .first { $0.side == .subjectRight }?.guide.anchors.outerCorner ?? corner
        }
        // The true outer corner of the right eye moved 118 px; the filter lags by only a few pixels.
        let truth = SyntheticEye.frame(t: 0, shift: CGPoint(x: 118, y: 0)).subjectRight!.outerCorner
        XCTAssertLessThan((corner - truth).length, 12)
    }
}

final class LinerSolutionTests: XCTestCase {
    private func solution(time: CFTimeInterval = 10) -> LinerSolution {
        let tracker = LinerTracker()
        var eyes: [RenderedEye] = []
        for i in 0..<5 {
            eyes = tracker.render(SyntheticEye.frame(t: Double(i) / 30),
                                  spec: LinerSpec(style: EyelinerPlanner.variant(for: .almond)))
        }
        // Face reference points as ARKit would project them: origin, +x, +y, -x, -y.
        let refs = [CGPoint(x: 300, y: 400), CGPoint(x: 360, y: 400), CGPoint(x: 300, y: 340),
                    CGPoint(x: 240, y: 400), CGPoint(x: 300, y: 460)]
        return LinerSolution(eyes: eyes, raw: tracker.lastRaw, smoothed: tracker.lastSmoothed, references: refs, time: time)
    }

    func testTheLinerFollowsTheHeadWhenTheDetectorHasNothingNew() throws {
        let solution = solution()
        // The head moved 25 px right and 10 px down, with no detector result.
        let moved = solution.references.map { CGPoint(x: $0.x + 25, y: $0.y + 10) }
        let result = try XCTUnwrap(solution.moved(to: moved, now: 10.1))
        for (before, after) in zip(solution.eyes, result.eyes) {
            XCTAssertEqual(after.guide.anchors.outerCorner.x, before.guide.anchors.outerCorner.x + 25, accuracy: 1e-6)
            XCTAssertEqual(after.guide.anchors.outerCorner.y, before.guide.anchors.outerCorner.y + 10, accuracy: 1e-6)
            XCTAssertEqual(after.guide.upperLiner.count, before.guide.upperLiner.count)
        }
        XCTAssertEqual(result.smoothed.count, 2)
    }

    func testHeadRollAndDistanceMoveTheLinerToo() throws {
        let solution = solution()
        // The head rolled a quarter turn about its centre and came 50% closer.
        let centre = solution.references[0]
        let moved = solution.references.map { p -> CGPoint in
            let d = p - centre
            return centre + CGPoint(x: -d.y, y: d.x) * 1.5
        }
        let result = try XCTUnwrap(solution.moved(to: moved, now: 10.1))
        let before = solution.eyes[0].guide.anchors, after = result.eyes[0].guide.anchors
        XCTAssertEqual((after.outerCorner - after.innerCorner).length, (before.outerCorner - before.innerCorner).length * 1.5,
                       accuracy: 1e-6)
        let d = before.outerCorner - centre
        XCTAssertEqual(after.outerCorner.x, centre.x - d.y * 1.5, accuracy: 1e-6)
        XCTAssertEqual(after.outerCorner.y, centre.y + d.x * 1.5, accuracy: 1e-6)
    }

    func testAMeasurementFadesAndThenExpires() throws {
        let solution = solution(time: 10)
        let refs = solution.references
        XCTAssertEqual(try XCTUnwrap(solution.moved(to: refs, now: 10.3)).eyes[0].alpha, solution.eyes[0].alpha, accuracy: 1e-9)
        let fading = try XCTUnwrap(solution.moved(to: refs, now: 10 + (LinerSolution.fadeStart + LinerSolution.holdDuration) / 2))
        XCTAssertEqual(fading.eyes[0].alpha, solution.eyes[0].alpha * 0.5, accuracy: 1e-6)
        XCTAssertNil(solution.moved(to: refs, now: 10 + LinerSolution.holdDuration + 0.01), "Too old to trust")
    }

    func testFaceLostDoesNotMakeTheLinerJump() throws {
        // A degenerate reading (reference points all equal) cannot define a motion: the last shape is kept as it was.
        let solution = solution()
        let collapsed = Array(repeating: CGPoint(x: 5, y: 5), count: 5)
        let result = try XCTUnwrap(solution.moved(to: collapsed, now: 10.1))
        XCTAssertEqual(result.eyes[0].guide.anchors.outerCorner, solution.eyes[0].guide.anchors.outerCorner)
    }
}
