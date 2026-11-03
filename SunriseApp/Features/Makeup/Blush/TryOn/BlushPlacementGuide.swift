// -Nimah: Personal cheek placement from calibrated eye/nose anchors, bound to real mesh triangles.
import Foundation
import simd

enum BlushPlacementStyle:String,CaseIterable,Identifiable,Sendable {
    case youthful,sunkissed,lifted,apple,cheekbone,outerSweep,highLift,wideHorizontal,centerCheek,centerDown,upperInner,templeSweep,diagonalBlend,placementDots,innerCheek
    static let referenceLooks:[Self]=[.youthful,.sunkissed,.lifted]
    var isReferenceLook:Bool {Self.referenceLooks.contains(self)}
    var id:String { rawValue }
    var title:String {
        switch self {
        case .youthful:return "Youthful"
        case .sunkissed:return "Sunkissed"
        case .lifted:return "Lifted"
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
        case .youthful:return "Focus color on the middle cheeks; softly blend the edges."
        case .sunkissed:return "Blend a soft horizontal wash over the cheeks and upper nose bridge; keep nostrils clear."
        case .lifted:return "Sweep from the outer cheek upward toward the temple, below the eyes."
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
    var noseBridge:BlushPigmentField? = nil
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
    var curvature:Float = 0
    var softProfile=false
    /// Landmark-fitted wash: 1 - smoothstep(0, 1, r), flat-topped and with no visible edge (BeautyBlush.metal `paint.z`).
    var wash=false
    var bounds:[SIMD2<Float>] {
        (0...64).map { i in
            let a=Float(i)*2*Float.pi/64
            let nx=cos(a)
            let q=SIMD2(radius.x*nx,radius.y*(sin(a)+curvature*(nx*nx-0.25)))
            return center+SIMD2(side*(q.x*cos(angle)-q.y*sin(angle)),q.x*sin(angle)+q.y*cos(angle))
        }
    }
    func coverage(_ point:SIMD2<Float>)->Float {
        guard point.x*side>=nasalLimit,point.x*side<=outerLimit,point.y<=eyeLimit else { return 0 }
        let d=point-center,x=d.x*side,y=d.y
        var q=SIMD2((x*cos(angle)+y*sin(angle))/radius.x,(-x*sin(angle)+y*cos(angle))/radius.y)
        q.y -= curvature*(q.x*q.x-0.25)
        let r2=simd_length_squared(q)
        let raw=pow(max(0,1-r2),power)
        let smooth=raw*raw*(3-2*raw)
        let r=r2.squareRoot(),t=max(0,min(1,r))
        let radial=wash ? 1-t*t*(3-2*t):(softProfile ? raw*exp(-0.8*r2):raw+(smooth-raw)*smoothstepMix)
        // -Nimah: Fade inward at safe skin boundaries, without moving or shrinking the JSON ellipse.
        func mask(_ clearance:Float)->Float {
            let t=edgeFeather>0 ? max(0,min(1,clearance/edgeFeather)) : 1
            return t*t*(3-2*t)
        }
        // Separate smooth masks avoid a hard gradient ridge where two exclusions meet.
        return radial*mask(point.x*side-nasalLimit)*mask(outerLimit-point.x*side)*mask(eyeLimit-point.y)
    }
}
/// MediaPipe face landmarks lifted onto ARKit's face mesh (`BrowFaceFrame.faceLocal`), in the anchor's face-local metres:
/// the median of several frontal frames. Gives each person's own cheek corridor: nostril wing to face edge, mouth corner
/// to lower eyelid. Indices are MediaPipe's 468-point topology, never ARKit vertex indices.
struct BlushCheekLandmarks:Sendable,Equatable {
    struct Cheek:Sendable,Equatable {
        var outerEye,innerEye,lowerLid,ala,mouthCorner,cheekbone,apple,faceEdge:SIMD3<Float>
    }
    /// (subject right, subject left) pairs, in `Cheek` member order.
    static let pairs:[(Int,Int)]=[(33,263),(133,362),(145,374),(129,358),(61,291),(116,345),(50,280),(234,454)]
    static var indices:[Int] {pairs.flatMap {[$0.0,$0.1]}}
    let cheeks:[Cheek]
    /// `points` in `indices` order. Sides are told apart by measured x, never by screen mirroring.
    init?(points:[SIMD3<Float>]) {
        guard points.count==Self.indices.count,points.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}) else {return nil}
        func cheek(_ k:Int)->Cheek {
            let p=(0..<Self.pairs.count).map {points[$0*2+k]}
            return Cheek(outerEye:p[0],innerEye:p[1],lowerLid:p[2],ala:p[3],mouthCorner:p[4],cheekbone:p[5],apple:p[6],faceEdge:p[7])
        }
        let a=cheek(0),b=cheek(1)
        guard a.ala.x*b.ala.x<0,a.faceEdge.x*b.faceEdge.x<0 else {return nil}
        cheeks=[a,b]
    }
    /// The cheek on the side whose x has `sign`.
    func cheek(sign:Float)->Cheek? {cheeks.first {$0.ala.x*sign>0}}
    /// Per-coordinate median of several samples (each in `indices` order).
    static func median(_ samples:[[SIMD3<Float>]])->[SIMD3<Float>]? {
        guard let first=samples.first,samples.allSatisfy({$0.count==first.count}) else {return nil}
        func mid(_ v:[Float])->Float {let s=v.sorted();return s.count%2==1 ? s[s.count/2]:(s[s.count/2-1]+s[s.count/2])/2}
        return first.indices.map {i in SIMD3(mid(samples.map {$0[i].x}),mid(samples.map {$0[i].y}),mid(samples.map {$0[i].z}))}
    }
}
enum BlushPlacementGenerator {
    /// One cheek's wash from its measured corridor, or nil when the landmarks do not form a usable cheek.
    static func landmarkField(_ c:BlushCheekLandmarks.Cheek,sign:Float,rule:MakeupRuleDatabase.Preset,width:Float,style:BlushPlacementStyle)->BlushPigmentField? {
        guard ["landmark_center_across","landmark_center_up","landmark_radius_across","landmark_radius_up","landmark_edge_feather","landmark_eye_clearance"].allSatisfy({rule.parameters[$0] != nil}) else {return nil}
        let inner=c.ala.x*sign
        let outer=c.faceEdge.x*sign-width*rule.number("face_edge_margin")
        let top=min(c.lowerLid.y,c.outerEye.y),bottom=c.mouthCorner.y
        let across=outer-inner,height=top-bottom
        // A real cheek is at least ~2.5 cm across and tall; anything less is a bad fit, not a small face.
        guard across>0.025,height>0.025,across<0.12,height<0.12 else {return nil}
        let eyeLimit=top-height*rule.number("landmark_eye_clearance")
        let center=SIMD2(sign*(inner+across*rule.number("landmark_center_across")),bottom+height*rule.number("landmark_center_up"))
        let radius=SIMD2(across*rule.number("landmark_radius_across"),height*rule.number("landmark_radius_up"))
        return BlushPigmentField(center:center,radius:radius,angle:rule.number("outward_up_angle")*Float.pi/180,side:sign,
            nasalLimit:inner,outerLimit:outer,eyeLimit:eyeLimit,opacity:rule.number("max_alpha"),power:1,
            edgeFeather:across*rule.number("landmark_edge_feather"),smoothstepMix:0,curvature:rule.parameters["curvature"]?.value ?? 0,
            softProfile:true,wash:true)
    }

