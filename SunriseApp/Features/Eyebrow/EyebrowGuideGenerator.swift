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
            func intended(_ t:Float) -> SIMD2<Float> {
                let x=inner.x+(outer.x-inner.x)*t
                let bump=sin(Float.pi*t)*sin(Float.pi*t)
                let adjustment:Float
                switch style {
                case .straight:adjustment = -min(fit.rise*0.4,0.001)*bump
                case .softArch:adjustment = 0
                case .highArch:adjustment = 0.0006*bump
                case .feathered:adjustment = 0.0002*bump
                case .natural,.thin:adjustment=0
                case .lifted:adjustment=0.0008*t
                case .angular:adjustment=0.0008*max(0,1-abs(t-0.64)/0.36)
                case .rounded:adjustment=0.0005*sin(Float.pi*t)
                case .lowArch:adjustment = -min(fit.rise*0.55,0.0012)*bump
                }
                return SIMD2(x,fit.height(at:t)+adjustment)
            }
            let samples=(0...40).map { bind(intended(Float($0)/40)) }
            guard samples.compactMap({ $0 }).count>=36 else { return nil }
            // -Nimah: Outline atas/bawah dengan tail mengecil, sesuai referensi shape guide.
            func boundary(_ upper:Bool) -> [SurfaceAttachment?] {
                (0...40).map { i in
                    let t=Float(i)/40
                    let center=intended(t)
                    let half=fit.halfThickness*(1-0.75*t)*(style == .thin ? 0.55 : 1)
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
            if let m=brow.mapping {
                guard let peak=calibratedPeak(mapping:m,style:style) else { return nil }
                for p in [m.start,peak,m.tail] {
                    guard let mark=bind(p) else { return nil }
                    keyPoints.append(mark)
                    let n=SIMD2(m.ala.x,m.ala.y)
                    mappingLines.append((0...60).map { bind(n+(p-n)*Float($0)/60) })
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
