import XCTest
@testable import SunriseApp

final class EyeScanTests: XCTestCase {
    private func eyes(tilt: Float = 4, spacing: Float = 1, openness: Float = 0.25,
                      lid: LidType = .neither) -> EyeScan {
        EyeScan(tiltLeft: tilt, tiltRight: tilt, spacing: spacing, openness: openness, samples: 8, lidType: lid)
    }

    private func score(_ shape: EyeShape, _ eyes: EyeScan) -> Float { eyes.scores[shape] ?? -1 }

    // MARK: Thresholds

    func testTiltScoresRampAwayFromTheTypicalTilt() {
        XCTAssertEqual(score(.upturned, eyes(tilt: 7)), 0, accuracy: 1e-5)
        XCTAssertEqual(score(.upturned, eyes(tilt: 12)), 1, accuracy: 1e-5)
        XCTAssertEqual(score(.upturned, eyes(tilt: 4)), 0)
        XCTAssertEqual(score(.downturned, eyes(tilt: 1)), 0, accuracy: 1e-5)
        XCTAssertEqual(score(.downturned, eyes(tilt: -4)), 1, accuracy: 1e-5)
        XCTAssertEqual(score(.downturned, eyes(tilt: 4)), 0)
    }

    func testSpacingUsesOneEyeWidthAsTheThreshold() {
        XCTAssertEqual(score(.closeSet, eyes(spacing: 1)), 0)
        XCTAssertEqual(score(.wideSet, eyes(spacing: 1)), 0)
        XCTAssertEqual(score(.closeSet, eyes(spacing: 0.85)), 1, accuracy: 1e-5)
        XCTAssertEqual(score(.wideSet, eyes(spacing: 1.15)), 1, accuracy: 1e-5)
        XCTAssertGreaterThan(score(.closeSet, eyes(spacing: 0.95)), 0)
        XCTAssertEqual(score(.wideSet, eyes(spacing: 0.95)), 0)
    }

    func testOpennessSeparatesRoundFromAlmond() {
        XCTAssertEqual(score(.round, eyes(openness: 0.30)), 0, accuracy: 1e-5)
        XCTAssertEqual(score(.round, eyes(openness: 0.40)), 1, accuracy: 1e-5)
        XCTAssertEqual(score(.almond, eyes(openness: 0.25)), EyeScan.almondBaseline, accuracy: 1e-5)
        XCTAssertEqual(score(.almond, eyes(openness: 0.45)), 0, accuracy: 1e-5)
    }

    func testHoodedAndMonolidOnlyScoreWhenChosen() {
        XCTAssertEqual(score(.hooded, eyes()), 0)
        XCTAssertEqual(score(.monolid, eyes()), 0)
        XCTAssertEqual(score(.hooded, eyes(lid: .hooded)), 1)
        XCTAssertEqual(score(.monolid, eyes(lid: .monolid)), 1)
    }

    func testRankingWeighsScoresByTheResearchConfidence() {
        // Upturned is fully present but the research trusts it less than a two-thirds-present close-set reading.
        let ranked = eyes(tilt: 12, spacing: 0.9).ranked
        XCTAssertEqual(ranked.map(\.shape).prefix(2), [.closeSet, .upturned])
        XCTAssertEqual(ranked[1].weighted, 0.5, accuracy: 1e-5)
    }

    // MARK: Confidence (R7, R8)

    func testLowConfidenceCases() {
        XCTAssertFalse(eyes().isLowConfidence, "A plain almond reading is trusted")
        XCTAssertTrue(eyes(openness: 0.10).isLowConfidence, "Eyes closed")
        XCTAssertTrue(EyeScan(tiltLeft: 8, tiltRight: 0, spacing: 1, openness: 0.25, samples: 8).isLowConfidence,
                      "Left and right disagree")
        // Between almond and round: neither scores high enough once weighted (almond .24, round .24).
        XCTAssertTrue(eyes(openness: 0.34).isLowConfidence)
        XCTAssertFalse(eyes(openness: 0.32).isLowConfidence)
        XCTAssertFalse(eyes(openness: 0.38).isLowConfidence)
    }

    // MARK: Sample gate

    func testGateAcceptsOnlyStraightOpenEyes() {
        func verdict(tracked: Bool = true, straight: Bool = true, blink: Float = 0, squint: Float = 0) -> EyeSampleGate.Verdict {
            EyeSampleGate.verdict(isTracked: tracked, headIsStraight: straight, blinkLeft: blink, blinkRight: 0,
                                  squintLeft: 0, squintRight: squint)
        }
        XCTAssertEqual(verdict(), .accept)
        XCTAssertEqual(verdict(tracked: false), .lookStraight)
        XCTAssertEqual(verdict(straight: false), .lookStraight)
        XCTAssertEqual(verdict(blink: 0.6), .openEyes)
        XCTAssertEqual(verdict(squint: 0.8), .openEyes)
    }

    // MARK: Stored with the scan

    func testEyesAreStoredWithTheFaceShapeResult() throws {
        let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
        var result = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
        result.eyes = eyes(tilt: 9, spacing: 0.9, openness: 0.33, lid: .monolid)
        let decoded = try JSONDecoder().decode(FaceShapeResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.eyes?.lidType, .monolid)
    }

    func testScansSavedWithoutEyesStillDecode() throws {
        let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
        let old = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
        XCTAssertNil(old.eyes)
        let decoded = try JSONDecoder().decode(FaceShapeResult.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.eyes)
    }
}
