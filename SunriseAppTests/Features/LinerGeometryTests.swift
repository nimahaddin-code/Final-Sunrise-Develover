import XCTest
import simd
@testable import SunriseApp

final class LinerGeometryTests: XCTestCase {
    /// An eye like Vision's: two corners plus three points on each lid. `outward` is +1 for the face's left side of
    /// the texture (right of the nose) and -1 for the other. Texture v grows downward.
    private func side(centerX: Float, outward: Float, contour: Int = 8) -> FaceFeatureMap.Side {
        func point(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(centerX + outward * x, 0.38 + y) }
        let eye: [SIMD2<Float>]
        switch contour {
        case 8:
            eye = [point(-0.04, 0.012), point(-0.02, -0.010), point(0, -0.015), point(0.02, -0.010),
                   point(0.04, 0.008), point(0.02, 0.022), point(0, 0.026), point(-0.02, 0.020)]
        default:
            // Corners only: no interior lid points at all.
            eye = [point(-0.04, 0.012), point(0.04, 0.008), point(0, 0.0)]
        }
        return FaceFeatureMap.Side(brow: [point(-0.05, -0.06), point(0, -0.08), point(0.06, -0.065)], eye: eye)
    }

    private func map(contour: Int = 8) -> FaceFeatureMap {
        FaceFeatureMap(left: side(centerX: 0.65, outward: 1, contour: contour),
                       right: side(centerX: 0.35, outward: -1, contour: contour))
    }

    private let shade = MakeupPalette.black
    private func style(start: Float = 0, wingLength: Float = 0.25, wingAngle: Float = 15,
                       lower: LowerLine = LowerLine()) -> LinerStyle {
        LinerStyle(innerWidth: 0.02, outerWidth: 0.06, start: start, wingLength: wingLength, wingAngle: wingAngle,
                   lowerLine: lower, shade: shade)
    }

    private func shape(_ style: LinerStyle, _ features: FaceFeatureMap, left: Bool) throws -> (LinerGeometry.Shape, FeatureFrame, FaceFeatureMap.Side) {
        let side = left ? features.left : features.right
        let frame = FeatureFrame(side: side, in: features)
        let shape = try XCTUnwrap(LinerGeometry.shape(style, eye: side.eye, brow: side.brow, frame: frame))
        return (shape, frame, side)
    }

    func testOutlinesAreNotEmptyForBothEyes() throws {
        for isLeft in [true, false] {
            let (shape, _, _) = try shape(style(), map(), left: isLeft)
            XCTAssertFalse(shape.outlines.isEmpty)
            XCTAssertTrue(shape.outlines.allSatisfy { $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        }
    }

    func testPositiveWingAngleLiftsTheTipAboveAndPastTheOuterCornerOnBothEyes() throws {
        for isLeft in [true, false] {
            let (shape, frame, side) = try shape(style(wingAngle: 20), map(), left: isLeft)
            let outer = side.eye.max { frame.across($0) < frame.across($1) }!
            let tip = try XCTUnwrap(shape.wingTip)
            XCTAssertGreaterThan(simd_dot(tip - outer, frame.up), 0.005, "tip should be above the outer corner")
            XCTAssertGreaterThan(simd_dot(tip - outer, frame.outward), 0.01, "tip should reach past the outer corner")
        }
    }

    func testStartLeavesTheInnerPartBare() throws {
        for isLeft in [true, false] {
            let bare = try shape(style(start: 0.5), map(), left: isLeft)
            let full = try shape(style(start: 0), map(), left: isLeft)
            func innermost(_ result: (LinerGeometry.Shape, FeatureFrame, FaceFeatureMap.Side)) -> Float {
                result.0.outlines.flatMap { $0 }.map { result.1.across($0) }.min()!
            }
            let inner = bare.2.eye.map { bare.1.across($0) }.min()!
            let width = bare.2.eye.map { bare.1.across($0) }.max()! - inner
            XCTAssertGreaterThan(innermost(bare), inner + width * 0.4)
            XCTAssertLessThan(innermost(full), inner + width * 0.1)
        }
    }

    func testLowerLineOnlyWhenEnabled() throws {
        let off = try shape(style(), map(), left: true).0
        let on = try shape(style(lower: LowerLine(enabled: true, extent: 0.5, thickness: 0.02)), map(), left: true).0
        XCTAssertFalse(off.hasLowerLine)
        XCTAssertTrue(on.hasLowerLine)
        XCTAssertEqual(on.outlines.count, off.outlines.count + 1)
    }

    func testLinerStaysOnTheUpperLidNotBelowTheEye() throws {
        for isLeft in [true, false] {
            let (shape, frame, side) = try shape(style(wingLength: 0), map(), left: isLeft)
            let lowest = shape.outlines.flatMap { $0 }.map { simd_dot($0 - side.eyeCenter, frame.up) }.min()!
            XCTAssertGreaterThan(lowest, -0.012, "liner must not hang below the lids")
        }
    }

    func testEyeWithoutInteriorLidPointsFallsBackToStraightLine() throws {
        for isLeft in [true, false] {
            let (shape, _, _) = try shape(style(), map(contour: 3), left: isLeft)
            XCTAssertFalse(shape.outlines.isEmpty)
        }
        XCTAssertEqual(LinerGeometry.localLashLine([]), [SIMD2(0, 0), SIMD2(1, 0)])
    }

    func testLashLineKeepsInteriorPointsOfAnEightPointContour() {
        let line = LinerGeometry.localLashLine([SIMD2(0.25, -0.1), SIMD2(0.5, -0.12), SIMD2(0.75, -0.1)])
        XCTAssertEqual(line.count, 5)
    }
}
