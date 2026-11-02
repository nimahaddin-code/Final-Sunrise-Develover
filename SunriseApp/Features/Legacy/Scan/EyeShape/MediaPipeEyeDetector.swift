import CoreVideo
import Foundation
import MediaPipeTasksVision

/// Finds the eye landmarks in camera frames with MediaPipe's Face Landmarker. This is the only file that imports
/// MediaPipe; everything it returns is plain `EyeScanLandmarks`.
///
/// Frames must come in order from one serial queue: video mode keeps tracking state between calls. MediaPipe's
/// classes are not `Sendable`, so this type guards them by that rule instead of by the compiler.
final class MediaPipeEyeDetector: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case modelMissing
        case loadFailed(String)
    }

    enum Outcome: Equatable {
        case noFace
        case face(EyeScanLandmarks)

        var landmarks: EyeScanLandmarks? {
            if case .face(let landmarks) = self { landmarks } else { nil }
        }
    }

    /// The Face Landmarker bundle (`Resources/face_landmarker.task`), shipped inside the app. Never downloaded.
    static var bundledModelURL: URL? { Bundle.main.url(forResource: "face_landmarker", withExtension: "task") }

    private let landmarker: FaceLandmarker
    private var lastTimestamp = -1

    init(modelURL: URL? = MediaPipeEyeDetector.bundledModelURL) throws {
        guard let modelURL else { throw Failure.modelMissing }
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelURL.path
        options.runningMode = .video
        options.numFaces = 1
        do {
            landmarker = try FaceLandmarker(options: options)
        } catch {
            throw Failure.loadFailed(error.localizedDescription)
        }
    }

    /// `pixelBuffer` must be upright BGRA. `timestampMs` must grow with every call; a frame that does not is
    /// dropped. Returns `nil` when the frame was dropped or MediaPipe failed, `.noFace` when it saw no face.
    func detect(pixelBuffer: CVPixelBuffer, timestampMs: Int) -> Outcome? {
        guard timestampMs > lastTimestamp else { return nil }
        lastTimestamp = timestampMs
        guard let image = try? MPImage(pixelBuffer: pixelBuffer),
              let result = try? landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs) else { return nil }
        guard let face = result.faceLandmarks.first else { return .noFace }
        let size = SIMD2(Float(CVPixelBufferGetWidth(pixelBuffer)), Float(CVPixelBufferGetHeight(pixelBuffer)))
        guard let landmarks = EyeScanLandmarks(normalizedMesh: face.map { SIMD2($0.x, $0.y) }, imageSize: size) else { return nil }
        return .face(landmarks)
    }

    /// Compares the indices in `EyeScanLandmarks.MeshIndex` with MediaPipe's own connection tables for the eyes, irises and
    /// brows. Empty means they agree. This catches a wrong index without a camera or a face.
    static func topologyProblems() -> [String] {
        func indices(_ connections: [Connection]) -> Set<Int> {
            Set(connections.flatMap { [Int($0.start), Int($0.end)] })
        }
        var problems: [String] = []
        func compare(_ name: String, mine: Set<Int>, theirs: Set<Int>, exact: Bool) {
            let missing = mine.subtracting(theirs)
            if !missing.isEmpty { problems.append("\(name): \(missing.sorted()) are not in MediaPipe's table") }
            if exact, !theirs.subtracting(mine).isEmpty {
                problems.append("\(name): MediaPipe also has \(theirs.subtracting(mine).sorted())")
            }
        }
        let sides: [(String, EyeScanLandmarks.MeshIndex.Eye, [Connection], [Connection])] = [
            ("right", EyeScanLandmarks.MeshIndex.personRight, FaceLandmarker.rightEyeConnections(), FaceLandmarker.rightEyebrowConnections()),
            ("left", EyeScanLandmarks.MeshIndex.personLeft, FaceLandmarker.leftEyeConnections(), FaceLandmarker.leftEyebrowConnections()),
        ]
        for (name, eye, eyeTable, browTable) in sides {
            compare("\(name) eye outline", mine: Set(eye.lid + [eye.inner, eye.outer]), theirs: indices(eyeTable), exact: true)
            compare("\(name) brow", mine: Set(eye.brow), theirs: indices(browTable), exact: false)
        }
        // MediaPipe's iOS right-iris table currently returns the left ring, so only the union can be compared: the
        // left table must be one of our rings. Eyes get their ring by distance (see `MeshIndex.irisRings`).
        let leftIris = indices(FaceLandmarker.leftIrisConnections())
        if !EyeScanLandmarks.MeshIndex.irisRings.contains(where: { Set($0) == leftIris }) {
            problems.append("iris: MediaPipe's left iris \(leftIris.sorted()) is not one of our rings")
        }
        return problems
    }
}
