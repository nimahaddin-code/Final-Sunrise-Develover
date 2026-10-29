// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): the 3D hair brow on ARKit's face pose.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

extension BeautyBlushEngine {
    /// The 3D brow mesh once it has loaded (loading starts here); nil until then, and the brow's picture is drawn meanwhile.
    func hairMeshIfReady()->BrowHairMesh? {
        guard let mesh=BrowHairStore.shared.mesh else {BrowHairStore.shared.prepare();return nil}
        installHairMesh(mesh)
        return hairBuffer==nil ? nil:mesh
    }
    func installHairMesh(_ mesh:BrowHairMesh) {
        guard hairBuffer==nil else {return}
        let vertices=mesh.vertices
        hairBuffer=vertices.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
        hairVertexCount=vertices.count
    }
    /// Where the hair mesh goes on each tracked brow: head and tail, the mesh normal between them and the way to the forehead,
    /// all lifted onto ARKit's face mesh from the brow's (steadied) landmarks.
    static func hairPlacements(_ o:BrowObservation,face:BrowFaceFrame,mesh:BrowHairMesh)->[HairDraw] {
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        var out:[HairDraw]=[]
        for side in [EyeSide.subjectRight,.subjectLeft] {
            guard let contour=o.brows[side],let g=BrowGeometry(contour:contour) else {continue}
            let headPixel=g.centerline(0).point,tailPixel=g.centerline(1).point,midPixel=g.point(u:0.5,w:0)
            guard let head=face.faceLocal(at:headPixel),let tail=face.faceLocal(at:tailPixel),let mid=face.faceLocal(at:midPixel),
                  let top=face.faceLocal(at:g.point(u:0.5,w:0.5)),
                  let frame=BrowHairPlacement.frame(mesh:mesh,head:head,tail:tail,normal:face.normal(near:mid),forehead:top-mid) else {continue}
            out.append(HairDraw(matrix:frame.matrix,scale:frame.scale,probe:(g.point(u:0.5,w:0.25)-midPixel)/image))
        }
        return out
    }
    /// ARKit's face mesh for this frame, in a ring of GPU buffers (for the depth pass).
    func uploadFaceMesh(_ face:BrowFaceFrame,slot:Int)->Bool {
        let count=face.vertices.count,stride=MemoryLayout<Vertex>.stride
        guard count>0,slot<3 else {return false}
        if faceMeshVertices.count != 3 || faceMeshVertices[0].length != count*stride {
            faceMeshVertices=(0..<3).compactMap {_ in device.makeBuffer(length:count*stride,options:.storageModeShared)}
        }
        guard faceMeshVertices.count==3 else {return false}
        if faceMeshIndices==nil || faceMeshIndexCount != face.triangles.count {
            faceMeshIndices=face.triangles.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
            faceMeshIndexCount=face.triangles.count
        }
        guard faceMeshIndices != nil else {return false}
        let target=faceMeshVertices[slot].contents().bindMemory(to:Vertex.self,capacity:count)
        for (i,v) in face.vertices.enumerated() {target[i]=Vertex(position:SIMD4(v,1),rest:SIMD4(v,1),uv:.zero)}
        return true
    }
    /// Draws the face mesh into the depth buffer only, then every hair of each brow against it. `mvp` is projection * view * face.
    func encodeHair(_ e:MTLRenderCommandEncoder,draws:[HairDraw],mvp:simd_float4x4,projectionScaleY:Float,size:CGSize,light:Float,uniforms u:Uniforms,obstruction:MTLTexture?,slot:Int) {
        guard let hairBuffer,let indices=faceMeshIndices,slot<faceMeshVertices.count,let obstruction else {return}
        var meshUniforms=u;meshUniforms.mvp=mvp
        e.setCullMode(.none)
        e.setRenderPipelineState(depth);e.setDepthStencilState(depthWrite)
        e.setVertexBuffer(faceMeshVertices[slot],offset:0,index:0);e.setVertexBytes(&meshUniforms,length:MemoryLayout<Uniforms>.stride,index:1)
        e.drawIndexedPrimitives(type:.triangle,indexCount:faceMeshIndexCount,indexType:.uint16,indexBuffer:indices,indexBufferOffset:0)
        e.setRenderPipelineState(browHairPipeline);e.setDepthStencilState(depthRead)
        var fragmentUniforms=u
        e.setFragmentBytes(&fragmentUniforms,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(obstruction,index:3)
        e.setVertexBuffer(hairBuffer,offset:0,index:0)
        for draw in draws {
            var h=HairUniforms(clipFromModel:mvp*draw.matrix,view:SIMD4(Float(size.width),Float(size.height),0.5*Float(size.height)*projectionScaleY,draw.scale),
                               look:SIMD4(light,1.5,0.04,0),probe:SIMD4(draw.probe.x,draw.probe.y,0,0))
            e.setVertexBytes(&h,length:MemoryLayout<HairUniforms>.stride,index:1);e.setFragmentBytes(&h,length:MemoryLayout<HairUniforms>.stride,index:1)
            e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:hairVertexCount)
        }
        e.setDepthStencilState(noDepth)
    }
}
