import XCTest
@testable import SunriseApp

final class CameraMessageEngineTests: XCTestCase {
    private func good() -> CameraSignals {
        var s = CameraSignals()
        s.faceTracked = true
        s.ambientIntensity = 800
        s.distance = 0.35
        s.yawDegrees = 3
        s.tiltDegrees = 8
        s.speed = 0.02
        s.turnRate = 5
        return s
    }

    func testNothingShowsWhenSetupIsGood() {
        var engine = CameraMessageEngine(context: .tryOn)
        for step in 0..<30 { XCTAssertNil(engine.update(good(), at: Double(step) * 0.1)) }
    }

    func testDarkShowsOnlyAfterOneSecond() {
        var engine = CameraMessageEngine(context: .tryOn)
        var dark = good(); dark.ambientIntensity = 200
        XCTAssertNil(engine.update(dark, at: 0))
        XCTAssertNil(engine.update(dark, at: 0.9))
        XCTAssertEqual(engine.update(dark, at: 1.0), .tooDark)
    }

    func testMessageHidesHalfASecondAfterTheProblemClears() {
        var engine = CameraMessageEngine(context: .tryOn)
        var dark = good(); dark.ambientIntensity = 200
        _ = engine.update(dark, at: 0)
        XCTAssertEqual(engine.update(dark, at: 1.0), .tooDark)
        XCTAssertEqual(engine.update(good(), at: 1.1), .tooDark)
        XCTAssertEqual(engine.update(good(), at: 1.5), .tooDark)
        XCTAssertNil(engine.update(good(), at: 1.7))
    }

    func testDarkHysteresisKeepsTheMessageBetweenShowAndClearValues() {
        var engine = CameraMessageEngine(context: .tryOn)
        var dark = good(); dark.ambientIntensity = 200
        _ = engine.update(dark, at: 0)
        XCTAssertEqual(engine.update(dark, at: 1.0), .tooDark)
        // 350 lm is above the show value (300) but below the clear value (400): still dark.
        var edge = good(); edge.ambientIntensity = 350
        XCTAssertEqual(engine.update(edge, at: 2.0), .tooDark)
        XCTAssertEqual(engine.update(edge, at: 4.0), .tooDark)
        var bright = good(); bright.ambientIntensity = 450
        _ = engine.update(bright, at: 5.0)
        XCTAssertNil(engine.update(bright, at: 5.6))
    }

    func testStartingAtTheEdgeDoesNotShow() {
        var engine = CameraMessageEngine(context: .tryOn)
        var edge = good(); edge.ambientIntensity = 350
        for step in 0..<40 { XCTAssertNil(engine.update(edge, at: Double(step) * 0.1)) }
    }

    func testHigherPriorityWinsAndLowerOneTakesOverWhenItClears() {
        var engine = CameraMessageEngine(context: .tryOn)
        var both = good(); both.ambientIntensity = 100; both.distance = 0.1
        _ = engine.update(both, at: 0)
        XCTAssertEqual(engine.update(both, at: 1.0), .tooDark)
        var closeOnly = good(); closeOnly.distance = 0.1
        _ = engine.update(closeOnly, at: 1.1)
        XCTAssertEqual(engine.update(closeOnly, at: 1.7), .tooClose)
    }

    func testNoFaceInTryOn() {
        var engine = CameraMessageEngine(context: .tryOn)
        var none = CameraSignals(); none.ambientIntensity = 800
        _ = engine.update(none, at: 0)
        XCTAssertEqual(engine.update(none, at: 1.0), .noFace)
    }

    func testTutorialBeforeAnyFaceSaysNoFace() {
        var engine = CameraMessageEngine(context: .tutorial)
        var none = CameraSignals(); none.ambientIntensity = 800
        _ = engine.update(none, at: 0)
        XCTAssertEqual(engine.update(none, at: 1.0), .noFace)
    }

    func testTutorialFaceLostMidStepWaitsTwoSecondsAndNeverSaysNoFace() {
        var engine = CameraMessageEngine(context: .tutorial)
        _ = engine.update(good(), at: 0)
        var lost = CameraSignals(); lost.ambientIntensity = 800
        XCTAssertNil(engine.update(lost, at: 1))
        XCTAssertNil(engine.update(lost, at: 2.5))
        XCTAssertEqual(engine.update(lost, at: 3.0), .faceLost)
    }

    func testFaceCoveredIsTryOnOnly() {
        var covered = good(); covered.faceCovered = true
        var tryOn = CameraMessageEngine(context: .tryOn)
        _ = tryOn.update(covered, at: 0)
        XCTAssertEqual(tryOn.update(covered, at: 1.0), .faceCovered)
        var tutorial = CameraMessageEngine(context: .tutorial)
        _ = tutorial.update(covered, at: 0)
        XCTAssertNil(tutorial.update(covered, at: 2.0))
    }

