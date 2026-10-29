// ARKit-pose brow stabilizer. MediaPipe finds the brow in the image, but its 2D points wobble from frame to frame while ARKit's
// face pose is steady. Each landmark is lifted onto ARKit's face mesh (face-local metres), smoothed there, where the head's own
// motion no longer counts, and projected back with the same frame's camera. A still face gives a still brow, and a turning head
// adds neither jitter nor lag. Pure maths on value types (no ARKit import), so the Simulator tests can check it.
import Foundation
import simd

/// One camera frame with the face ARKit tracked in it: enough to move between image pixels and face-local metres.
struct BrowFaceFrame: Sendable {
    let anchorID: UUID
    /// Face-local mesh of this frame (ARKit's 1220 vertices) and its triangles, three indices each.
    let vertices: [SIMD3<Float>]
    let triangles: [UInt16]
    /// Camera intrinsics at `imageSize` (captured-image pixels, origin top left).
    let intrinsics: simd_float3x3
    let imageSize: SIMD2<Float>
    /// Face-local to camera coordinates (x right, y up, the camera looks down -z), and its inverse.
    let cameraFromFace: simd_float4x4
    let faceFromCamera: simd_float4x4
    /// Face-local to world, for drawing 3D geometry placed in face-local coordinates.
    let faceToWorld: simd_float4x4

    init(anchorID: UUID, vertices: [SIMD3<Float>], triangles: [UInt16], intrinsics: simd_float3x3, imageSize: SIMD2<Float>,
         faceToWorld: simd_float4x4, cameraToWorld: simd_float4x4) {
        self.anchorID = anchorID
        self.vertices = vertices
        self.triangles = triangles
        self.intrinsics = intrinsics
        self.imageSize = imageSize
        self.faceToWorld = faceToWorld
        faceFromCamera = simd_inverse(faceToWorld) * cameraToWorld
        cameraFromFace = simd_inverse(faceFromCamera)
    }

    /// The camera ray through `pixel`, in face-local coordinates.
    func ray(through pixel: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let fx = intrinsics.columns.0.x, fy = intrinsics.columns.1.y, cx = intrinsics.columns.2.x, cy = intrinsics.columns.2.y
        let inCamera = SIMD4<Float>((pixel.x - cx) / fx, -(pixel.y - cy) / fy, -1, 0)
        let d = faceFromCamera * inCamera, o = faceFromCamera.columns.3
        return (SIMD3(o.x, o.y, o.z), simd_normalize(SIMD3(d.x, d.y, d.z)))
    }

    /// Where each mesh vertex lands in the image (NaN behind the camera). Passed to `faceLocal(at:projected:)` when many
    /// pixels are lifted from one frame, so each one skips the triangles it cannot be inside.
    func projectedVertices() -> [SIMD2<Float>] {
        vertices.map { pixel(of: $0) ?? SIMD2(.nan, .nan) }
    }

