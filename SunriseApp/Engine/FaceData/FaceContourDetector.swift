import CoreVideo
import ImageIO
import Vision
import simd

/// ARKit hands over camera buffers read-only, so sharing one with a background Vision request is safe.
struct SendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// Everything needed to compare one camera frame with the ARKit mesh, copied out of the ARFrame.
struct ContourInput: Sendable {
    let pixelBuffer: SendablePixelBuffer
    let cameraTransform: simd_float4x4
    let intrinsics: simd_float3x3
    let faceTransform: simd_float4x4

    /// Projects face-local points into the captured image (pixels, unrotated sensor orientation).
    func project(_ points: [SIMD3<Float>]) -> [SIMD2<Float>]? {
        let toCamera = simd_inverse(cameraTransform) * faceTransform
        var projected: [SIMD2<Float>] = []
        projected.reserveCapacity(points.count)
        for point in points {
            let p = toCamera * SIMD4(point, 1)
            // The camera looks down -z with +y up; image rows grow downward.
            guard p.z < 0 else { return nil }
            let depth = -p.z
            projected.append(SIMD2(intrinsics[0][0] * p.x / depth + intrinsics[2][0],
                                   intrinsics[1][1] * -p.y / depth + intrinsics[2][1]))
        }
        return projected
    }

    func silhouette(vertices: [SIMD3<Float>]) -> MeshSilhouette? {
        guard let axes = project([.zero, SIMD3(0.05, 0, 0), SIMD3(0, 0.05, 0)]),
              let frame = FaceFrame2D(origin: axes[0], xTip: axes[1], yTip: axes[2]),
              let projected = project(vertices) else { return nil }
        return FaceContourMeasurer.silhouette(vertices: vertices, projected: projected, frame: frame)
    }
}

/// Finds the real face outline with Vision and compares it with where the ARKit mesh says the face edge is.
enum FaceContourDetector {
    /// Portrait orientations of the sensor buffer. Mirrored and unmirrored variants give the same widths.
    static let orientations: [CGImagePropertyOrientation] = [.right, .leftMirrored, .left, .rightMirrored]

    /// Tries `preferred` (the orientation that worked before) or else every portrait orientation.
    static func correction(for input: ContourInput, silhouette: MeshSilhouette,
                           preferred: CGImagePropertyOrientation?) -> (ContourCorrection, CGImagePropertyOrientation)? {
        for orientation in preferred.map({ [$0] }) ?? orientations {
            if let correction = correction(for: input.pixelBuffer.buffer, silhouette: silhouette, orientation: orientation) {
                return (correction, orientation)
            }
        }
        return nil
    }

    private static func correction(for buffer: CVPixelBuffer, silhouette: MeshSilhouette,
                                   orientation: CGImagePropertyOrientation) -> ContourCorrection? {
        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
        } catch {
            return nil
        }
        let rawSize = SIMD2(Float(CVPixelBufferGetWidth(buffer)), Float(CVPixelBufferGetHeight(buffer)))
        let uprightSize = SIMD2(rawSize.y, rawSize.x)
        for face in request.results ?? [] {
            guard let contour = face.landmarks?.faceContour else { continue }
            let points = contour.pointsInImage(imageSize: CGSize(width: CGFloat(uprightSize.x), height: CGFloat(uprightSize.y)))
                .map { point in
                    // Vision's origin is bottom-left; convert to top-left, then back to sensor pixels.
                    rawPoint(SIMD2(Float(point.x), uprightSize.y - Float(point.y)), orientation: orientation, rawSize: rawSize)
                }
            if let correction = FaceContourMeasurer.correction(contour: points, silhouette: silhouette) {
                return correction
            }
        }
        return nil
    }

    /// Maps a top-left-origin point in the upright (rotated) image back to the sensor buffer.
    static func rawPoint(_ upright: SIMD2<Float>, orientation: CGImagePropertyOrientation,
                         rawSize: SIMD2<Float>) -> SIMD2<Float> {
        switch orientation {
        case .right: SIMD2(upright.y, rawSize.y - upright.x)
        case .left: SIMD2(rawSize.x - upright.y, upright.x)
        case .leftMirrored: SIMD2(upright.y, upright.x)
        case .rightMirrored: SIMD2(rawSize.x - upright.y, rawSize.y - upright.x)
        default: upright
        }
    }
}
