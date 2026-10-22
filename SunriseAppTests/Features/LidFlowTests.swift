import XCTest
@testable import SunriseApp

final class LidFlowTests: XCTestCase {
    /// A smooth, textured picture: sums of sines are differentiable, like skin at this scale.
    private func level(width: Int = 260, height: Int = 200, shift: CGPoint = .zero) -> LumaPyramid.Level {
        var data = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let u = Double(x) - Double(shift.x), v = Double(y) - Double(shift.y)
                let value = 128 + 40 * sin(u / 7) * cos(v / 9) + 30 * sin((u + 2 * v) / 11) + 20 * cos((2 * u - v) / 5)
                data[y * width + x] = Float(value)
            }
        }
        return LumaPyramid.Level(width: width, height: height, data: data)
    }

    func testTracksAKnownShiftToSubPixels() throws {
        let shift = CGPoint(x: 3.4, y: -2.2)
        let prev = LumaPyramid(origin: .zero, base: level())
        let next = LumaPyramid(origin: .zero, base: level(shift: shift))
        let start = CGPoint(x: 130, y: 100)
        let end = try XCTUnwrap(LucasKanade.track(start, from: prev, to: next))
        XCTAssertEqual(end.x, start.x + shift.x, accuracy: 0.3)
        XCTAssertEqual(end.y, start.y + shift.y, accuracy: 0.3)
    }

    func testFlatSkinIsNotTracked() {
        let flat = LumaPyramid.Level(width: 260, height: 200, data: [Float](repeating: 120, count: 260 * 200))
        let pyramid = LumaPyramid(origin: .zero, base: flat)
        XCTAssertNil(LucasKanade.track(CGPoint(x: 130, y: 100), from: pyramid, to: pyramid))
    }

    func testPictureChangedBeyondRecognitionIsRejected() {
        let prev = LumaPyramid(origin: .zero, base: level())
        var seed: UInt32 = 12345
        let noise = (0..<(260 * 200)).map { _ -> Float in
            seed = seed &* 1664525 &+ 1013904223
            return Float(seed >> 24)
        }
        let other = LumaPyramid(origin: .zero, base: LumaPyramid.Level(width: 260, height: 200, data: noise))
        XCTAssertNil(LucasKanade.track(CGPoint(x: 130, y: 100), from: prev, to: other))
    }

    // MARK: Fusing with the detector

    private func frame(t: TimeInterval, open: CGFloat = 0.32, lift: CGFloat = 0) -> EyeLandmarkFrame {
        var frame = SyntheticEye.frame(t: t, open: open, headShift: .zero)
        if var eye = frame.subjectRight {
            eye.upperLid = eye.upperLid.map { $0 + CGPoint(x: 0, y: -lift) }
            frame.subjectRight = eye
        }
        return frame
    }

    func testFirstResultPassesThroughUnchanged() throws {
        let follower = LidFollower()
        let input = frame(t: 0)
        let output = follower.fuse(input, now: 0)
        XCTAssertEqual(output.subjectRight?.upperLid, input.subjectRight?.upperLid)
    }

    func testDetectorPullsGentlyNotAtOnce() throws {
        let follower = LidFollower()
        _ = follower.fuse(frame(t: 0), now: 0)
        // Settle the blink gate with a steady eye.
        _ = follower.fuse(frame(t: 1), now: 1)
        let base = try XCTUnwrap(follower.fuse(frame(t: 2), now: 2).subjectRight?.upperLid)
        let lifted = try XCTUnwrap(follower.fuse(frame(t: 3, lift: 10), now: 3, hand: [.subjectRight: 1]).subjectRight?.upperLid)
        // The detector says 10 px higher; the followed points move only a fraction toward that.
        let moved = zip(base, lifted).map { $0.y - $1.y }
        for dy in moved {
            XCTAssertEqual(dy, 10 * LidFollower.pullPerResult, accuracy: 0.05)
        }
    }

    func testOuterCornerMovesWithTheLidPointsNextToIt() throws {
        let follower = LidFollower()
        for t in 0..<3 { _ = follower.fuse(frame(t: TimeInterval(t)), now: TimeInterval(t)) }
        _ = follower.fuse(frame(t: 3), now: 3, hand: [.subjectRight: 1])
        // The detector now says the lid is 10 px higher (its corner did not move): the followed lid stays, and so
        // does the corner, because it goes with the lid points beside it.
        let input = frame(t: 4, lift: 10)
        let out = try XCTUnwrap(follower.fuse(input, now: 4, hand: [.subjectRight: 1]).subjectRight)
        let detectedCorner = try XCTUnwrap(input.subjectRight?.outerCorner)
        XCTAssertEqual(out.outerCorner.y - detectedCorner.y, 10 * (1 - LidFollower.pullPerResult), accuracy: 0.1)
    }

    func testWingAnchorStartsWhereTheSkinWouldBeRigidly() throws {
        let follower = LidFollower()
        let input = frame(t: 0)
        let eye = try XCTUnwrap(follower.fuse(input, now: 0).subjectRight)
        let source = try XCTUnwrap(input.subjectRight)
        let rigid = try XCTUnwrap(EyeCoordinateFrame(inner: source.innerCorner, outer: source.outerCorner,
                                                     upper: source.upperLid, lower: source.lowerLid, brow: source.browPoints))
            .toWorld(LinerBuildOptions.wingAnchorLocal)
        let anchor = try XCTUnwrap(eye.wingAnchor)
        XCTAssertEqual(anchor.x, rigid.x, accuracy: 1e-6)
        XCTAssertEqual(anchor.y, rigid.y, accuracy: 1e-6)
    }

    func testWithoutAHandTheDetectorIsUsedAsItIs() throws {
        let follower = LidFollower()
        for t in 0..<3 { _ = follower.fuse(frame(t: TimeInterval(t)), now: TimeInterval(t)) }
        let input = frame(t: 4, lift: 10)
        let output = follower.fuse(input, now: 4)
        XCTAssertEqual(output.subjectRight?.upperLid, input.subjectRight?.upperLid, "no lag behind the detector")
        XCTAssertEqual(follower.followingCount, 0)
    }

    func testAFlickeringHandReadingKeepsFollowing() throws {
        let follower = LidFollower()
        for t in 0..<3 { _ = follower.fuse(frame(t: Double(t) * 0.1), now: Double(t) * 0.1, hand: [.subjectRight: 1]) }
        // One reading without the hand, 0.1 s later: still following, so the lid does not jump back.
        _ = follower.fuse(frame(t: 0.3, lift: 10), now: 0.3)
        XCTAssertEqual(follower.followingCount, 1)
    }

    func testBlinkGivesTheDetectorFullControl() throws {
        let follower = LidFollower()
        for t in 0..<4 { _ = follower.fuse(frame(t: TimeInterval(t)), now: TimeInterval(t)) }
        let closing = frame(t: 4, open: 0.05, lift: 6)
        let output = try XCTUnwrap(follower.fuse(closing, now: 4).subjectRight?.upperLid)
        XCTAssertEqual(output, closing.subjectRight?.upperLid, "while blinking the points are the detector's")
    }

    func testNoFaceResetsTheFollower() {
        let follower = LidFollower()
        _ = follower.fuse(frame(t: 0), now: 0)
        var lost = frame(t: 1)
        lost.context = nil
        _ = follower.fuse(lost, now: 1)
        XCTAssertEqual(follower.followingCount, 0)
    }
}
