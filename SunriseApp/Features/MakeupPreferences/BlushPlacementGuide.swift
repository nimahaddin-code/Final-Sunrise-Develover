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
    var pigmentFields:[BlushPigmentField] = []
}
// -Nimah: Exact JSON ellipse in native ARKit face-local metres. Pigment is independent of tutorial marks.
struct BlushPigmentField:Sendable {
    let center:SIMD2<Float>
    let radius:SIMD2<Float>
    let angle:Float
    let side:Float
    let nasalLimit:Float
    let outerLimit:Float
    let eyeLimit:Float
    let opacity:Float
    let power:Float
    var edgeFeather:Float = 0
    var smoothstepMix:Float = 0
    var bounds:[SIMD2<Float>] {
        (0...64).map { i in
            let a=Float(i)*2*Float.pi/64
            let q=SIMD2(radius.x*cos(a),radius.y*sin(a))
            return center+SIMD2(side*(q.x*cos(angle)-q.y*sin(angle)),q.x*sin(angle)+q.y*cos(angle))
        }
    }
    func coverage(_ point:SIMD2<Float>)->Float {
        guard point.x*side>=nasalLimit,point.x*side<=outerLimit,point.y<=eyeLimit else { return 0 }
        let d=point-center,x=d.x*side,y=d.y
        let q=SIMD2((x*cos(angle)+y*sin(angle))/radius.x,(-x*sin(angle)+y*cos(angle))/radius.y)
        let raw=pow(max(0,1-simd_length_squared(q)),power)
        let smooth=raw*raw*(3-2*raw)
        let radial=raw+(smooth-raw)*smoothstepMix
        // -Nimah: Fade inward at safe skin boundaries, without moving or shrinking the JSON ellipse.
        func mask(_ clearance:Float)->Float {
            let t=edgeFeather>0 ? max(0,min(1,clearance/edgeFeather)) : 1
            return t*t*(3-2*t)
        }
        // Separate smooth masks avoid a hard gradient ridge where two exclusions meet.
        return radial*mask(point.x*side-nasalLimit)*mask(outerLimit-point.x*side)*mask(eyeLimit-point.y)
    }
}
enum BlushPlacementGenerator {
    static func make(region:EyebrowRegion,style:BlushPlacementStyle) -> BlushPlacementGuide? {
        guard let rule=MakeupRuleDatabase.blush(style) else { return nil }
        let vertices=region.restVertices
        guard region.brows.count==2,let lo=vertices.map(\.x).min(),let hi=vertices.map(\.x).max() else { return nil }
        let width=hi-lo // Full face width, exactly as declared by the database.
        guard width>0.04,width<0.32 else { return nil }
        let mappings=region.brows.compactMap(\.mapping)
        let eyes=region.eyeCenters.count==2 ? region.eyeCenters : mappings.map(\.pupil)
        guard eyes.count==2 else { return nil }
        var areas:[FaceGuideArea]=[],fields:[BlushPigmentField]=[],arrows:[FaceGuideArea]=[]
        for brow in region.brows {
            let points=brow.landmarks.compactMap { $0.position(in:vertices) }
            guard !points.isEmpty else { return nil }
            let sign:Float=points.map(\.x).reduce(0,+)>0 ? 1 : -1
            // Anatomical side comes from measured coordinates, never mirrored screen labels.
            guard let eye=eyes.first(where:{$0.x*sign>0}) else { return nil }
            let center=SIMD2(eye.x+sign*width*rule.number("center_outward_offset"),eye.y+width*rule.number("center_vertical_offset"))
            let nose=brow.mapping.map { abs($0.ala.x)+width*rule.number("nose_margin") }
                ?? width*rule.number("fallback_midline_exclusion_half_width")
            // Current adapter lacks a lower-eyelid contour: conservative eye-center exclusion is explicit,
            // pending contour calibration; it is not represented as a measured eyelid boundary.
            let field=BlushPigmentField(center:center,radius:SIMD2(width*rule.number("major_radius"),width*rule.number("minor_radius")),
                angle:rule.number("outward_up_angle")*Float.pi/180,side:sign,nasalLimit:nose,
                outerLimit:(sign>0 ? hi : -lo)-width*rule.number("face_edge_margin"),
                eyeLimit:eye.y-width*max(0.06,rule.number("eye_margin")),opacity:rule.number("max_alpha"),power:rule.number("radial_power"),edgeFeather:width*rule.number("mask_edge_feather"),smoothstepMix:rule.number("falloff_smoothstep_mix"))
            let minimumZ=eye.z-width*0.35
            func bind(_ p:SIMD2<Float>)->SurfaceAttachment? {
                SurfaceAttachment.bind(p,vertices:vertices,triangles:region.triangles,minimumZ:minimumZ)
            }
            // Reject unsafe coverage instead of collapsing the original radii into small dots.
            var retained=0,total=0
            for y in -10...10 { for x in -10...10 {
                let q=SIMD2(Float(x)/10*field.radius.x,Float(y)/10*field.radius.y)
                guard simd_length_squared(q/field.radius)<=1 else { continue }
                total += 1
                let p=center+SIMD2(sign*(q.x*cos(field.angle)-q.y*sin(field.angle)),q.x*sin(field.angle)+q.y*cos(field.angle))
                if field.coverage(p)>0 { retained += 1 }
            } }
            guard Float(retained)/Float(total)>=0.5 else { return nil }
            let clipped=field.bounds.map { p in SIMD2(sign*max(field.nasalLimit,min(field.outerLimit,sign*p.x)),min(field.eyeLimit,p.y)) }
            let boundary=clipped.compactMap(bind)
            // Tutorial boundary and filled pigment have separate eligibility. Do not lose a valid
            // cheek field because a peripheral guide point falls outside the mesh.
            if boundary.count==clipped.count { areas.append(.init(id:brow.side.rawValue+"-pigment",boundary:boundary)) }
            fields.append(field)
            // Tutorial direction only; final pigment always remains one continuous ellipse per cheek.
            let direction:SIMD2<Float>
            switch style {
            case .centerDown:direction=SIMD2(0,-1)
            case .innerCheek:direction=SIMD2(-sign,0)
            case .wideHorizontal:direction=SIMD2(sign,0)
            default:direction=SIMD2(sign*cos(field.angle),sin(field.angle))
            }
            let end=center+direction*width*rule.number("blend_distance")
            let perpendicular=SIMD2(-direction.y,direction.x),head=width*0.015
            let paths=[(0...12).map { center+(end-center)*Float($0)/12 },[end-direction*head+perpendicular*head*0.6,end,end-direction*head-perpendicular*head*0.6]]
            for (index,path) in paths.enumerated() {
                let bound=path.compactMap(bind)
                if bound.count==path.count { arrows.append(.init(id:"arrow-\(brow.side.rawValue)-\(index)",boundary:bound)) }
            }
        }
        return .init(id:UUID(),style:style,areas:areas,blendArrows:arrows,pigmentFields:fields)
    }
}