    static func mouthExclusion(vertices:[SIMD3<Float>],triangles:[Int16],eyes:[SIMD3<Float>])->SIMD4<Float> {
        struct Edge:Hashable {let a:Int;let b:Int}
        guard eyes.count==2,!vertices.isEmpty,triangles.count%3==0 else{return .zero}
        var counts:[Edge:Int]=[:]
        for i in stride(from:0,to:triangles.count,by:3) {
            let ids=[Int(triangles[i]),Int(triangles[i+1]),Int(triangles[i+2])]
            guard ids.allSatisfy(vertices.indices.contains) else{return .zero}
            for j in 0..<3 {let a=ids[j],b=ids[(j+1)%3];counts[Edge(a:min(a,b),b:max(a,b)),default:0] += 1}
        }
        var adjacency:[Int:[Int]]=[:]
        for (e,count) in counts where count==1 {adjacency[e.a,default:[]].append(e.b);adjacency[e.b,default:[]].append(e.a)}
        var visited=Set<Int>(),loops:[[Int]]=[]
        for start in adjacency.keys where !visited.contains(start) {
            var stack=[start],component:[Int]=[];visited.insert(start)
            while let i=stack.popLast() {component.append(i);for next in adjacency[i] ?? [] where !visited.contains(next) {visited.insert(next);stack.append(next)}}
            loops.append(component)
        }
        guard let outer=loops.indices.max(by:{loops[$0].count<loops[$1].count}) else{return .zero}
        let width=(vertices.map(\.x).max() ?? 0)-(vertices.map(\.x).min() ?? 0),eyeY=(eyes[0].y+eyes[1].y)/2
        guard width>0 else{return .zero}
        for (i,loop) in loops.enumerated() where i != outer && loop.count>=4 {
            let points=loop.map {vertices[$0]},cx=points.map(\.x).reduce(0,+)/Float(loop.count),cy=points.map(\.y).reduce(0,+)/Float(loop.count)
            guard abs(cx)<width*0.15,cy<eyeY-width*0.15,cy>eyeY-width*0.65 else{continue}
            let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!,minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
            return SIMD4((minX+maxX)/2,(minY+maxY)/2,(maxX-minX)*0.6+width*0.015,(maxY-minY)*0.6+width*0.015)
        }
        return .zero
    }

