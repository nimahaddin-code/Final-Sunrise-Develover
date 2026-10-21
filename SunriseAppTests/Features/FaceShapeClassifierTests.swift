import XCTest
@testable import SunriseApp

final class FaceShapeClassifierTests: XCTestCase {
    private let reference = FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5)

    private func face(matching shape: FaceShape, classifier: FaceShapeClassifier) -> FaceProportions {
        let offset = FaceShapeClassifier.prototypes[shape]! * classifier.unit + 1
        return FaceProportions(length: reference.length * offset[0], forehead: reference.forehead * offset[1],
                               jaw: reference.jaw * offset[2], chin: reference.chin * offset[3])
    }

    func testEachPrototypeIsClassifiedAsItsOwnShape() {
        let classifier = FaceShapeClassifier(reference: reference)
        for shape in FaceShape.allCases {
            let result = classifier.classify(face(matching: shape, classifier: classifier))
            XCTAssertEqual(result.shape, shape)
            XCTAssertNotEqual(result.runnerUp, shape)
        }
    }

    func testAverageFaceIsOval() {
        XCTAssertEqual(FaceShapeClassifier(reference: reference).classify(reference).shape, .oval)
    }

    func testScoresSumToOneAndRankingIsDescending() {
        let result = FaceShapeClassifier(reference: reference)
            .classify(FaceProportions(length: 1.3, forehead: 0.8, jaw: 0.85, chin: 0.55))
        XCTAssertEqual(result.scores.values.reduce(0, +), 1, accuracy: 1e-9)
        let ranked = result.rankedShapes.map(\.score)
        XCTAssertEqual(ranked, ranked.sorted(by: >))
        XCTAssertEqual(result.confidence, ranked[0])
    }

    func testDeviationIsRelativeToReference() {
        let deviation = FaceShapeClassifier(reference: reference)
            .deviation(of: FaceProportions(length: 1.32, forehead: 0.85, jaw: 0.72, chin: 0.5))
        XCTAssertEqual(deviation.length, 0.1, accuracy: 1e-5)
        XCTAssertEqual(deviation.forehead, 0, accuracy: 1e-5)
        XCTAssertEqual(deviation.jaw, -0.1, accuracy: 1e-5)
    }
}

final class FaceMeshMeasurerTests: XCTestCase {
    /// Builds a flat outline whose width at each height fraction (0 = chin, 1 = top) comes from `width`.
    private func outline(length: Float, width: (Float) -> Float) -> [SIMD3<Float>] {
        stride(from: Float(0), through: 1, by: 0.01).flatMap { fraction -> [SIMD3<Float>] in
            let half = width(fraction) / 2, y = fraction * length - 0.1
            return [SIMD3(-half, y, 0), SIMD3(0, y, 0.05), SIMD3(half, y, 0)]
        }
    }

    func testMeasuresBandWidthsRelativeToCheekbones() throws {
        let vertices = outline(length: 0.2) { fraction in
            switch fraction {
            case ..<0.12: 0.04
            case ..<0.4: 0.10
            case ..<0.75: 0.16
            default: 0.12
            }
        }
        let proportions = try XCTUnwrap(FaceMeshMeasurer.proportions(of: vertices))
        XCTAssertEqual(proportions.length, 0.2 / 0.16, accuracy: 1e-4)
        XCTAssertEqual(proportions.forehead, 0.12 / 0.16, accuracy: 1e-4)
        XCTAssertEqual(proportions.jaw, 0.10 / 0.16, accuracy: 1e-4)
        XCTAssertEqual(proportions.chin, 0.04 / 0.10, accuracy: 1e-4)
    }

    func testRejectsEmptyOrFlatMeshes() {
        XCTAssertNil(FaceMeshMeasurer.proportions(of: []))
        XCTAssertNil(FaceMeshMeasurer.proportions(of: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)]))
    }

    func testSamplerReportsProgressAndMedian() {
        var sampler = FaceProportionsSampler(requiredSamples: 3)
        for length: Float in [1.0, 9.0, 1.2] {
            sampler.add(FaceProportions(length: length, forehead: 1, jaw: 1, chin: 1))
        }
        sampler.add(FaceProportions(length: 50, forehead: 1, jaw: 1, chin: 1))
        XCTAssertTrue(sampler.isComplete)
        XCTAssertEqual(sampler.progress, 1)
        XCTAssertEqual(sampler.median()?.length, 1.2)
        sampler.reset()
        XCTAssertNil(sampler.median())
        XCTAssertEqual(sampler.progress, 0)
    }
}

final class FaceContourMeasurerTests: XCTestCase {
    private let identity = FaceFrame2D(origin: .zero, xTip: SIMD2(1, 0), yTip: SIMD2(0, 1))!

    private var silhouette: MeshSilhouette {
        MeshSilhouette(frame: identity, chinHeight: 0,
                       chin: .init(height: 1, meshWidth: 2),
                       jaw: .init(height: 3, meshWidth: 8),
                       cheekbones: .init(height: 10, meshWidth: 12))
    }

