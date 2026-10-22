import CoreGraphics
import ImageIO
import Vision
import simd

/// One camera frame plus the face mesh in it, copied out of the ARFrame for background Vision work.
struct FeatureLocatorInput: Sendable {
    let contour: ContourInput
    let vertices: [SIMD3<Float>]
    let textureCoordinates: [SIMD2<Float>]
    let triangleIndices: [Int16]

    func projectedMesh() -> ProjectedFaceMesh? {
        guard let points = contour.project(vertices) else { return nil }
        let toCamera = simd_inverse(contour.cameraTransform) * contour.faceTransform
        let depths = vertices.map { -(toCamera * SIMD4($0, 1)).z }
        return ProjectedFaceMesh(points: points, depths: depths, textureCoordinates: textureCoordinates,
                                 triangleIndices: triangleIndices)
    }
}

/// Finds the brows and eyes with Vision and maps them onto the ARKit face mesh's texture.
enum FaceFeatureLocator {
    /// Tries `preferred` (the orientation that worked before) or else every portrait orientation.
    static func features(for input: FeatureLocatorInput,
                         preferred: CGImagePropertyOrientation?) -> (FaceFeatureMap, CGImagePropertyOrientation)? {
        guard let mesh = input.projectedMesh() else { return nil }
        for orientation in preferred.map({ [$0] }) ?? FaceContourDetector.orientations {
            if let map = features(in: input.contour.pixelBuffer.buffer, mesh: mesh, orientation: orientation) {
                return (map, orientation)
            }
        }
        return nil
    }

    private static func features(in buffer: CVPixelBuffer, mesh: ProjectedFaceMesh,
                                 orientation: CGImagePropertyOrientation) -> FaceFeatureMap? {
        let request = VNDetectFaceLandmarksRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
        } catch {
            return nil
        }
        let rawSize = SIMD2(Float(CVPixelBufferGetWidth(buffer)), Float(CVPixelBufferGetHeight(buffer)))
        let uprightSize = SIMD2(rawSize.y, rawSize.x)
        let imageSize = CGSize(width: CGFloat(uprightSize.x), height: CGFloat(uprightSize.y))
        let largest = (request.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }
        guard let landmarks = largest?.landmarks else { return nil }

        func textureCoordinates(_ region: VNFaceLandmarkRegion2D?) -> [SIMD2<Float>]? {
            guard let region else { return nil }
            let mapped = region.pointsInImage(imageSize: imageSize).compactMap { point in
                // Vision's origin is bottom-left; convert to top-left, then back to sensor pixels.
                let raw = FaceContourDetector.rawPoint(SIMD2(Float(point.x), uprightSize.y - Float(point.y)),
                                                       orientation: orientation, rawSize: rawSize)
                return mesh.textureCoordinate(at: raw)
            }
            return mapped.count == region.pointCount ? mapped : nil
        }

        guard let leftBrow = textureCoordinates(landmarks.leftEyebrow), let leftEye = textureCoordinates(landmarks.leftEye),
              let rightBrow = textureCoordinates(landmarks.rightEyebrow),
              let rightEye = textureCoordinates(landmarks.rightEye) else { return nil }
        let map = FaceFeatureMap(left: .init(brow: leftBrow, eye: leftEye), right: .init(brow: rightBrow, eye: rightEye),
                                 nose: textureCoordinates(landmarks.nose) ?? [])
        return map.isPlausible ? map : nil
    }
}
