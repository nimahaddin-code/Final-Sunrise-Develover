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

import XCTest
@testable import SunriseApp

final class EyeScanGuideTests: XCTestCase {
    /// The synthetic eyes' centres are about 60 points apart, so a 300-wide image puts them at 0.2 of the width.
    private func evaluate(_ eyes: SyntheticEyes = SyntheticEyes(), headTurn: Float? = 0, imageWidth: Float = 300) -> EyeScanFrame {
        var landmarks = eyes.landmarks()
        landmarks.headTurn = headTurn
        return EyeScanGuide.evaluate(landmarks, imageWidth: imageWidth)
    }

    func testNoFaceAsksToFindTheFace() {
        XCTAssertEqual(EyeScanGuide.evaluate(nil, imageWidth: 300), EyeScanFrame(guidance: .findFace))
    }

    func testGoodFrameCountsAndCarriesItsMeasurements() throws {
        let frame = evaluate()
        XCTAssertEqual(frame.guidance, .holdStill)
        XCTAssertEqual(try XCTUnwrap(frame.measurements).openness, 0.3, accuracy: 1e-3)
    }

    func testTooFarAndTooCloseAreToldApart() {
        XCTAssertEqual(evaluate(imageWidth: 1000).guidance, .moveCloser)
        XCTAssertEqual(evaluate(imageWidth: 100).guidance, .moveBack)
        XCTAssertNil(evaluate(imageWidth: 1000).measurements)
    }

    func testTurnedHeadAndClosedEyesDoNotCount() {
        XCTAssertEqual(evaluate(headTurn: 0.3).guidance, .lookStraight)
        XCTAssertEqual(evaluate(headTurn: -0.3).guidance, .lookStraight)
        XCTAssertEqual(evaluate(headTurn: 0.05).guidance, .holdStill)
        XCTAssertEqual(evaluate(SyntheticEyes(openness: 0.05)).guidance, .openEyes)
        XCTAssertNil(evaluate(SyntheticEyes(openness: 0.05)).measurements)
    }
}

@MainActor final class EyeScanViewModelTests: XCTestCase {
    private let good = EyeScanFrame(guidance: .holdStill,
                                    measurements: EyeMeasurements(openness: 0.3, tilt: 4, spacing: 1, lidSpace: 1.2))

    func testIgnoresFramesUntilScanning() {
        let model = EyeScanViewModel()
        model.handle(good)
        XCTAssertEqual(model.phase, .idle)
    }

    func testBadFramesShowGuidanceWithoutProgress() {
        let model = EyeScanViewModel()
        model.resetMeasurements()
        model.handle(EyeScanFrame(guidance: .lookStraight))
        XCTAssertEqual(model.phase, .scanning(progress: 0, guidance: .lookStraight))
    }

    func testEnoughGoodFramesFinishWithAClassifiedResult() throws {
        let model = EyeScanViewModel()
        model.resetMeasurements()
        for _ in 0..<(EyeScanViewModel.requiredSamples / 2) { model.handle(good) }
        XCTAssertEqual(model.phase, .scanning(progress: 0.5, guidance: .holdStill))
        for _ in 0..<(EyeScanViewModel.requiredSamples / 2) { model.handle(good) }
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(result.openness, .almond)
        XCTAssertEqual(result.tilt, .straight)
        XCTAssertEqual(result.spacing, .balanced)
        XCTAssertNil(result.lid)
    }

    func testFinishedScanKeepsItsResultAndTakesTheEyelidChoice() throws {
        let model = EyeScanViewModel()
        model.resetMeasurements()
        for _ in 0..<EyeScanViewModel.requiredSamples { model.handle(good) }
        let finished = try XCTUnwrap(model.result)
        model.handle(EyeScanFrame(guidance: .lookStraight))
        XCTAssertEqual(model.result, finished, "late frames must not disturb a finished scan")
        model.chooseLid(.hooded)
        XCTAssertEqual(model.result?.lid, .hooded)
        model.chooseLid(nil)
        XCTAssertNil(model.result?.lid)
    }

