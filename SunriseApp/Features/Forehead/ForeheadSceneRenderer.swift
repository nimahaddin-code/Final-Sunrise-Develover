// -Nimah: Closed dashed area di kulit forehead; satu sesi dan depth mesh milik foundation existing.
import SceneKit
import UIKit
import simd

final class ForeheadSceneRenderer {
    let root=SCNNode()
    private var id:UUID?
    private var dots:[(SCNNode,SurfaceAttachment)]=[]
    private var lines:[(SCNNode,SurfaceAttachment,SurfaceAttachment)]=[]
    func update(guide:ForeheadGuide?,vertices:[SIMD3<Float>],configuration:EyebrowConfiguration) {
        guard let guide else { root.isHidden=true; return }
        updateAreas(id:guide.id,areas:guide.areas,vertices:vertices,configuration:configuration,
            tint:guide.style.category == .highlight ? .white : UIColor(red:1,green:0.82,blue:0.86,alpha:1))
    }
    // -Nimah: Same mesh-bound area renderer for blush, including optional blend direction arrows.
    func update(blush:BlushPlacementGuide?,vertices:[SIMD3<Float>],configuration:EyebrowConfiguration) {
        guard let blush else { root.isHidden=true; return }
        updateAreas(id:blush.id,areas:blush.areas+blush.blendArrows,vertices:vertices,configuration:configuration,
            tint:UIColor(red:1,green:0.76,blue:0.84,alpha:1))
    }
    private func updateAreas(id:UUID,areas:[FaceGuideArea],vertices:[SIMD3<Float>],configuration:EyebrowConfiguration,tint:UIColor) {
        if self.id != id { rebuild(id:id,areas:areas,tint:tint) }
        root.isHidden = !configuration.showGuide
        for (node,point) in dots {
            let position=point.position(in:vertices,lift:0.001)
            node.isHidden=configuration.mode == .dashed || position==nil
            if let position { node.simdPosition=position }
        }
        for (node,a,b) in lines {
            guard configuration.mode != .dots,let start=a.position(in:vertices,lift:0.0009),let end=b.position(in:vertices,lift:0.0009) else { node.isHidden=true; continue }
            let delta=end-start,length=simd_length(delta)
            node.isHidden=length<0.00001 || length>0.015
            if !node.isHidden {
                node.simdPosition=(start+end)/2
                node.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:delta/length)
                (node.geometry as? SCNCapsule)?.height=CGFloat(length+0.0007)
            }
        }
    }
    private func rebuild(id:UUID,areas:[FaceGuideArea],tint:UIColor) {
        self.id=id; root.childNodes.forEach { $0.removeFromParentNode() }; dots=[]; lines=[]
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=tint
        material.readsFromDepthBuffer=true; material.writesToDepthBuffer=false
        for area in areas {
            for i in area.boundary.indices where i%5==0 {
                let sphere=SCNSphere(radius:0.0008); sphere.segmentCount=8; sphere.materials=[material]
                let node=SCNNode(geometry:sphere); root.addChildNode(node); dots.append((node,area.boundary[i]))
            }
            for i in 1..<area.boundary.count where (i-1)%5<3 {
                let shape=SCNCapsule(capRadius:0.00035,height:0.002); shape.radialSegmentCount=6; shape.capSegmentCount=3; shape.materials=[material]
                let node=SCNNode(geometry:shape); root.addChildNode(node); lines.append((node,area.boundary[i-1],area.boundary[i]))
            }
        }
    }
}

// -Nimah: Sparse points dari vertex mesh nyata untuk tahap face tracking; bukan landmark semantik tambahan.
final class FaceTrackingDotsRenderer {
    let root=SCNNode()
    private var points:[(SCNNode,Int)]=[]
    func update(vertices:[SIMD3<Float>],visible:Bool) {
        root.isHidden = !visible
        guard visible else { return }
        if points.isEmpty {
            let material=SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents=UIColor.white
            material.readsFromDepthBuffer=true
            let width=(vertices.map(\.x).max() ?? 0)-(vertices.map(\.x).min() ?? 0)
            var chosen:[Int]=[]
            for i in vertices.indices where vertices[i].z>0 {
                if chosen.allSatisfy({ simd_distance(vertices[$0],vertices[i])>width*0.055 }) { chosen.append(i) }
                if chosen.count>=100 { break }
            }
            for i in chosen {
                let sphere=SCNSphere(radius:0.0006); sphere.segmentCount=6; sphere.materials=[material]
                let node=SCNNode(geometry:sphere); root.addChildNode(node); points.append((node,i))
            }
        }
        for (node,index) in points {
            node.isHidden = !vertices.indices.contains(index)
            if vertices.indices.contains(index) { node.simdPosition=vertices[index]+SIMD3(0,0,0.001) }
        }
    }
}

