// -Nimah: Personal cheek placement from calibrated eye/nose anchors, bound to real mesh triangles.
import Foundation
import simd

enum BlushPlacementStyle:String,CaseIterable,Identifiable,Sendable {
    case apple,cheekbone,outerSweep,highLift,wideHorizontal,centerCheek,centerDown,upperInner,templeSweep,diagonalBlend,placementDots,innerCheek
    var id:String { rawValue }
    var title:String {
        switch self {
        case .apple:return "Apple of cheeks"
        case .cheekbone:return "Cheekbone"
        case .outerSweep:return "Outer sweep"
        case .highLift:return "High cheekbone"
        case .wideHorizontal:return "Horizontal blend"
        case .centerCheek:return "Center cheek"
        case .centerDown:return "Center · blend down"
        case .upperInner:return "Upper inner cheek"
        case .templeSweep:return "Temple sweep"
        case .diagonalBlend:return "Diagonal blend"
        case .placementDots:return "Placement dots"
        case .innerCheek:return "Blend inward"
        }
    }
    var instruction:String {
        switch self {
        case .apple:return "Place blush in the compact apple zones. Keep the boundary soft."
        case .cheekbone:return "Apply near the upper cheekbone zones, below the eyes. Blend outward softly."
        case .outerSweep:return "Keep blush on the outer cheeks and blend along the elongated guide."
        case .highLift:return "Apply lightly inside the higher cheekbone zones. Keep product away from the lower eyelids."
        case .wideHorizontal:return "Blend horizontally across each cheek. Do not connect the cheeks across the nose."
        case .centerCheek:return "Focus the color on the center of each cheek."
        case .centerDown:return "Start on the center cheek, then soften a little downward along the arrow."
        case .upperInner:return "Use a light layer within the upper inner cheek shapes, leaving the nose and eye area clear."
        case .templeSweep:return "Sweep along the outer cheek toward the temple. Stay on visible skin."
        case .diagonalBlend:return "Start on the upper cheek and soften diagonally outward along the arrow."
        case .placementDots:return "Use the small zones to distribute product, then blend the dots together on the cheeks."
        case .innerCheek:return "Blend gently inward within each cheek. This is a cheek-only interpretation of reference E."
        }
    }
}
struct FaceGuideArea:Sendable { let id:String; let boundary:[SurfaceAttachment] }
struct BlushPlacementGuide:Sendable {
    let id:UUID
    let style:BlushPlacementStyle
    let areas:[FaceGuideArea]
    let blendArrows:[FaceGuideArea]
}
enum BlushPlacementGenerator {
    static func make(region:EyebrowRegion,style:BlushPlacementStyle) -> BlushPlacementGuide? {
        let vertices=region.restVertices
        guard region.brows.count==2,let lo=vertices.map(\.x).min(),let hi=vertices.map(\.x).max() else { return nil }
        let width=(hi-lo)/2
        guard width>0.02,width<0.16 else { return nil }
        var areas:[FaceGuideArea]=[],arrows:[FaceGuideArea]=[]
        for brow in region.brows {
            guard let map=brow.mapping else { return nil }
            let eye=map.pupil,nose=map.ala,sign:Float=eye.x>0 ? 1 : -1
            let eyeNose=eye.y-nose.y
            guard eyeNose>width*0.12,eyeNose<width*1.1 else { return nil }
            let nasalLimit=abs(nose.x)+width*0.025,outerLimit=width*0.94,eyeLimit=eye.y-width*0.085
            func bind(_ points:[SIMD2<Float>],id:String,closed:Bool) -> FaceGuideArea? {
                guard !points.isEmpty,points.allSatisfy({ p in
                    p.x.isFinite && p.y.isFinite && sign*p.x>=nasalLimit && abs(p.x)<=outerLimit && p.y<=eyeLimit
                }) else { return nil }
                let attachments=points.compactMap { SurfaceAttachment.bind($0,vertices:vertices,triangles:region.triangles,minimumZ:map.ala.z-width*0.7) }
                guard attachments.count==points.count else { return nil }
                return .init(id:id,boundary:attachments)
            }
            var center=SIMD2(abs(eye.x)+width*0.08,eye.y-eyeNose*0.85)
            var rx=width*0.14,ry=width*0.13,angle:Float=0
            var blend=SIMD2<Float>.zero
            switch style {
            case .apple:break
            case .centerCheek:rx=width*0.17; ry=width*0.14
            case .cheekbone:center=SIMD2(abs(eye.x)+width*0.11,eye.y-eyeNose*0.62);rx=width*0.20;ry=width*0.08;angle=0.25;blend=SIMD2(width*0.12,width*0.04)
            case .outerSweep:center=SIMD2(abs(eye.x)+width*0.16,eye.y-eyeNose*0.75);rx=width*0.23;ry=width*0.09;angle=0.25;blend=SIMD2(width*0.11,width*0.03)
            case .highLift:center=SIMD2(abs(eye.x)+width*0.13,eye.y-eyeNose*0.53);rx=width*0.18;ry=width*0.065;angle=0.20;blend=SIMD2(width*0.10,width*0.025)
            case .wideHorizontal:center=SIMD2(abs(eye.x)+width*0.08,eye.y-eyeNose*0.94);rx=width*0.22;ry=width*0.09;blend=SIMD2(width*0.12,0)
            case .centerDown:rx=width*0.16;ry=width*0.16;blend=SIMD2(0,-width*0.10)
            case .upperInner:center=SIMD2(abs(eye.x)+width*0.015,eye.y-eyeNose*0.65);rx=width*0.12;ry=width*0.10;angle = -0.20
            case .templeSweep:center=SIMD2(abs(eye.x)+width*0.23,eye.y-eyeNose*0.52);rx=width*0.23;ry=width*0.07;angle=0.65;blend=SIMD2(width*0.10,width*0.09)
            case .diagonalBlend:center=SIMD2(abs(eye.x)+width*0.12,eye.y-eyeNose*0.72);rx=width*0.20;ry=width*0.10;angle=0.45;blend=SIMD2(width*0.10,width*0.08)
            case .placementDots:rx=width*0.035;ry=width*0.035
            case .innerCheek:rx=width*0.17;ry=width*0.09;blend=SIMD2(-width*0.10,0)
            }
            // -Nimah: Personalize width to available cheek skin; no camera-distance scaling or screen offset.
            rx=min(rx,max(0,center.x-nasalLimit-width*0.005),max(0,outerLimit-center.x-width*0.005))
            guard rx>width*0.025 else { return nil }
            var offsets:[SIMD2<Float>] = [.zero]
            if style == .placementDots { offsets=[.init(-width*0.045,width*0.035),.init(width*0.045,width*0.035),.init(-width*0.045,-width*0.035),.init(width*0.045,-width*0.035)] }
            for (index,offset) in offsets.enumerated() {
                var points:[SIMD2<Float>]
                if style == .upperInner {
                    points=[.init(-rx,ry*0.5),.init(0,-ry),.init(rx,ry*0.5),.init(rx*0.7,ry),.init(0,-ry*0.25),.init(-rx*0.7,ry),.init(-rx,ry*0.5)]
                } else {
                    points=(0...48).map { i in let a=Float(i)*2*Float.pi/48; return SIMD2(rx*cos(a),ry*sin(a)) }
                }
                let rotated=points.map { p -> SIMD2<Float> in
                    let x=p.x*cos(angle)-p.y*sin(angle),y=p.x*sin(angle)+p.y*cos(angle)
                    return SIMD2(sign*(center.x+offset.x+x),center.y+offset.y+y)
                }
                guard let area=bind(rotated,id:"\(brow.side.rawValue)-\(index)",closed:true) else { return nil }
                areas.append(area)
            }
            if simd_length(blend)>0 {
                let a=SIMD2(sign*center.x,center.y),b=a+SIMD2(sign*blend.x,blend.y)
                let d=simd_normalize(b-a),perp=SIMD2(-d.y,d.x),head=width*0.035
                let body=(0...12).map { a+(b-a)*Float($0)/12 }
                let paths=[body,[b-d*head+perp*head*0.6,b,b-d*head-perp*head*0.6]]
                for (i,path) in paths.enumerated() {
                    if let arrow=bind(path,id:"arrow-\(brow.side.rawValue)-\(i)",closed:false) { arrows.append(arrow) }
                }
            }
        }
        return .init(id:UUID(),style:style,areas:areas,blendArrows:arrows)
    }
}
