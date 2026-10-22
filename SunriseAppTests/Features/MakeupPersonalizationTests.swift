import XCTest
import simd
@testable import SunriseApp

final class MakeupPersonalizationTests: XCTestCase {
    private let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))

    private func scan(length: Float = 1.15, forehead: Float = 0.85, jaw: Float = 0.8, chin: Float = 0.47) -> FaceShapeResult {
        classifier.classify(FaceProportions(length: length, forehead: forehead, jaw: jaw, chin: chin))
    }

    // MARK: Plan from the scan

    func testPlanBlendsClosestShapesAndPutsMadeForYouFirst() {
        let result = scan()
        let plan = MakeupPlan(scan: result)
        XCTAssertEqual(plan.shape, result.shape)
        XCTAssertEqual(plan.blend.first?.shape, result.shape)
        XCTAssertEqual(plan.blend.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(plan.blend.count, 3)
        for category in MakeupCategory.allCases {
            let items = plan.recommendations(in: category)
            XCTAssertTrue(MakeupPlan.isMadeForYou(items[0]))
            XCTAssertEqual(items.filter(MakeupPlan.isMadeForYou).count, 1)
        }
        XCTAssertEqual(plan.madeForYou.map(\.category), MakeupCategory.allCases)
    }

    func testChosenShapeUsesOnlyThatShape() {
        let plan = MakeupPlan(scan: scan(), chosenShape: .diamond)
        XCTAssertEqual(plan.shape, .diamond)
        XCTAssertEqual(plan.blend, [ShapeWeight(shape: .diamond, weight: 1)])
    }

    func testSingleShapeWithAverageProportionsMatchesItsBestStyle() {
        let plan = MakeupPlan(shape: .round)
        guard case .eyebrow(let personal) = plan.madeForYou[0].style,
              case .eyebrow(let best) = MakeupRecommender.recommendations(for: .round, in: .eyebrow)[0].style else {
            return XCTFail("Expected eyebrow styles")
        }
        XCTAssertEqual(personal.archHeight, best.archHeight, accuracy: 1e-6)
        XCTAssertEqual(personal.archPosition, best.archPosition, accuracy: 1e-6)
        XCTAssertEqual(personal.tailExtension, best.tailExtension, accuracy: 1e-6)
    }

    func testLongerFaceGetsFlatterBrowAndFlatterBlush() {
        let base = MakeupRecommender.recommendations(for: .oval, in: .eyebrow)[0]
        guard case .eyebrow(let brow) = base.style else { return XCTFail() }
        let longer = MakeupPersonalizer.eyebrow([(brow, 1)], shade: brow.shade,
                                                deviation: FaceProportions(length: 0.06, forehead: 0, jaw: 0, chin: 0))
        let shorter = MakeupPersonalizer.eyebrow([(brow, 1)], shade: brow.shade,
                                                 deviation: FaceProportions(length: -0.06, forehead: 0, jaw: 0, chin: 0))
        XCTAssertLessThan(longer.archHeight, shorter.archHeight)

        guard case .blush(let blush) = MakeupRecommender.recommendations(for: .oval, in: .blush)[0].style else {
            return XCTFail()
        }
        let longBlush = MakeupPersonalizer.blush([(blush, 1)], shade: blush.shade,
                                                 deviation: FaceProportions(length: 0.06, forehead: 0, jaw: 0, chin: 0))
        XCTAssertLessThan(longBlush.tilt, blush.tilt)
        XCTAssertGreaterThan(longBlush.radii.x, blush.radii.x)
    }

    // MARK: Fit to measured features

    /// A face in texture space: v grows downward, the left eye is at larger u. `halfWidth` is half an eye's width.
    private func features(tilt degrees: Float = 4, halfWidth: Float = 0.06) -> FaceFeatureMap {
        func side(_ centerX: Float, outward: Float) -> FaceFeatureMap.Side {
            let lift = halfWidth * tan(degrees * .pi / 180)
            return FaceFeatureMap.Side(
                brow: [SIMD2(centerX - outward * 0.05, 0.33), SIMD2(centerX + outward * 0.02, 0.31),
                       SIMD2(centerX + outward * 0.08, 0.32)],
                eye: [SIMD2(centerX - outward * halfWidth, 0.40 + lift), SIMD2(centerX, 0.38),
                      SIMD2(centerX + outward * halfWidth, 0.40 - lift), SIMD2(centerX, 0.42)])
        }
        return FaceFeatureMap(left: side(0.62, outward: 1), right: side(0.38, outward: -1),
                              nose: [SIMD2(0.5, 0.42), SIMD2(0.47, 0.55), SIMD2(0.5, 0.58), SIMD2(0.53, 0.55)])
    }

    func testMeasuresEyeTiltSpacingAndNose() throws {
        let fit = try XCTUnwrap(FaceFit(features: features(tilt: -3)))
        XCTAssertEqual(fit.eyeTilt, -3, accuracy: 0.5)
        XCTAssertEqual(fit.tilt, .down)
        XCTAssertEqual(fit.eyeSpacing, 1, accuracy: 0.01) // a tilted eye is slightly wider
        XCTAssertEqual(fit.spacing, .balanced)
        XCTAssertEqual(fit.left.noseWing, SIMD2(0.53, 0.55))
        XCTAssertEqual(fit.right.noseWing, SIMD2(0.47, 0.55))
        XCTAssertEqual(try XCTUnwrap(fit.left.noseDepth), 0.75, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(FaceFit(features: features(tilt: 10))).tilt, .up)
        XCTAssertEqual(try XCTUnwrap(FaceFit(features: features(halfWidth: 0.07))).spacing, .close)
    }

    func testLinerWingCompensatesForEyeTiltAndSpacing() throws {
        let style = LinerStyle(innerWidth: 0.02, outerWidth: 0.06, start: 0.1, wingLength: 0.2, wingAngle: 18,
                               shade: MakeupPalette.black)
        let down = MakeupFitter.eyeliner(style, fit: try XCTUnwrap(FaceFit(features: features(tilt: -2))))
        let up = MakeupFitter.eyeliner(style, fit: try XCTUnwrap(FaceFit(features: features(tilt: 10))))
        XCTAssertGreaterThan(down.wingAngle, style.wingAngle)
        XCTAssertLessThan(up.wingAngle, style.wingAngle)
        let closeSet = MakeupFitter.eyeliner(style, fit: try XCTUnwrap(FaceFit(features: features(halfWidth: 0.07))))
        XCTAssertGreaterThan(closeSet.start, style.start)
    }

    func testBlushStaysAboveTheNoseTipAndBelowTheEye() throws {
        let fit = try XCTUnwrap(FaceFit(features: features()))
        let style = BlushStyle(center: SIMD2(0.05, 0.6), radii: SIMD2(0.3, 0.2), tilt: 10, shade: MakeupPalette.rose)
        let fitted = MakeupFitter.blush(style, side: fit.left)
        let depth = try XCTUnwrap(fit.left.noseDepth)
        XCTAssertLessThanOrEqual(fitted.center.y + style.radii.y * 0.6, depth + 1e-5)
        XCTAssertGreaterThanOrEqual(fitted.center.y - style.radii.y * 0.8, 0.15 - 1e-5)
    }

    func testBrowEndsMoveTowardTheGuideLines() throws {
        let map = features()
        let fit = try XCTUnwrap(FaceFit(features: map))
        let naturalHead = SIMD2<Float>(0.57, 0.33), naturalTail = SIMD2<Float>(0.70, 0.32)
        let guides = MakeupFitter.browGuides(side: fit.left, naturalHead: naturalHead, naturalTail: naturalTail)
        let frame = fit.left.frame
        // The nose-to-outer-corner line reaches the brow line outside the natural tail here.
        XCTAssertGreaterThan(guides.tail, frame.across(naturalTail))
        XCTAssertLessThan(guides.head, frame.across(naturalHead))
        XCTAssertGreaterThan(guides.peak, 0)
        XCTAssertLessThan(guides.peak, guides.tail)
    }

    func testLineIntersection() throws {
        let point = try XCTUnwrap(MakeupFitter.intersection(SIMD2(0, 0), SIMD2(1, 1), SIMD2(0, 1), SIMD2(1, 0)))
        XCTAssertEqual(point.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(point.y, 0.5, accuracy: 1e-6)
        XCTAssertNil(MakeupFitter.intersection(SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)))
    }
}
