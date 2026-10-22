import CoreVideo
import XCTest
@testable import SunriseApp

/// These run in the Simulator against the real MediaPipe library and the bundled model, but with no face. What a
/// real face gives (and whether the thresholds suit it) can only be checked on a device.
final class MediaPipeEyeDetectorTests: XCTestCase {
    private func blankFrame(width: Int = 360, height: Int = 640) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let frame = try XCTUnwrap(buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 128, CVPixelBufferGetBytesPerRow(frame) * height)
        CVPixelBufferUnlockBaseAddress(frame, [])
        return frame
    }

    func testEyeIndicesAgreeWithMediaPipesOwnTables() {
        XCTAssertEqual(MediaPipeEyeDetector.topologyProblems(), [])
    }

    func testBundledModelLoadsAndSeesNoFaceInABlankFrame() throws {
        XCTAssertNotNil(MediaPipeEyeDetector.bundledModelURL, "face_landmarker.task must be in the app bundle")
        let detector = try MediaPipeEyeDetector()
        XCTAssertEqual(detector.detect(pixelBuffer: try blankFrame(), timestampMs: 0), .noFace)
        XCTAssertEqual(detector.detect(pixelBuffer: try blankFrame(), timestampMs: 33), .noFace)
    }

    func testFramesWithoutALaterTimestampAreDropped() throws {
        let detector = try MediaPipeEyeDetector()
        let frame = try blankFrame()
        XCTAssertNotNil(detector.detect(pixelBuffer: frame, timestampMs: 100))
        XCTAssertNil(detector.detect(pixelBuffer: frame, timestampMs: 100))
        XCTAssertNil(detector.detect(pixelBuffer: frame, timestampMs: 50))
        XCTAssertNotNil(detector.detect(pixelBuffer: frame, timestampMs: 101))
    }

    func testMissingModelThrows() {
        XCTAssertThrowsError(try MediaPipeEyeDetector(modelURL: nil)) {
            XCTAssertEqual($0 as? MediaPipeEyeDetector.Failure, .modelMissing)
        }
        XCTAssertThrowsError(try MediaPipeEyeDetector(modelURL: URL(fileURLWithPath: "/nonexistent/model.task")))
    }
}
