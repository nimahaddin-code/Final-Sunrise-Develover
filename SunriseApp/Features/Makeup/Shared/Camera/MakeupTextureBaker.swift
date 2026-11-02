// -Nimah: Texture transparan dibake satu kali; mesh native dipakai ulang setiap frame.
import Foundation
import CoreGraphics
import simd

struct BakedMakeupProfile: @unchecked Sendable {
    let surface: FaceSurfaceProfile
    let textures: [TutorialStep: CGImage]
    let fullLook: CGImage
    // -Nimah: Rest surface untuk rebuild attachment saat fine adjustment berubah.
    let cumulative: [TutorialStep: CGImage]
    let restVertices: [SIMD3<Float>]
    let triangles: [Int16]
    let defaultEyeliner: EyelinerRegion
}
enum MakeupTextureBaker {
    static func bake(surface: FaceSurfaceProfile, uv: [SIMD2<Float>], triangles: [Int16], referenceID: String, size: Int = 512, vertices: [SIMD3<Float>] = []) -> BakedMakeupProfile? {
        guard size >= 8, size <= 2048, uv.count == surface.vertexCount,
              uv.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), triangles.count % 3 == 0,
              triangles.allSatisfy({ uv.indices.contains(Int($0)) }) else { return nil }
        guard TutorialStep.allCases.allSatisfy({ step in
            surface.weights[step]?.count == uv.count && surface.weights[step]!.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
        }) else { return nil }
        var colors: [TutorialStep:[SIMD4<Float>]] = [:]
        for step in TutorialStep.allCases {
            let pigment=tone(step,referenceID)
            colors[step]=surface.weights[step]!.map { weight in
                let a=weight*pigment.w
                return SIMD4(pigment.x*a,pigment.y*a,pigment.z*a,a)
            }
        }
        var combined=Array(repeating:SIMD4<Float>.zero,count:uv.count)
        // -Nimah: Eyeliner tidak pernah masuk atlas; dirender melalui triangle attachments.
        for step in [TutorialStep.contour,.blush,.eyeshadow,.lips] {
            for i in combined.indices { let source=colors[step]![i]; combined[i]=source+combined[i]*(1-source.w) }
        }
        func raster(_ values: [SIMD4<Float>]) -> CGImage? {
            var pixels=Array(repeating:UInt8(0),count:size*size*4)
            for t in stride(from:0,to:triangles.count,by:3) {
                let ia=Int(triangles[t]), ib=Int(triangles[t+1]), ic=Int(triangles[t+2])
                if max(values[ia].w,max(values[ib].w,values[ic].w)) < 0.001 { continue }
                let a=uv[ia]*Float(size-1), b=uv[ib]*Float(size-1), c=uv[ic]*Float(size-1)
                let denom=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
                if abs(denom)<0.000001 { continue }
                let x0=max(0,Int(floor(min(a.x,min(b.x,c.x))))), x1=min(size-1,Int(ceil(max(a.x,max(b.x,c.x)))))
                let y0=max(0,Int(floor(min(a.y,min(b.y,c.y))))), y1=min(size-1,Int(ceil(max(a.y,max(b.y,c.y)))))
                guard x0<=x1,y0<=y1 else { continue }
                for y in y0...y1 { for x in x0...x1 {
                    let px=Float(x)+0.5, py=Float(y)+0.5
                    let wa=((b.y-c.y)*(px-c.x)+(c.x-b.x)*(py-c.y))/denom
                    let wb=((c.y-a.y)*(px-c.x)+(a.x-c.x)*(py-c.y))/denom
                    let wc=1-wa-wb
                    if wa < -0.001 || wb < -0.001 || wc < -0.001 { continue }
                    let rgba=values[ia]*wa+values[ib]*wb+values[ic]*wc
                    // -Nimah: SceneKit UV v=0 berada di bawah; baris CGImage dimulai dari atas.
                    let offset=((size-1-y)*size+x)*4
                    for channel in 0..<4 { pixels[offset+channel]=UInt8(max(0,min(255,rgba[channel]*255))) }
                } }
            }
            guard let provider=CGDataProvider(data:Data(pixels) as CFData) else { return nil }
            return CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
        }
        var images: [TutorialStep:CGImage]=[:]
        for step in TutorialStep.allCases { guard let image=raster(colors[step]!) else { return nil }; images[step]=image }
        var cumulative: [TutorialStep:CGImage]=[:]
        var previous=Array(repeating:SIMD4<Float>.zero,count:uv.count)
        for step in TutorialStep.allCases {
            if step != .eyeliner {
                for i in previous.indices { let source=colors[step]![i]; previous[i]=source+previous[i]*(1-source.w) }
            }
            guard let image=raster(previous) else { return nil }; cumulative[step]=image
        }
        guard let full=raster(combined) else { return nil }
        return BakedMakeupProfile(surface:surface,textures:images,fullLook:full,cumulative:cumulative,restVertices:vertices,triangles:triangles,
            defaultEyeliner:EyelinerRegion.make(vertices:vertices,triangles:triangles,rims:surface.eyeRims,style:EyelinerStyle()))
    }
    // -Nimah: Palet bersama untuk renderer vertex dan utilitas atlas historis.
    static func tone(_ step: TutorialStep, _ id: String) -> SIMD4<Float> {
        switch step {
        case .blush:
            if id == "douyin" { return SIMD4(0.85,0.24,0.42,0.37) }
            if id == "clean-girl" { return SIMD4(0.90,0.47,0.35,0.28) }
            return SIMD4(0.82,0.38,0.26,0.48)
        case .contour: return SIMD4(0.32,0.18,0.11,0.32)
        case .eyeshadow: return SIMD4(0.38,0.23,0.18,0.58)
        case .eyeliner: return SIMD4(0.06,0.035,0.025,0.85)
        case .lips: return SIMD4(0.57,0.27,0.32,0.85)
        }
    }
}