// -Nimah: A skin-bound colored patch for live Before/After. No UV atlas or screen-space mask.
final class FaceRegionPreviewRenderer {
    let root=SCNNode()
    private var key:String?
    private struct Patch {
        let node:SCNNode
        let attachments:[SurfaceAttachment]
        // -Nimah: Immutable colors/topology are built once per placement, not every frame.
        let colors:SCNGeometrySource
        let element:SCNGeometryElement
        let material:SCNMaterial
    }
    private var patches:[Patch]=[]
    func update(brow:EyebrowGuide?,forehead:ForeheadGuide?,blush:BlushPlacementGuide? = nil,vertices:[SIMD3<Float>],triangles:[Int16],configuration:EyebrowConfiguration) {
        guard configuration.showMakeupPreview && configuration.previewAfter else { root.isHidden=true; return }
        let newKey:String?
        switch configuration.region {
        case .eyebrows:newKey=brow?.id.uuidString
        case .blush:newKey=blush?.id.uuidString
        case .forehead:newKey=forehead?.id.uuidString
        }
        guard let newKey else { root.isHidden=true; return }
        if key != newKey {
            key=newKey; root.childNodes.forEach { $0.removeFromParentNode() }; patches=[]
            if configuration.region == .eyebrows,let brow {
                for curve in brow.curves {
                    // -Nimah: Do not bridge missing outline attachments across unmapped skin.
                    guard curve.outline.allSatisfy({ $0 != nil }) else { continue }
                    let polygon=curve.outline.compactMap { $0?.position(in:vertices) }
                    add(polygon:polygon,vertices:vertices,triangles:triangles,tint:SIMD3(0.16,0.085,0.055),opacity:0.85)
                }
            } else if configuration.region == .blush,let blush {
                for area in blush.areas {
                    add(polygon:area.boundary.compactMap { $0.position(in:vertices) },vertices:vertices,triangles:triangles,
                        tint:SIMD3(0.87,0.25,0.37),opacity:0.65)
                }
            } else if let forehead {
                let highlight=forehead.style.category == .highlight
                for area in forehead.areas {
                    add(polygon:area.boundary.compactMap { $0.position(in:vertices) },vertices:vertices,triangles:triangles,
                        tint:highlight ? SIMD3(1,0.88,0.72) : SIMD3(0.34,0.18,0.10),opacity:highlight ? 0.40 : 0.48)
                }
            }
        }
        root.isHidden=patches.isEmpty
        let strength=max(0,min(1,configuration.previewIntensity))
        for patch in patches {
            let positions=patch.attachments.compactMap { $0.position(in:vertices,lift:0.0004) }
            guard positions.count==patch.attachments.count else { patch.node.isHidden=true; continue }
            patch.node.isHidden=false
            let source=SCNGeometrySource(vertices:positions.map { SCNVector3($0.x,$0.y,$0.z) })
            let geometry=SCNGeometry(sources:[source,patch.colors],elements:[patch.element])
            patch.material.transparency=CGFloat(strength)
            geometry.materials=[patch.material]
            patch.node.geometry=geometry
        }
    }
    private func add(polygon:[SIMD3<Float>],vertices:[SIMD3<Float>],triangles:[Int16],tint:SIMD3<Float>,opacity:Float) {
        guard polygon.count>=4,let minX=polygon.map(\.x).min(),let maxX=polygon.map(\.x).max(),
              let minY=polygon.map(\.y).min(),let maxY=polygon.map(\.y).max(),let minZ=polygon.map(\.z).min(),maxX>minX,maxY>minY else { return }
        let outline=polygon.map { SIMD2($0.x,$0.y) }
        let tiny=max(maxX-minX,maxY-minY)<0.008
        let columns=tiny ? 12 : 36,rows=tiny ? 12 : 24
        var attachments:[SurfaceAttachment]=[],alphas:[Float]=[],mapping:[Int:Int]=[:],indices:[Int32]=[]
        for y in 0...rows {
            for x in 0...columns {
                let p=SIMD2(minX+(maxX-minX)*Float(x)/Float(columns),minY+(maxY-minY)*Float(y)/Float(rows))
                if let attachment=SurfaceAttachment.bind(p,vertices:vertices,triangles:triangles,minimumZ:minZ-0.003) {
                    mapping[y*(columns+1)+x]=attachments.count
                    attachments.append(attachment)
                    let feather=max(0.0005,min(maxX-minX,maxY-minY)*0.28)
                    alphas.append(Self.coverage(p,polygon:outline,feather:feather)*opacity)
                }
            }
        }
        for y in 0..<rows {
            for x in 0..<columns {
                let a=y*(columns+1)+x,b=a+1,c=a+columns+1,d=c+1
                for tri in [[a,b,c],[b,d,c]] {
                    if let i=mapping[tri[0]],let j=mapping[tri[1]],let k=mapping[tri[2]],max(alphas[i],max(alphas[j],alphas[k]))>0 {
                        indices += [Int32(i),Int32(j),Int32(k)]
                    }
                }
            }
        }
        guard !indices.isEmpty else { return }
        let node=SCNNode(); root.addChildNode(node)
        let colors=alphas.map { SIMD4(tint.x,tint.y,tint.z,$0) }
        let colorSource=SCNGeometrySource(data:colors.withUnsafeBytes { Data($0) },semantic:.color,vectorCount:colors.count,
            usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
        let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
        let material=EyelinerRenderer.material(tint:.white)
        patches.append(Patch(node:node,attachments:attachments,colors:colorSource,element:element,material:material))
    }
    // -Nimah: Feather stays inside the intended polygon, including concave hairline bands.
    static func coverage(_ point:SIMD2<Float>,polygon:[SIMD2<Float>],feather:Float) -> Float {
        guard polygon.count>=3,point.x.isFinite,point.y.isFinite else { return 0 }
        var inside=false,distance=Float.infinity
        for i in polygon.indices {
            let a=polygon[i],b=polygon[(i+1)%polygon.count],edge=b-a
            if (a.y>point.y) != (b.y>point.y),point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
            let t=max(0,min(1,simd_dot(point-a,edge)/max(simd_length_squared(edge),0.000000001)))
            distance=min(distance,simd_distance(point,a+edge*t))
        }
        guard inside else { return 0 }
        let t=max(0,min(1,distance/max(feather,0.000001)))
        return t*t*(3-2*t)
    }
}