    /// The point of the face mesh seen at `pixel`. A ray that misses the mesh (a brow tail past the face's edge) takes the plane
    /// of the nearest triangle, so every landmark gets a place on the face. `projected` (from `projectedVertices()`) only
    /// makes it faster: a ray can only hit a triangle whose image contains the pixel.
    func faceLocal(at pixel: SIMD2<Float>, projected: [SIMD2<Float>]? = nil) -> SIMD3<Float>? {
        guard pixel.x.isFinite, pixel.y.isFinite, triangles.count >= 3 else { return nil }
        let (origin, direction) = ray(through: pixel)
        let projected = projected?.count == vertices.count ? projected : nil
        var bestT = Float.infinity
        for t in 0..<triangles.count / 3 {
            let ia = Int(triangles[t * 3]), ib = Int(triangles[t * 3 + 1]), ic = Int(triangles[t * 3 + 2])
            if let projected {
                let pa = projected[ia], pb = projected[ib], pc = projected[ic]
                // One pixel of margin; a vertex behind the camera (NaN) keeps the triangle in.
                if pa.x.isFinite, pb.x.isFinite, pc.x.isFinite,
                   pixel.x < min(pa.x, pb.x, pc.x) - 1 || pixel.x > max(pa.x, pb.x, pc.x) + 1
                    || pixel.y < min(pa.y, pb.y, pc.y) - 1 || pixel.y > max(pa.y, pb.y, pc.y) + 1 { continue }
            }
            let a = vertices[ia], b = vertices[ib], c = vertices[ic]
            // Moller-Trumbore, two-sided.
            let e1 = b - a, e2 = c - a, p = simd_cross(direction, e2), det = simd_dot(e1, p)
            guard abs(det) > 1e-12 else { continue }
            let inv = 1 / det, s = origin - a
            let u = simd_dot(s, p) * inv
            let q = simd_cross(s, e1), v = simd_dot(direction, q) * inv
            if u >= 0, v >= 0, u + v <= 1 {
                let hit = simd_dot(e2, q) * inv
                if hit > 0, hit < bestT { bestT = hit }
            }
        }
        if bestT.isFinite { return origin + direction * bestT }
        // No hit: every triangle missed, so the nearest is searched among all of them.
        var nearest: (distance: Float, triangle: Int)?
        for t in 0..<triangles.count / 3 {
            let a = vertices[Int(triangles[t * 3])], b = vertices[Int(triangles[t * 3 + 1])], c = vertices[Int(triangles[t * 3 + 2])]
            let centre = (a + b + c) / 3, toCentre = centre - origin
            let distance = simd_length(toCentre - direction * simd_dot(toCentre, direction))
            if nearest == nil || distance < nearest!.distance { nearest = (distance, t) }
        }
        guard let nearest else { return nil }
        let t = nearest.triangle
        let a = vertices[Int(triangles[t * 3])], b = vertices[Int(triangles[t * 3 + 1])], c = vertices[Int(triangles[t * 3 + 2])]
        let normal = simd_cross(b - a, c - a), denominator = simd_dot(normal, direction)
        guard abs(denominator) > 1e-9 else { return nil }
        let hit = simd_dot(normal, a - origin) / denominator
        return hit > 0 ? origin + direction * hit : nil
    }

    /// Where a face-local point lands in the image.
    func pixel(of point: SIMD3<Float>) -> SIMD2<Float>? {
        let c = cameraFromFace * SIMD4(point, 1)
        guard c.z < -1e-4 else { return nil }
        let fx = intrinsics.columns.0.x, fy = intrinsics.columns.1.y, cx = intrinsics.columns.2.x, cy = intrinsics.columns.2.y
        let p = SIMD2(cx + fx * c.x / -c.z, cy - fy * c.y / -c.z)
        return p.x.isFinite && p.y.isFinite ? p : nil
    }

    /// The mesh's outward normal at a face-local point (the nearest triangle's), pointing towards the camera.
    func normal(near point: SIMD3<Float>) -> SIMD3<Float> {
        var best: (distance: Float, normal: SIMD3<Float>)?
        for t in 0..<triangles.count / 3 {
            let a = vertices[Int(triangles[t * 3])], b = vertices[Int(triangles[t * 3 + 1])], c = vertices[Int(triangles[t * 3 + 2])]
            let distance = simd_distance((a + b + c) / 3, point)
            if best == nil || distance < best!.distance {
                var n = simd_cross(b - a, c - a)
                let length = simd_length(n)
                n = length > 1e-12 ? n / length : SIMD3(0, 0, 1)
                best = (distance, n)
            }
        }
        var n = best?.normal ?? SIMD3(0, 0, 1)
        // Towards the camera, in face-local coordinates.
        let toCamera = SIMD3(faceFromCamera.columns.3.x, faceFromCamera.columns.3.y, faceFromCamera.columns.3.z) - point
        if simd_dot(n, toCamera) < 0 { n = -n }
        return n
    }
}

