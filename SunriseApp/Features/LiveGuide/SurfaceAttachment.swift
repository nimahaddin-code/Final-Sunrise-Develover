// -Nimah: Attachment barycentric pada triangle aktual; tidak memakai screen offset atau UV.
import Foundation
import simd

struct SurfaceAttachment: Sendable {
    let indices: SIMD3<Int>
    let weights: SIMD3<Float>
    func position(in vertices: [SIMD3<Float>], lift: Float = 0) -> SIMD3<Float>? {
        // -Nimah: Avoid allocating an index array for each live vertex attachment.
        guard vertices.indices.contains(indices.x),vertices.indices.contains(indices.y),vertices.indices.contains(indices.z) else { return nil }
        let a=vertices[indices.x], b=vertices[indices.y], c=vertices[indices.z]
        let n=simd_cross(b-a,c-a), length=simd_length(n)
        guard length > 0.00000001 else { return nil }
        let normal=n/length * (n.z < 0 ? Float(-1) : 1)
        let point=a*weights.x+b*weights.y+c*weights.z+normal*lift
        return point.x.isFinite && point.y.isFinite && point.z.isFinite ? point : nil
    }
    static func bind(_ point: SIMD2<Float>, vertices: [SIMD3<Float>], triangles: [Int16], minimumZ: Float) -> SurfaceAttachment? {
        guard point.x.isFinite, point.y.isFinite, triangles.count % 3 == 0 else { return nil }
        var result: SurfaceAttachment?, frontZ = -Float.infinity
        for offset in stride(from: 0, to: triangles.count, by: 3) {
            let ids=SIMD3(Int(triangles[offset]),Int(triangles[offset+1]),Int(triangles[offset+2]))
            guard [ids.x,ids.y,ids.z].allSatisfy(vertices.indices.contains) else { return nil }
            let a=vertices[ids.x], b=vertices[ids.y], c=vertices[ids.z]
            let denominator=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
            guard abs(denominator)>0.000000001 else { continue }
            let u=((b.y-c.y)*(point.x-c.x)+(c.x-b.x)*(point.y-c.y))/denominator
            let v=((c.y-a.y)*(point.x-c.x)+(a.x-c.x)*(point.y-c.y))/denominator
            let w=1-u-v
            guard min(u,min(v,w)) >= -0.00001 else { continue }
            let z=a.z*u+b.z*v+c.z*w
            guard z>=minimumZ,z>frontZ else { continue }
            result=SurfaceAttachment(indices:ids,weights:SIMD3(u,v,w)); frontZ=z
        }
        return result
    }
}

// -Nimah: Scope eksplisit; pergantian langkah selalu kembali ke satu layer.
enum MakeupLayerSelection {
    static func layers(step: TutorialStep, fullLook: Bool, previous: Bool) -> [TutorialStep] {
        if fullLook { return TutorialStep.allCases }
        guard previous,let index=TutorialStep.allCases.firstIndex(of:step) else { return [step] }
        return Array(TutorialStep.allCases.prefix(index+1))
    }
}
