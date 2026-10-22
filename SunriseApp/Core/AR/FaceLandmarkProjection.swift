// -Nimah: Koordinat Vision diubah kembali ke sensor mentah sebelum ray–triangle intersection.
import Foundation
import ImageIO
import simd

struct FaceLandmarkProjection: Sendable {
    let intrinsics: simd_float3x3
    let cameraFromFace: simd_float4x4
    let imageWidth: Int
    let imageHeight: Int
    static func rawPoint(fromOriented point: SIMD2<Float>, orientation: CGImagePropertyOrientation) -> SIMD2<Float> {
        let x=point.x,y=point.y
        switch orientation {
        case .up: return point
        case .upMirrored: return SIMD2(1-x,y)
        case .down: return SIMD2(1-x,1-y)
        case .downMirrored: return SIMD2(x,1-y)
        case .left: return SIMD2(1-y,x)
        case .right: return SIMD2(y,1-x)
        case .leftMirrored: return SIMD2(y,x)
        case .rightMirrored: return SIMD2(1-y,1-x)
        @unknown default: return point
        }
    }
    static func landmarkToRaw(_ point: CGPoint, faceBox: CGRect, orientation: CGImagePropertyOrientation) -> SIMD2<Float> {
        // -Nimah: Vision origin lower-left; orientation inverse memakai top-left normalized coordinates.
        let oriented=SIMD2(Float(faceBox.minX+point.x*faceBox.width),Float(1-(faceBox.minY+point.y*faceBox.height)))
        return rawPoint(fromOriented:oriented,orientation:orientation)
    }
    func ray(for raw: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard imageWidth>0,imageHeight>0,raw.x.isFinite,raw.y.isFinite,
              raw.x>=0,raw.x<=1,raw.y>=0,raw.y<=1,intrinsics[0,0]>0,intrinsics[1,1]>0 else { return nil }
        let x=(raw.x*Float(imageWidth)-intrinsics[2,0])/intrinsics[0,0]
        let y=(raw.y*Float(imageHeight)-intrinsics[2,1])/intrinsics[1,1]
        let faceFromCamera=simd_inverse(cameraFromFace)
        let origin4=faceFromCamera*SIMD4<Float>(0,0,0,1)
        let direction4=faceFromCamera*SIMD4<Float>(x,-y,-1,0)
        let direction=SIMD3(direction4.x,direction4.y,direction4.z)
        guard simd_length(direction)>0,direction.x.isFinite,direction.y.isFinite,direction.z.isFinite else { return nil }
        return (SIMD3(origin4.x,origin4.y,origin4.z),simd_normalize(direction))
    }
    // -Nimah: Estimate lid depth from nearby actual 3D face vertices, not the eyeball center transform.
    func eyeSurfaceDepth(contour:[SIMD2<Float>],vertices:[SIMD3<Float>],eye:SIMD3<Float>,faceWidth:Float) -> Float? {
        let candidates=vertices.filter { abs($0.x-eye.x)<faceWidth*0.35 && abs($0.y-eye.y)<faceWidth*0.24 && $0.z>eye.z-faceWidth*0.1 }
            .compactMap { vertex -> (SIMD3<Float>,SIMD2<Float>)? in project(vertex).map { (vertex,$0) } }
        guard contour.count>=4,!candidates.isEmpty else { return nil }
        var depths:[Float]=[]
        for raw in contour {
            guard let nearest=candidates.min(by:{ simd_distance_squared($0.1,raw)<simd_distance_squared($1.1,raw) }),
                  simd_distance(nearest.1,raw)<0.012 else { continue }
            depths.append(nearest.0.z)
        }
        guard depths.count>=4,Float(depths.count)/Float(contour.count)>=0.6 else { return nil }
        depths.sort()
        return depths[depths.count/2]
    }
    // -Nimah: Pupil rays cross a mesh eye opening; intersect the eye-depth plane instead of inventing skin there.
    func pointOnEyePlane(for raw:SIMD2<Float>,depth:Float) -> SIMD3<Float>? {
        guard depth.isFinite,let ray=ray(for:raw),abs(ray.direction.z)>0.00001 else { return nil }
        let t=(depth-ray.origin.z)/ray.direction.z
        guard t>0 else { return nil }
        return ray.origin+ray.direction*t
    }
    func project(_ local: SIMD3<Float>) -> SIMD2<Float>? {
        let p=cameraFromFace*SIMD4(local.x,local.y,local.z,1)
        guard p.z < -0.001,imageWidth>0,imageHeight>0 else { return nil }
        return SIMD2((intrinsics[0,0]*p.x/(-p.z)+intrinsics[2,0])/Float(imageWidth),
            (intrinsics[2,1]-intrinsics[1,1]*p.y/(-p.z))/Float(imageHeight))
    }
    func attachment(for raw: SIMD2<Float>, vertices:[SIMD3<Float>], triangles:[Int16]) -> SurfaceAttachment? {
        guard let ray=ray(for:raw),triangles.count%3==0 else { return nil }
        var nearest=Float.infinity,result:SurfaceAttachment?
        for offset in stride(from:0,to:triangles.count,by:3) {
            let ids=SIMD3(Int(triangles[offset]),Int(triangles[offset+1]),Int(triangles[offset+2]))
            guard [ids.x,ids.y,ids.z].allSatisfy(vertices.indices.contains) else { return nil }
            let a=vertices[ids.x],b=vertices[ids.y],c=vertices[ids.z],edge1=b-a,edge2=c-a
            let h=simd_cross(ray.direction,edge2),det=simd_dot(edge1,h)
            guard abs(det)>0.000000001 else { continue }
            let inverse=1/det,s=ray.origin-a,u=inverse*simd_dot(s,h)
            guard u>=0,u<=1 else { continue }
            let q=simd_cross(s,edge1),v=inverse*simd_dot(ray.direction,q)
            guard v>=0,u+v<=1 else { continue }
            let t=inverse*simd_dot(edge2,q)
            if t>0.001,t<nearest {
                nearest=t; result=SurfaceAttachment(indices:ids,weights:SIMD3(1-u-v,u,v))
            }
        }
        return result
    }
}
