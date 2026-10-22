// -Nimah: Strip eyeliner pada kulit upper eye rim; titik dan pigmen berbagi attachment yang sama.
import Foundation
import simd

struct EyelinerStyle: Equatable, Sendable {
    var wingLength: Float = 0.16 // relatif lebar mata
    var wingAngle: Float = 18 // derajat, ke atas dari sudut luar
    var thickness: Float = 0.035 // relatif lebar mata
    var clamped: Self {
        Self(wingLength:max(0,min(0.3,wingLength)),wingAngle:max(0,min(35,wingAngle)),thickness:max(0.015,min(0.065,thickness)))
    }
}
struct EyelinerRegion: Sendable {
    enum Side: String, Sendable { case negativeX = "face −X", positiveX = "face +X" }
    struct Eye: Sendable {
        let side: Side
        let attachments: [SurfaceAttachment]
        let alpha: [Float]
        let triangles: [Int32]
        let guides: [SurfaceAttachment]
    }
    let eyes: [Eye]
    let reason: String
    static func make(vertices: [SIMD3<Float>], triangles: [Int16], rims: [[Int]], style: EyelinerStyle) -> Self {
        guard rims.count == 2 else { return Self(eyes:[],reason:"Eyeliner hidden · both eye rims are required; refit with eyes open") }
        let style=style.clamped
        var eyes: [Eye]=[]
        for rim in rims {
            guard rim.count>=5,rim.allSatisfy(vertices.indices.contains) else { continue }
            let center=rim.reduce(SIMD3<Float>.zero) { $0+vertices[$1] }/Float(rim.count)
            let points=rim.map { vertices[$0] }, minX=points.map(\.x).min()!, maxX=points.map(\.x).max()!
            let width=maxX-minX
            guard width>0.008,width<0.06,abs(center.x)>width*0.35 else { continue }
            let sign: Float=center.x<0 ? -1 : 1
            let upper=points.filter { $0.y>=center.y-width*0.0001 }.sorted { $0.x*sign < $1.x*sign }
            guard upper.count>=3 else { continue }
            // -Nimah: Ambil envelope tertinggi pada x yang sama; tidak menyambung upper/lower rim.
            var ordered: [SIMD3<Float>]=[]
            for point in upper {
                if let last=ordered.last,abs(last.x-point.x)<width*0.0001 {
                    if point.y>last.y { ordered[ordered.count-1]=point }
                } else { ordered.append(point) }
            }
            guard ordered.count>=3,let first=ordered.first,let last=ordered.last else { continue }
            var stations: [(SIMD2<Float>,Float)]=[]
            for i in 0..<25 {
                let t=Float(i)/24, x=first.x+(last.x-first.x)*t
                guard let j=(1..<ordered.count).first(where: { x*sign <= ordered[$0].x*sign+width*0.00001 }) else { continue }
                let a=ordered[j-1], b=ordered[j], f=max(0,min(1,(x-a.x)/(b.x-a.x)))
                let y=a.y+(b.y-a.y)*f+width*0.008
                stations.append((SIMD2(x,y),width*style.thickness*(0.35+0.65*t)))
            }
            if style.wingLength>0 {
                let radians=style.wingAngle*Float.pi/180
                for i in 1...8 {
                    let t=Float(i)/8, length=width*style.wingLength*t
                    stations.append((SIMD2(last.x+sign*length*cos(radians),last.y+width*0.008+length*sin(radians)),width*style.thickness*max(0.05,1-t)))
                }
            }
            var attachments:[SurfaceAttachment]=[], alpha:[Float]=[], indices:[Int32]=[], guides:[SurfaceAttachment]=[]
            var previousStart: Int?
            for (stationIndex,station) in stations.enumerated() {
                // -Nimah: Strip + feathering selalu di atas rim; tidak ada extrapolation ke hole bola mata.
                let offsets:[Float]=[0,0.15,0.80,1]
                let bound=offsets.compactMap { amount in
                    SurfaceAttachment.bind(station.0+SIMD2(0,station.1*amount),vertices:vertices,triangles:triangles,minimumZ:center.z-width*0.5)
                }
                guard bound.count==4 else { previousStart=nil; continue }
                let start=attachments.count
                attachments.append(contentsOf:bound); alpha.append(contentsOf:[0,1,1,0])
                if let previousStart {
                    for row in 0..<3 {
                        let a=Int32(previousStart+row),b=Int32(start+row)
                        indices.append(contentsOf:[a,b,a+1,b,b+1,a+1])
                    }
                }
                previousStart=start
                if stationIndex % 5 == 0 { guides.append(bound[1]) }
            }
            guard indices.count>=36,guides.count>=3 else { continue }
            eyes.append(Eye(side:sign<0 ? .negativeX : .positiveX,attachments:attachments,alpha:alpha,triangles:indices,guides:guides))
        }
        let reason=eyes.count==2 ? "Eyeliner surface attached · approximate lash line; device validation pending" : "Partial eyeliner · unsupported eye region hidden; refit with eyes open"
        return Self(eyes:eyes,reason:reason)
    }
}
