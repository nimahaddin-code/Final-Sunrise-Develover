// -Nimah: Data alis hasil Vision + attachment mesh, tanpa daftar indeks alis buatan.
import Foundation
import simd

enum EyebrowSide: String, Sendable, Codable { case left, right }
struct EyebrowRegion: Sendable {
    struct Brow: Sendable, Codable {
        let side: EyebrowSide
        let landmarks: [SurfaceAttachment]
        var mapping:BrowAnatomicalMapping? = nil
    }
    let brows: [Brow]
    let faceObservationConfidence: Float
    let timestamp: TimeInterval
    let anchorID: UUID
    let restVertices: [SIMD3<Float>]
    let triangles: [Int16]
    var eyeCenters:[SIMD3<Float>] = []
}
enum EyebrowRegionMapper {
    static func map(_ detection: DetectedEyebrows, projection: FaceLandmarkProjection, vertices:[SIMD3<Float>], triangles:[Int16],
                    leftEye: SIMD3<Float>, rightEye: SIMD3<Float>, timestamp: TimeInterval, anchorID: UUID,requireFormula:Bool = true,diagnostic:((String)->Void)? = nil) -> EyebrowRegion? {
        guard detection.faceObservationConfidence>=0.5,vertices.count>=12,
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              let low=vertices.map(\.x).min(),let high=vertices.map(\.x).max() else { return nil }
        let width=(high-low)/2
        guard width>0.02,width<0.16 else { return nil }
        var brows:[EyebrowRegion.Brow]=[]
        for points in [detection.first,detection.second] {
            guard points.count>=3 else { return nil }
            let attachments=points.compactMap { projection.attachment(for:$0,vertices:vertices,triangles:triangles) }
            guard attachments.count>=3,Float(attachments.count)/Float(points.count)>=0.8 else { diagnostic?("projection_insufficient_attachments");return nil }
            let local=attachments.compactMap { $0.position(in:vertices) }
            guard local.count==attachments.count else { return nil }
            let center=local.reduce(SIMD3<Float>.zero,+)/Float(local.count)
            let leftDistance=simd_distance(center,leftEye),rightDistance=simd_distance(center,rightEye)
            let side: EyebrowSide=leftDistance<rightDistance ? .left : .right
            let eye=side == .left ? leftEye : rightEye
            let browWidth=local.map(\.x).max()!-local.map(\.x).min()!
            // -Nimah: Gate anatomi relatif ukuran wajah; salah wajah/hidung/kelopak tidak dijadikan alis.
            guard center.y-eye.y>width*0.025,center.y-eye.y<width*0.65,
                  abs(center.x-eye.x)<width*0.35,browWidth>width*0.12,browWidth<width*0.9,
                  local.allSatisfy({ abs($0.x)<width*1.15 && $0.y>eye.y-width*0.03 }),
                  !brows.contains(where: { $0.side==side }) else { diagnostic?("anatomical_bounds");return nil }
            // -Nimah: Pigment uses measured brow contours. Optional formula rays must not invalidate those contours.
            let mapping=detection.eyeScan.flatMap { scan in BrowMappingFormula.scan(scan,side:side,eye:eye,otherEye:side == .left ? rightEye : leftEye,
                brow:local,projection:projection,vertices:vertices,triangles:triangles,faceWidth:width) }
            if requireFormula && mapping==nil { diagnostic?("formula_missing");return nil }
            brows.append(.init(side:side,landmarks:attachments,mapping:mapping))
        }
        guard brows.count==2 else { return nil }
        return EyebrowRegion(brows:brows,faceObservationConfidence:detection.faceObservationConfidence,timestamp:timestamp,
            anchorID:anchorID,restVertices:vertices,triangles:triangles,eyeCenters:[leftEye,rightEye])
    }
}