    func testBlinksAreLeftOutOfTheMedian() throws {
        let model = EyeScanViewModel()
        model.resetMeasurements()
        // A blink frame has no measurements, so it never reaches the sampler.
        for index in 0..<EyeScanViewModel.requiredSamples * 2 {
            model.handle(index.isMultiple(of: 2) ? good : EyeScanFrame(guidance: .openEyes))
        }
        XCTAssertEqual(try XCTUnwrap(model.result).measurements.openness, 0.3, accuracy: 1e-6)
    }
}

@MainActor final class FaceShapeStoreEyesTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "EyeScanTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private let eyes = EyeShapeClassifier().classify(EyeMeasurements(openness: 0.45, tilt: 9, spacing: 1.2, lidSpace: 0.6))

    func testEyesSurviveARelaunch() throws {
        let defaults = try makeDefaults()
        let store = FaceShapeStore(defaults: defaults)
        XCTAssertNil(store.eyes)
        var chosen = eyes
        chosen.lid = .monolid
        store.eyes = chosen
        XCTAssertEqual(FaceShapeStore(defaults: defaults).eyes, chosen)
    }

    func testEyesAndFaceShapeAreKeptIndependently() throws {
        let defaults = try makeDefaults()
        let store = FaceShapeStore(defaults: defaults)
        store.eyes = eyes
        XCTAssertNil(FaceShapeStore(defaults: defaults).latest, "an eye scan alone is not a face shape")
        store.latest = nil
        XCTAssertEqual(FaceShapeStore(defaults: defaults).eyes, eyes, "clearing the face shape keeps the eyes")
        store.eyes = nil
        XCTAssertNil(FaceShapeStore(defaults: defaults).eyes)
    }
}

final class EyeScanLevelTests: XCTestCase {
    /// A pose 40 cm in front of the camera, pitched by `angle` (positive turns the face's forward direction up, toward +y).
    private func pose(pitch angle: Float, columnMajor: Bool) -> [Float] {
        let c = cos(angle), s = sin(angle)
        // Rotation about x taking (0, 0, 1) to (0, sin, cos); rows of R.
        let rows: [[Float]] = [[1, 0, 0, 0], [0, c, s, 0], [0, -s, c, -40], [0, 0, 0, 1]]
        return columnMajor ? (0..<4).flatMap { column in rows.map { $0[column] } } : rows.flatMap { $0 }
    }

    func testPitchIsReadInEitherStorageOrder() throws {
        for columnMajor in [true, false] {
            let angle: Float = 0.3
            XCTAssertEqual(try XCTUnwrap(EyeScanLandmarks.pitch(fromPoseMatrix: pose(pitch: angle, columnMajor: columnMajor))),
                           angle, accuracy: 1e-5, "columnMajor \(columnMajor)")
            XCTAssertEqual(try XCTUnwrap(EyeScanLandmarks.pitch(fromPoseMatrix: pose(pitch: 0, columnMajor: columnMajor))), 0, accuracy: 1e-6)
        }
    }

    func testUnusableMatricesGiveNoPitch() {
        XCTAssertNil(EyeScanLandmarks.pitch(fromPoseMatrix: [1, 2, 3]))
        XCTAssertNil(EyeScanLandmarks.pitch(fromPoseMatrix: pose(pitch: .pi, columnMajor: true)), "face pointing away")
    }

    private func evaluate(pitch: Float?) -> EyeScanFrame {
        var landmarks = SyntheticEyes().landmarks()
        landmarks.headTurn = 0
        landmarks.headPitch = pitch
        return EyeScanGuide.evaluate(landmarks, imageWidth: 300)
    }

    func testOnlyFramesNearEyeLevelCount() {
        XCTAssertEqual(evaluate(pitch: 0).guidance, .holdStill)
        XCTAssertEqual(evaluate(pitch: 0.1).guidance, .holdStill)
        XCTAssertEqual(evaluate(pitch: nil).guidance, .holdStill)
        XCTAssertEqual(evaluate(pitch: 0.3).guidance, .raisePhone)
        XCTAssertEqual(evaluate(pitch: -0.3).guidance, .lowerPhone)
        XCTAssertNil(evaluate(pitch: 0.3).measurements)
        XCTAssertNil(evaluate(pitch: -0.3).measurements)
    }
}
