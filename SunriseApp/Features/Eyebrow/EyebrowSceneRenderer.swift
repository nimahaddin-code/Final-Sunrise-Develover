// -Nimah: Node dipool per guide; posisi selalu dievaluasi dari vertex frame terbaru di renderer thread.
import SceneKit
import UIKit
import simd

final class EyebrowSceneRenderer {
    let root=SCNNode()
    private var guideID:UUID?
    private var step:Int?
    private var showFormula=false
    private struct Dot { let node:SCNNode; let attachment:SurfaceAttachment; let diagnostic:Bool }
    private struct Dash { let node:SCNNode; let start:SurfaceAttachment; let end:SurfaceAttachment }
    private var dots:[Dot]=[],dashes:[Dash]=[]
    private let material:SCNMaterial = {
        let material=SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents=UIColor(red:1,green:0.77,blue:0.84,alpha:1)
        material.readsFromDepthBuffer=true; material.writesToDepthBuffer=false
        return material
    }()
    private let diagnosticMaterial:SCNMaterial = {
        let material=SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents=UIColor.white
        material.readsFromDepthBuffer=true; return material
    }()
    init() { root.renderingOrder=8; root.isHidden=true }
    func update(guide:EyebrowGuide?,vertices:[SIMD3<Float>],configuration:EyebrowConfiguration) {
        guard let guide else { root.isHidden=true; return }
        if guideID != guide.id || step != configuration.tutorialStep || showFormula != configuration.showMappingFormula { step=configuration.tutorialStep; showFormula=configuration.showMappingFormula; rebuild(guide) }
        root.isHidden = !configuration.showGuide
        for dot in dots {
            let shouldShow=dot.diagnostic ? configuration.debugMesh : (configuration.mode != .dashed || step == 0)
            let point=dot.attachment.position(in:vertices,lift:0.001)
            dot.node.isHidden = !shouldShow || point==nil
            if let point { dot.node.simdPosition=point }
        }
        for dash in dashes {
            guard configuration.mode != .dots,let start=dash.start.position(in:vertices,lift:0.0008),
                  let end=dash.end.position(in:vertices,lift:0.0008) else { dash.node.isHidden=true; continue }
            let delta=end-start,length=simd_length(delta)
            guard length>0.00001,length<0.015 else { dash.node.isHidden=true; continue }
            dash.node.isHidden=false; dash.node.simdPosition=(start+end)/2
            dash.node.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:delta/length)
            (dash.node.geometry as? SCNCapsule)?.height=CGFloat(length+0.0006)
        }
    }
    private func rebuild(_ guide:EyebrowGuide) {
        guideID=guide.id; root.childNodes.forEach { $0.removeFromParentNode() }; dots=[]; dashes=[]
        func addDot(_ attachment:SurfaceAttachment,diagnostic:Bool) {
            let sphere=SCNSphere(radius:diagnostic ? 0.00055 : 0.0009); sphere.segmentCount=8
            sphere.materials=[diagnostic ? diagnosticMaterial : material]
            let node=SCNNode(geometry:sphere); root.addChildNode(node)
            dots.append(.init(node:node,attachment:attachment,diagnostic:diagnostic))
        }
        func addDash(_ start:SurfaceAttachment,_ end:SurfaceAttachment) {
            let capsule=SCNCapsule(capRadius:0.0003,height:0.002)
            capsule.radialSegmentCount=6; capsule.capSegmentCount=3; capsule.materials=[material]
            let node=SCNNode(geometry:capsule); root.addChildNode(node)
            dashes.append(.init(node:node,start:start,end:end))
        }
        for curve in guide.curves {
            let points:[SurfaceAttachment?]
            if step == 0 { points=curve.shapeKeyPoints.isEmpty ? [curve.samples[0],curve.samples[26],curve.samples[40]] : curve.shapeKeyPoints.map { Optional($0) } }
            else if step == 1 { points=Array(curve.outline.prefix(41)) }
            else if step == 2 { points=Array(curve.outline.dropFirst(41).prefix(41)) }
            else { points=curve.outline }
            for index in points.indices where step == 0 || index%5==0 {
                if let attachment=points[index] { addDot(attachment,diagnostic:false) }
            }
            for attachment in curve.landmarks { addDot(attachment,diagnostic:true) }
            if step != 0 {
                for index in 1..<points.count where (index-1)%5<3 {
                    if let a=points[index-1],let b=points[index] { addDash(a,b) }
                }
            }
            // -Nimah: A vertical nose start, pupil arch ray and outer-corner tail ray share the actual guide anchors.
            if showFormula {
                for point in curve.keyPoints { addDot(point,diagnostic:false) }
                for line in curve.mappingLines {
                    for i in 1..<line.count where (i-1)%5<3 {
                        if let a=line[i-1],let b=line[i] { addDash(a,b) }
                    }
                }
            }
            if step==nil || step==3 { for stroke in curve.strokes { addDash(stroke.0,stroke.1) } }
        }
    }
}