// -Nimah: Makeup mapping convention, not a universal rule of beauty or a symmetry correction.
struct BrowAnatomicalMapping:Sendable,Codable {
    let ala:SIMD3<Float>
    let pupil:SIMD3<Float>
    let outerEye:SIMD3<Float>
    let start:SIMD2<Float>
    let arch:SIMD2<Float>
    let tail:SIMD2<Float>
}
enum BrowMappingFormula {
    // -Nimah: Intersection of N + t(E-N) with brow level Y. Reject parallel/backward rays.
    static func intersection(nose:SIMD2<Float>,through eye:SIMD2<Float>,level:Float) -> SIMD2<Float>? {
        guard [nose.x,nose.y,eye.x,eye.y,level].allSatisfy(\.isFinite),eye.y-nose.y>0.0001 else { return nil }
        let t=(level-nose.y)/(eye.y-nose.y)
        guard t>1 else { return nil }
        return nose+(eye-nose)*t
    }
    static func scan(_ scan:DetectedEyeScan,side:EyebrowSide,eye:SIMD3<Float>,otherEye:SIMD3<Float>,brow:[SIMD3<Float>],
                     projection:FaceLandmarkProjection,vertices:[SIMD3<Float>],triangles:[Int16],faceWidth:Float) -> BrowAnatomicalMapping? {
        guard scan.eyes.count==2,scan.nose.count>=3,
              let head=brow.min(by:{ abs($0.x)<abs($1.x) }),let end=brow.max(by:{ abs($0.x)<abs($1.x) }),
              let archY=brow.map(\.y).max() else { return nil }
        let sign:Float=eye.x>otherEye.x ? 1 : -1
        var candidates:[([SIMD3<Float>],SIMD3<Float>)]=[]
        for detected in scan.eyes {
            let rough=detected.contour.compactMap { projection.pointOnEyePlane(for:$0,depth:eye.z) }
            guard rough.count==detected.contour.count,!rough.isEmpty else { return nil }
            let center=rough.reduce(SIMD3<Float>.zero,+)/Float(rough.count)
            guard simd_distance(center,eye)<simd_distance(center,otherEye) else { continue }
            guard let depth=projection.eyeSurfaceDepth(contour:detected.contour,vertices:vertices,eye:eye,faceWidth:faceWidth) else { return nil }
            let contour=detected.contour.compactMap { projection.pointOnEyePlane(for:$0,depth:depth) }
            guard contour.count==detected.contour.count,let pupil=projection.pointOnEyePlane(for:detected.pupil,depth:depth) else { return nil }
            candidates.append((contour,pupil))
        }
        guard candidates.count==1 else { return nil }
        let (contour,pupil)=candidates[0]
        guard let inner=contour.min(by:{ sign*$0.x<sign*$1.x }),let outer=contour.max(by:{ sign*$0.x<sign*$1.x }),
              let top=contour.map(\.y).max(),let bottom=contour.map(\.y).min() else { return nil }
        let eyeWidth=abs(outer.x-inner.x),pupilRatio=(pupil.x-inner.x)/(outer.x-inner.x)
        // -Nimah: Reject closed eyes, off-center gaze and implausible eye regions before computing brows.
        guard eyeWidth>faceWidth*0.18,eyeWidth<faceWidth*0.65,(top-bottom)/eyeWidth>0.12,
              pupilRatio>0.20,pupilRatio<0.80,pupil.y>=bottom,pupil.y<=top,
              abs(pupil.y-eye.y)<faceWidth*0.16 else { return nil }
        let nose=scan.nose.compactMap { projection.attachment(for:$0,vertices:vertices,triangles:triangles)?.position(in:vertices) }
        guard nose.count>=3,Float(nose.count)/Float(scan.nose.count)>=0.8,
              let ala=nose.max(by:{ sign*$0.x<sign*$1.x }),sign*ala.x>0,
              abs(ala.x)<faceWidth*0.4,eye.y-ala.y>faceWidth*0.12,eye.y-ala.y<faceWidth*1.1 else { return nil }
        let n=SIMD2(ala.x,ala.y),start=SIMD2(ala.x,head.y)
        guard let arch=intersection(nose:n,through:SIMD2(pupil.x,pupil.y),level:archY),
              let tail=intersection(nose:n,through:SIMD2(outer.x,outer.y),level:end.y) else { return nil }
        let width=sign*(tail.x-start.x),ratio=sign*(arch.x-start.x)/width
        guard width>faceWidth*0.22,width<faceWidth*0.95,ratio>0.25,ratio<0.9,
              abs(start.x-head.x)<faceWidth*0.20,abs(tail.x-end.x)<faceWidth*0.32 else { return nil }
        // -Nimah: Formula points must be on actual brow skin; do not clamp erroneous mappings into place.
        for p in [start,arch,tail] {
            guard SurfaceAttachment.bind(p,vertices:vertices,triangles:triangles,minimumZ:min(head.z,end.z)-faceWidth*0.2) != nil else { return nil }
        }
        return .init(ala:ala,pupil:pupil,outerEye:outer,start:start,arch:arch,tail:tail)
    }
}
