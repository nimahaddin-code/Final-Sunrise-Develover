import CoreGraphics
import XCTest
@testable import SunriseApp

final class ScanDebugTests: XCTestCase {
    private let facePositions: [String: CGPoint] = [
        "top": CGPoint(x: 0.5, y: 0.1), "bottom": CGPoint(x: 0.5, y: 0.9),
        "forehead.left": CGPoint(x: 0.3, y: 0.25), "forehead.right": CGPoint(x: 0.7, y: 0.25),
        "cheekbone.left": CGPoint(x: 0.25, y: 0.45), "cheekbone.right": CGPoint(x: 0.75, y: 0.45),
        "jaw.left": CGPoint(x: 0.32, y: 0.7), "jaw.right": CGPoint(x: 0.68, y: 0.7),
        "chin.left": CGPoint(x: 0.42, y: 0.85), "chin.right": CGPoint(x: 0.58, y: 0.85),
    ]

    private var eyePositions: [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let left: [String: CGPoint] = ["outer": CGPoint(x: 0.20, y: 0.50), "inner": CGPoint(x: 0.40, y: 0.50),
                                       "lidTop": CGPoint(x: 0.30, y: 0.47), "lidBottom": CGPoint(x: 0.30, y: 0.53),
                                       "irisA": CGPoint(x: 0.28, y: 0.50), "irisB": CGPoint(x: 0.32, y: 0.50),
                                       "brow": CGPoint(x: 0.30, y: 0.42)]
        for (part, point) in left {
            positions["eye.left.\(part)"] = point
            positions["eye.right.\(part)"] = CGPoint(x: 1 - point.x, y: point.y)
        }
        return positions
    }

