// -Nimah: Fit masks ke topology wajah aktual, bukan template posisi berukuran tetap.
import Foundation
import simd

enum MakeupPreviewMode: String, CaseIterable, Identifiable {
    case pointsAndLook, lookOnly, pointsOnly, original
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pointsAndLook: return "Points + makeup"
        case .lookOnly: return "Makeup only"
        case .pointsOnly: return "Points only"
        case .original: return "Original camera"
        }
    }
    var showsMakeup: Bool { self == .pointsAndLook || self == .lookOnly }
    var showsPoints: Bool { self == .pointsAndLook || self == .pointsOnly }
}
struct FaceSurfaceProfile: Sendable {
    let weights: [TutorialStep: [Float]]
    let guides: [TutorialStep: [Int]]
    let fittedEyes: Bool
    let fittedLips: Bool
    let vertexCount: Int
    // -Nimah: Rim tervalidasi menjadi input attachment eyeliner, bukan indeks template.
    var eyeRims: [[Int]] = []
    var status: String {
        if fittedEyes && fittedLips { return "Surface estimated · makeup alignment needs device validation" }
        return "Partial fit · eye or lip effects hidden when landmarks are unavailable"
    }
    private struct Edge: Hashable { let a: Int; let b: Int; init(_ a: Int, _ b: Int) { self.a = min(a,b); self.b = max(a,b) } }
    static func make(vertices v: [SIMD3<Float>], triangles: [Int16], eyeCenters: [SIMD3<Float>]) -> FaceSurfaceProfile? {
        guard v.count >= 12, eyeCenters.count == 2, triangles.count % 3 == 0,
              v.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
        let width = (v.map(\.x).max()! - v.map(\.x).min()!) / 2
        guard width > 0.02, width < 0.16 else { return nil }
        var counts: [Edge: Int] = [:], neighbors = Array(repeating: Set<Int>(), count: v.count)
        for t in stride(from: 0, to: triangles.count, by: 3) {
            let a = Int(triangles[t]), b = Int(triangles[t+1]), c = Int(triangles[t+2])
            guard v.indices.contains(a), v.indices.contains(b), v.indices.contains(c) else { return nil }
            for e in [Edge(a,b), Edge(b,c), Edge(c,a)] { counts[e, default: 0] += 1; neighbors[e.a].insert(e.b); neighbors[e.b].insert(e.a) }
        }
        var boundary: [Int: Set<Int>] = [:]
        for (edge, count) in counts where count == 1 { boundary[edge.a, default: []].insert(edge.b); boundary[edge.b, default: []].insert(edge.a) }
        var visited = Set<Int>(), loops: [[Int]] = []
        for start in boundary.keys.sorted() where !visited.contains(start) {
            var todo = [start], component: [Int] = []
            while let i = todo.popLast() {
                guard visited.insert(i).inserted else { continue }
                component.append(i); todo.append(contentsOf: boundary[i] ?? [])
            }
            if component.count >= 5 { loops.append(component.sorted()) }
        }
        func center(_ ids: [Int]) -> SIMD3<Float> { ids.reduce(SIMD3<Float>.zero) { $0 + v[$1] } / Float(max(ids.count,1)) }
        // -Nimah: Buang boundary luar; dua hole dekat eye transforms menjadi rim mata.
        let outer = loops.indices.max { loops[$0].count < loops[$1].count }
        let holes = loops.indices.filter { $0 != outer }
        var used = Set<Int>(), eyes: [[Int]] = []
        for eye in eyeCenters.sorted(by: { $0.x < $1.x }) {
            let candidate = holes.filter { !used.contains($0) }.min {
                simd_length(SIMD2(center(loops[$0]).x-eye.x,center(loops[$0]).y-eye.y)) < simd_length(SIMD2(center(loops[$1]).x-eye.x,center(loops[$1]).y-eye.y))
            }
            if let candidate {
                let c = center(loops[candidate])
                if simd_length(SIMD2(c.x-eye.x,c.y-eye.y)) < width * 0.34 { used.insert(candidate); eyes.append(loops[candidate]) }
            }
        }
        let eyeY = eyeCenters.map(\.y).reduce(0,+) / 2
        let mouth = holes.filter { !used.contains($0) && center(loops[$0]).y < eyeY-width*0.25 && abs(center(loops[$0]).x) < width*0.25 }
            .min { center(loops[$0]).y < center(loops[$1]).y }.map { loops[$0] } ?? []
        let mouthWidth = mouth.isEmpty ? 0 : mouth.map { v[$0].x }.max()! - mouth.map { v[$0].x }.min()!
        let lipFit = mouth.count >= 5 && mouthWidth > width * 0.20 && mouthWidth < width * 1.1
        let eyeFit = eyes.count == 2 && eyes.allSatisfy { rim in
            let w = rim.map { v[$0].x }.max()! - rim.map { v[$0].x }.min()!
            return w > width * 0.12 && w < width * 0.9
        }
        let mouthY = lipFit ? center(mouth).y : eyeY-width*1.15
        let eyeMouth = max(eyeY-mouthY,width*0.65)
        var layers = Dictionary(uniqueKeysWithValues: TutorialStep.allCases.map { ($0, Array(repeating: Float(0), count: v.count)) })
        func fade(_ distance: Float, _ inner: Float, _ outer: Float) -> Float {
            let t = max(0,min(1,(distance-inner)/max(outer-inner,0.00001)))
            return 1-t*t*(3-2*t)
        }
        func ellipse(_ p: SIMD3<Float>, x: Float, y: Float, rx: Float, ry: Float, slope: Float = 0) -> Float {
            let dx=(p.x-x)/rx, dy=(p.y-y-slope*(abs(p.x)-abs(x)))/ry
            return fade(dx*dx+dy*dy,0.08,1)
        }
        for i in v.indices {
            let p=v[i], front = p.z > 0 ? Float(1) : 0
            layers[.blush]![i] = max(ellipse(p,x:-width*0.57,y:eyeY-eyeMouth*0.54,rx:width*0.34,ry:eyeMouth*0.25,slope:0.38), ellipse(p,x:width*0.57,y:eyeY-eyeMouth*0.54,rx:width*0.34,ry:eyeMouth*0.25,slope:0.38)) * front
            let cheek = max(ellipse(p,x:-width*0.65,y:eyeY-eyeMouth*0.82,rx:width*0.32,ry:eyeMouth*0.15,slope:0.45),ellipse(p,x:width*0.65,y:eyeY-eyeMouth*0.82,rx:width*0.32,ry:eyeMouth*0.15,slope:0.45))
            let nose = max(ellipse(p,x:-width*0.11,y:eyeY-eyeMouth*0.40,rx:width*0.045,ry:eyeMouth*0.26),ellipse(p,x:width*0.11,y:eyeY-eyeMouth*0.40,rx:width*0.045,ry:eyeMouth*0.26))
            layers[.contour]![i] = max(cheek,nose*0.55)*front
        }
        // -Nimah: Mask eyeliner atlas sengaja kosong; hanya EyelinerRegion yang menentukan jalurnya.
        if eyeFit {
            for rim in eyes {
                let c=center(rim), minX=rim.map { v[$0].x }.min()!, maxX=rim.map { v[$0].x }.max()!
                let w=maxX-minX, top=rim.map { v[$0].y }.max()!
                for i in v.indices where v[i].z > 0 {
                    let p=v[i]
                    if p.y >= c.y - width * 0.0001 { layers[.eyeshadow]![i] = max(layers[.eyeshadow]![i],ellipse(p,x:c.x,y:top+w*0.11,rx:w*0.66,ry:w*0.30)) }

                }
            }
        }
        if lipFit {
            // -Nimah: Geodesic distance dari inner lip rim membatasi warna ke tetangga permukaan bibir.
            let radius=mouthWidth*0.19
            var distance=Array(repeating:Float.infinity,count:v.count), todo=mouth, cursor=0
            for i in mouth { distance[i]=0 }
            while cursor < todo.count {
                let i=todo[cursor]; cursor += 1
                for j in neighbors[i] {
                    let d=distance[i]+simd_distance(v[i],v[j])
                    if d < distance[j] && d < radius { distance[j]=d; todo.append(j) }
                }
            }
            for i in v.indices { layers[.lips]![i] = fade(distance[i],radius*0.48,radius) }
        }
        let renderedIndices = Set(triangles.map(Int.init))
        var guides: [TutorialStep:[Int]] = [:]
        for step in TutorialStep.allCases {
            let weights=layers[step]!
            var candidates=v.indices.filter { renderedIndices.contains($0) && weights[$0] > 0.20 }
                .sorted { weights[$0] == weights[$1] ? $0 < $1 : weights[$0] > weights[$1] }
            var chosen: [Int]=[]
            let spacing: Float = step == .lips || step == .eyeliner ? width*0.10 : width*0.15
            while !candidates.isEmpty && chosen.count < 10 {
                let index=candidates.removeFirst()
                if chosen.allSatisfy({ simd_distance(v[$0],v[index]) >= spacing }) { chosen.append(index) }
            }
            guides[step]=chosen
        }
        var profile=FaceSurfaceProfile(weights:layers,guides:guides,fittedEyes:eyeFit,fittedLips:lipFit,vertexCount:v.count)
        profile.eyeRims = eyeFit ? eyes : []
        return profile
    }
}
