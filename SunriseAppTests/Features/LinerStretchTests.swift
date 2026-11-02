import CoreVideo
import XCTest
@testable import SunriseApp

/// A replayable stretch benchmark: the skin (a textured picture) is pulled while the detector keeps reporting the
/// resting eye, the way MediaPipe's face prior does when a lid is held sideways. No camera needed.
final class LinerStretchTests: XCTestCase {
    private let eyeWidth: CGFloat = 100

    /// 640 x 480 YCbCr frame whose luma is a smooth texture moved by `shift` (chroma is flat).
    private func buffer(shift: CGPoint) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &created)
        let buffer = try XCTUnwrap(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<480 {
            for x in 0..<640 {
                let u = Double(x) - Double(shift.x), v = Double(y) - Double(shift.y)
                // Wavelengths of 20 to 70 px: the follower looks at a half-size picture, like real skin at this scale.
                let value = 128 + 40 * sin(u / 21) * cos(v / 27) + 30 * sin((u + 2 * v) / 33) + 20 * cos((2 * u - v) / 15)
                luma[y * stride + x] = UInt8(max(0, min(255, value)))
            }
        }
        if let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            memset(chroma, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1))
        }
        return buffer
    }

    private func detected(t: TimeInterval) -> EyeLandmarkFrame { SyntheticEye.frame(t: t, headShift: .zero) }

    private var headAnchors: [CGPoint] {
        [CGPoint(x: 220, y: 380), CGPoint(x: 220, y: 420), CGPoint(x: 380, y: 380), CGPoint(x: 380, y: 420)]
    }

    /// The skin's pull at camera frame `k` of `frames`: eased from nothing to `distance`.
    private func pull(_ k: Int, frames: Int, distance: CGPoint) -> CGPoint {
        let p = min(1, Double(k) / Double(max(frames, 1)))
        let eased = p * p * (3 - 2 * p)
        return CGPoint(x: distance.x * eased, y: distance.y * eased)
    }

    struct Run {
        /// Distance of the followed outer corner from where the skin really is, in eye widths, at every detector result.
        var cornerError: [CGFloat] = []
        var following: [Int] = []
        var follower = LidFollower()
        var lastFused: EyeLandmarkFrame?
    }

    /// 60 Hz camera frames, a detector result every other frame (30 Hz) that never follows the skin.
    private func simulate(hand: Double, distance: CGPoint, pullFrames: Int = 20, holdFrames: Int = 60,
                          releaseFrames: Int = 0, restFrames: Int = 0) throws -> Run {
        var run = Run()
        let right = EyeSide.subjectRight
        let rest = try XCTUnwrap(detected(t: 0).subjectRight).outerCorner
        // A new track counts its first result as a blink (0.3 s of detector only): settle it before the pull starts.
        let resting = try buffer(shift: .zero)
        for warm in 0..<3 {
            _ = run.follower.fuse(detected(t: Double(warm - 3)), now: Double(warm - 3), hand: [right: hand])
            run.follower.advance(resting, headAnchors: headAnchors)
        }
        let total = pullFrames + holdFrames + releaseFrames + restFrames
        for k in 1...total {
            let t = Double(k) / 60
            var shift = pull(min(k, pullFrames), frames: pullFrames, distance: distance)
            if k > pullFrames + holdFrames {
                let back = pull(k - pullFrames - holdFrames, frames: releaseFrames, distance: distance)
                shift = CGPoint(x: distance.x - back.x, y: distance.y - back.y)
            }
            run.follower.advance(try buffer(shift: shift), headAnchors: headAnchors)
            if k % 2 == 0 {
                let out = run.follower.fuse(detected(t: t), now: t, hand: [right: hand])
                run.lastFused = out
                let corner = try XCTUnwrap(out.subjectRight).outerCorner
                let truth = CGPoint(x: rest.x + shift.x, y: rest.y + shift.y)
                run.cornerError.append(hypot(corner.x - truth.x, corner.y - truth.y) / eyeWidth)
                run.following.append(run.follower.followingCount)
            }
        }
        return run
    }

    // MARK: Following a pulled lid

    func testRestingSkinIsNeverFollowed() throws {
        let run = try simulate(hand: 0, distance: .zero)
        XCTAssertEqual(run.following.max(), 0, "nothing pulls the lid: the detector is used as it is")
        XCTAssertLessThan(run.cornerError.max() ?? 1, 0.001)
    }

    func testOuterCornerPullWithAHandIsFollowed() throws {
        let run = try simulate(hand: 1, distance: CGPoint(x: 40, y: -10))
        XCTAssertLessThan(try XCTUnwrap(run.cornerError.last), 0.08)
    }

    /// The hand mask can miss a thin finger or a hand at the temple: the moving skin itself must start following.
    func testPullWithoutAHandMaskIsFollowedFromTheSkinMotion() throws {
        let run = try simulate(hand: 0, distance: CGPoint(x: 40, y: -10))
        XCTAssertLessThan(try XCTUnwrap(run.cornerError.last), 0.08)
        XCTAssertGreaterThan(run.following.last ?? 0, 0)
    }

    func testHeldPullWithoutAHandMaskDoesNotSnapBack() throws {
        let run = try simulate(hand: 0, distance: CGPoint(x: 40, y: -10), holdFrames: 180)
        let tail = run.cornerError.suffix(30)
        XCTAssertLessThan(tail.max() ?? 1, 0.1, "three seconds into the hold the liner is still on the pulled skin")
    }

    func testReleasedPullReturnsToTheDetector() throws {
        // Half a second of rest after the release (the pull is kept that long after the skin last moved fast).
        let run = try simulate(hand: 0, distance: CGPoint(x: 40, y: -10), holdFrames: 30, releaseFrames: 30, restFrames: 45)
        XCTAssertLessThan(try XCTUnwrap(run.cornerError.last), 0.05)
        XCTAssertEqual(run.following.last, 0, "back at rest the detector is trusted again")
    }

    func testLargePullBeyondTheOldLimitStillFollowed() throws {
        let run = try simulate(hand: 1, distance: CGPoint(x: 60, y: -20), pullFrames: 40)
        XCTAssertLessThan(try XCTUnwrap(run.cornerError.last), 0.1)
    }

    func testFollowingLagIsAtMostTwoDetectorResultsBehindAFastPull() throws {
        let run = try simulate(hand: 0, distance: CGPoint(x: 30, y: 0), pullFrames: 12)
        // 12 camera frames = 6 detector results; two results after the pull ends the error is already small.
        XCTAssertLessThan(run.cornerError[7], 0.08)
    }

    // MARK: The wing on a stretched corner

    /// The wing tip goes with the pulled anchor in full (the style's 24 degree limit only bends its own direction), so a
    /// pull of half an eye width is not clipped, and the wing still grows from the corner.
    func testWingTipFollowsAStretchedAnchorWithoutClipping() throws {
        let spec = LinerSpec(style: EyelinerPlanner.variant(for: .almond))
        var eye = SyntheticEye.landmarks()
        let rest = try XCTUnwrap(LinerPathBuilder.build(landmarks: eye, spec: spec, options: LinerBuildOptions()))
        let frame = try XCTUnwrap(EyeCoordinateFrame(inner: eye.innerCorner, outer: eye.outerCorner, upper: eye.upperLid,
                                                     lower: eye.lowerLid, brow: eye.browPoints))
        let pull = CGPoint(x: 0.5, y: -0.25)
        eye.wingAnchor = frame.toWorld(LinerBuildOptions.wingAnchorLocal + pull)
        let pulled = try XCTUnwrap(LinerPathBuilder.build(landmarks: eye, spec: spec, options: LinerBuildOptions()))
        let tipRest = frame.toLocal(try XCTUnwrap(rest.anchors.wingTip)), tipPulled = frame.toLocal(try XCTUnwrap(pulled.anchors.wingTip))
        XCTAssertEqual(tipPulled.x - tipRest.x, pull.x, accuracy: 0.01)
        XCTAssertEqual(tipPulled.y - tipRest.y, pull.y, accuracy: 0.01)
        let root = frame.toLocal(try XCTUnwrap(pulled.anchors.wingRoot)), corner = frame.toLocal(eye.outerCorner)
        XCTAssertEqual(root.x, corner.x, accuracy: 0.02, "the wing still grows from the outer corner")
    }

    // MARK: Between detector results

    func testRefreshMovesTheLinerBetweenDetectorResults() throws {
        var run = try simulate(hand: 1, distance: CGPoint(x: 40, y: -10), pullFrames: 20, holdFrames: 4)
        let fused = try XCTUnwrap(run.lastFused)
        let before = try XCTUnwrap(fused.subjectRight).outerCorner
        // The skin keeps moving; no detector result arrives, only camera frames.
        for k in 1...3 {
            run.follower.advance(try buffer(shift: CGPoint(x: 40 + 4 * CGFloat(k), y: -10)), headAnchors: headAnchors)
        }
        let refreshed = try XCTUnwrap(run.follower.refresh(fused, headAnchors: headAnchors))
        let after = try XCTUnwrap(refreshed.subjectRight).outerCorner
        XCTAssertEqual(after.x - before.x, 12, accuracy: 3, "the newest camera frames are already in the picture")
    }

    func testRefreshIsNilWhenNothingIsFollowed() throws {
        let run = try simulate(hand: 0, distance: .zero, pullFrames: 4, holdFrames: 4)
        XCTAssertNil(run.follower.refresh(try XCTUnwrap(run.lastFused), headAnchors: headAnchors))
    }
}
