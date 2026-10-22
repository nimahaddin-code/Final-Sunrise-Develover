import CoreGraphics
import XCTest
@testable import SunriseApp

final class PhotoFaceMeasurerTests: XCTestCase {
    /// Upright face (y up): eyes at 0, brows at 10, chin at -40. The outline is 60 wide down to -16,
    /// 40 wide across the jaw (-28...-18) and 12 wide at the chin, so the facial-thirds top is 35 and length 75.
    private let face: PhotoLandmarks = {
        let left: [SIMD2<Float>] = [SIMD2(-30, 0), SIMD2(-30, -16), SIMD2(-20, -18), SIMD2(-20, -28), SIMD2(-6, -30), SIMD2(-6, -40)]
        let contour = left + left.reversed().map { SIMD2(-$0.x, $0.y) }
        let brow: [SIMD2<Float>] = [SIMD2(-26, 10), SIMD2(-16, 10), SIMD2(-8, 10)]
        let eye: [SIMD2<Float>] = [SIMD2(-20, 0), SIMD2(-15, 2), SIMD2(-10, 0), SIMD2(-15, -2)]
        return PhotoLandmarks(faceContour: contour, leftEyebrow: brow, rightEyebrow: brow.map { SIMD2(-$0.x, $0.y) },
                              leftEye: eye, rightEye: eye.map { SIMD2(-$0.x, $0.y) }, boundingBox: nil)
    }()

    private func assertProportions(_ landmarks: PhotoLandmarks, length: Float = 75,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let proportions = try XCTUnwrap(PhotoFaceMeasurer.proportions(of: landmarks), file: file, line: line)
        XCTAssertEqual(proportions.length, length / 60, accuracy: 1e-4, file: file, line: line)
        XCTAssertEqual(proportions.forehead, 52.0 / 60, accuracy: 1e-4, file: file, line: line)
        XCTAssertEqual(proportions.jaw, 40.0 / 60, accuracy: 1e-4, file: file, line: line)
        XCTAssertEqual(proportions.chin, 12.0 / 40, accuracy: 1e-4, file: file, line: line)
    }

    private func transformed(_ landmarks: PhotoLandmarks, _ transform: (SIMD2<Float>) -> SIMD2<Float>) -> PhotoLandmarks {
        PhotoLandmarks(faceContour: landmarks.faceContour.map(transform), leftEyebrow: landmarks.leftEyebrow.map(transform),
                       rightEyebrow: landmarks.rightEyebrow.map(transform), leftEye: landmarks.leftEye.map(transform),
                       rightEye: landmarks.rightEye.map(transform), boundingBox: nil)
    }

    func testMeasuresOutlineAndBrowsRelativeToCheekbones() throws {
        try assertProportions(face)
    }

    func testIgnoresHeadRollPositionAndMirroring() throws {
        let angle = Float.pi / 6
        try assertProportions(transformed(face) { p in
            SIMD2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle)) + SIMD2(400, 300)
        })
        // Mirrored: the "left" eye is now on the right, which flips the eye line.
        try assertProportions(transformed(face) { SIMD2(-$0.x, $0.y) })
    }

    func testFaceBoxAboveBrowsRaisesTheTop() throws {
        var boxed = face
        boxed.boundingBox = CGRect(x: -40, y: -45, width: 80, height: 90)
        try assertProportions(boxed, length: 80)
        boxed.boundingBox = CGRect(x: -40, y: -45, width: 80, height: 50)
        try assertProportions(boxed)
    }

    func testRejectsMissingLandmarks() {
        var noEyes = face
        noEyes.leftEye = []
        XCTAssertNil(PhotoFaceMeasurer.proportions(of: noEyes))
        var noContour = face
        noContour.faceContour = []
        XCTAssertNil(PhotoFaceMeasurer.proportions(of: noContour))
    }

    func testPhotoClassifierUsesItsOwnReference() {
        XCTAssertEqual(FaceShapeClassifier.photo.reference, PhotoFaceMeasurer.reference)
        XCTAssertEqual(FaceShapeClassifier.photo.classify(PhotoFaceMeasurer.reference).deviation,
                       FaceProportions(length: 0, forehead: 0, jaw: 0, chin: 0))
    }
}
