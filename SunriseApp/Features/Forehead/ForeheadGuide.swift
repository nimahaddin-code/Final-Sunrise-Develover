// -Nimah: Forehead guide adalah area placement perkiraan pada mesh, bukan deteksi hairline.
import Foundation
import simd

enum FaceGuideRegion:String,CaseIterable,Identifiable,Sendable {
    case eyebrows,blush,forehead
    var id:String { rawValue }
    var title:String { switch self { case .eyebrows:return "Eyebrows"; case .blush:return "Blush"; case .forehead:return "Forehead" } }
}
enum ForeheadCategory:String,CaseIterable,Identifiable,Sendable {
    case contour,highlight
    var id:String { rawValue }
    var title:String { self == .contour ? "Contour" : "Highlight" }
}
enum ForeheadStyle:String,CaseIterable,Identifiable,Sendable {
    case hairline,temple,softSculpt,centerHighlight,softGlow
    var id:String { rawValue }
    var title:String {
        switch self {
        case .hairline:return "Hairline"
        case .temple:return "Temple"
        case .softSculpt:return "Soft Sculpt"
        case .centerHighlight:return "Center Highlight"
        case .softGlow:return "Soft Glow"
        }
    }
    var category:ForeheadCategory { [.centerHighlight,.softGlow].contains(self) ? .highlight : .contour }
}
struct ForeheadGuide:Sendable {
    typealias Area = FaceGuideArea
    let id:UUID
    let style:ForeheadStyle
    let height:Float
    let areas:[Area]
    let lowerY:Float
}
enum ForeheadGuideGenerator {
    static func make(region:EyebrowRegion,style:ForeheadStyle,height:Float) -> ForeheadGuide? {
        let vertices=region.restVertices
        let brows=region.brows.flatMap(\.landmarks).compactMap { $0.position(in:vertices) }
        guard region.brows.count==2,brows.count>=6,let browTop=brows.map(\.y).max(),
              let minX=vertices.map(\.x).min(),let maxX=vertices.map(\.x).max(),height.isFinite else { return nil }
        let width=(maxX-minX)/2,lower=browTop+width*0.09
        let forehead=vertices.filter { $0.y>lower && abs($0.x)<width*0.7 }
        guard let top=forehead.map(\.y).max(),let minimumZ=forehead.map(\.z).min(),width>0.02 else { return nil }
        let clamped=max(0.45,min(1,height)),usable=(top-lower)*clamped
        guard usable>width*0.14 else { return nil }
        var paths:[(String,[SIMD2<Float>])]=[]
        func ellipse(_ id:String,x:Float,y:Float,rx:Float,ry:Float) {
            paths.append((id,(0...60).map { i in
                let angle=Float(i)*2*Float.pi/60
                return SIMD2(x+rx*cos(angle),y+ry*sin(angle))
            }))
        }
        switch style {
        case .hairline:
            let upper=(0...40).map { i -> SIMD2<Float> in
                let t=Float(i)/40,x=(2*t-1)*width*0.6
                return SIMD2(x,lower+usable*(0.38+0.55*sin(t*Float.pi)))
            }
            let lowerArc=(0...40).reversed().map { i -> SIMD2<Float> in
                let t=Float(i)/40,x=(2*t-1)*width*0.6
                return SIMD2(x,lower+usable*(0.20+0.42*sin(t*Float.pi)))
            }
            paths=[("upper-contour",upper+lowerArc+[upper[0]])]
        case .temple:
            ellipse("left-temple",x:-width*0.51,y:lower+usable*0.4,rx:width*0.13,ry:usable*0.30)
            ellipse("right-temple",x:width*0.51,y:lower+usable*0.4,rx:width*0.13,ry:usable*0.30)
        case .softSculpt:ellipse("soft-sculpt",x:0,y:lower+usable*0.55,rx:width*0.60,ry:usable*0.31)
        case .centerHighlight:ellipse("center-highlight",x:0,y:lower+usable*0.38,rx:width*0.20,ry:usable*0.27)
        case .softGlow:ellipse("soft-glow",x:0,y:lower+usable*0.43,rx:width*0.39,ry:usable*0.29)
        }
        var areas:[ForeheadGuide.Area]=[]
        for (id,points) in paths {
            let bound=points.compactMap { SurfaceAttachment.bind($0,vertices:vertices,triangles:region.triangles,minimumZ:minimumZ-0.005) }
            // -Nimah: Tidak menutup loop lewat screen offset atau segmen melayang jika keluar mesh.
            guard bound.count==points.count else { return nil }
            areas.append(.init(id:id,boundary:bound))
        }
        return ForeheadGuide(id:UUID(),style:style,height:clamped,areas:areas,lowerY:lower)
    }
}