/// Smooths every brow landmark in face-local metres. See the file comment.
struct BrowFaceStabilizer {
    /// Metres. A landmark's own motion on the face (a raised brow) is a few millimetres in a fifth of a second, so a low cutoff
    /// that opens with speed keeps real expressions and calms pixel noise (about 0.2 mm at arm's length).
    static let config = OneEuroConfig(minCutoff: 1.5, beta: 60, dCutoff: 1, deadband: 0)
    /// Output holds still until the smoothed point has moved this far (metres).
    static let hold: Float = 0.00012
    static let resetGap: TimeInterval = 0.25
    /// The most a steadied point may sit from where it was seen, in eye spans, before ARKit's pose is not trusted for this face.
    static let disagreement: Float = 0.15

    private var filters: [[OneEuroFilter]] = []
    private var held: [SIMD3<Float>] = []
    private var anchorID: UUID?
    private var last: TimeInterval?

    mutating func reset() { filters = []; held = []; anchorID = nil; last = nil }

    /// `nil` when a landmark cannot be placed on the face; the caller then falls back to the image-space smoother.
    mutating func stabilize(_ observation: BrowObservation, face: BrowFaceFrame) -> BrowObservation? {
        let t = observation.timestamp
        guard t.isFinite else { return nil }
        if let last, t <= last { return nil }
        if anchorID != face.anchorID || (last.map { t - $0 > Self.resetGap } ?? false) { reset() }
        let points = observation.flattened
        var lifted: [SIMD3<Float>] = []
        lifted.reserveCapacity(points.count)
        let projected = face.projectedVertices()
        for p in points {
            guard let q = face.faceLocal(at: p, projected: projected) else { return nil }
            lifted.append(q)
        }
        if filters.count != points.count {
            filters = Array(repeating: Array(repeating: OneEuroFilter(), count: 3), count: points.count)
            held = []
        }
        anchorID = face.anchorID
        last = t
        var smoothed: [SIMD3<Float>] = []
        smoothed.reserveCapacity(points.count)
        for (i, q) in lifted.enumerated() {
            let s = SIMD3(Float(filters[i][0].filter(Double(q.x), t: t, config: Self.config)),
                          Float(filters[i][1].filter(Double(q.y), t: t, config: Self.config)),
                          Float(filters[i][2].filter(Double(q.z), t: t, config: Self.config)))
            smoothed.append(held.count == points.count && simd_distance(s, held[i]) < Self.hold ? held[i] : s)
        }
        let out = zip(smoothed, points).map { face.pixel(of: $0) ?? $1 }
        // ARKit's face and MediaPipe's landmarks come from the same frame, so they agree to a few pixels. If they do not (the pose is
        // off, or the two use different image frames), the image-space smoother is the safer way to steady the brow.
        let limit = (observation.eyeSpan ?? face.imageSize.x * 0.1) * Self.disagreement
        if zip(out, points).contains(where: { simd_distance($0, $1) > limit }) { reset(); return nil }
        held = smoothed
        return observation.replacing(out)
    }

    /// The last steadied brow (`steady`, as `stabilize` returned it) moved onto a later camera frame of the same face: its
    /// face-local points are projected with that frame's pose and camera. This is how the brow follows the head on every
    /// ARKit frame while MediaPipe answers less often. Nil when there is nothing to move or the face changed.
    func reproject(_ steady: BrowObservation, onto face: BrowFaceFrame) -> BrowObservation? {
        guard face.anchorID == anchorID, held.count == steady.flattened.count else { return nil }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(held.count)
        for p in held {
            guard let q = face.pixel(of: p) else { return nil }
            out.append(q)
        }
        return steady.replacing(out)
    }

    /// The smoothed landmarks lifted onto the face of this frame, for placing 3D geometry (nil when one cannot be placed).
    static func lift(_ observation: BrowObservation, face: BrowFaceFrame) -> [SIMD3<Float>]? {
        let points = observation.flattened
        let projected = face.projectedVertices()
        let lifted = points.compactMap { face.faceLocal(at: $0, projected: projected) }
        return lifted.count == points.count ? lifted : nil
    }
}
