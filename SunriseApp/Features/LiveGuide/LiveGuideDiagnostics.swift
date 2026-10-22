// -Nimah: Debug hanya di memori; tidak merekam foto, video atau mesh wajah.
import SceneKit
import UIKit
import simd

enum LiveGuideDebugMode: String, CaseIterable, Identifiable {
    case off, wireframe, regions, uv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .wireframe: return "Face wireframe"
        case .regions: return "Eye attachments + region IDs"
        case .uv: return "UV orientation atlas"
        }
    }
}
enum EyelinerRenderer {
    static func material(tint: UIColor = UIColor(red:0.09,green:0.045,blue:0.035,alpha:1)) -> SCNMaterial {
        let material=SCNMaterial()
        material.lightingModel = .constant; material.diffuse.contents=tint
        material.blendMode = .alpha; material.transparencyMode = .aOne
        material.isDoubleSided=true; material.writesToDepthBuffer=false
        material.readsFromDepthBuffer=true
        return material
    }
    static func geometry(eye: EyelinerRegion.Eye, vertices: [SIMD3<Float>], material: SCNMaterial) -> SCNGeometry? {
        let positions=eye.attachments.compactMap { $0.position(in:vertices,lift:0.0006) }
        guard positions.count==eye.attachments.count,positions.count==eye.alpha.count else { return nil }
        let source=SCNGeometrySource(vertices:positions.map { SCNVector3($0.x,$0.y,$0.z) })
        let colors=eye.alpha.map { SIMD4<Float>(1,1,1,$0) }
        let data=colors.withUnsafeBytes { Data($0) }
        let colorSource=SCNGeometrySource(data:data,semantic:.color,vectorCount:colors.count,usesFloatComponents:true,
            componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
        let element=SCNGeometryElement(indices:eye.triangles,primitiveType:.triangles)
        let geometry=SCNGeometry(sources:[source,colorSource],elements:[element]); geometry.materials=[material]
        return geometry
    }
}
enum LiveGuideDiagnostics {
    // -Nimah: Membaca UV milik renderer sebenarnya, termasuk data offset/stride, bukan mengasumsikan buffer ARKit sama.
    static func textureCoordinates(of geometry: SCNGeometry) -> [SIMD2<Float>]? {
        guard let source=geometry.sources(for:.texcoord).first,source.usesFloatComponents,
              source.bytesPerComponent==4,source.componentsPerVector>=2 else { return nil }
        return source.data.withUnsafeBytes { buffer in
            var result:[SIMD2<Float>]=[]
            for i in 0..<source.vectorCount {
                let offset=source.dataOffset+i*source.dataStride
                guard offset>=0,offset+8<=buffer.count else { return nil }
                let u=buffer.loadUnaligned(fromByteOffset:offset,as:Float.self)
                let v=buffer.loadUnaligned(fromByteOffset:offset+4,as:Float.self)
                guard u.isFinite,v.isFinite else { return nil }
                result.append(SIMD2(u,v))
            }
            return result
        }
    }
    static func atlas() -> UIImage {
        let size: CGFloat=512
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:size,height:size),format:format).image { context in
            let entries:[(UIColor,String,CGPoint)]=[
                (.red,"TOP / V1 · LEFT / U0",CGPoint(x:0,y:0)),(.green,"TOP / V1 · RIGHT / U1",CGPoint(x:256,y:0)),
                (.blue,"BOTTOM / V0 · LEFT / U0",CGPoint(x:0,y:256)),(.yellow,"BOTTOM / V0 · RIGHT / U1",CGPoint(x:256,y:256))]
            for (color,title,point) in entries {
                color.withAlphaComponent(0.75).setFill(); context.fill(CGRect(origin:point,size:CGSize(width:256,height:256)))
                (title as NSString).draw(in:CGRect(x:point.x+8,y:point.y+80,width:240,height:100),withAttributes:[.font:UIFont.boldSystemFont(ofSize:16),.foregroundColor:UIColor.black])
            }
        }
    }
    static func label(_ title: String) -> SCNNode {
        let text=SCNText(string:title,extrusionDepth:0)
        text.font=UIFont.systemFont(ofSize:8); text.flatness=0.3
        let material=SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents=UIColor.cyan
        material.readsFromDepthBuffer=true; text.materials=[material]
        let node=SCNNode(geometry:text); node.scale=SCNVector3(0.0004,0.0004,0.0004)
        return node
    }
}

// -Nimah: Pigmen non-eyeliner diikat langsung ke vertex yang sama dengan panduan; tidak melewati UV/atlas.
struct SurfaceRenderProfile: Sendable {
    let surface: FaceSurfaceProfile
    let restVertices: [SIMD3<Float>]
    let triangles: [Int16]
    let defaultEyeliner: EyelinerRegion
    init(surface: FaceSurfaceProfile, vertices: [SIMD3<Float>], triangles: [Int16]) {
        self.surface=surface; restVertices=vertices; self.triangles=triangles
        defaultEyeliner=EyelinerRegion.make(vertices:vertices,triangles:triangles,rims:surface.eyeRims,style:EyelinerStyle())
    }
}
enum SurfaceMakeupRenderer {
    static func colors(surface: FaceSurfaceProfile, steps: [TutorialStep], referenceID: String) -> [SIMD4<Float>] {
        var combined=Array(repeating:SIMD4<Float>.zero,count:surface.vertexCount)
        // -Nimah: Layer order stabil; eyeliner memakai renderer strip terpisah.
        for step in [TutorialStep.contour,.blush,.eyeshadow,.lips] where steps.contains(step) {
            guard let weights=surface.weights[step],weights.count==combined.count else { continue }
            let tone=MakeupTextureBaker.tone(step,referenceID)
            for i in combined.indices {
                let alpha=max(0,min(1,weights[i]))*tone.w
                let source=SIMD4(tone.x*alpha,tone.y*alpha,tone.z*alpha,alpha)
                combined[i]=source+combined[i]*(1-alpha)
            }
        }
        // -Nimah: Atribut vertex menyimpan straight RGB; SceneKit melakukan alpha blending.
        return combined.map { color in
            color.w>0 ? SIMD4(color.x/color.w,color.y/color.w,color.z/color.w,color.w) : .zero
        }
    }
    static func colorSource(_ colors: [SIMD4<Float>]) -> SCNGeometrySource {
        SCNGeometrySource(data:colors.withUnsafeBytes { Data($0) },semantic:.color,vectorCount:colors.count,
            usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
    }
    static func geometry(vertices: [SIMD3<Float>], triangles: [Int16], colorSource: SCNGeometrySource, material: SCNMaterial) -> SCNGeometry? {
        guard vertices.count==colorSource.vectorCount,triangles.count%3==0,
              triangles.allSatisfy({ vertices.indices.contains(Int($0)) }) else { return nil }
        let source=SCNGeometrySource(vertices:vertices.map { SCNVector3($0.x,$0.y,$0.z) })
        let geometry=SCNGeometry(sources:[source,colorSource],elements:[SCNGeometryElement(indices:triangles,primitiveType:.triangles)])
        geometry.materials=[material]
        return geometry
    }
}
