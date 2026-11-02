// -Nimah: Apple Vision mencari alis di frame AR yang sama; tidak membuat sesi kamera kedua.
import ARKit
import Vision
import CoreML
import ImageIO

struct FaceLandmarkFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let projection: FaceLandmarkProjection
    let orientation: CGImagePropertyOrientation
    let timestamp: TimeInterval
    let anchorID: UUID
    let vertices: [SIMD3<Float>]
    let triangles: [Int16]
    let leftEye: SIMD3<Float>
    let rightEye: SIMD3<Float>
    // -Nimah: Input eksplisit juga dipakai fixture/probe; tidak menyimpan buffer setelah worker selesai.
    init(pixelBuffer:CVPixelBuffer,projection:FaceLandmarkProjection,orientation:CGImagePropertyOrientation,timestamp:TimeInterval,
         anchorID:UUID,vertices:[SIMD3<Float>],triangles:[Int16],leftEye:SIMD3<Float>,rightEye:SIMD3<Float>) {
        self.pixelBuffer=pixelBuffer; self.projection=projection; self.orientation=orientation; self.timestamp=timestamp
        self.anchorID=anchorID; self.vertices=vertices; self.triangles=triangles; self.leftEye=leftEye; self.rightEye=rightEye
    }
    init(frame: ARFrame, anchor: ARFaceAnchor) {
        pixelBuffer=frame.capturedImage; timestamp=frame.timestamp; anchorID=anchor.identifier
        // -Nimah: UI portrait saja. Mirroring ini hanya input Vision, dibalik sebelum proyeksi sensor.
        orientation = .leftMirrored
        projection=FaceLandmarkProjection(intrinsics:frame.camera.intrinsics,
            cameraFromFace:simd_inverse(frame.camera.transform)*anchor.transform,
            imageWidth:CVPixelBufferGetWidth(pixelBuffer),imageHeight:CVPixelBufferGetHeight(pixelBuffer))
        vertices=Array(anchor.geometry.vertices); triangles=Array(anchor.geometry.triangleIndices)
        let left=anchor.leftEyeTransform.columns.3,right=anchor.rightEyeTransform.columns.3
        leftEye=SIMD3(left.x,left.y,left.z); rightEye=SIMD3(right.x,right.y,right.z)
    }
}
// -Nimah: Real Vision eye/pupil/nose observations, not an iris or medical scanner.
struct DetectedEyeScan:Sendable {
    struct Eye:Sendable { let contour:[SIMD2<Float>]; let pupil:SIMD2<Float> }
    let eyes:[Eye]
    let nose:[SIMD2<Float>]
}
struct DetectedEyebrows: Sendable {
    let first: [SIMD2<Float>]
    let second: [SIMD2<Float>]
    // -Nimah: Confidence observasi wajah Vision, bukan confidence pixel/landmark alis individual.
    let faceObservationConfidence: Float
    var eyeScan:DetectedEyeScan? = nil
}
protocol FaceLandmarkProviding: Sendable {
    func detectEyebrows(in frame: FaceLandmarkFrame) throws -> [DetectedEyebrows]
}
struct VisionFaceLandmarkProvider: FaceLandmarkProviding {
    // -Nimah: Real brow contours remain usable even when optional pupil/nose formula points are absent.
    var requireEyeFormula=true
    func detectEyebrows(in frame: FaceLandmarkFrame) throws -> [DetectedEyebrows] {
        let request=VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        // -Nimah: Simulator dapat gagal membuat konteks GPU Vision; jalankan inference CPU sungguhan.
        for (stage,devices) in try request.supportedComputeStageDevices {
            if let cpu=devices.first(where:{ if case .cpu=$0 { return true }; return false }) {
                request.setComputeDevice(cpu,for:stage)
            }
        }
        #endif
        try VNImageRequestHandler(cvPixelBuffer:frame.pixelBuffer,orientation:frame.orientation,options:[:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard observation.confidence>=0.5,let landmarks=observation.landmarks,
                  let left=landmarks.leftEyebrow,let right=landmarks.rightEyebrow,left.pointCount>=3,right.pointCount>=3 else { return nil }
            func raw(_ region: VNFaceLandmarkRegion2D) -> [SIMD2<Float>] {
                region.normalizedPoints.map { FaceLandmarkProjection.landmarkToRaw($0,faceBox:observation.boundingBox,orientation:frame.orientation) }
            }
            guard let le=landmarks.leftEye,let re=landmarks.rightEye,
                  let lp=landmarks.leftPupil,let rp=landmarks.rightPupil,let nose=landmarks.nose,
                  le.pointCount>=4,re.pointCount>=4,lp.pointCount>0,rp.pointCount>0,nose.pointCount>=3 else {
                return requireEyeFormula ? nil : DetectedEyebrows(first:raw(left),second:raw(right),faceObservationConfidence:observation.confidence)
            }
            return DetectedEyebrows(first:raw(left),second:raw(right),faceObservationConfidence:observation.confidence,
                eyeScan:DetectedEyeScan(eyes:[.init(contour:raw(le),pupil:raw(lp)[0]),.init(contour:raw(re),pupil:raw(rp)[0])],nose:raw(nose)))
        }
    }
}
