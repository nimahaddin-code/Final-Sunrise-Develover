// -Nimah: Intended makeup curves menggunakan bounds personal hasil Vision, lalu di-bind ke kulit.
import Foundation
import simd

struct EyebrowGuide: Sendable {
    struct Curve: Sendable {
        let side: EyebrowSide
        let landmarks: [SurfaceAttachment]
        let samples: [SurfaceAttachment?]
        let outline: [SurfaceAttachment?]
        let strokes: [(SurfaceAttachment,SurfaceAttachment)]
        var mappingLines:[[SurfaceAttachment?]] = []
        var keyPoints:[SurfaceAttachment] = []
        var shapeKeyPoints:[SurfaceAttachment] = []
    }
    let id: UUID
    let style: EyebrowStyle
    let curves: [Curve]
}
enum EyebrowGuideGenerator {
    static func target(t: Float, inner: SIMD3<Float>, outer: SIMD3<Float>, style: EyebrowStyle) -> SIMD2<Float> {
        let t=max(0,min(1,t)),width=abs(outer.x-inner.x)
        let tailSlope=max(-width*0.12,min(width*0.12,outer.y-inner.y))
        let peak:Float=0.64
        let phase=t<peak ? t/peak : (1-t)/(1-peak)
        let smooth:Float=style == .angular ? phase : (style == .rounded ? sin(t*Float.pi) : phase*phase*(3-2*phase))
        return SIMD2(inner.x+(outer.x-inner.x)*t,inner.y+tailSlope*t+width*style.archRatio*smooth+(style == .lifted ? width*0.10*t : 0))
    }
    // -Nimah: Anchor height to the observed brow, never add a generic arch percentage above it.
    static func calibratedPeak(mapping m:BrowAnatomicalMapping,style:EyebrowStyle) -> SIMD2<Float>? {
        let span=abs(m.tail.x-m.start.x)
        let naturalRise=max(0,m.arch.y-max(m.start.y,m.tail.y))
        let offset:Float
        switch style {
        case .straight:offset = -min(naturalRise*0.55,0.0015)
        case .softArch:offset = 0
        case .highArch:offset = min(span*0.025,0.001)
        case .feathered:offset = min(span*0.008,0.0004)
        case .natural,.thin:offset=0
        case .lifted:offset=0.0004
        case .angular:offset=0.0008
        case .rounded:offset=0.0005
        case .lowArch:offset = -min(naturalRise*0.4,0.001)
        }
        return BrowMappingFormula.intersection(nose:SIMD2(m.ala.x,m.ala.y),through:SIMD2(m.pupil.x,m.pupil.y),level:m.arch.y+offset)
    }
    static func make(region: EyebrowRegion, style: EyebrowStyle) -> EyebrowGuide? {
        var curves:[EyebrowGuide.Curve]=[]
        for brow in region.brows {
            let points=brow.landmarks.compactMap { $0.position(in:region.restVertices) }
            guard points.count>=3,let inner=points.min(by:{ abs($0.x)<abs($1.x) }),let outer=points.max(by:{ abs($0.x)<abs($1.x) }) else { return nil }
            let width=abs(outer.x-inner.x)
            guard width>0.008 else { return nil }
            let minimumZ=min(inner.z,outer.z)-width*0.6
            func bind(_ p: SIMD2<Float>) -> SurfaceAttachment? {
                SurfaceAttachment.bind(p,vertices:region.restVertices,triangles:region.triangles,minimumZ:minimumZ)
            }
            // -Nimah: Fit all measured eyebrow points, not the highest point or formula endpoints.
            guard let fit=ObservedBrowFit(points:points,inner:inner,outer:outer) else { return nil }
            let rule=MakeupRuleDatabase.brow(style == .thin || style == .feathered ? .natural : style)
            guard let rule else { return nil }
            let peak=rule.number("arch_t"),limit=rule.number("max_displacement")
            func adjusted(_ t:Float)->SIMD2<Float> {
                let phase=t<=peak ? t/max(peak,0.0001) : (1-t)/max(1-peak,0.0001)
                let bump=phase*phase*(3-2*phase)
                let shift=width*(rule.number("arch_delta")*bump+rule.number("tail_delta")*t)
                return SIMD2(inner.x+(outer.x-inner.x)*t,fit.height(at:t)+max(-limit,min(limit,shift)))
            }
            // Two cubic segments keep measured head/tail and the selected arch continuous.
            func tangent(_ t:Float)->SIMD2<Float> {
                let lo=max(0,t-0.001),hi=min(1,t+0.001)
                return (adjusted(hi)-adjusted(lo))/(hi-lo)
            }
            func intended(_ t:Float) -> SIMD2<Float> {
                let start:Float=t<=peak ? 0 : peak,end:Float=t<=peak ? peak : 1
                let fraction=(t-start)/(end-start),span=end-start
                let params=MakeupRuleDatabase.shared?.runtime_fitting_rules.parameters
                let h0=params?[start==0 ? "brow_handle_head" : "brow_handle_arch"]?.value ?? 0.33
                let h1=params?[end==1 ? "brow_handle_tail" : "brow_handle_arch"]?.value ?? 0.33
                let p0=adjusted(start),p3=adjusted(end)
                let p1=p0+tangent(start)*span*h0,p2=p3-tangent(end)*span*h1
                let u=1-fraction
                let b0:Float=u*u*u,b1:Float=3*u*u*fraction
                let b2:Float=3*u*fraction*fraction,b3:Float=fraction*fraction*fraction
                let first=p0*b0+p1*b1
                let second=p2*b2+p3*b3
                let p=first+second
                let baseline=fit.height(at:t)
                return SIMD2(p.x,baseline+max(-limit,min(limit,p.y-baseline)))
            }
            let samples=(0...40).map { bind(intended(Float($0)/40)) }
            guard samples.compactMap({ $0 }).count>=36 else { return nil }
            // -Nimah: Outline atas/bawah dengan tail mengecil, sesuai referensi shape guide.
            func boundary(_ upper:Bool) -> [SurfaceAttachment?] {
                (0...40).map { i in
                    let t=Float(i)/40
                    let center=intended(t)
                    let rule=MakeupRuleDatabase.brow(style == .thin || style == .feathered ? .natural : style)
                    let peak=rule?.number("arch_t") ?? 0.64
                    let head=rule?.number("head_taper") ?? 0.65,tail=rule?.number("tail_taper") ?? 0.08
                    let taper=t<=peak ? head+(1-head)*t/peak : 1+(tail-1)*(t-peak)/(1-peak)
                    // Vision open contour supplies centerline, not measured brow thickness.
                    let designHalf=width*(rule?.number("half_thickness_design") ?? 0.035)
                    let half=designHalf*taper*(rule?.number("thickness_scale") ?? 1)*(style == .thin ? 0.55 : 1)
                    return bind(center+SIMD2(0,upper ? half : -half))
                }
            }
            let upper=boundary(true),lower=boundary(false)
            let outline=upper+Array(lower.reversed())+[upper[0]]
            guard outline.compactMap({ $0 }).count>=75 else { return nil }
            var strokes:[(SurfaceAttachment,SurfaceAttachment)]=[]
            if style == .feathered {
                let direction:Float=outer.x>inner.x ? 1 : -1
                for i in stride(from:3,to:38,by:3) {
                    let p=intended(Float(i)/40)
                    if let start=bind(p),let end=bind(p+SIMD2(direction*width*0.035,width*0.07)) { strokes.append((start,end)) }
                }
            }
            var mappingLines:[[SurfaceAttachment?]]=[],keyPoints:[SurfaceAttachment]=[]
            // -Nimah: Optional formula annotations cannot erase a correctly fitted observed brow.
            if let m=brow.mapping,let peak=calibratedPeak(mapping:m,style:style) {
                let marks=[m.start,peak,m.tail].compactMap(bind)
                if marks.count==3 {
                    keyPoints=marks
                    for p in [m.start,peak,m.tail] {
                        let n=SIMD2(m.ala.x,m.ala.y)
                        mappingLines.append((0...60).map { bind(n+(p-n)*Float($0)/60) })
                    }
                }
            }
            let peakIndex=(0..<samples.count).max { a,b in
                (samples[a]?.position(in:region.restVertices)?.y ?? -.infinity)<(samples[b]?.position(in:region.restVertices)?.y ?? -.infinity)
            } ?? 20
            let shapeKeyPoints=[samples[0],samples[peakIndex],samples[40]].compactMap { $0 }
            curves.append(.init(side:brow.side,landmarks:brow.landmarks,samples:samples,outline:outline,strokes:strokes,mappingLines:mappingLines,keyPoints:keyPoints,shapeKeyPoints:shapeKeyPoints))
        }
        guard curves.count==2 else { return nil }
        return EyebrowGuide(id:UUID(),style:style,curves:curves)
    }
}

