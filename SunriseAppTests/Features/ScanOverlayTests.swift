import CoreGraphics
import CoreVideo
import AVFoundation
import XCTest
import simd
@testable import SunriseApp

private func makeImage(width: Int, height: Int) throws -> CGImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.8, green: 0.6, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try XCTUnwrap(context.makeImage())
}

final class ScanOverlayTests: XCTestCase {
    private let overlay = ScanOverlay(strokes: [
        .init(points: [CGPoint(x: 0.4, y: 0.25), CGPoint(x: 0.6, y: 0.75)], style: .outline),
        .init(points: [CGPoint(x: 0.5, y: 0.5)], style: .guide),
    ])

    func testBoundsCoverEveryPoint() throws {
        let bounds = try XCTUnwrap(overlay.bounds)
        XCTAssertEqual(bounds.minX, 0.4, accuracy: 1e-9)
        XCTAssertEqual(bounds.minY, 0.25, accuracy: 1e-9)
        XCTAssertEqual(bounds.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(bounds.height, 0.5, accuracy: 1e-9)
        XCTAssertNil(ScanOverlay(strokes: []).bounds)
    }

    func testRemappingMovesPointsOntoTheCrop() {
        let remapped = overlay.remapped(to: CGRect(x: 0.4, y: 0.25, width: 0.2, height: 0.5))
        let ends = remapped.strokes[0].points
        XCTAssertEqual(ends[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(ends[0].y, 0, accuracy: 1e-9)
        XCTAssertEqual(ends[1].x, 1, accuracy: 1e-9)
        XCTAssertEqual(ends[1].y, 1, accuracy: 1e-9)
        XCTAssertEqual(remapped.strokes[1].points[0].x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(remapped.strokes[1].points[0].y, 0.5, accuracy: 1e-9)
    }

    func testSnapshotCropsAroundTheLinesAndKeepsThemOnTheSamePlaces() throws {
        let snapshot = try XCTUnwrap(ScanSnapshot(image: makeImage(width: 200, height: 400), overlay: overlay, padding: 0.5))
        // 0.2 x 0.5 of the picture plus half of that on every side, capped at the picture.
        XCTAssertEqual(Double(snapshot.image.width), 80, accuracy: 2)
        XCTAssertEqual(Double(snapshot.image.height), 400, accuracy: 2)
        let first = snapshot.overlay.strokes[0].points
        // A point at 0.4 of 200 px is 80 px in; the crop starts at 60 px, so it is 20 px into an 80 px crop.
        XCTAssertEqual(first[0].x, 0.25, accuracy: 0.03)
        XCTAssertEqual(first[1].x, 0.75, accuracy: 0.03)
    }

    func testSnapshotNeedsLinesToCropAround() throws {
        XCTAssertNil(ScanSnapshot(image: try makeImage(width: 10, height: 10), overlay: ScanOverlay(strokes: [])))
    }

    func testSmoothPathStillPassesThroughItsEndPoints() {
        let points = (0..<6).map { CGPoint(x: Double($0) * 10, y: Double($0 % 2) * 5) }
        let path = ScanOverlayView.path(through: points, closed: false, smooth: true)
        XCTAssertEqual(path.boundingRect.minX, 0, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.maxX, 50, accuracy: 0.5)
        XCTAssertEqual(path.currentPoint, points.last)
    }
}

final class FaceGuideTests: XCTestCase {
    /// A face 0.20 m tall whose half width grows from chin to cheekbones and shrinks again toward the forehead.
    private func vertices() -> [SIMD3<Float>] {
        (0...100).flatMap { step -> [SIMD3<Float>] in
            let fraction = Float(step) / 100
            let half: Float = 0.02 + 0.045 * sin(min(fraction, 0.7) / 0.7 * .pi / 2) - 0.012 * max(0, fraction - 0.7)
            return [SIMD3(-half, fraction * 0.2, 0.02), SIMD3(half, fraction * 0.2, 0.02), SIMD3(0, fraction * 0.2, 0.05)]
        }
    }

    func testSpansMatchTheWidthsTheClassifierUses() throws {
        let vertices = vertices()
        let guide = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices))
        let proportions = try XCTUnwrap(FaceMeshMeasurer.proportions(of: vertices))
        func width(_ span: FaceGuide.Span) -> Float { span.right.x - span.left.x }
        XCTAssertEqual(guide.top.y - guide.bottom.y, 0.2, accuracy: 1e-5)
        XCTAssertEqual((guide.top.y - guide.bottom.y) / width(guide.cheekbones), proportions.length, accuracy: 2e-3)
        XCTAssertEqual(width(guide.forehead) / width(guide.cheekbones), proportions.forehead, accuracy: 2e-3)
        XCTAssertEqual(width(guide.jaw) / width(guide.cheekbones), proportions.jaw, accuracy: 2e-3)
        XCTAssertEqual(width(guide.chin) / width(guide.jaw), proportions.chin, accuracy: 2e-3)
    }

    func testContourCorrectionMovesTheLinesTheWayItMovesTheProportions() throws {
        let vertices = vertices()
        let correction = ContourCorrection(chin: 1.3, jaw: 1.2, cheekbones: 1.1)
        let guide = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices, correction: correction))
        let applied = correction.applied(to: try XCTUnwrap(FaceMeshMeasurer.proportions(of: vertices)))
        func width(_ span: FaceGuide.Span) -> Float { span.right.x - span.left.x }
        XCTAssertEqual((guide.top.y - guide.bottom.y) / width(guide.cheekbones), applied.length, accuracy: 2e-3)
        XCTAssertEqual(width(guide.forehead) / width(guide.cheekbones), applied.forehead, accuracy: 2e-3)
        XCTAssertEqual(width(guide.jaw) / width(guide.cheekbones), applied.jaw, accuracy: 2e-3)
        XCTAssertEqual(width(guide.chin) / width(guide.jaw), applied.chin, accuracy: 2e-3)
    }

