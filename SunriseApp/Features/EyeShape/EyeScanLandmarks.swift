// -Nimah: Scan-specific name avoids Hanum's independent eyeliner landmark type/file.
import simd

/// The eye landmarks of one face as plain 2D points, so measuring never depends on MediaPipe or the camera.
///
/// Points can be in any image coordinates (pixels, y up or down, mirrored or rolled); `EyeMeasurer` works out
/// the face's own axes from the points. The two eyes can come in either order.
struct EyeScanLandmarks: Equatable, Sendable {
    struct Eye: Equatable, Sendable {
        /// Corner next to the nose.
        var innerCorner: SIMD2<Float>
        /// Corner toward the temple.
        var outerCorner: SIMD2<Float>
        /// Every point on the lid outline, upper and lower lid together.
        var lid: [SIMD2<Float>]
        /// Points on the iris rim; the farthest pair gives the iris diameter.
        var iris: [SIMD2<Float>]
        /// The lower edge of the eyebrow above this eye.
        var brow: [SIMD2<Float>]
    }

    var first: Eye
    var second: Eye
    /// How far the head is turned away from the camera: 0 when facing it, up to 1 when the nose is over a face edge
    /// (positive toward the person's left edge). `nil` when unknown. Turned heads squash one eye and distort tilt, so scans only use frames near 0.
    var headTurn: Float? = nil
    /// Up/down angle between where the face points and the camera, in radians: positive when the face points above the camera, which
    /// means the phone is held below eye level. `nil` when unknown. Seen from above or below, lids and tilt look different, so scans only
    /// use frames near 0. See `pitch(fromPoseMatrix:)`.
    var headPitch: Float? = nil
}

extension EyeScanLandmarks {
    /// The up/down angle from MediaPipe's facial transformation matrix: 4 x 4 values taking its canonical face (looking down +z) into
    /// camera space (the camera looks down -z with +y up). The face's forward direction there is the rotation's third column.
    ///
    /// The storage order (column- or row-major) is told from where the translation sits: the face is always in front of the camera,
    /// so its z translation is clearly non-zero. `nil` for a matrix that is not 4 x 4 or a face pointing away from the camera.
    static func pitch(fromPoseMatrix m: [Float]) -> Float? {
        guard m.count == 16 else { return nil }
        let columnMajor = abs(m[14]) >= abs(m[11])
        let forward = columnMajor ? SIMD3<Float>(m[8], m[9], m[10]) : SIMD3<Float>(m[2], m[6], m[10])
        let length = simd_length(forward)
        guard length > 0 else { return nil }
        let direction = forward / length
        guard direction.z > 0 else { return nil }
        return asin(direction.y)
    }
}

extension EyeScanLandmarks {
    /// MediaPipe Face Landmarker topology (468 face points plus 10 iris points). "Right" and "left" are the
    /// person's own sides. A mirrored selfie only swaps which one is on the image's left, and the two eyes
    /// are measured the same either way. Check these indices against a real scan on a device.
    enum MeshIndex {
        struct Eye {
            let inner: Int, outer: Int
            let lid: [Int]
            let brow: [Int]
        }

        static let pointCount = 478
        /// Nose tip and the two face edges, for `headTurn`.
        static let noseTip = 1, faceEdgeRight = 234, faceEdgeLeft = 454
        static let personRight = Eye(
            inner: 133, outer: 33,
            lid: [246, 161, 160, 159, 158, 157, 173, 7, 163, 144, 145, 153, 154, 155],
            brow: [46, 53, 52, 65, 55])
        static let personLeft = Eye(
            inner: 362, outer: 263,
            lid: [466, 388, 387, 386, 385, 384, 398, 249, 390, 373, 374, 380, 381, 382],
            brow: [276, 283, 282, 295, 285])
        /// The two iris rings (each four rim points; 468 and 473 are the centres). Which ring belongs to which eye is
        /// decided by distance, because MediaPipe's own left/right iris tables disagree with the commonly used
        /// numbering (its iOS right-iris table returns the left ring).
        static let irisRings = [[469, 470, 471, 472], [474, 475, 476, 477]]
    }

    /// Builds the landmarks from MediaPipe's normalized face mesh (x and y in 0...1). `imageSize` restores the
    /// image's aspect ratio, without which a wide image would stretch every ratio. `nil` unless all 478 points
    /// (including the iris) are present.
    init?(normalizedMesh points: [SIMD2<Float>], imageSize: SIMD2<Float>) {
        guard points.count >= MeshIndex.pointCount, imageSize.x > 0, imageSize.y > 0 else { return nil }
        func pixel(_ i: Int) -> SIMD2<Float> { points[i] * imageSize }
        func center(_ indices: [Int]) -> SIMD2<Float> { indices.map(pixel).reduce(.zero, +) / Float(indices.count) }
        func eye(_ index: MeshIndex.Eye) -> Eye {
            let eyeCenter = center(index.lid)
            let ring = MeshIndex.irisRings.min { simd_distance(center($0), eyeCenter) < simd_distance(center($1), eyeCenter) }!
            return Eye(innerCorner: pixel(index.inner), outerCorner: pixel(index.outer), lid: index.lid.map(pixel),
                       iris: ring.map(pixel), brow: index.brow.map(pixel))
        }
        // Facing the camera, the nose tip projects onto the middle of the line between the face edges; a turned head
        // slides it toward one edge. Projecting makes this ignore head roll and the nose sitting lower than the edges.
        let right = points[MeshIndex.faceEdgeRight] * imageSize, left = points[MeshIndex.faceEdgeLeft] * imageSize
        let edges = left - right
        let nose = points[MeshIndex.noseTip] * imageSize
        let turn: Float? = simd_length_squared(edges) > 0 ? 2 * simd_dot(nose - right, edges) / simd_length_squared(edges) - 1 : nil
        self.init(first: eye(MeshIndex.personRight), second: eye(MeshIndex.personLeft), headTurn: turn)
    }
}
