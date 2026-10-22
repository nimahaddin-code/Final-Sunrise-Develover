import XCTest
import simd
@testable import SunriseApp

final class HeadPoseTests: XCTestCase {
    /// Face at the world origin, rotated by `yaw` about +y and then `pitch` about +x.
    private func face(yaw: Float = 0, pitch: Float = 0) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
    }

    private func camera(at position: SIMD3<Float>) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(position, 1)
        return transform
    }

    func testFacingCameraAtArmsLengthNeedsNoAdjustment() {
        let pose = HeadPose(face: face(), camera: camera(at: SIMD3(0, 0, 0.4)))
        XCTAssertEqual(pose.distance, 0.4, accuracy: 1e-5)
        XCTAssertEqual(pose.yaw, 0, accuracy: 1e-5)
        XCTAssertEqual(pose.pitch, 0, accuracy: 1e-5)
        XCTAssertNil(pose.adjustment)
    }

    func testTurnedHeadIsToldWhichWayToTurn() {
        // Head turned 20° to the person's right (toward -x), so the camera is off to their left.
        let turnedRight = HeadPose(face: face(yaw: -.pi / 9), camera: camera(at: SIMD3(0, 0, 0.4)))
        XCTAssertEqual(turnedRight.yaw, .pi / 9, accuracy: 1e-4)
        XCTAssertEqual(turnedRight.adjustment, .turnLeft)
        XCTAssertEqual(HeadPose(face: face(yaw: .pi / 9), camera: camera(at: SIMD3(0, 0, 0.4))).adjustment, .turnRight)
        XCTAssertNil(HeadPose(face: face(yaw: .pi / 30), camera: camera(at: SIMD3(0, 0, 0.4))).adjustment)
    }

    func testPhoneAboveOrBelowEyeLevelIsToldToMove() {
        let below = HeadPose(face: face(), camera: camera(at: SIMD3(0, -0.2, 0.4)))
        XCTAssertLessThan(below.pitch, -HeadPose.maxPitch)
        XCTAssertEqual(below.adjustment, .raisePhone)
        XCTAssertEqual(HeadPose(face: face(), camera: camera(at: SIMD3(0, 0.2, 0.4))).adjustment, .lowerPhone)
        // A chin tipped down puts the camera above the face's line of sight, same as a high phone.
        XCTAssertEqual(HeadPose(face: face(pitch: .pi / 9), camera: camera(at: SIMD3(0, 0, 0.4))).adjustment, .lowerPhone)
    }

    func testDistanceIsCheckedFirst() {
        XCTAssertEqual(HeadPose(face: face(yaw: .pi / 4), camera: camera(at: SIMD3(0, 0, 0.15))).adjustment, .moveBack)
        XCTAssertEqual(HeadPose(face: face(), camera: camera(at: SIMD3(0, 0, 0.9))).adjustment, .moveCloser)
    }
}
