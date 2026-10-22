import XCTest
import simd
@testable import SunriseApp

final class MakeupPersonalizationTests: XCTestCase {
    private let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))

    private func scan(length: Float = 1.15, forehead: Float = 0.85, jaw: Float = 0.8, chin: Float = 0.47) -> FaceShapeResult {
        classifier.classify(FaceProportions(length: length, forehead: forehead, jaw: jaw, chin: chin))
    }

    // MARK: Plan from the scan

    // -Nimah: Saved eye output drives Hanum's planner independently of face-shape labels.
    func testSavedEyeOutputOverridesOldFaceEyeReadings() throws {
        var eyes=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:1.5))
        eyes.lid = .monolid
        let plan=MakeupPlan(scan:scan(),eyeScan:eyes)
        let adapted=try XCTUnwrap(plan.eyes)
        XCTAssertEqual(adapted.spacing,0.72,accuracy:0.001)
        XCTAssertEqual(adapted.lidType,.monolid)
        XCTAssertEqual(adapted.samples,0)
        XCTAssertEqual(plan.eyeliner.style,MakeupPlan(shape:.heart,eyeScan:eyes).eyeliner.style)
        let defaultLid=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:0.1))
        XCTAssertEqual(MakeupPlan.savedEyeMeasurements(defaultLid)?.lidType,.neither)
    }

    func testUnclearSavedEyesUseNeutralRatherThanInventingResults() {
        let unclear=EyeShapeResult(openness:.almond,tilt:.straight,spacing:.balanced,mayBeHooded:false,lid:nil,
            measurements:EyeMeasurements(openness:0.30,tilt:4,spacing:1,lidSpace:1),confidence:0)
        XCTAssertNil(MakeupPlan.savedEyeMeasurements(unclear))
        XCTAssertTrue(MakeupPlan(scan:scan(),eyeScan:unclear).eyeliner.isNeutral)
    }

    @MainActor func testSavedFaceOpensPreviewWithoutAnotherScanPhase() {
        for region in [FaceGuideRegion.eyebrows,.blush] {
            let model=EyebrowViewModel(checker:MockFaceTrackingChecker(),assessment:.init(shape:.heart,origin:.analysis),initialRegion:region)
            XCTAssertEqual(model.phase,.chooseStyle)
            XCTAssertTrue(model.backLeavesStudio)
            XCTAssertEqual(model.configuration.region,region)
            XCTAssertTrue(model.liveConfiguration.showMakeupPreview)
            model.beginTutorial()
            XCTAssertEqual(model.phase,.tutorial)
            XCTAssertFalse(model.backLeavesStudio)
        }
    }

    func testPlanBlendsClosestShapesAndPutsMadeForYouFirst() {
        let result = scan()
        let plan = MakeupPlan(scan: result)
        XCTAssertEqual(plan.shape, result.shape)
        XCTAssertEqual(plan.blend.first?.shape, result.shape)
        XCTAssertEqual(plan.blend.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(plan.blend.count, 3)
        for category in [MakeupCategory.eyeliner] {
            let items = plan.recommendations(in: category)
            XCTAssertTrue(MakeupPlan.isMadeForYou(items[0]))
            XCTAssertEqual(items.filter(MakeupPlan.isMadeForYou).count, 1)
        }
        XCTAssertEqual(plan.madeForYou.map(\.category), [.eyeliner])
    }

    func testChosenShapeUsesOnlyThatShape() {
        let plan = MakeupPlan(scan: scan(), chosenShape: .diamond)
        XCTAssertEqual(plan.shape, .diamond)
        XCTAssertEqual(plan.blend, [ShapeWeight(shape: .diamond, weight: 1)])
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
        XCTAssertEqual(fit.eyeOpenness, 0.33, accuracy: 0.03) // 0.04 high over 0.12 wide
        XCTAssertEqual(fit.eyeScan(samples: 5).samples, 5)
        XCTAssertEqual(fit.spacing, .balanced)
        XCTAssertEqual(fit.left.noseWing, SIMD2(0.53, 0.55))
        XCTAssertEqual(fit.right.noseWing, SIMD2(0.47, 0.55))
        XCTAssertEqual(try XCTUnwrap(fit.left.noseDepth), 0.75, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(FaceFit(features: features(tilt: 10))).tilt, .up)
        XCTAssertEqual(try XCTUnwrap(FaceFit(features: features(halfWidth: 0.07))).spacing, .close)
    }






}