    private func faceSet() -> ScanDebugPointSet {
        ScanDebugPointSet(kind: .face, imageWidth: 1000, imageHeight: 1000, positions: facePositions)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScanDebugTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFaceMeasurementsAreInPhotoPixels() throws {
        let report = ScanDebugMeasure.report(for: faceSet())
        XCTAssertEqual(try XCTUnwrap(report.value("length")), 800, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.value("cheekbone")), 500, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.value("jaw")), 360, accuracy: 0.01)
        XCTAssertNotNil(report.classification)
    }

    func testEyeMeasurementsUseTheSameMeasurerAsTheScan() throws {
        let set = ScanDebugPointSet(kind: .eyes, imageWidth: 1000, imageHeight: 1000, positions: eyePositions)
        let report = ScanDebugMeasure.report(for: set)
        XCTAssertEqual(try XCTUnwrap(report.value("openness")), 0.3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(report.value("tilt")), 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(report.value("spacing")), 1.0, accuracy: 0.01)
        XCTAssertNotNil(report.classification)
    }

    func testMovingAPointClampsToThePhotoAndChangesTheMeasurement() throws {
        var set = faceSet()
        set.move("cheekbone.left", to: CGPoint(x: -0.4, y: 0.45))
        XCTAssertEqual(try XCTUnwrap(set.position("cheekbone.left")).x, 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ScanDebugMeasure.report(for: set).value("cheekbone")), 750, accuracy: 0.01)
        XCTAssertEqual(set.meanShift(from: faceSet()), 250 / 10, accuracy: 0.01)
    }

    func testOverlayHasAnOutlineAndMeasuredLines() {
        let strokes = faceSet().overlay.strokes
        XCTAssertEqual(strokes.filter { $0.style == .outline }.count, 1)
        XCTAssertGreaterThanOrEqual(strokes.filter { $0.style == .measure }.count, 4)
    }

    func testFaceScanOverlayRoundTripsToThePointsTheScanDrew() throws {
        func span(_ y: Float, _ half: Float) -> FaceGuide.Span { .init(left: SIMD3(-half, y, 0), right: SIMD3(half, y, 0)) }
        let guide = FaceGuide(forehead: span(0.06, 0.05), cheekbones: span(0.02, 0.06), jaw: span(-0.03, 0.045), chin: span(-0.06, 0.02),
                              top: SIMD3(0, 0.09, 0), bottom: SIMD3(0, -0.08, 0))
        let overlay = try XCTUnwrap(guide.overlay { CGPoint(x: Double($0.x) * 5 + 0.5, y: 0.5 - Double($0.y) * 5) })
        let positions = try XCTUnwrap(ScanDebugSnapshotReader.facePositions(overlay))
        XCTAssertEqual(positions.count, 10)
        for name in ["forehead", "cheekbone", "jaw", "chin"] {
            XCTAssertLessThan(try XCTUnwrap(positions["\(name).left"]).x, try XCTUnwrap(positions["\(name).right"]).x)
        }
        XCTAssertLessThan(try XCTUnwrap(positions["top"]).y, try XCTUnwrap(positions["bottom"]).y)
        XCTAssertEqual(try XCTUnwrap(positions["cheekbone.left"]).x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(positions["bottom"]).y, 0.9, accuracy: 1e-6)
    }

    func testEyeScanOverlayRoundTripsToThePointsTheScanDrew() throws {
        func eye(innerX: Float, outerX: Float) -> EyeLandmarks.Eye {
            let y: Float = 100
            let xs = (0..<7).map { outerX + (innerX - outerX) * Float($0 + 1) / 8 }
            let upper = xs.map { SIMD2($0, y - 6) }, lower = xs.map { SIMD2($0, y + 6) }
            let middle = (innerX + outerX) / 2
            return .init(innerCorner: SIMD2(innerX, y), outerCorner: SIMD2(outerX, y), lid: upper + lower,
                         iris: [SIMD2(middle - 4, y), SIMD2(middle + 4, y), SIMD2(middle, y - 4), SIMD2(middle, y + 4)],
                         brow: (0..<5).map { SIMD2(xs[0] + Float($0) * 5, y - 25) })
        }
        let landmarks = EyeLandmarks(first: eye(innerX: 180, outerX: 120), second: eye(innerX: 220, outerX: 280))
        let overlay = try XCTUnwrap(EyeOverlay.overlay(for: landmarks, imageSize: SIMD2(400, 200)))
        let positions = try XCTUnwrap(ScanDebugSnapshotReader.eyePositions(overlay))
        XCTAssertEqual(positions.count, 14)
        let set = ScanDebugPointSet(kind: .eyes, imageWidth: 400, imageHeight: 200, positions: positions)
        let left = try XCTUnwrap(set.pixel("eye.left.lidTop")), bottom = try XCTUnwrap(set.pixel("eye.left.lidBottom"))
        XCTAssertLessThan(left.y, bottom.y)
        XCTAssertLessThan(try XCTUnwrap(set.pixel("eye.left.inner")).x, try XCTUnwrap(set.pixel("eye.right.inner")).x)
        XCTAssertNotNil(ScanDebugMeasure.report(for: set).value("openness"))
    }

    private func faceSnapshot() throws -> ScanSnapshot {
        func span(_ y: Float, _ half: Float) -> FaceGuide.Span { .init(left: SIMD3(-half, y, 0), right: SIMD3(half, y, 0)) }
        let guide = FaceGuide(forehead: span(0.06, 0.05), cheekbones: span(0.02, 0.06), jaw: span(-0.03, 0.045), chin: span(-0.06, 0.02),
                              top: SIMD3(0, 0.09, 0), bottom: SIMD3(0, -0.08, 0))
        let overlay = try XCTUnwrap(guide.overlay { CGPoint(x: Double($0.x) * 5 + 0.5, y: 0.5 - Double($0.y) * 5) })
        let context = try XCTUnwrap(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return ScanSnapshot(croppedImage: try XCTUnwrap(context.makeImage()), overlay: overlay)
    }

    @MainActor private func modelWithFaceScan() throws -> ScanDebugViewModel {
        let model = ScanDebugViewModel(store: ScanDebugStore(directory: temporaryDirectory()))
        model.accept(try faceSnapshot(), kind: .face)
        model.stage = .corrected
        return model
    }

    @MainActor func testUndoRevertsOneDragAtATime() throws {
        let model = try modelWithFaceScan()
        let original = try XCTUnwrap(model.session).corrected
        XCTAssertFalse(model.canUndo)
        for step in 1...3 { model.move("jaw.left", toShown: CGPoint(x: 0.1 * Double(step), y: 0.7)) }  // one drag
        model.endEdit()
        model.move("jaw.left", toShown: CGPoint(x: 0.9, y: 0.7))  // a second drag
        model.endEdit()
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(try XCTUnwrap(model.session).corrected.position("jaw.left")?.x ?? 0, 0.3, accuracy: 1e-9)
        model.undo()
        XCTAssertEqual(try XCTUnwrap(model.session).corrected, original)
        XCTAssertFalse(model.canUndo)
    }

    @MainActor func testCancelDropsEverythingMovedSinceEditingBegan() throws {
        let model = try modelWithFaceScan()
        model.move("top", toShown: CGPoint(x: 0.5, y: 0.2)); model.endEdit()
        let before = try XCTUnwrap(model.session).corrected
        model.beginEditing()
        model.move("jaw.left", toShown: CGPoint(x: 0.1, y: 0.7)); model.endEdit()
        model.move("jaw.right", toShown: CGPoint(x: 0.9, y: 0.7)); model.endEdit()
        model.cancelEditing()
        XCTAssertEqual(try XCTUnwrap(model.session).corrected, before)
        model.undo()  // only the move made before the checkpoint is left to undo
        XCTAssertEqual(try XCTUnwrap(model.session).corrected, try XCTUnwrap(model.session).raw)
        XCTAssertFalse(model.canUndo)
    }

    func testExportFileRoundTripsPicturePointsAndMeasurements() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let picture = try XCTUnwrap(context.makeImage())
        var corrected = faceSet()
        corrected.move("jaw.left", to: CGPoint(x: 0.3, y: 0.7))

        let file = try ScanDebugExportFile(name: "demo", raw: faceSet(), corrected: corrected, picture: picture)
        let decoded = try ScanDebugExportFile.decode(try file.encoded())
        XCTAssertEqual(decoded.name, "demo")
        XCTAssertEqual(decoded.kind, .face)
        XCTAssertEqual(decoded.rawSet.points, faceSet().points)
        XCTAssertEqual(decoded.correctedSet.points, corrected.points)
        XCTAssertEqual(decoded.measurements["cheekbone"] ?? 0, 20, accuracy: 0.01)
        let image = try XCTUnwrap(decoded.picture())
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 30)
    }

    @MainActor func testASavedPointsFileIsRecognizedAsHavingNoPicture() throws {
        let store = ScanDebugStore(directory: temporaryDirectory())
        try store.save(name: "p", raw: faceSet(), corrected: faceSet())
        let url = try XCTUnwrap(store.items.first).url
        XCTAssertThrowsError(try ScanDebugExportFile.decode(Data(contentsOf: url))) { error in
            XCTAssertEqual(error as? ScanDebugExportFile.Failure, .pointsOnly)
        }
    }

    func testExportFileRejectsOtherJSONAndNewerVersions() throws {
        XCTAssertThrowsError(try ScanDebugExportFile.decode(Data("{\"hello\":1}".utf8)))
        XCTAssertThrowsError(try ScanDebugExportFile.decode(Data("{\"format\":\"sunrise-scan-debug\",\"version\":99}".utf8))) { error in
            XCTAssertEqual(error as? ScanDebugExportFile.Failure, .newerVersion(99))
        }
    }

    @MainActor func testANewScanOfTheSameKindKeepsTheOldOneForBulkExport() throws {
        let model = try modelWithFaceScan()
        let first = try XCTUnwrap(model.session).id
        XCTAssertEqual(model.exportItems.count, 1)
        model.accept(try faceSnapshot(), kind: .face)
        XCTAssertEqual(model.exportItems.count, 2)
        XCTAssertNotEqual(try XCTUnwrap(model.session).id, first)

        model.activate(first)  // the old scan becomes the one being edited; the newer goes to the list
        XCTAssertEqual(try XCTUnwrap(model.session).id, first)
        XCTAssertEqual(model.allScans.count, 2)
        model.remove(first)
        XCTAssertEqual(model.allScans.count, 1)
        XCTAssertNil(model.session)
    }

    func testAScanWithoutLinesIsRejected() {
        XCTAssertNil(ScanDebugSnapshotReader.facePositions(ScanOverlay(strokes: [])))
        XCTAssertNil(ScanDebugSnapshotReader.eyePositions(ScanOverlay(strokes: [])))
    }

    @MainActor func testConfirmWritesRawAndCorrectedAsSeparateNamedFiles() throws {
        let store = ScanDebugStore(directory: temporaryDirectory())
        var corrected = faceSet()
        corrected.move("jaw.left", to: CGPoint(x: 0.3, y: 0.7))

        let names = try store.save(name: "my face", raw: faceSet(), corrected: corrected)
        XCTAssertEqual(names, ["face-my-face.raw.json", "face-my-face.corrected.json"])
        let byStage = Dictionary(uniqueKeysWithValues: store.items.map { ($0.record.stage, $0.record) })
        XCTAssertEqual(byStage[.raw]?.points, faceSet().points)
        XCTAssertEqual(byStage[.corrected]?.points, corrected.points)
        XCTAssertNotEqual(byStage[.raw]?.measurements["jaw"], byStage[.corrected]?.measurements["jaw"])
    }

    @MainActor func testSavingTheSameNameAgainNeverOverwrites() throws {
        let store = ScanDebugStore(directory: temporaryDirectory())
        try store.save(name: "a", raw: faceSet(), corrected: faceSet())
        let second = try store.save(name: "a", raw: faceSet(), corrected: faceSet())
        XCTAssertEqual(second, ["face-a-2.raw.json", "face-a-2.corrected.json"])
        XCTAssertEqual(store.items.count, 4)
    }

    func testNamesAreMadeFileSafe() {
        XCTAssertEqual(ScanDebugStore.sanitized("  ../My Face/1  ", fallback: "x"), "My-Face-1")
        XCTAssertEqual(ScanDebugStore.sanitized("///", fallback: "fallback"), "fallback")
    }
}