    func testMissingCorrectionsFallBackTheWayAppliedDoes() throws {
        let vertices = vertices()
        let plain = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices))
        let guide = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices, correction: ContourCorrection(chin: nil, jaw: nil, cheekbones: 1.1)))
        func width(_ span: FaceGuide.Span) -> Float { span.right.x - span.left.x }
        XCTAssertEqual(width(guide.jaw), width(plain.jaw) * 1.1, accuracy: 1e-5)
        XCTAssertEqual(width(guide.chin), width(plain.chin) * 1.1, accuracy: 1e-5)
        XCTAssertEqual(width(guide.forehead), width(plain.forehead), accuracy: 1e-5)
    }

    func testOverlayHasOutlineThreeLabelledWidthsAndLength() throws {
        let guide = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices()))
        let overlay = try XCTUnwrap(guide.overlay { CGPoint(x: CGFloat($0.x) * 5 + 0.5, y: 0.9 - CGFloat($0.y) * 4) })
        XCTAssertEqual(overlay.strokes.map(\.style), [.outline, .measure, .measure, .measure, .measure])
        XCTAssertEqual(overlay.strokes.compactMap(\.label), ["Forehead", "Cheekbones", "Jaw"])
        XCTAssertEqual(overlay.strokes[0].points.count, 9)
        // The outline runs down one side, around the chin, and up the other.
        XCTAssertLessThan(overlay.strokes[0].points[0].x, overlay.strokes[0].points[8].x)
    }

    func testOverlayIsMissingWhenAPointCannotBePlaced() throws {
        let guide = try XCTUnwrap(FaceMeshMeasurer.guide(of: vertices()))
        XCTAssertNil(guide.overlay { _ in nil })
    }

    func testNoGuideForAFlatOrEmptyMesh() {
        XCTAssertNil(FaceMeshMeasurer.guide(of: []))
        XCTAssertNil(FaceMeshMeasurer.guide(of: [SIMD3(0, 0, 0), SIMD3(0.1, 0, 0)]))
    }
}

