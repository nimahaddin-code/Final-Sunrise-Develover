// -Nimah: TrackingReadinessTests.swift — implementasi MVP SunriseApp.
import XCTest
@testable import SunriseApp

final class TrackingReadinessTests: XCTestCase {
    func testRequiresTwoSecondsOfContinuousTracking() {
        var readiness = TrackingReadiness()
        for i in 0..<20 { XCTAssertFalse(readiness.update(timestamp: Double(i) * 0.1, tracked: true, steady: true)) }
        XCTAssertTrue(readiness.update(timestamp: 2, tracked: true, steady: true))
    }
    func testTrackingLossMovementAndFrameGapsResetReadiness() {
        var readiness = TrackingReadiness()
        for i in 0...22 { _ = readiness.update(timestamp: Double(i) * 0.1, tracked: true, steady: true) }
        XCTAssertFalse(readiness.update(timestamp: 2.3, tracked: false, steady: true))
        XCTAssertFalse(readiness.update(timestamp: 2.4, tracked: true, steady: true))
        XCTAssertFalse(readiness.update(timestamp: 2.5, tracked: true, steady: false))
        XCTAssertFalse(readiness.update(timestamp: 9, tracked: true, steady: true))
    }
    func testBlushMaskAvoidsCenterAndBackOfFaceAndIsSymmetric() {
        XCTAssertEqual(BlushMask.weight(x: 0, y: -0.026, z: 0.04), 0)
        XCTAssertEqual(BlushMask.weight(x: 0.043, y: -0.026, z: -0.02), 0)
        let left = BlushMask.weight(x: -0.043, y: -0.026, z: 0.04)
        XCTAssertGreaterThan(left, 0)
        XCTAssertEqual(left, BlushMask.weight(x: 0.043, y: -0.026, z: 0.04))
    }
}
