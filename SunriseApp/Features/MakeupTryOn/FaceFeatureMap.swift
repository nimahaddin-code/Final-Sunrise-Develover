import simd

/// Brows and eyes located on the face mesh's texture map (UV, 0...1, v grows downward).
///
/// Because makeup is drawn into this texture, it sticks to the tracked face mesh and follows every movement.
struct FaceFeatureMap: Equatable, Sendable {
    struct Side: Equatable, Sendable {
        var brow: [SIMD2<Float>]
        var eye: [SIMD2<Float>]

        var eyeCenter: SIMD2<Float> { eye.reduce(.zero, +) / Float(max(eye.count, 1)) }
        var browCenter: SIMD2<Float> { brow.reduce(.zero, +) / Float(max(brow.count, 1)) }
    }

    var left: Side
    var right: Side
    /// Nose outline; empty when it was not found. Used for the brow, liner and blush guide lines.
    var nose: [SIMD2<Float>] = []

    var sides: [Side] { [left, right] }
    var midpoint: SIMD2<Float> { (left.eyeCenter + right.eyeCenter) / 2 }
    var eyeDistance: Float { simd_distance(left.eyeCenter, right.eyeCenter) }

    var isPlausible: Bool {
        sides.allSatisfy { $0.brow.count >= 2 && $0.eye.count >= 3 } && eyeDistance > 0.01
    }

    /// Point-wise mean of several maps; `nil` if they are empty or have different point counts.
    static func average(_ maps: [FaceFeatureMap]) -> FaceFeatureMap? {
        guard let first = maps.first else { return nil }
        func mean(_ points: KeyPath<FaceFeatureMap, [SIMD2<Float>]>) -> [SIMD2<Float>]? {
            let count = first[keyPath: points].count
            guard maps.allSatisfy({ $0[keyPath: points].count == count }) else { return nil }
            return (0..<count).map { index in
                maps.reduce(SIMD2<Float>.zero) { $0 + $1[keyPath: points][index] } / Float(maps.count)
            }
        }
        guard let leftBrow = mean(\.left.brow), let leftEye = mean(\.left.eye),
              let rightBrow = mean(\.right.brow), let rightEye = mean(\.right.eye) else { return nil }
        // The nose is optional, so a mismatch only drops it.
        return FaceFeatureMap(left: Side(brow: leftBrow, eye: leftEye), right: Side(brow: rightBrow, eye: rightEye),
                              nose: mean(\.nose) ?? [])
    }
}

/// The face mesh as seen in one camera image, used to look up which texture point lies under an image point.
struct ProjectedFaceMesh: Sendable {
    /// Per-vertex position in the image.
    let points: [SIMD2<Float>]
    /// Per-vertex distance from the camera; picks the visible surface where the mesh overlaps itself.
    let depths: [Float]
    let textureCoordinates: [SIMD2<Float>]
    /// Three vertex indices per triangle.
    let triangleIndices: [Int16]

    /// Texture coordinate under `point`. Points just outside the mesh, such as inside the eye openings,
    /// are extrapolated from the nearest triangle. `nil` only for an empty mesh.
    func textureCoordinate(at point: SIMD2<Float>) -> SIMD2<Float>? {
        var inside: (uv: SIMD2<Float>, depth: Float)?
        var nearest: (uv: SIMD2<Float>, outside: Float)?
        var index = 0
        while index + 2 < triangleIndices.count {
            let a = Int(triangleIndices[index]), b = Int(triangleIndices[index + 1]), c = Int(triangleIndices[index + 2])
            index += 3
            guard let weights = Self.barycentric(point, points[a], points[b], points[c]) else { continue }
            let uv = weights.x * textureCoordinates[a] + weights.y * textureCoordinates[b]
                + weights.z * textureCoordinates[c]
            let outside = -min(weights.x, weights.y, weights.z)
            if outside <= 1e-4 {
                let depth = weights.x * depths[a] + weights.y * depths[b] + weights.z * depths[c]
                if depth < inside?.depth ?? .infinity { inside = (uv, depth) }
            } else if outside < nearest?.outside ?? .infinity {
                nearest = (uv, outside)
            }
        }
        return inside?.uv ?? nearest?.uv
    }

    /// Barycentric weights of `p` in triangle (a, b, c); `nil` for a degenerate triangle.
    static func barycentric(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>,
                            _ c: SIMD2<Float>) -> SIMD3<Float>? {
        let ab = b - a, ac = c - a, ap = p - a
        let denominator = ab.x * ac.y - ab.y * ac.x
        guard abs(denominator) > 1e-6 else { return nil }
        let v = (ap.x * ac.y - ap.y * ac.x) / denominator
        let w = (ab.x * ap.y - ab.y * ap.x) / denominator
        return SIMD3(1 - v - w, v, w)
    }
}