    /// Outline 10% wider than the mesh at the jaw and equal elsewhere.
    private let contour: [SIMD2<Float>] = [
        SIMD2(-6, 12), SIMD2(-6, 6), SIMD2(-4.4, 3), SIMD2(-1, 1), SIMD2(0, 0),
        SIMD2(1, 1), SIMD2(4.4, 3), SIMD2(6, 6), SIMD2(6, 12),
    ]

    func testWidthInterpolatesBetweenContourPoints() {
        let vShape: [SIMD2<Float>] = [SIMD2(-2, 2), SIMD2(0, 0), SIMD2(2, 2)]
        XCTAssertEqual(try XCTUnwrap(FaceContourMeasurer.width(of: vShape, atHeight: 1)), 2, accuracy: 1e-5)
        XCTAssertNil(FaceContourMeasurer.width(of: vShape, atHeight: 3))
    }

    func testCorrectionComparesOutlineWithMeshPerBand() throws {
        let correction = try XCTUnwrap(FaceContourMeasurer.correction(contour: contour, silhouette: silhouette))
        XCTAssertEqual(try XCTUnwrap(correction.chin), 1, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(correction.jaw), 1.1, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(correction.cheekbones), 1, accuracy: 1e-5)
    }

    func testOutlineWhoseChinIsElsewhereIsRejected() {
        let shifted = contour.map { $0 + SIMD2(0, 5) }
        XCTAssertNil(FaceContourMeasurer.correction(contour: shifted, silhouette: silhouette))
    }

    func testAppliedCorrectionRescalesProportions() {
        let mesh = FaceProportions(length: 1.2, forehead: 0.9, jaw: 0.8, chin: 0.5)
        let wideJaw = ContourCorrection(chin: nil, jaw: 1.1, cheekbones: 1).applied(to: mesh)
        XCTAssertEqual(wideJaw.jaw, 0.88, accuracy: 1e-5)
        XCTAssertEqual(wideJaw.chin, 0.5, accuracy: 1e-5)
        XCTAssertEqual(wideJaw.length, 1.2, accuracy: 1e-5)

        let wideCheeks = ContourCorrection(chin: 1, jaw: 1, cheekbones: 1.2).applied(to: mesh)
        XCTAssertEqual(wideCheeks.length, 1.0, accuracy: 1e-5)
        XCTAssertEqual(wideCheeks.forehead, 0.75, accuracy: 1e-5)
        XCTAssertEqual(ContourCorrection().applied(to: mesh), mesh)
    }

    func testMedianSkipsMissingBands() {
        let median = ContourCorrection.median(of: [
            ContourCorrection(chin: 1.0, jaw: 1.0, cheekbones: nil),
            ContourCorrection(chin: 1.2, jaw: 1.1, cheekbones: nil),
            ContourCorrection(chin: nil, jaw: 1.3, cheekbones: nil),
        ])
        XCTAssertEqual(try XCTUnwrap(median?.chin), 1.1, accuracy: 1e-5)
        XCTAssertEqual(median?.jaw, 1.1)
        XCTAssertNil(median?.cheekbones)
        XCTAssertNil(ContourCorrection.median(of: []))
    }

    func testSilhouetteFindsMeshBandsInTheImage() throws {
        // Flat mesh outline: chin 4 cm, jaw 10 cm, cheekbones 16 cm wide; projected at 100 px per metre.
        let vertices = stride(from: Float(0), through: 1, by: 0.01).flatMap { fraction -> [SIMD3<Float>] in
            let half: Float = fraction < 0.12 ? 0.02 : fraction < 0.4 ? 0.05 : fraction < 0.75 ? 0.08 : 0.06
            let y = fraction * 0.2 - 0.1
            return [SIMD3(-half, y, 0), SIMD3(half, y, 0)]
        }
        let projected = vertices.map { SIMD2($0.x * 100, $0.y * 100) }
        let silhouette = try XCTUnwrap(FaceContourMeasurer.silhouette(vertices: vertices, projected: projected, frame: identity))
        XCTAssertEqual(silhouette.chinHeight, -10, accuracy: 1e-4)
        XCTAssertEqual(silhouette.chin.meshWidth, 4, accuracy: 1e-4)
        XCTAssertEqual(silhouette.jaw.meshWidth, 10, accuracy: 1e-4)
        XCTAssertEqual(silhouette.cheekbones.meshWidth, 16, accuracy: 1e-4)
    }

    func testRawPointUndoesPortraitRotation() {
        let raw = SIMD2<Float>(640, 480)
        // Sensor top-left shows up top-right after the 90° clockwise `.right` rotation.
        XCTAssertEqual(FaceContourDetector.rawPoint(SIMD2(480, 0), orientation: .right, rawSize: raw), SIMD2(0, 0))
        XCTAssertEqual(FaceContourDetector.rawPoint(SIMD2(0, 0), orientation: .left, rawSize: raw), SIMD2(640, 0))
        XCTAssertEqual(FaceContourDetector.rawPoint(SIMD2(10, 20), orientation: .leftMirrored, rawSize: raw), SIMD2(20, 10))
    }
}
