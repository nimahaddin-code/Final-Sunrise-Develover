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

    /// This map with both eyes moved toward `live`'s by `weight` (0...1). `nil` if the eye point counts differ.
    /// Used to follow the eyes frame by frame while the brows and nose keep their averaged positions.
    func replacingEyes(blending live: FaceFeatureMap, weight: Float) -> FaceFeatureMap? {
        guard left.eye.count == live.left.eye.count, right.eye.count == live.right.eye.count else { return nil }
        func blend(_ old: [SIMD2<Float>], _ new: [SIMD2<Float>]) -> [SIMD2<Float>] {
            zip(old, new).map { $0 + ($1 - $0) * weight }
        }
        var result = self
        result.left.eye = blend(left.eye, live.left.eye)
        result.right.eye = blend(right.eye, live.right.eye)
        return result
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

    /// Texture coordinate under `point`. Points outside every triangle, such as inside the eye openings (the mesh
    /// has a hole there, but the rendered face mesh fills it), come from a local fit through the nearest mesh points
    /// instead of one stretched triangle. `nil` only for an empty mesh.
    func textureCoordinate(at point: SIMD2<Float>) -> SIMD2<Float>? {
        var inside: (uv: SIMD2<Float>, depth: Float)?
        var index = 0
        while index + 2 < triangleIndices.count {
            let a = Int(triangleIndices[index]), b = Int(triangleIndices[index + 1]), c = Int(triangleIndices[index + 2])
            index += 3
            guard let weights = Self.barycentric(point, points[a], points[b], points[c]) else { continue }
            guard -min(weights.x, weights.y, weights.z) <= 1e-4 else { continue }
            let uv = weights.x * textureCoordinates[a] + weights.y * textureCoordinates[b]
                + weights.z * textureCoordinates[c]
            let depth = weights.x * depths[a] + weights.y * depths[b] + weights.z * depths[c]
            if depth < inside?.depth ?? .infinity { inside = (uv, depth) }
        }
        return inside?.uv ?? localFit(at: point)
    }

    /// Number of nearest mesh points the local fit uses; enough to surround an eye opening.
    private static let fitPointCount = 16

    /// Texture coordinate at `point` from a distance-weighted affine fit (image to texture) through the nearest
    /// mesh points. Around an eye opening those points surround `point`, so this interpolates the texture
    /// across the hole the way the filled face mesh does.
    private func localFit(at point: SIMD2<Float>) -> SIMD2<Float>? {
        guard !points.isEmpty else { return nil }
        let nearest = points.indices.sorted { simd_distance_squared(points[$0], point) < simd_distance_squared(points[$1], point) }
            .prefix(Self.fitPointCount)
        guard nearest.count >= 3 else { return textureCoordinates[nearest[nearest.startIndex]] }
        // Weighted least squares on coordinates relative to `point`, so the fit's constant term is the answer.
        // Softened by the ring's size so the nearest points do not dominate when `point` is close to one of them.
        let softening = Double(simd_length_squared(points[nearest[nearest.index(before: nearest.endIndex)]] - point)) * 0.25
        var normal = simd_double3x3(0), rightU = SIMD3<Double>(0), rightV = SIMD3<Double>(0)
        for vertex in nearest {
            let d = points[vertex] - point
            let weight = 1 / (Double(simd_length_squared(d)) + softening + 1e-9)
            let row = SIMD3<Double>(1, Double(d.x), Double(d.y))
            normal += simd_double3x3(rows: [row * row.x, row * row.y, row * row.z]) * weight
            rightU += row * (Double(textureCoordinates[vertex].x) * weight)
            rightV += row * (Double(textureCoordinates[vertex].y) * weight)
        }
        guard abs(normal.determinant) > 1e-12 else { return textureCoordinates[nearest[nearest.startIndex]] }
        let inverse = normal.inverse
        return SIMD2(Float((inverse * rightU).x), Float((inverse * rightV).x))
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