    /// With `cheeks` (reference looks only), each cheek is fitted to the person's measured corridor; without, or when a
    /// side's landmarks do not form a usable cheek, the ARKit-only fit below is used for that side.
    static func make(region:EyebrowRegion,style:BlushPlacementStyle,cheeks:BlushCheekLandmarks?=nil) -> BlushPlacementGuide? {
        guard let rule=MakeupRuleDatabase.blush(style) else { return nil }
        let vertices=region.restVertices
        guard region.brows.count==2,let lo=vertices.map(\.x).min(),let hi=vertices.map(\.x).max() else { return nil }
        let width=hi-lo // Full face width, exactly as declared by the database.
        guard width>0.04,width<0.32 else { return nil }
        let mappings=region.brows.compactMap(\.mapping)
        let eyes=region.eyeCenters.count==2 ? region.eyeCenters : mappings.map(\.pupil)
        guard eyes.count==2 else { return nil }
        let mouth=mouthExclusion(vertices:vertices,triangles:region.triangles,eyes:eyes)
        let personal=MakeupRuleDatabase.shared?.runtime_fitting_rules.parameters
        func parameter(_ key:String,_ fallback:Float)->Float {personal?[key]?.value ?? fallback}
        let strength=parameter("blush_personalization_strength",0.85)
        let minScale=parameter("blush_personal_scale_min",0.8),maxScale=parameter("blush_personal_scale_max",1.25)
        let band=width*parameter("blush_contour_band",0.035)
        func scale(_ ratio:Float)->Float {1+strength*(max(minScale,min(maxScale,ratio))-1)}
        // Eye spacing measures the local facial frame; it does not classify a face shape.
        let eyeWidth=abs(eyes[0].x-eyes[1].x)
        let nominalWidth=eyeWidth/parameter("blush_nominal_interocular_ratio",0.4)
        guard nominalWidth.isFinite,nominalWidth>0.04,nominalWidth<0.32 else {return nil}
        var areas:[FaceGuideArea]=[],fields:[BlushPigmentField]=[],arrows:[FaceGuideArea]=[]
        for brow in region.brows {
            let points=brow.landmarks.compactMap { $0.position(in:vertices) }
            guard !points.isEmpty else { return nil }
            let sign:Float=points.map(\.x).reduce(0,+)>0 ? 1 : -1
            // Anatomical side comes from measured coordinates, never mirrored screen labels.
            guard let eye=eyes.first(where:{$0.x*sign>0}) else { return nil }
            let nominalCenter=SIMD2(eye.x+sign*width*rule.number("center_outward_offset"),eye.y+width*rule.number("center_vertical_offset"))
            let nose=brow.mapping.map { abs($0.ala.x)+width*rule.number("nose_margin") }
                ?? width*rule.number("fallback_midline_exclusion_half_width")
            // Use the per-side outer cheek at this height, not the widest vertex anywhere on the head.
            let cheek=vertices.filter {abs($0.y-nominalCenter.y)<=band && $0.x*sign>nose && $0.z>=eye.z-width*0.35}
            let outward=cheek.map {$0.x*sign}.sorted()
            let globalOuter=(sign>0 ? hi : -lo)-width*rule.number("face_edge_margin")
            let localOuter=outward.count>=4 ? min(globalOuter,outward[Int(Float(outward.count-1)*0.95)]-width*rule.number("face_edge_margin")):globalOuter
            let baseCorridor=width*0.5-width*rule.number("face_edge_margin")-nose
            let corridor=localOuter-nose
            guard corridor>width*0.08,baseCorridor>0 else {return nil}
            let horizontal=scale(corridor/baseCorridor)
            // Mouth-opening topology is optional. Nose ala provides a measured midface reference otherwise.
            // This is not an inferred cheekbone or a measured lower eyelid.
            let lowerReference:Float?
            if mouth.z>0 && mouth.w>0 {lowerReference=mouth.y+mouth.w}
            else {lowerReference=brow.mapping?.ala.y}
            let expectedDistance=width*(mouth.z>0 ? 0.48:0.28125)
            let vertical=lowerReference.map {scale((eye.y-$0)/expectedDistance)} ?? scale(nominalWidth/width)
            let eyeLimit=eye.y-width*max(0.06,rule.number("eye_margin"))
            var center=SIMD2(sign*(nose+(nominalCenter.x*sign-nose)*horizontal),eye.y+(nominalCenter.y-eye.y)*vertical)
            let radius=SIMD2(width*rule.number("major_radius")*horizontal,width*rule.number("minor_radius")*vertical)
            // Keep the center inside usable skin without forcing both sides to be symmetric.
            center.x=sign*max(nose+width*0.025,min(localOuter-width*0.025,sign*center.x))
            center.y=min(center.y,eyeLimit-width*0.025)
            if mouth.z>0 {center.y=max(center.y,mouth.y+mouth.w+width*parameter("blush_mouth_clearance",0.025))}
            let fitted=style.isReferenceLook ? cheeks?.cheek(sign:sign).flatMap {landmarkField($0,sign:sign,rule:rule,width:width,style:style)}:nil
            if let fitted {center=fitted.center}
            let field=fitted ?? BlushPigmentField(center:center,radius:radius,
                angle:rule.number("outward_up_angle")*Float.pi/180,side:sign,nasalLimit:nose,
                outerLimit:localOuter,
                eyeLimit:eyeLimit,opacity:rule.number("max_alpha"),power:rule.number("radial_power"),edgeFeather:width*rule.number("mask_edge_feather"),smoothstepMix:rule.number("falloff_smoothstep_mix"),curvature:rule.parameters["curvature"]?.value ?? 0,softProfile:style.isReferenceLook)
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
            // A landmark wash is meant to be wider than the cheek and cut softly by its borders.
            guard fitted != nil || Float(retained)/Float(total)>=0.5 else { return nil }
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
        var bridge:BlushPigmentField?
        if style == .sunkissed {
            let eye=eyes.reduce(SIMD3<Float>.zero,+)/2
            let radius=SIMD2(width*rule.number("bridge_radius_x"),width*rule.number("bridge_radius_y"))
            let x=eye.x,y=eye.y+width*rule.number("bridge_vertical_offset")
            bridge=BlushPigmentField(center:SIMD2(x,y),radius:radius,angle:0,side:1,
                nasalLimit:x-radius.x,outerLimit:x+radius.x,eyeLimit:eyes.map(\.y).min()!-width*0.08,
                opacity:rule.number("max_alpha")*rule.number("bridge_strength"),power:rule.number("radial_power"),
                edgeFeather:width*0.012,smoothstepMix:0,softProfile:true)
            if let bridge {
                let boundary=bridge.bounds.compactMap {SurfaceAttachment.bind($0,vertices:vertices,triangles:region.triangles,minimumZ:eye.z-width*0.35)}
                if boundary.count==bridge.bounds.count {areas.append(.init(id:"nose-bridge",boundary:boundary))}
            }
        }
        return .init(id:UUID(),style:style,areas:areas,blendArrows:arrows,pigmentFields:fields,noseBridge:bridge)
    }
}
