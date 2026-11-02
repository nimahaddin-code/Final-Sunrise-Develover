import CoreGraphics
import CoreML
import ImageIO
import Vision
import simd

/// Vision face landmarks of one photo, in image pixels with Vision's bottom-left origin (+y up).
struct PhotoLandmarks: Equatable, Sendable {
    var faceContour: [SIMD2<Float>]
    var leftEyebrow: [SIMD2<Float>]
    var rightEyebrow: [SIMD2<Float>]
    var leftEye: [SIMD2<Float>]
    var rightEye: [SIMD2<Float>]
    var boundingBox: CGRect?
}

/// Measures `FaceProportions` from a single 2D photo instead of the ARKit mesh.
///
/// Vision's face contour only runs from temple to temple around the jaw, so the upper face is estimated:
/// the forehead width is the span of the outer eyebrow ends, and the face top is the mean of the facial-thirds
/// rule (brow-to-hairline = half of chin-to-brow) and the top of Vision's face box. Cheekbones are the contour's
/// widest point; jaw and chin use `FaceMeshMeasurer`'s bands as fractions of chin-to-top. Measurements are taken
/// along the eye line, so head roll does not matter. Photo ratios differ from mesh ratios, so classify them
/// with `FaceShapeClassifier.photo`, not the AR reference.
enum PhotoFaceMeasurer {
    /// Average photo proportions, fitted on a labelled dataset; see `FaceShapeDatasetEvalTests`.
    static let reference = FaceProportions(length: 1.25, forehead: 0.85, jaw: 0.8, chin: 0.45)
    static let unit: Float = 0.06
    /// Larger head turns squash one side of the face in 2D.
    static let maxYaw = Float.pi / 8

    enum Failure: Error, Equatable { case visionFailed, noFace, turnedAway, unmeasurable }

    static func proportions(of image: CGImage, orientation: CGImagePropertyOrientation = .up) -> Result<FaceProportions, Failure> {
        landmarks(in: image, orientation: orientation).flatMap { landmarks in
            proportions(of: landmarks).map { .success($0) } ?? .failure(.unmeasurable)
        }
    }

    static func proportions(of landmarks: PhotoLandmarks) -> FaceProportions? {
        guard let leftEye = centroid(landmarks.leftEye), let rightEye = centroid(landmarks.rightEye),
              let brow = centroid(landmarks.leftEyebrow + landmarks.rightEyebrow) else { return nil }
        let eyes = (leftEye + rightEye) / 2, across = rightEye - leftEye
        var up = SIMD2(-across.y, across.x)
        if simd_dot(up, brow - eyes) < 0 { up = -up }
        guard let frame = FaceFrame2D(origin: eyes, xTip: eyes + across, yTip: eyes + up) else { return nil }

        let contour = landmarks.faceContour.map(frame.local)
        let brows = (landmarks.leftEyebrow + landmarks.rightEyebrow).map(frame.local)
        guard let chinHeight = contour.map(\.y).min(), let contourTop = [contour.first?.y, contour.last?.y].compactMap({ $0 }).min(),
              let browMinX = brows.map(\.x).min(), let browMaxX = brows.map(\.x).max() else { return nil }
        let browHeight = frame.local(brow).y
        guard browHeight > chinHeight, contourTop > chinHeight else { return nil }

        var top = browHeight + (browHeight - chinHeight) / 2
        if let box = landmarks.boundingBox {
            let boxTop = frame.local(SIMD2(Float(box.midX), Float(box.maxY))).y
            if boxTop > browHeight { top = (top + boxTop) / 2 }
        }
        let length = top - chinHeight

        func width(_ band: FaceMeshMeasurer.Band) -> Float? {
            let widths = (0...4).compactMap { step in
                let fraction = band.lower + (band.upper - band.lower) * Float(step) / 4
                return FaceContourMeasurer.width(of: contour, atHeight: chinHeight + fraction * length)
            }
            return widths.isEmpty ? nil : widths.reduce(0, +) / Float(widths.count)
        }
        let cheekbones = (1...24).compactMap { step in
            FaceContourMeasurer.width(of: contour, atHeight: chinHeight + (contourTop - chinHeight) * Float(step) / 24)
        }.max()

        guard let cheekbones, let jaw = width(FaceMeshMeasurer.jawBand), let chin = width(FaceMeshMeasurer.chinBand),
              browMaxX > browMinX else { return nil }
        return FaceProportions(length: length / cheekbones, forehead: (browMaxX - browMinX) / cheekbones,
                               jaw: jaw / cheekbones, chin: chin / jaw)
    }

    /// Landmarks of the largest face in the photo.
    static func landmarks(in image: CGImage, orientation: CGImagePropertyOrientation) -> Result<PhotoLandmarks, Failure> {
        let request = VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        // The simulator cannot create Vision's GPU/Neural Engine inference context; run on the CPU (dataset eval).
        if let cpu = try? request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
        do {
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        } catch {
            return .failure(.visionFailed)
        }
        guard let face = request.results?.max(by: { $0.boundingBox.area < $1.boundingBox.area }),
              let landmarks = face.landmarks, let contour = landmarks.faceContour,
              let leftEyebrow = landmarks.leftEyebrow, let rightEyebrow = landmarks.rightEyebrow,
              let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye else { return .failure(.noFace) }
        if let yaw = face.yaw?.floatValue, abs(yaw) > maxYaw { return .failure(.turnedAway) }

        // Normalized coordinates refer to the upright image, so swap the size for 90° EXIF rotations.
        let rotated = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let size = rotated ? CGSize(width: image.height, height: image.width) : CGSize(width: image.width, height: image.height)
        func points(_ region: VNFaceLandmarkRegion2D) -> [SIMD2<Float>] {
            region.pointsInImage(imageSize: size).map { SIMD2(Float($0.x), Float($0.y)) }
        }
        return .success(PhotoLandmarks(faceContour: points(contour), leftEyebrow: points(leftEyebrow), rightEyebrow: points(rightEyebrow),
                              leftEye: points(leftEye), rightEye: points(rightEye),
                              boundingBox: VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))))
    }

    private static func centroid(_ points: [SIMD2<Float>]) -> SIMD2<Float>? {
        points.isEmpty ? nil : points.reduce(.zero, +) / Float(points.count)
    }
}

extension FaceShapeClassifier {
    /// Classifier for `PhotoFaceMeasurer`; the AR scan keeps its own reference from ARKit's neutral mesh.
    static let photo = FaceShapeClassifier(reference: PhotoFaceMeasurer.reference, unit: PhotoFaceMeasurer.unit)
}

private extension CGRect {
    var area: CGFloat { width * height }
}
