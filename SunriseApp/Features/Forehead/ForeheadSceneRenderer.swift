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
        // -Nimah: Pigment-only try-on skips all hidden guide geometry work.
        guard configuration.showGuide else { root.isHidden=true; return }
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
    private var lastDiagnostic:String?
    private func diagnose(_ message:String,region:FaceGuideRegion) {
        guard message != lastDiagnostic else { return };lastDiagnostic=message
        UserDefaults.standard.set(message,forKey:"makeupRender.\(region).v1")
    }
    private var previousTint:SIMD3<Float>?
    private(set) var bindingBuildCount=0
    private struct Cell:Hashable { let x:Int;let y:Int }
    private var triangleCells:[Cell:[Int16]]=[:]
    private let cellWidth:Float=0.006
    private struct Patch {
        let node:SCNNode
        let attachments:[SurfaceAttachment]
        // -Nimah: Immutable colors/topology are built once per placement, not every frame.
        let colors:SCNGeometrySource
        let element:SCNGeometryElement
        let material:SCNMaterial
        let baseTint:SIMD3<Float>
    }
    private var patches:[Patch]=[]
    func update(brow:EyebrowGuide?,forehead:ForeheadGuide?,blush:BlushPlacementGuide? = nil,vertices:[SIMD3<Float>],triangles:[Int16],configuration:EyebrowConfiguration) {
        guard configuration.showMakeupPreview && configuration.previewAfter else { root.isHidden=true;diagnose("hidden-by-configuration",region:configuration.region); return }
        let regionKey:String?
        switch configuration.region {
        case .eyebrows:regionKey=brow?.id.uuidString
        case .blush:regionKey=blush?.id.uuidString
        case .forehead:regionKey=forehead?.id.uuidString
        }
        // -Nimah: Shade/intensity changes never rebind skin attachments.
        let newKey=regionKey
        guard let newKey else { root.isHidden=true;diagnose("missing-guide",region:configuration.region);return }
        let rebuilding=key != newKey
        if rebuilding {
            bindingBuildCount += 1
            buildTriangleIndex(vertices:vertices,triangles:triangles)
            key=newKey; root.childNodes.forEach { $0.removeFromParentNode() }; patches=[]
            if configuration.region == .eyebrows,let brow {
                for curve in brow.curves {
                    // -Nimah: Render valid strips separately. A missing edge sample must not erase both brows
                    // or be joined across an unmapped hole in the surface.
                    for polygon in Self.browPolygons(curve:curve,vertices:vertices) {
                        add(polygon:polygon,vertices:vertices,triangles:triangles,tint:SIMD3(0.16,0.085,0.055),opacity:MakeupRuleDatabase.brow(brow.style)?.number("max_alpha") ?? 0.55,featherFraction:(MakeupRuleDatabase.brow(brow.style)?.number("edge_feather") ?? 0.55)/2,browFade:curve.samples.compactMap { $0?.position(in:vertices) },headFade:MakeupRuleDatabase.brow(brow.style)?.number("head_fade_extent") ?? 0.18)
                    }
                }
            } else if configuration.region == .blush,let blush {
                for field in blush.pigmentFields {
                    let depth=vertices.map(\.z).min() ?? 0
                    let polygon=field.bounds.map { SIMD3($0.x,$0.y,depth) }
                    add(polygon:polygon,vertices:vertices,triangles:triangles,
                        tint:SIMD3(0.87,0.25,0.37),opacity:field.opacity,featherFraction:0.45,softPigment:true,field:field)
                }
            } else if let forehead {
                let highlight=forehead.style.category == .highlight
                for area in forehead.areas {
                    add(polygon:area.boundary.compactMap { $0.position(in:vertices) },vertices:vertices,triangles:triangles,
                        tint:highlight ? SIMD3(1,0.88,0.72) : SIMD3(0.34,0.18,0.10),opacity:highlight ? 0.40 : 0.48)
                }
            }
        }
        if rebuilding || previousTint != configuration.shadeTint {
            previousTint=configuration.shadeTint
            for patch in patches {
                let tint=configuration.region == .forehead ? patch.baseTint : configuration.shadeTint ?? patch.baseTint
                patch.material.diffuse.contents=UIColor(red:CGFloat(tint.x),green:CGFloat(tint.y),blue:CGFloat(tint.z),alpha:1)
            }
        }
        root.isHidden=patches.isEmpty
        diagnose("patches=\(patches.count);browCurves=\(brow?.curves.count ?? 0);missingOutline=\(brow?.curves.reduce(0) { $0+$1.outline.filter { $0==nil }.count } ?? 0);blushFields=\(blush?.pigmentFields.count ?? 0);strength=\(configuration.previewIntensity)",region:configuration.region)
        let strength=max(0,min(1,configuration.previewIntensity))
        for patch in patches {
            // -Nimah: One packed position array, without intermediate compactMap/map arrays per frame.
            var positions:[SCNVector3]=[];positions.reserveCapacity(patch.attachments.count)
            for attachment in patch.attachments {
                guard let p=attachment.position(in:vertices,lift:0.001) else { break }
                positions.append(SCNVector3(p.x,p.y,p.z))
            }
            guard positions.count==patch.attachments.count else { patch.node.isHidden=true; continue }
            patch.node.isHidden=false
            let source=SCNGeometrySource(vertices:positions)
            let geometry=SCNGeometry(sources:[source,patch.colors],elements:[patch.element])
            patch.material.transparency=CGFloat(strength)
            geometry.materials=[patch.material]
            patch.node.geometry=geometry
        }
    }
    private func add(polygon:[SIMD3<Float>],vertices:[SIMD3<Float>],triangles:[Int16],tint:SIMD3<Float>,opacity:Float,featherFraction:Float = 0.14,softPigment:Bool = false,field:BlushPigmentField? = nil,browFade:[SIMD3<Float>] = [],headFade:Float = 0) {
        guard polygon.count>=4,let minX=polygon.map(\.x).min(),let maxX=polygon.map(\.x).max(),
              let minY=polygon.map(\.y).min(),let maxY=polygon.map(\.y).max(),let minZ=polygon.map(\.z).min(),maxX>minX,maxY>minY else { return }
        let outline=polygon.map { SIMD2($0.x,$0.y) }
        let tiny=max(maxX-minX,maxY-minY)<0.008
        // -Nimah: Denser blush alpha interpolation is cached once; shade edits still reuse all bindings.
        let columns=tiny ? 12 : (softPigment ? 48 : 36),rows=tiny ? 12 : (softPigment ? 32 : 24)
        var attachments:[SurfaceAttachment]=[],alphas:[Float]=[],mapping:[Int:Int]=[:],indices:[Int32]=[]
        for y in 0...rows {
            for x in 0...columns {
                let p=SIMD2(minX+(maxX-minX)*Float(x)/Float(columns),minY+(maxY-minY)*Float(y)/Float(rows))
                if let nearby=triangleCells[cell(p)],let attachment=SurfaceAttachment.bind(p,vertices:vertices,triangles:nearby,minimumZ:minZ-0.003) {
                    mapping[y*(columns+1)+x]=attachments.count
                    attachments.append(attachment)
                    let feather=max(0.0005,min(maxX-minX,maxY-minY)*featherFraction)
                    let alpha:Float
                    if softPigment {
                        let center=SIMD2((minX+maxX)/2,(minY+maxY)/2)
                        let radius=SIMD2((maxX-minX)/2,(maxY-minY)/2)
                        alpha=field?.coverage(p) ?? Self.softBlushCoverage(p,center:center,radius:radius)
                    } else { alpha=Self.coverage(p,polygon:outline,feather:feather) }
                    var fade:Float=1
                    if let first=browFade.first,let last=browFade.last,abs(last.x-first.x)>0.0001,headFade>0 {
                        let t=max(0,min(1,(p.x-first.x)/(last.x-first.x)/headFade))
                        fade=t*t*(3-2*t)
                    }
                    alphas.append(alpha*opacity*fade)
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
        let colors=alphas.map { SIMD4<Float>(1,1,1,$0) }
        let colorSource=SCNGeometrySource(data:colors.withUnsafeBytes { Data($0) },semantic:.color,vectorCount:colors.count,
            usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:MemoryLayout<SIMD4<Float>>.stride)
        let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
        // -Nimah: Keep a strong pigment core with a soft edge; lift above the face depth mesh to avoid clipping.
        node.renderingOrder=1
        let material=EyelinerRenderer.material(tint:.white)
        // -Nimah: Cosmetic patches are already bound to the visible front skin. The coarse native
        // face depth mesh must not occlude its own interpolated pigment (camera video has no depth).
        // Keep this policy local to pigment; guide/eyeliner depth materials are unchanged.
        material.readsFromDepthBuffer=false
        patches.append(Patch(node:node,attachments:attachments,colors:colorSource,element:element,material:material,baseTint:tint))
    }
    static func browPolygons(curve:EyebrowGuide.Curve,vertices:[SIMD3<Float>])->[[SIMD3<Float>]] {
        let count=curve.samples.count
        guard count>=2,curve.outline.count>=count*2 else { return [] }
        var upper:[SIMD3<Float>]=[],lower:[SIMD3<Float>]=[],polygons:[[SIMD3<Float>]]=[]
        func flush() {
            if upper.count>=2 { polygons.append(upper+lower.reversed()+[upper[0]]) }
            upper=[];lower=[]
        }
        for i in 0..<count {
            if let a=curve.outline[i]?.position(in:vertices),let b=curve.outline[count*2-1-i]?.position(in:vertices) {
                upper.append(a);lower.append(b)
            } else { flush() }
        }
        flush();return polygons
    }
    // -Nimah: Smooth radial falloff across the entire patch, with zero pigment at its edge.
    static func softBlushCoverage(_ p:SIMD2<Float>,center:SIMD2<Float>,radius:SIMD2<Float>)->Float {
        guard radius.x>0,radius.y>0 else { return 0 }
        let q=(p-center)/radius,r2=simd_length_squared(q)
        guard r2.isFinite,r2<1 else { return 0 }
        let value=1-r2
        return value*value
    }
    // -Nimah: Spatial lookup preserves exact barycentric binding, while skipping unrelated triangles.
    private func cell(_ point:SIMD2<Float>)->Cell { Cell(x:Int(floor(point.x/cellWidth)),y:Int(floor(point.y/cellWidth))) }
    private func buildTriangleIndex(vertices:[SIMD3<Float>],triangles:[Int16]) {
        triangleCells.removeAll(keepingCapacity:true)
        guard triangles.count % 3 == 0 else { return }
        for i in stride(from:0,to:triangles.count,by:3) {
            let a=Int(triangles[i]),b=Int(triangles[i+1]),c=Int(triangles[i+2])
            guard vertices.indices.contains(a),vertices.indices.contains(b),vertices.indices.contains(c) else { continue }
            let p=vertices[a],q=vertices[b],r=vertices[c]
            guard [p,q,r].allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { continue }
            let low=cell(SIMD2(min(p.x,min(q.x,r.x))-0.000001,min(p.y,min(q.y,r.y))-0.000001))
            let high=cell(SIMD2(max(p.x,max(q.x,r.x))+0.000001,max(p.y,max(q.y,r.y))+0.000001))
            guard high.x-low.x<100,high.y-low.y<100 else { continue }
            for y in low.y...high.y { for x in low.x...high.x {
                triangleCells[Cell(x:x,y:y),default:[]].append(contentsOf:[triangles[i],triangles[i+1],triangles[i+2]])
            } }
        }
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
