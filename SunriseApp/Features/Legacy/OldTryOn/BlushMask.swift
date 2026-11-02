// -Nimah: BlushMask.swift — implementasi MVP SunriseApp.
import Foundation

// -Nimah: Legacy mask untuk regresi awal. Live try-on sekarang menggunakan FaceSurfaceProfile.
enum BlushMask {
    static func weight(x: Float, y: Float, z: Float) -> Float {
        guard z > 0.015 else { return 0 }
        let dx = (abs(x) - 0.043) / 0.025
        let dy = (y + 0.026) / 0.018
        return max(0, 1 - dx * dx - dy * dy) * 0.60
    }
}

// -Nimah: Template untuk sketsa edukasi saja; live renderer memakai FaceSurfaceProfile aktual.
enum PlacementDots {
    static func targets(for step: TutorialStep) -> [SIMD3<Float>] {
        func paired(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
            points.flatMap { [SIMD3(-$0.x, $0.y, $0.z), $0] }
        }
        switch step {
        case .blush:
            return paired([.init(0.032,-0.023,0.044),.init(0.043,-0.015,0.036),.init(0.055,-0.007,0.025)])
        case .contour:
            return paired([.init(0.035,-0.047,0.035),.init(0.047,-0.037,0.026),.init(0.059,-0.027,0.016),
                           .init(0.010,0.002,0.060),.init(0.010,-0.014,0.068)])
        case .eyeshadow:
            return paired([.init(0.020,0.038,0.040),.init(0.031,0.041,0.036),.init(0.043,0.037,0.030)])
        case .eyeliner:
            return paired([.init(0.025,0.025,0.044),.init(0.037,0.025,0.038),.init(0.047,0.028,0.030),.init(0.055,0.033,0.024)])
        case .lips:
            return paired([.init(0.008,-0.048,0.060),.init(0.018,-0.053,0.057),.init(0.024,-0.060,0.052),.init(0.012,-0.067,0.053)])
        }
    }
    // -Nimah: Tidak mengasumsikan indeks ARKit tertentu; titik yang sama tidak diduplikasi.
    static func vertexIndices(vertices: [SIMD3<Float>], step: TutorialStep) -> [Int] {
        guard !vertices.isEmpty else { return [] }
        var used = Set<Int>()
        return targets(for: step).compactMap { target in
            let index = vertices.indices.min { a, b in
                let da = vertices[a] - target, db = vertices[b] - target
                return da.x*da.x + da.y*da.y + da.z*da.z < db.x*db.x + db.y*db.y + db.z*db.z
            }!
            return used.insert(index).inserted ? index : nil
        }
    }
}