    func testMovingFastIsSoftAndWaitsOneAndAHalfSeconds() {
        var engine = CameraMessageEngine(context: .tryOn)
        var fast = good(); fast.speed = 0.5
        _ = engine.update(fast, at: 0)
        XCTAssertNil(engine.update(fast, at: 1.2))
        XCTAssertEqual(engine.update(fast, at: 1.5), .movingFast)
    }

    func testHeadTurnedOnlyWhenStronglyTurned() {
        var strong = good(); strong.yawDegrees = 50
        var engine = CameraMessageEngine(context: .tryOn)
        _ = engine.update(strong, at: 0)
        XCTAssertEqual(engine.update(strong, at: 1), .headTurned)
        // A moderate turn keeps the filter on and says nothing.
        var moderate = good(); moderate.yawDegrees = 35
        var other = CameraMessageEngine(context: .tryOn)
        for step in 0..<30 { XCTAssertNil(other.update(moderate, at: Double(step) * 0.1)) }
    }

    func testTiltingTheHeadSidewaysSaysNothing() {
        // Roll is no longer measured at all: a tilted head looks like a good setup.
        var engine = CameraMessageEngine(context: .tryOn)
        for step in 0..<30 { XCTAssertNil(engine.update(good(), at: Double(step) * 0.1)) }
    }

    func testTrackingLostRightAfterBeingCloseSaysMoveBack() {
        var engine = CameraMessageEngine(context: .tryOn)
        var near = good(); near.distance = 0.27
        _ = engine.update(near, at: 0)
        var lost = CameraSignals(); lost.ambientIntensity = 800
        _ = engine.update(lost, at: 0.2)
        XCTAssertEqual(engine.update(lost, at: 1.3), .tooClose)
    }

    func testTrackingLostRightAfterTurningAwaySaysFaceStraight() {
        var engine = CameraMessageEngine(context: .tryOn)
        var turned = good(); turned.yawDegrees = 40
        _ = engine.update(turned, at: 0)
        var lost = CameraSignals(); lost.ambientIntensity = 800
        _ = engine.update(lost, at: 0.2)
        XCTAssertEqual(engine.update(lost, at: 1.3), .headTurned)
    }

    func testTrackingLostFarAwayStillSaysNoFace() {
        var engine = CameraMessageEngine(context: .tryOn)
        _ = engine.update(good(), at: 0)
        var lost = CameraSignals(); lost.ambientIntensity = 800
        _ = engine.update(lost, at: 0.2)
        XCTAssertEqual(engine.update(lost, at: 1.3), .noFace)
    }

    func testDistanceAndTiltMessages() {
        var far = good(); far.distance = 0.7
        var engine = CameraMessageEngine(context: .tryOn)
        _ = engine.update(far, at: 0)
        XCTAssertEqual(engine.update(far, at: 1), .tooFar)
        var tilted = good(); tilted.tiltDegrees = 40
        var other = CameraMessageEngine(context: .tryOn)
        _ = other.update(tilted, at: 0)
        XCTAssertEqual(other.update(tilted, at: 1), .tiltedPhone)
    }

    func testMoreThanOneFaceAndBacklight() {
        var crowd = good(); crowd.faceCount = 2
        var engine = CameraMessageEngine(context: .tutorial)
        _ = engine.update(crowd, at: 0)
        XCTAssertEqual(engine.update(crowd, at: 1), .multipleFaces)
        var backlit = good(); backlit.faceLumaRatio = 0.4
        var other = CameraMessageEngine(context: .tutorial)
        _ = other.update(backlit, at: 0)
        XCTAssertEqual(other.update(backlit, at: 1), .backlit)
    }

    func testResetForgetsTheFaceSeenBefore() {
        var engine = CameraMessageEngine(context: .tutorial)
        _ = engine.update(good(), at: 0)
        engine.reset()
        var none = CameraSignals(); none.ambientIntensity = 800
        _ = engine.update(none, at: 0)
        XCTAssertEqual(engine.update(none, at: 1.0), .noFace)
    }

    func testPriorityOrderMatchesTheSpec() {
        XCTAssertEqual(Array(CameraMessage.allCases.sorted().dropFirst()),
                       [.tooDark, .backlit, .noFace, .faceLost, .multipleFaces, .faceCovered, .tooClose, .tooFar,
                        .tiltedPhone, .headTurned, .movingFast])
    }
}