final class EyeOverlayTests: XCTestCase {
    /// Shifted so every point falls inside a 400 x 300 picture.
    private func landmarks() -> EyeScanLandmarks {
        let synthetic = SyntheticEyes().landmarks()
        func move(_ eye: EyeScanLandmarks.Eye) -> EyeScanLandmarks.Eye {
            func place(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x + 200, 150 - p.y) }
            return EyeScanLandmarks.Eye(innerCorner: place(eye.innerCorner), outerCorner: place(eye.outerCorner),
                                    lid: eye.lid.map(place), iris: eye.iris.map(place), brow: eye.brow.map(place))
        }
        return EyeScanLandmarks(first: move(synthetic.first), second: move(synthetic.second))
    }

    func testDrawsEachEyeAndTheGapBetweenThem() throws {
        let overlay = try XCTUnwrap(EyeOverlay.overlay(for: landmarks(), imageSize: SIMD2(400, 300)))
        // Per eye: outline, brow, iris, tilt line, opening line. Then one spacing line.
        XCTAssertEqual(overlay.strokes.count, 11)
        XCTAssertEqual(overlay.strokes.compactMap(\.label), ["Spacing"])
        XCTAssertEqual(overlay.strokes.filter { $0.style == .outline }.count, 2)
        for point in overlay.allPoints {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "\(point) is outside the picture")
        }
    }

    func testMirroringMatchesTheSelfiePreview() throws {
        let eyes = landmarks()
        let plain = try XCTUnwrap(EyeOverlay.overlay(for: eyes, imageSize: SIMD2(400, 300), mirrored: false))
        let mirrored = try XCTUnwrap(EyeOverlay.overlay(for: eyes, imageSize: SIMD2(400, 300), mirrored: true))
        for (a, b) in zip(plain.allPoints, mirrored.allPoints) {
            XCTAssertEqual(a.x + b.x, 1, accuracy: 1e-6)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        }
    }

    func testOpeningLineIsAsTallAsTheMeasuredOpening() throws {
        let eye = SyntheticEyes(openness: 0.3, tilt: 0).landmarks().first
        let line = try XCTUnwrap(EyeOverlay.openingLine(of: eye))
        XCTAssertEqual(simd_distance(line[0], line[1]) / simd_distance(eye.innerCorner, eye.outerCorner), 0.3, accuracy: 1e-3)
    }

    func testIrisRingHasTheIrisDiameter() throws {
        let eye = SyntheticEyes(irisDiameter: 12).landmarks().first
        let ring = try XCTUnwrap(EyeOverlay.circle(through: eye.iris))
        let center = ring.reduce(.zero, +) / Float(ring.count)
        XCTAssertEqual(simd_distance(ring[0], center), 6, accuracy: 1e-4)
    }

    func testSnapshotIsCroppedAroundTheEyesWithTheLinesInsideIt() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 400, 300, kCVPixelFormatType_32BGRA, nil, &buffer)
        let picture = try XCTUnwrap(buffer)
        let snapshot = try XCTUnwrap(EyeFrameSnapshot.make(from: picture, landmarks: landmarks()))
        XCTAssertLessThan(snapshot.image.width, 400)
        XCTAssertLessThan(snapshot.image.height, 300)
        XCTAssertGreaterThan(snapshot.image.width, 0)
        for point in snapshot.overlay.allPoints {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "\(point) is outside the crop")
        }
    }
}

final class ContourReportTests: XCTestCase {
    func testReportShowsCountMedianAndSpreadPerBand() {
        let report = ContourCorrection.report(of: [
            ContourCorrection(chin: nil, jaw: 1.0, cheekbones: 1.1),
            ContourCorrection(chin: nil, jaw: 1.2, cheekbones: 1.1),
            ContourCorrection(chin: nil, jaw: 1.1, cheekbones: 1.1),
        ])
        XCTAssertTrue(report.contains("outlines=3"))
        XCTAssertTrue(report.contains("chin: no samples"))
        XCTAssertTrue(report.contains("jaw: n=3 median=1.100 min=1.000 max=1.200 sd=0.082"), report)
        XCTAssertTrue(report.contains("cheekbones: n=3 median=1.100 min=1.100 max=1.100 sd=0.000"), report)
    }

    func testReportHandlesNoOutlines() {
        XCTAssertTrue(ContourCorrection.report(of: []).contains("jaw: no samples"))
    }
}

final class ScanDoneSoundTests: XCTestCase {
    func testSystemSoundFileIsReadableWhenPresent() throws {
        guard FileManager.default.fileExists(atPath: ScanDoneSound.systemSoundURL.path) else {
            throw XCTSkip("This iOS version has no payment_success.caf; the app falls back to the built-in chime.")
        }
        let player = try AVAudioPlayer(contentsOf: ScanDoneSound.systemSoundURL)
        XCTAssertGreaterThan(player.duration, 0.1)
        print("payment_success.caf duration:", player.duration)
    }

    func testChimeIsAValidQuietOneSecondWav() throws {
        let data = ScanDoneSound.wav()
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        let samples = data.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertEqual(samples.count, 44_100)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 3_000, "silent")
        XCTAssertLessThan(peak, Int(Int16.max) * 9 / 10, "clipping")
        XCTAssertLessThan(abs(Int(samples.last ?? 0)), 50, "should have faded out")
        XCTAssertNoThrow(try AVAudioPlayer(data: data))
    }
}