// -Nimah: Quadratic least-squares centerline in normalized brow coordinates. Upper/lower observations
// contribute equally; a contour's highest point must not become the entire makeup centerline.
struct ObservedBrowFit {
    let a:Float,b:Float,c:Float
    let halfThickness:Float
    var rise:Float { max(0,height(at:0.5)-(height(at:0)+height(at:1))/2) }
    func height(at t:Float) -> Float { a+b*t+c*t*t }
    init?(points:[SIMD3<Float>],inner:SIMD3<Float>,outer:SIMD3<Float>) {
        let span=outer.x-inner.x
        guard points.count>=3,abs(span)>0.008 else { return nil }
        var matrix=Array(repeating:Array(repeating:Float(0),count:4),count:3)
        for p in points {
            let t=(p.x-inner.x)/span,v:[Float]=[1,t,t*t]
            guard t.isFinite,p.y.isFinite else { return nil }
            for row in 0..<3 {
                for column in 0..<3 { matrix[row][column] += v[row]*v[column] }
                matrix[row][3] += v[row]*p.y
            }
        }
        for column in 0..<3 {
            guard let pivot=(column..<3).max(by:{ abs(matrix[$0][column])<abs(matrix[$1][column]) }),abs(matrix[pivot][column])>0.000001 else { return nil }
            if pivot != column { matrix.swapAt(pivot,column) }
            let divisor=matrix[column][column]
            for j in column...3 { matrix[column][j] /= divisor }
            for row in 0..<3 where row != column {
                let factor=matrix[row][column]
                for j in column...3 { matrix[row][j] -= factor*matrix[column][j] }
            }
        }
        let ca=matrix[0][3],cb=matrix[1][3],cc=matrix[2][3]
        a=ca; b=cb; c=cc
        let residuals=points.map { p -> Float in
            let t=(p.x-inner.x)/span
            return abs(p.y-(ca+cb*t+cc*t*t))
        }
        halfThickness=max(0.0008,min(0.002,(residuals.reduce(0,+)/Float(residuals.count))*1.5))
    }
}
