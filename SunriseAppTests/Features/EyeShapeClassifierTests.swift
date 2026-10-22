import XCTest
@testable import SunriseApp

final class EyeShapeClassifierTests: XCTestCase {
    private let classifier = EyeShapeClassifier()

    private func measurements(openness: Float = 0.3, tilt: Float = 4, spacing: Float = 1, lidSpace: Float = 1.2) -> EyeMeasurements {
        EyeMeasurements(openness: openness, tilt: tilt, spacing: spacing, lidSpace: lidSpace)
    }

    func testTypicalEyesAreAlmondStraightAndEvenlySpaced() {
        let result = classifier.classify(measurements())
        XCTAssertEqual(result.openness, .almond)
        XCTAssertEqual(result.tilt, .straight)
        XCTAssertEqual(result.spacing, .balanced)
        XCTAssertFalse(result.mayBeHooded)
        XCTAssertNil(result.lid, "the eyelid is chosen by the person, never guessed")
    }

    func testRoundUpturnedWideSetEyes() {
        let result = classifier.classify(measurements(openness: 0.46, tilt: 11, spacing: 1.3))
        XCTAssertEqual(result.openness, .round)
        XCTAssertEqual(result.tilt, .upturned)
        XCTAssertEqual(result.spacing, .wide)
    }

    func testDownturnedCloseSetEyes() {
        let result = classifier.classify(measurements(tilt: -3, spacing: 0.8))
        XCTAssertEqual(result.tilt, .downturned)
        XCTAssertEqual(result.spacing, .close)
    }

    func testSmallBrowToLidGapFlagsPossibleHoodedLid() {
        XCTAssertTrue(classifier.classify(measurements(lidSpace: 0.5)).mayBeHooded)
        XCTAssertFalse(classifier.classify(measurements(lidSpace: 1.4)).mayBeHooded)
    }

    func testConfidenceIsZeroOnAThresholdAndFullWellAwayFromIt() {
        let t = classifier.thresholds
        XCTAssertEqual(classifier.classify(measurements(openness: t.roundOpenness)).confidence, 0, accuracy: 1e-6)
        XCTAssertEqual(classifier.classify(measurements(openness: t.roundOpenness)).openness, .round)
        XCTAssertEqual(classifier.classify(measurements(tilt: 4, spacing: 1.025)).confidence, 1, accuracy: 1e-6)
    }

    func testConfidenceIsTheLeastCertainAttribute() {
        let t = classifier.thresholds
        // Openness and tilt are clear, but spacing is halfway between its threshold and full certainty.
        let result = classifier.classify(measurements(openness: 0.3, tilt: 4, spacing: t.wideSpacing + t.spacingBand / 2))
        XCTAssertEqual(result.confidence, 0.5, accuracy: 1e-4)
    }

    func testResultSurvivesEncodingAndKeepsThePersonsLidChoice() throws {
        var result = classifier.classify(measurements())
        result.lid = .hooded
        let decoded = try JSONDecoder().decode(EyeShapeResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.lid, .hooded)
    }
}
