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
