// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): tutorial brow mapping lines and the landmark tracking view.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

extension BeautyBlushEngine {
    /// Lines and dots in the camera image, turned into alpha-blended triangles in clip space.
    struct MarkBuilder {
        let image:SIMD2<Float>,pixels:SIMD2<Float>,display:CGAffineTransform
        let thickness:Float
        var out:[MarkVertex]=[]
        init(imageSize:CGSize,drawable:CGSize,display:CGAffineTransform) {
            image=SIMD2(Float(imageSize.width),Float(imageSize.height));pixels=SIMD2(Float(drawable.width),Float(drawable.height))
            self.display=display;thickness=max(2,pixels.x*0.004)
        }
        func view(_ p:SIMD2<Float>)->SIMD2<Float> {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display)
            return SIMD2(Float(v.x),Float(v.y))*pixels
        }
        func clip(_ p:SIMD2<Float>)->SIMD4<Float> {SIMD4(p.x/pixels.x*2-1,1-p.y/pixels.y*2,0,1)}
        mutating func line(_ a:SIMD2<Float>,_ b:SIMD2<Float>,_ color:SIMD4<Float>,width:Float=1) {
            let p=view(a),q=view(b),d=q-p,length=simd_length(d)
            guard length>1 else {return}
            let n=SIMD2(-d.y,d.x)/length*thickness*width/2
            out += [p+n,p-n,q+n,p-n,q-n,q+n].map {MarkVertex(position:clip($0),color:color)}
        }
        /// A straight line of dashes, `dash` and `gap` in screen pixels.
        mutating func dashedLine(_ a:SIMD2<Float>,_ b:SIMD2<Float>,_ color:SIMD4<Float>,width:Float=1,dash:Float,gap:Float) {
            let p=view(a),q=view(b),length=simd_length(q-p)
            guard length>1 else {return}
            var start:Float=0
            while start<length {
                let end=min(start+dash,length)
                let from=p+(q-p)*(start/length),to=p+(q-p)*(end/length)
                let d=to-from,l=simd_length(d)
                if l>0.5 {
                    let n=SIMD2(-d.y,d.x)/l*thickness*width/2
                    out += [from+n,from-n,to+n,from-n,to-n,to+n].map {MarkVertex(position:clip($0),color:color)}
                }
                start += dash+gap
            }
        }
        mutating func polyline(_ points:[SIMD2<Float>],_ color:SIMD4<Float>,width:Float=1) {
            for (a,b) in zip(points,points.dropFirst()) {line(a,b,color,width:width)}
        }
        mutating func dot(_ c:SIMD2<Float>,_ radius:Float,_ color:SIMD4<Float>,segments:Int=12) {
            let p=view(c)
            for i in 0..<segments {
                let a0=Float(i)/Float(segments)*2*Float.pi,a1=Float(i+1)/Float(segments)*2*Float.pi
                out += [p,p+SIMD2(cos(a0),sin(a0))*radius,p+SIMD2(cos(a1),sin(a1))*radius].map {MarkVertex(position:clip($0),color:color)}
            }
        }
    }
    struct MappingMark {let name:String;let point:SIMD2<Float>}
    struct MappingBrow {let side:EyeSide;let origin:SIMD2<Float>;let marks:[MappingMark]}
    /// Brow mapping, as a brow pencil is laid: every line starts at the side of the nose on that side (the widest point of
    /// the nostril wing). Through the inner eye corner it marks where the brow starts, through the outer edge of the iris its
    /// arch, through the outer eye corner its end. Each mark is where the line crosses the brow's centerline.
    /// The nostril wing and the iris ring come from the full mesh, as offsets from the (steadied) ala and iris centre, so the
    /// marks move with the same smoothing as the brow; without the mesh they are estimated from the eye.
    static func mappingMarks(_ o:BrowObservation)->[MappingBrow] {
        func offset(from base:Int,to target:Int)->SIMD2<Float>? {
            o.mesh.count>max(base,target) ? o.mesh[target]-o.mesh[base]:nil
        }
        var out:[MappingBrow]=[]
        for side in [EyeSide.subjectRight,.subjectLeft] {
            guard let eye=o.eyes[side],let contour=o.brows[side],let brow=BrowGeometry(contour:contour) else {continue}
            let across=eye.outer-eye.inner
            let toEar=across/max(simd_length(across),1e-3)
            // Which half of the mesh this eye is: the iris centre and ala nearest this eye's points.
            let mediaPipeLeftHalf=o.mesh.count>477 && simd_distance(o.mesh[98],eye.ala)<simd_distance(o.mesh[327],eye.ala)
            let wing=offset(from:mediaPipeLeftHalf ? 98:327,to:mediaPipeLeftHalf ? 129:358)
            let nose=eye.ala+(wing.map {simd_dot($0,toEar)>0 ? $0:.zero} ?? .zero)
            let center:SIMD2<Float>=eye.iris ?? (eye.inner+eye.outer)/2
            var irisEdge=center+across*0.2
            if o.mesh.count>477,let iris=eye.iris {
                let base=simd_distance(o.mesh[468],iris)<simd_distance(o.mesh[473],iris) ? 468:473
                let ring=(base+1...base+4).compactMap {offset(from:base,to:$0)}
                if let edge=ring.max(by: {simd_dot($0,toEar)<simd_dot($1,toEar)}),simd_dot(edge,toEar)>0 {irisEdge=center+edge}
            }
            let throughs:[(String,SIMD2<Float>)]=[("Start",eye.inner),("Arch",irisEdge),("End",eye.outer)]
            var marks:[MappingMark]=[]
            for (name,through) in throughs {
                if let hit=brow.crossing(from:nose,through:through) {marks.append(MappingMark(name:name,point:hit))}
            }
            if !marks.isEmpty {out.append(MappingBrow(side:side,origin:nose,marks:marks))}
        }
        return out
    }
    /// Tutorial brow mapping (white dashed lines from the nostril through inner eye corner, outer iris edge and outer eye
    /// corner, a pink dot where each crosses the brow) and landmark debug dots, in clip space.
    static func browMarks(_ o:BrowObservation,display:CGAffineTransform,size:CGSize,landmarks:Bool,mapping:Bool,alpha:Float)->[MarkVertex] {
        var m=MarkBuilder(imageSize:o.imageSize,drawable:size,display:display)
        let thickness=m.thickness
        if mapping {
            // Soft white dashes and small pink dots ringed in white, like a pencil-mapping camera effect.
            let line=SIMD4<Float>(1,1,1,0.75*alpha),ring=SIMD4<Float>(1,1,1,0.95*alpha),dot=SIMD4<Float>(0.93,0.3,0.52,alpha)
            let dash=thickness*5,gap=thickness*3.5
            for brow in mappingMarks(o) {
                for mark in brow.marks {
                    // Like a pencil held against the face: from beside the nostril on past the brow.
                    let along=mark.point-brow.origin
                    m.dashedLine(brow.origin+along*0.08,mark.point+along*0.22,line,width:1.6,dash:dash,gap:gap)
                }
                for mark in brow.marks {m.dot(mark.point,thickness*2.3,ring);m.dot(mark.point,thickness*1.6,dot)}
            }
        }
        if landmarks {
            for (side,contour) in o.brows {
                for p in contour.upper+contour.lower {m.dot(p,thickness*1.5,SIMD4(1,0.15,0.1,1))}
                if let eye=o.eyes[side] {
                    for p in [eye.inner,eye.outer]+(eye.iris.map {[$0]} ?? []) {m.dot(p,thickness*1.5,SIMD4(0.1,0.9,1,1))}
                    m.dot(eye.ala,thickness*1.5,SIMD4(1,0.9,0.1,1))
                }
            }
            m.dot(o.noseBridge,thickness*1.5,SIMD4(1,0.9,0.1,1))
        }
        return m.out
    }
    /// The MediaPipe tracking view: every face landmark, each brow's raw and smoothed points and contours, the fitted
    /// centerline and the brow frame a shape is drawn in, and the eye, iris, nose and nose-bridge points.
    static func browTrackingMarks(_ o:BrowObservation,raw:BrowObservation?,display:CGAffineTransform,size:CGSize,tracked:Bool)->[MarkVertex] {
        var m=MarkBuilder(imageSize:o.imageSize,drawable:size,display:display)
        let t=m.thickness,fade:Float=tracked ? 1:0.45
        for p in o.mesh {m.dot(p,t*0.55,SIMD4(1,1,1,0.4),segments:4)}
        let upper=SIMD4<Float>(1,0.25,0.2,fade),lower=SIMD4<Float>(1,0.6,0.1,fade),center=SIMD4<Float>(1,0.9,0.1,fade)
        let frame=SIMD4<Float>(0.1,0.85,1,0.8*fade),tick=SIMD4<Float>(0.3,1,0.4,0.8*fade),eyeColor=SIMD4<Float>(1,0.2,0.9,1)
        let contours=o.brows.compactMap {$0.value}
        let across=contours.compactMap {BrowGeometry(contour:$0)?.width}.max()
        for contour in contours {
            if let g=BrowGeometry(contour:contour,across:across) {
                let e=browExtent
                let us=(0...24).map {e.x+(e.y-e.x)*Float($0)/24}
                m.polyline(us.map {g.point(u:$0,w:e.z)},frame,width:0.6)
                m.polyline(us.map {g.point(u:$0,w:-e.z)},frame,width:0.6)
                m.line(g.point(u:e.x,w:-e.z),g.point(u:e.x,w:e.z),frame,width:0.6)
                m.line(g.point(u:e.y,w:-e.z),g.point(u:e.y,w:e.z),frame,width:0.6)
                for u:Float in [0,0.5,1] {m.line(g.point(u:u,w:-e.z),g.point(u:u,w:e.z),tick,width:0.6)}
                m.polyline((0...30).map {g.point(u:Float($0)/30,w:0)},center,width:1.2)
            }
            m.polyline(contour.upper,upper);m.polyline(contour.lower,lower)
        }
        if let raw {for contour in raw.brows.values {for p in contour.upper+contour.lower {m.dot(p,t*1.1,SIMD4(0.75,0.75,0.75,0.9))}}}
        for contour in contours {
            for p in contour.upper {m.dot(p,t*2.1,upper)}
            for p in contour.lower {m.dot(p,t*2.1,lower)}
        }
        for eye in o.eyes.values {
            m.polyline(eye.lid,eyeColor,width:0.7)
            m.dot(eye.inner,t*1.8,eyeColor);m.dot(eye.outer,t*1.8,eyeColor);m.dot(eye.ala,t*1.8,eyeColor)
            if let iris=eye.iris {m.dot(iris,t*2.4,eyeColor)}
        }
        m.dot(o.noseBridge,t*2.4,SIMD4(1,1,1,1))
        return m.out
    }
    /// Head pose as seen on screen. MediaPipe's matrix follows the camera sensor, which is turned 90° in portrait, so
    /// its roll is re-measured from the eye corners on screen and yaw/pitch are turned by the same amount.
    static func screenPose(_ o:BrowObservation,display:CGAffineTransform)->BrowHeadPose {
        guard let r=o.eyes[.subjectRight]?.inner,let l=o.eyes[.subjectLeft]?.inner else {return o.pose}
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        func view(_ p:SIMD2<Float>)->SIMD2<Float> {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display);return SIMD2(Float(v.x),Float(v.y))
        }
        let axis=view(l)-view(r)
        var roll=atan2(axis.y,axis.x)*180/Float.pi
        // The eye axis has no front or back: keep the reading within ±90°, whichever way the view is mirrored.
        if roll>90 {roll -= 180} else if roll < -90 {roll += 180}
        return o.pose.turned(toRoll:roll)
    }
    /// MediaPipe indices beside the points, for the tracking view's labels (view-normalized positions).
    static func browTrackingLabels(_ o:BrowObservation,display:CGAffineTransform)->[BrowTrackingSnapshot.Label] {
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        func label(_ text:String,_ p:SIMD2<Float>)->BrowTrackingSnapshot.Label {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display)
            return .init(text:text,x:Float(v.x),y:Float(v.y))
        }
        var out:[BrowTrackingSnapshot.Label]=[]
        let maps:[(EyeSide,MediaPipeEyeLandmarkProvider.EyeIndexMap)]=[(.subjectRight,MediaPipeEyeLandmarkProvider.subjectRightMap),(.subjectLeft,MediaPipeEyeLandmarkProvider.subjectLeftMap)]
        for (side,map) in maps {
            // Contours run head to tail; the index rows run tail to head.
            if let contour=o.brows[side] {
                out += zip(map.browUpper.reversed(),contour.upper).map {label("\($0)",$1)}
                out += zip(map.browLower.reversed(),contour.lower).map {label("\($0)",$1+SIMD2(0,0))}
            }
            if let eye=o.eyes[side] {
                out += [label("\(map.inner)",eye.inner),label("\(map.outer)",eye.outer),label("ala",eye.ala)]
                if let iris=eye.iris {out.append(label("iris",iris))}
            }
        }
        out.append(label("\(MediaPipeBrowTracker.noseBridge)",o.noseBridge))
        return out
    }
}
