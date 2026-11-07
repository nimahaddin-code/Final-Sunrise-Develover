// A 3D brow made of individual hair ribbons (from `Resources/brow-hair-3d.obj`, see Tools/BrowOverlay/extract_hair_obj.py) and the
// maths that lays it on a face: the brow's head and tail, found by tracking and lifted onto ARKit's face mesh, fix its length,
// and the mesh normal and the direction of the forehead fix how it stands on the skin.
import Foundation
import simd

struct BrowHairMesh: Sendable {
    struct Ribbon: Sendable {
        /// The ribbon's two ends (the midpoints of its short edges) in model metres, its width, and how light it is
        /// against the shade (1 = the shade itself).
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var width: Float
        var tone: Float
    }

    let ribbons: [Ribbon]
    /// The brow's head and tail in model coordinates, and the plane the hairs grow from (the base surface, front is -Y).
    let head: SIMD3<Float>
    let tail: SIMD3<Float>
    let surfaceY: Float

    static let tones: [String: Float] = ["hair_dark": 0.7, "hair_mid": 1.15, "hair_light": 1.7]
    /// The OBJ's base surface sits here; a hair's depth is measured from it.
    static let baseY: Float = -0.0018

    /// Parses the hair faces of an OBJ (quads; other faces are skipped).
    static func parse(_ obj: String) -> BrowHairMesh? {
        var points: [SIMD3<Float>] = [], tone: Float = 1
        var ribbons: [Ribbon] = []
        for line in obj.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard let kind = parts.first else { continue }
            switch kind {
            case "v" where parts.count >= 4:
                guard let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) else { return nil }
                points.append(SIMD3(x, y, z))
            case "usemtl" where parts.count >= 2:
                tone = tones[String(parts[1])] ?? 1
            case "f" where parts.count == 5:
                let q = parts[1...4].compactMap { Int($0.split(separator: "/")[0]).map { $0 - 1 } }
                guard q.count == 4, q.allSatisfy({ points.indices.contains($0) }) else { return nil }
                let v = q.map { points[$0] }
                let e = (0..<4).map { simd_distance(v[$0], v[($0 + 1) % 4]) }
                // The two short edges are the ribbon's ends: edges k and k + 2.
                let k = e[0] + e[2] < e[1] + e[3] ? 0 : 1
                let a = (v[k] + v[(k + 1) % 4]) / 2, b = (v[(k + 2) % 4] + v[(k + 3) % 4]) / 2
                let width = (e[k] + e[(k + 2) % 4]) / 2
                guard simd_distance(a, b) > 1e-6, width > 0 else { continue }
                ribbons.append(Ribbon(a: a, b: b, width: width, tone: tone))
            default: break
            }
        }
        guard ribbons.count >= 100 else { return nil }
        // Head and tail: the ends of the brow by position along X, ignoring a few stray hairs, at the height the hairs sit there.
        let xs = ribbons.flatMap { [$0.a.x, $0.b.x] }.sorted()
        let x0 = xs[Int(Float(xs.count) * 0.005)], x1 = xs[min(xs.count - 1, Int(Float(xs.count) * 0.995))]
        let span = x1 - x0
        func centre(_ range: ClosedRange<Float>) -> SIMD3<Float> {
            let ends = ribbons.flatMap { [$0.a, $0.b] }.filter { range.contains($0.x) }
            guard !ends.isEmpty else { return SIMD3(range.lowerBound, baseY, 0) }
            let mean = ends.reduce(SIMD3<Float>.zero, +) / Float(ends.count)
            return SIMD3(range.lowerBound == x0 ? x0 : x1, baseY, mean.z)
        }
        return BrowHairMesh(ribbons: ribbons, head: centre(x0...(x0 + span * 0.04)), tail: centre((x1 - span * 0.04)...x1), surfaceY: baseY)
    }

    static func load(bundle: Bundle = .main) -> BrowHairMesh? {
        guard let url = bundle.url(forResource: "brow-hair-3d", withExtension: "obj"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// GPU vertices: six per ribbon (two triangles), each carrying both ends so the vertex shader can widen it on screen.
    struct Vertex { var a: SIMD4<Float>; var b: SIMD4<Float>; var extra: SIMD4<Float> }
    var vertices: [Vertex] {
        var out: [Vertex] = []
        out.reserveCapacity(ribbons.count * 6)
        // (end, side): A-, A+, B-, then A+, B+, B-.
        let corners: [(Float, Float)] = [(0, -1), (0, 1), (1, -1), (0, 1), (1, 1), (1, -1)]
        for r in ribbons {
            for (end, side) in corners {
                out.append(Vertex(a: SIMD4(r.a, r.width), b: SIMD4(r.b, r.tone), extra: SIMD4(end, side, 0, 0)))
            }
        }
        return out
    }
}

/// Where the brow mesh goes on a face.
enum BrowHairPlacement {
    /// The picture-based overlays run a little past the tracked head and tail (see `BrowSpriteBaker`); the mesh does too.
    static let headU: Float = BrowSpriteBaker.headU, tailU: Float = BrowSpriteBaker.tailU
    /// Hairs grow this far above the mesh surface, so ARKit's coarse mesh does not cut them off (metres).
    static let lift: Float = 0.0022

    struct Frame {
        /// Model to face-local.
        var matrix: simd_float4x4
        /// Face-local metres per model metre.
        var scale: Float
    }

    /// `head` and `tail` are the tracked brow's ends on the face, `normal` the mesh normal there (outwards) and `forehead` a
    /// direction from the brow towards the forehead; all face-local. A brow on the other side of the face gives the mirror image.
    static func frame(mesh: BrowHairMesh, head: SIMD3<Float>, tail: SIMD3<Float>, normal: SIMD3<Float>, forehead: SIMD3<Float>) -> Frame? {
        let chord = tail - head, length = simd_length(chord)
        guard length > 1e-4, simd_length(normal) > 1e-6, simd_length(forehead) > 1e-6 else { return nil }
        let x = chord / length
        var up = simd_cross(simd_normalize(normal), x)
        guard simd_length(up) > 1e-6 else { return nil }
        up = simd_normalize(up)
        if simd_dot(up, forehead) < 0 { up = -up }
        var out = simd_normalize(simd_cross(x, up))
        if simd_dot(out, normal) < 0 { out = -out }

        // The model's own chord, in its X-Z plane: along it, up from it, and outwards (towards -Y).
        let modelChord = mesh.tail - mesh.head, modelLength = simd_length(modelChord)
        guard modelLength > 1e-6 else { return nil }
        let along = SIMD3(modelChord.x, 0, modelChord.z) / modelLength, modelUp = SIMD3<Float>(-along.z, 0, along.x)
        let scale = length * (tailU - headU) / modelLength
        // model point m -> origin + scale * (a x + b up + c out) with a, b, c measured from the model's head on its surface plane.
        let origin = head + chord * headU + out * lift
        let from = SIMD3(mesh.head.x, mesh.surfaceY, mesh.head.z)
        // Rows of the 3x3 that turns (m - from) into (a, b, c).
        let rows = simd_float3x3(rows: [along, modelUp, SIMD3(0, -1, 0)])
        let basis = simd_float3x3(columns: (x * scale, up * scale, out * scale))
        let linear = basis * rows
        var matrix = matrix_identity_float4x4
        matrix.columns.0 = SIMD4(linear.columns.0, 0)
        matrix.columns.1 = SIMD4(linear.columns.1, 0)
        matrix.columns.2 = SIMD4(linear.columns.2, 0)
        matrix.columns.3 = SIMD4(origin - linear * from, 1)
        return Frame(matrix: matrix, scale: scale)
    }
}

/// Loads the brow mesh once, off the render queue.
final class BrowHairStore: @unchecked Sendable {
    static let shared = BrowHairStore()
    private let lock = NSLock()
    private var loaded: BrowHairMesh?, working = false, failed = false

    var mesh: BrowHairMesh? { lock.lock(); defer { lock.unlock() }; return loaded }
    var hasFailed: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    func prepare() {
        lock.lock()
        guard loaded == nil, !working, !failed else { lock.unlock(); return }
        working = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let mesh = BrowHairMesh.load()
            lock.lock()
            working = false
            if let mesh { loaded = mesh } else { failed = true }
            lock.unlock()
        }
    }
}
